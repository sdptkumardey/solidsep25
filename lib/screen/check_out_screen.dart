import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidplyaug25/globals.dart' as globals;

import 'attendance_service.dart';

class CheckOutScreen extends StatefulWidget {
  const CheckOutScreen({super.key});

  @override
  State<CheckOutScreen> createState() => _CheckOutScreenState();
}

class _CheckOutScreenState extends State<CheckOutScreen> {
  bool _busy = true;
  String _status = 'Starting...';

  @override
  void initState() {
    super.initState();
    _runFlow();
  }

  // --- helpers: base URL + endpoint ---

  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _nativeAppEndpoint(String baseUrl, String fileWithQuery) {
    final hasNative = RegExp(r'/native_app/?$').hasMatch(baseUrl) || baseUrl.contains('/native_app/');
    final root = hasNative ? baseUrl : "$baseUrl/native_app";
    return "$root/$fileWithQuery";
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

  String _fmtNowDdMMyyHHmm() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(now.day)}/${two(now.month)}/${now.year.toString().substring(2)} "
        "${two(now.hour)}:${two(now.minute)}";
  }

  // --- main flow ---

  Future<void> _runFlow() async {
    try {
      setState(() => _status = 'Reading config...');
      final base = _baseUrl();
      if (base.isEmpty) throw 'Server base URL not set.';
      if (kDebugMode) {
        print('=== CHECKOUT DEBUG ===');
        print('Base URL           : $base');
      }

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob    = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      // 1) Location
      setState(() => _status = 'Fetching location...');
      final pos = await _getCurrentPosition();
      if (pos == null) throw 'Location unavailable. Enable GPS & permission.';
      if (kDebugMode) {
        print('Device Location    : lat=${pos.latitude}, lon=${pos.longitude}');
      }

      // 2) Save checkout
      setState(() => _status = 'Saving check-out...');
      final ok = await _saveCheckout(
        baseUrl: base,
        userId: userId,
        mob: mob,
        lat: pos.latitude,
        lon: pos.longitude,
      );
      if (!ok) throw 'Checkout save failed.';

      // 3) Cache locally for Home
      await AttendanceService.instance.markTodayCheckedOutLocally(
        dateTime: _fmtNowDdMMyyHHmm(), // client time; swap to server time if your API returns it
        lat: pos.latitude.toString(),
        lon: pos.longitude.toString(),
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Done!';
      });
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  // --- location ---

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

  // --- network ---

  Future<bool> _saveCheckout({
    required String baseUrl,
    required String userId,
    required String mob,
    required double lat,
    required double lon,
  }) async {
    final endpoint = _nativeAppEndpoint(baseUrl, 'checkout_save.php?subject=checkout&action=save');
    final url = Uri.parse(endpoint);

    final bodyMap = {
      'user_id': userId,
      'mob': mob,
      'lat': lat.toString(),
      'lon': lon.toString(),
    };

    // DEBUG: print what we're sending
    if (kDebugMode) {
      print('Endpoint           : $endpoint');
      print('POST body (sent)   : ${jsonEncode(bodyMap)}');
    }

    final resp = await http.post(url, body: bodyMap);

    // DEBUG: print what we got back
    if (kDebugMode) {
      print('HTTP Status        : ${resp.statusCode}');
      print('Response headers   : ${resp.headers}');
      // Avoid huge prints; trim if necessary
      final bodyPreview = resp.body.length > 2000 ? '${resp.body.substring(0, 2000)}...<truncated>' : resp.body;
      print('Response body(raw) : $bodyPreview');
    }

    if (resp.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error ${resp.statusCode}')),
        );
      }
      return false;
    }

    final map = _safeJson(resp.body);
    if (kDebugMode) {
      print('Response body(json): $map');
    }

    if (map == null) {
      if (mounted) {
        final preview = resp.body.length > 200 ? resp.body.substring(0, 200) + '…' : resp.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid JSON: $preview')),
        );
      }
      return false;
    }

    final ok = _asBool(map['status']) || _asBool(map['success']) || _asBool(map['att_st']);
    if (kDebugMode) {
      print('Response OK (bool) : $ok');
      print('====================');
    }

    if (!ok) {
      final msg = (map['message'] ?? 'Checkout save failed.').toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
    return ok;
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      if (body.isEmpty) return null;
      // Strip UTF-8 BOM and trim
      body = body.replaceFirst(RegExp(r'^\uFEFF'), '').trim();

      if (body.startsWith('{') && body.endsWith('}')) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      // try to extract first { ... }
      final s = body.indexOf('{');
      final e = body.lastIndexOf('}');
      if (s != -1 && e != -1 && e > s) {
        return jsonDecode(body.substring(s, e + 1)) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('JSON parse error: $e');
      }
      return null;
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check Out')),
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
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Please wait…', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
