// call_client_company_introduction.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solidplyaug25/globals.dart' as globals;

import 'call_stage_args.dart';
import 'call_client_det.dart'; // redirect after save

class CompanyIntroductionScreen extends StatefulWidget {
  static const String id = 'call_client_company_introduction';

  const CompanyIntroductionScreen({super.key});

  @override
  State<CompanyIntroductionScreen> createState() =>
      _CompanyIntroductionScreenState();
}

class _CompanyIntroductionScreenState extends State<CompanyIntroductionScreen> {
  bool _didInit = false;
  late CallStageArgs _args;

  // Overall saving overlay
  bool _saving = false;

  // Per-image local preview + server filename + per-tile uploading flag
  String? _img1Local, _img2Local, _img3Local;
  String _img1Server = '', _img2Server = '', _img3Server = '';
  bool _up1 = false, _up2 = false, _up3 = false;

  // Form controllers
  final _remarksCtrl = TextEditingController();
  final _followDateCtrl = TextEditingController(); // yyyy-MM-dd
  final _chanceCtrl = TextEditingController(); // 0..100
  final _numSheetCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final a = ModalRoute.of(context)?.settings.arguments;
    _args = (a is CallStageArgs) ? a : const CallStageArgs(clientId: 0);
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    _followDateCtrl.dispose();
    _chanceCtrl.dispose();
    _numSheetCtrl.dispose();
    super.dispose();
  }

  // ---------- URL helpers ----------
  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _endpoint(String base, String fileWithQuery) {
    final hasNative = RegExp(r'/native_app/?$').hasMatch(base) ||
        base.contains('/native_app/');
    final root = hasNative ? base : '$base/native_app';
    return '$root/$fileWithQuery';
  }

  // ---------- Image helpers ----------
  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    return c.future;
  }

  /// Pick (camera/gallery) → resize to EXACT height=450 (keep ratio width) → compress → temp file path
  Future<String?> _pickAndCompress(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source);
    if (x == null) return null;

    final orig = await x.readAsBytes();
    final uiImg = await _decodeUiImage(orig);
    final origW = uiImg.width;
    final origH = uiImg.height;

    const int targetH = 450;
    final int targetW = ((origW * targetH) / origH).round().clamp(1, 100000);

    // Resize to target dims
    Uint8List resized = await FlutterImageCompress.compressWithList(
      orig,
      format: CompressFormat.jpeg,
      minHeight: targetH,
      minWidth: targetW,
      quality: 92,
    );

    // If still heavy, nudge quality down to ~<= 250KB
    const int targetBytes = 250 * 1024;
    int quality = 85;
    Uint8List out = resized;
    while (out.length > targetBytes && quality > 40) {
      out = await FlutterImageCompress.compressWithList(
        resized,
        format: CompressFormat.jpeg,
        quality: quality,
      );
      quality -= 10;
    }

    final tmp = await getTemporaryDirectory();
    final path = '${tmp.path}/call_img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(path);
    await file.writeAsBytes(out, flush: true);
    return file.path;
  }

  Future<String?> _uploadSingle(String filePath) async {
    final base = _baseUrl();
    if (base.isEmpty) {
      _showSnack('Base URL not set');
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    if (userId.isEmpty) {
      _showSnack('Missing user_id');
      return null;
    }

    final url = Uri.parse(_endpoint(base, 'upload_call_file.php'));
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
    print('UPLOAD -> ${resp.statusCode} $body');

    if (resp.statusCode != 200) {
      _showSnack('Upload failed (${resp.statusCode})');
      return null;
    }
    final map = _safeJson(body);
    if (map == null) {
      _showSnack('Invalid upload response');
      return null;
    }
    final ok = (map['success'] == true) || (map['status'] == true);
    if (!ok) {
      _showSnack((map['message'] ?? 'Upload failed').toString());
      return null;
    }
    if (map['uploaded_files'] is List && map['uploaded_files'].isNotEmpty) {
      return map['uploaded_files'][0].toString();
    }
    _showSnack('No file name returned.');
    return null;
  }

  // ---------- Pickers per image ----------
  void _chooseSourceFor(int which) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickUpload(which, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickUpload(which, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickUpload(int which, ImageSource src) async {
    setState(() {
      if (which == 1) _up1 = true;
      if (which == 2) _up2 = true;
      if (which == 3) _up3 = true;
    });

    try {
      final local = await _pickAndCompress(src);
      if (local == null) return;

      final server = await _uploadSingle(local);
      if (server == null) return;

      setState(() {
        if (which == 1) {
          _img1Local = local;
          _img1Server = server;
        } else if (which == 2) {
          _img2Local = local;
          _img2Server = server;
        } else {
          _img3Local = local;
          _img3Server = server;
        }
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      setState(() {
        if (which == 1) _up1 = false;
        if (which == 2) _up2 = false;
        if (which == 3) _up3 = false;
      });
    }
  }

  // ---------- Save ----------
  Future<Position?> _getPosition() async {
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

  Future<void> _saveStage() async {
    // --- Validation ---
    if (_up1 || _up2 || _up3) {
      _showSnack('Please wait for uploads to finish.');
      return;
    }
    if (_img1Server.isEmpty) {
      _showSnack('Image 1 is required.');
      return;
    }
    final follow = _followDateCtrl.text.trim();
    if (follow.isEmpty) {
      _showSnack('Next follow-up date is required.');
      return;
    }
    // chance 0..100
    final chanceStr = _chanceCtrl.text.trim();
    if (chanceStr.isEmpty) {
      _showSnack('Chance For Closure is required.');
      return;
    }
    final chanceVal = int.tryParse(chanceStr);
    if (chanceVal == null || chanceVal < 0 || chanceVal > 100) {
      _showSnack('Chance must be a number between 0 and 100.');
      return;
    }

    setState(() => _saving = true);

    try {
      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      // Location
      final pos = await _getPosition();
      if (pos == null) throw 'Location unavailable. Enable GPS & permission.';

      final url = Uri.parse(_endpoint(
          base, 'call_client_company_introduction.php?subject=call&action=stage'));

      final body = {
        'user_id': userId,
        'mob': mob,
        'client': _args.clientId.toString(),
        'lat': pos.latitude.toString(),
        'lon': pos.longitude.toString(),
        'image1': _img1Server,
        'image2': _img2Server,
        'image3': _img3Server,
        'remarks': _remarksCtrl.text.trim(),
        'follow_up_date': follow, // already yyyy-MM-dd
        'take_chance': chanceStr,
        'num_sheet': _numSheetCtrl.text.trim(),
      };

      final resp = await http.post(url, body: body);
      // ignore: avoid_print
      print('SAVE -> ${resp.statusCode} ${resp.body}');
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';

      final map = _safeJson(resp.body);
      if (map == null) throw 'Invalid JSON from server';
      if (map['status'] == true) {
        _showSnack((map['message'] ?? 'Saved Successfully').toString());

        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          ClientDetailScreen.id,
          arguments: ClientDetailArgs(clientId: _args.clientId, name: _args.clientName),
        );
      } else {
        throw (map['message'] ?? 'Save failed').toString();
      }
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Misc ----------
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day), // lock past
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) {
      final yyyy = d.year.toString().padLeft(4, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      // API & display use yyyy-MM-dd
      _followDateCtrl.text = '$yyyy-$mm-$dd';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Company Introduction')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // (1) Top: client name only
                Text(
                  (_args.clientName?.isNotEmpty ?? false)
                      ? _args.clientName!
                      : 'Client #${_args.clientId}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // (2) Images
                _ImagePickerTile(
                  title: 'Image 1 *',
                  localPath: _img1Local,
                  uploading: _up1,
                  onPick: () => _chooseSourceFor(1),
                  requiredHint: true,
                ),
                const SizedBox(height: 12),

                _ImagePickerTile(
                  title: 'Image 2',
                  localPath: _img2Local,
                  uploading: _up2,
                  onPick: () => _chooseSourceFor(2),
                ),
                const SizedBox(height: 12),

                _ImagePickerTile(
                  title: 'Image 3',
                  localPath: _img3Local,
                  uploading: _up3,
                  onPick: () => _chooseSourceFor(3),
                ),
                const SizedBox(height: 16),

                // Remarks
                const _FieldLabel('Remarks :'),
                const SizedBox(height: 6),
                TextField(
                  controller: _remarksCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: _decoration(),
                ),
                const SizedBox(height: 14),

                // Follow up date (yyyy-MM-dd, mandatory, no past)
                const _FieldLabel('Next Followup Date *'),
                const SizedBox(height: 6),
                TextField(
                  controller: _followDateCtrl,
                  readOnly: true,
                  onTap: _pickDate,
                  decoration: _decoration(hint: 'yyyy-MM-dd').copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickDate,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Chance % (0..100, mandatory)
                const _FieldLabel('Chance For Closure (%) *'),
                const SizedBox(height: 6),
                TextField(
                  controller: _chanceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: _decoration(hint: '0 - 100'),
                ),
                const SizedBox(height: 14),

                // Number of sheets
                const _FieldLabel('No. Of Sheet Taking :'),
                const SizedBox(height: 6),
                TextField(
                  controller: _numSheetCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(),
                ),
                const SizedBox(height: 18),

                // Save
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveStage,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Attractive saving overlay
        if (_saving)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Saving your entry…',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Please hold on a moment.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  final String title;
  final String? localPath;
  final bool uploading;
  final VoidCallback onPick;
  final bool requiredHint;

  const _ImagePickerTile({
    required this.title,
    required this.localPath,
    required this.uploading,
    required this.onPick,
    this.requiredHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final preview = localPath == null
        ? Container(
      width: 90,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE6F2)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.image, color: Colors.black45),
    )
        : ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(localPath!),
        width: 90,
        height: 70,
        fit: BoxFit.cover,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFEFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF3)),
      ),
      child: Row(
        children: [
          preview,
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (requiredHint) ...[
                  const SizedBox(width: 6),
                  const Text('*', style: TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          if (uploading)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            )
          else
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload),
              label: Text(localPath == null ? 'Upload' : 'Replace'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
    );
  }
}
