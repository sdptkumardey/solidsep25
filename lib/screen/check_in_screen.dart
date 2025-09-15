import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui; // for decoding image size

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http_parser/http_parser.dart';

import 'package:solidplyaug25/globals.dart' as globals; // GLOBAL BASE URL
import 'attendance_service.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  bool _busy = true;
  String _status = 'Starting...';

  @override
  void initState() {
    super.initState();
    _runFlow();
  }

  // Normalize global base URL (remove trailing slash if present)
  String _baseUrlFromGlobals() {
    final raw = globals.ipAddress.trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  Future<void> _runFlow() async {
    try {
      setState(() => _status = 'Reading config...');
      final baseUrl = _baseUrlFromGlobals();
      if (baseUrl.isEmpty) throw 'Server base URL not set in globals.ipAddress.';
      // ignore: avoid_print
      print('Base URL: $baseUrl');

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob in preferences.';

      // 1) Camera (front)
      setState(() => _status = 'Opening camera...');
      final selfiePath = await _captureCompressedSelfieToTemp();
      if (selfiePath == null) throw 'Camera cancelled.';

      // 2) Upload
      setState(() => _status = 'Uploading selfie...');
      final uploadedFileName = await _uploadSelfie(
        baseUrl: baseUrl,
        userId: userId,
        filePath: selfiePath,
      );
      if (uploadedFileName == null) throw 'Upload failed.';

      // 3) Location
      setState(() => _status = 'Fetching location...');
      final pos = await _getCurrentPosition();
      if (pos == null) throw 'Location unavailable. Enable GPS & permission.';

      // 4) Save check-in
      setState(() => _status = 'Saving check-in...');
      final ok = await _saveCheckIn(
        baseUrl: baseUrl,
        userId: userId,
        mob: mob,
        lat: pos.latitude,
        lon: pos.longitude,
        imgFileName: uploadedFileName,
      );
      if (!ok) throw 'Check-in save failed.';

      // 5) Pull fresh detail from server; fallback to local if not present.
      final detail = await _pullAndCacheTodayDetailReturningMap(
        baseUrl: baseUrl,
        userId: userId,
        mob: mob,
        fallbackImgFile: uploadedFileName,
        fallbackLat: pos.latitude.toString(),
        fallbackLon: pos.longitude.toString(),
      );

      // 6) Mark check-in done locally (so pending=false immediately)
      await AttendanceService.instance.markTodayDoneLocally();

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Done!';
      });

      // 7) Return detail to Home so it updates instantly
      Navigator.pop(context, detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  // ---- helpers ----

  /// Fetch today's check-in detail (checkin_chk) and cache it to prefs.
  /// If server doesn't provide it, fallback to local values.
  /// Returns a map: { img_url, send_date_time, lat, lon } for Home to use immediately.
  Future<Map<String, String>> _pullAndCacheTodayDetailReturningMap({
    required String baseUrl,
    required String userId,
    required String mob,
    required String fallbackImgFile,
    required String fallbackLat,
    required String fallbackLon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final url = Uri.parse('$baseUrl/native_app/checkin_chk.php?subject=checkin&action=chk');
      final resp = await http.post(url, body: {'mob': mob, 'user_id': userId});
      // ignore: avoid_print
      print('Detail fetch: ${resp.statusCode} ${resp.body}');
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final bool attSt = _asBool(data['att_st']);
        if (attSt) {
          final imgUrl = (data['img_url'] ?? '').toString();
          final sendDT = (data['send_date_time'] ?? '').toString();
          final lat    = (data['lat'] ?? '').toString();
          final lon    = (data['lon'] ?? '').toString();

          await prefs.setString('att_img_url', imgUrl);
          await prefs.setString('att_send_date_time', sendDT);
          await prefs.setString('att_lat', lat);
          await prefs.setString('att_lon', lon);

          return {
            'img_url': imgUrl,
            'send_date_time': sendDT,
            'lat': lat,
            'lon': lon,
          };
        }
      }
    } catch (_) {
      // ignore and fallback
    }

    // Fallback to what we know locally (and cache it)
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final fallbackDt =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';

    await prefs.setString('att_img_url', fallbackImgFile);
    await prefs.setString('att_send_date_time', fallbackDt);
    await prefs.setString('att_lat', fallbackLat);
    await prefs.setString('att_lon', fallbackLon);

    return {
      'img_url': fallbackImgFile,
      'send_date_time': fallbackDt,
      'lat': fallbackLat,
      'lon': fallbackLon,
    };
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    return c.future;
  }

  /// Capture selfie from FRONT camera, resize to EXACT height=450px (keep ratio for width),
  /// then compress toward ~<= 80KB. Saves to temp .jpg and returns the path.
  Future<String?> _captureCompressedSelfieToTemp() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front, // front camera requested
    );
    if (x == null) return null;

    // Original bytes and size
    Uint8List orig = await x.readAsBytes();
    final uiImg = await _decodeUiImage(orig);
    final origW = uiImg.width;
    final origH = uiImg.height;

    // Target: height = 450 px, width by aspect ratio
    const int targetH = 450;
    final int targetW = ((origW * targetH) / origH).round().clamp(1, 100000);

    // First pass: resize to EXACT target size (height=450, width=ratio)
    Uint8List resized = await FlutterImageCompress.compressWithList(
      orig,
      format: CompressFormat.jpeg,
      minHeight: targetH,
      minWidth: targetW,
      quality: 95,
    );

    // Second pass: shrink file size by lowering quality until <= 80KB
    const int targetBytes = 80 * 1024;
    int quality = 85;
    Uint8List out = resized;

    while (out.length > targetBytes && quality > 30) {
      out = await FlutterImageCompress.compressWithList(
        resized, // recompress from the resized base
        quality: quality,
        format: CompressFormat.jpeg,
      );
      quality -= 10;
    }

    // Safeguard: if still too big, slightly reduce width
    if (out.length > targetBytes) {
      final int narrowerW = (targetW * 0.9).round().clamp(1, 100000);
      final Uint8List narrower = await FlutterImageCompress.compressWithList(
        orig,
        format: CompressFormat.jpeg,
        minHeight: targetH,
        minWidth: narrowerW,
        quality: quality.clamp(30, 85),
      );
      out = narrower.length <= targetBytes ? narrower : out;
    }

    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final f = File(path);
    await f.writeAsBytes(out, flush: true);
    return f.path;
  }

  // Upload to {baseUrl}/native_app/upload_file.php (fields: user_id, image)
  Future<String?> _uploadSelfie({
    required String baseUrl,
    required String userId,
    required String filePath,
  }) async {
    final url = Uri.parse('$baseUrl/native_app/upload_file.php');
    final req = http.MultipartRequest('POST', url)
      ..fields['user_id'] = userId
      ..files.add(await http.MultipartFile.fromPath(
        'image',
        filePath,
        contentType: MediaType('image', 'jpeg'),
      ));

    final resp = await req.send();
    final body = await resp.stream.bytesToString();

    // ignore: avoid_print
    print('Upload response: ${resp.statusCode} $body');

    if (resp.statusCode != 200) return null;

    final map = _safeJson(body);
    if (map == null) return null;

    final success = (map['success'] == true) || (map['status'] == true);
    if (!success) return null;

    if (map['uploaded_files'] is List && map['uploaded_files'].isNotEmpty) {
      return map['uploaded_files'][0].toString();
    }
    return null;
  }

  // Get current GPS position with permissions
  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  // POST to {baseUrl}/native_app/checkin_save.php?subject=checkin&action=save
  Future<bool> _saveCheckIn({
    required String baseUrl,
    required String userId,
    required String mob,
    required double lat,
    required double lon,
    required String imgFileName,
  }) async {
    final url = Uri.parse('$baseUrl/native_app/checkin_save.php?subject=checkin&action=save');
    final resp = await http.post(url, body: {
      'user_id': userId,
      'mob': mob,
      'lat': lat.toString(),
      'lon': lon.toString(),
      'img_url': imgFileName,
    });

    // ignore: avoid_print
    print('Save response: ${resp.statusCode} ${resp.body}');

    if (resp.statusCode != 200) return false;

    final map = _safeJson(resp.body);
    if (map == null) return false;

    return (map['status'] == true) || (map['success'] == true);
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check In'),
        actions: [
          if (!_busy)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, false),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please wait, this may take a few seconds.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
