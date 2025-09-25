// call_client_closure.dart
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

class ClosureScreen extends StatefulWidget {
  static const String id = 'call_client_closure';

  const ClosureScreen({super.key});

  @override
  State<ClosureScreen> createState() => _ClosureScreenState();
}

class _ClosureScreenState extends State<ClosureScreen> {
  bool _didInit = false;
  late CallStageArgs _args;

  // init data
  List<_ItemOpt> _items = []; // id + name
  List<String> _sizes = [];
  List<String> _mms = [];

  bool _loading = true;
  String? _error;

  // Overall saving overlay
  bool _saving = false;

  // Per-image local preview + server filename + per-tile uploading flag
  String? _img1Local, _img2Local, _img3Local;
  String _img1Server = '', _img2Server = '', _img3Server = '';
  bool _up1 = false, _up2 = false, _up3 = false;

  // Lines (up to 20)
  late List<_LineData> _lines;

  // Other fields
  final _deliveryDateCtrl = TextEditingController(); // yyyy-MM-dd (mandatory)
  final _supplyPlaceCtrl  = TextEditingController(); // text
  final _paymentPosCtrl   = TextEditingController(); // text
  final _paymentDateCtrl  = TextEditingController(); // yyyy-MM-dd (no past)
  String? _closureType; // Primary / Secondary
  String? _lostVal;     // Yes / No (send 1/0)
  final _remarksCtrl     = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final a = ModalRoute.of(context)?.settings.arguments;
    _args = (a is CallStageArgs) ? a : const CallStageArgs(clientId: 0);
    _lines = List.generate(20, (_) => _LineData());
    _loadInit();
  }

  @override
  void dispose() {
    _deliveryDateCtrl.dispose();
    _supplyPlaceCtrl.dispose();
    _paymentPosCtrl.dispose();
    _paymentDateCtrl.dispose();
    _remarksCtrl.dispose();
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
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

  Future<void> _loadInit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob    = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      final url = Uri.parse(_endpoint(base, 'call_client_closure_init.php?subject=call&action=init'));
      final resp = await http.post(url, body: {'user_id': userId, 'mob': mob});
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = _safeJson(resp.body);
      if (map == null || map['status'] != true) {
        throw (map?['message'] ?? 'Failed to load').toString();
      }

      final List<dynamic> ms_item = (map['ms_item'] ?? []) as List<dynamic>;
      _items = ms_item
          .map((e) => _ItemOpt(id: (e['id'] ?? '').toString(), name: (e['name'] ?? '').toString()))
          .where((x) => x.id.isNotEmpty && x.name.isNotEmpty)
          .toList();

      final List<dynamic> ms_size = (map['ms_size'] ?? []) as List<dynamic>;
      _sizes = ms_size.map((e) => (e['name'] ?? '').toString()).where((x) => x.isNotEmpty).toList();

      final List<dynamic> ms_mm = (map['ms_mm'] ?? []) as List<dynamic>;
      _mms = ms_mm.map((e) => (e['name'] ?? '').toString()).where((x) => x.isNotEmpty).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    if (_deliveryDateCtrl.text.trim().isEmpty) {
      _showSnack('Delivery Date is required.');
      return;
    }
    // At least one line
    final arr = <Map<String, String>>[];
    for (final l in _lines) {
      final item = l.itemId?.trim() ?? '';
      final size = l.size?.trim() ?? '';
      final mm   = l.mm?.trim() ?? '';
      final qty  = l.qtyCtrl.text.trim();
      if (item.isEmpty && size.isEmpty && mm.isEmpty && qty.isEmpty) {
        continue; // blank row
      }
      if (item.isEmpty || size.isEmpty || mm.isEmpty || qty.isEmpty) {
        _showSnack('Please complete all fields for filled rows (Item/Size/MM/Qty).');
        return;
      }
      if (int.tryParse(qty) == null) {
        _showSnack('Qty must be numeric.');
        return;
      }
      // mm/sizes are strings from init; item is id
      arr.add({'item': item, 'qty': qty, 'size': size, 'mm': mm});
    }
    if (arr.isEmpty) {
      _showSnack('Add at least one line item.');
      return;
    }
    // lost mapping Yes/No -> 1/0
    final lost = (_lostVal == 'Yes') ? '1' : '0';

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

      // Save endpoint (adjust filename here if your server differs)
      final url = Uri.parse(_endpoint(
        base, 'call_client_closure.php?subject=call&action=stage',
      ));

      final body = {
        'user_id'     : userId,
        'mob'         : mob,
        'client'      : _args.clientId.toString(),
        'lat'         : pos.latitude.toString(),
        'lon'         : pos.longitude.toString(),
        'image1'      : _img1Server,
        'image2'      : _img2Server,
        'image3'      : _img3Server,
        'remarks'     : _remarksCtrl.text.trim(),
        'delivery_date': _deliveryDateCtrl.text.trim(), // yyyy-MM-dd
        'supply_place': _supplyPlaceCtrl.text.trim(),
        'payment_pos' : _paymentPosCtrl.text.trim(),
        'payment_date': _paymentDateCtrl.text.trim(),   // yyyy-MM-dd
        'closure_type': _closureType ?? '',
        'lost'        : lost, // 1/0
        'arr'         : jsonEncode(arr),
      };

      final resp = await http.post(url, body: body);
      // ignore: avoid_print
      print('SAVE (closure) -> ${resp.statusCode} ${resp.body}');
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


  /// Small helper to parse yyyy-MM-dd safely
  DateTime? _parseYMD(String s) {
    try {
      if (s.trim().isEmpty) return null;
      final d = DateTime.parse(s.trim()); // requires yyyy-MM-dd format
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }


  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();

    // If the field already has a date, open the picker there.
    final initial = _parseYMD(_deliveryDateCtrl.text) ?? DateTime(now.year, now.month, now.day);

    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      // ⬇️ Allow past dates
      firstDate: DateTime(1970, 1, 1), // pick any lower bound you prefer
      lastDate: DateTime(now.year + 5, 12, 31),
    );

    if (d != null) {
      final yyyy = d.year.toString().padLeft(4, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      _deliveryDateCtrl.text = '$yyyy-$mm-$dd';
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickPaymentDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day), // no past dates
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) {
      final yyyy = d.year.toString().padLeft(4, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      _paymentDateCtrl.text = '$yyyy-$mm-$dd';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Closure')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null
              ? _ErrorState(message: _error!, onRetry: _loadInit)
              : SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top: client name only
                Text(
                  (_args.clientName?.isNotEmpty ?? false)
                      ? _args.clientName!
                      : 'Client #${_args.clientId}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Images
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

                // 20 lines grid
                const _FieldLabel('Items (up to 20 rows):'),
                const SizedBox(height: 8),
                ...List.generate(_lines.length, (i) {
                  return _LineRow(
                    idx: i + 1,
                    line: _lines[i],
                    items: _items,
                    sizes: _sizes,
                    mms: _mms,
                  );
                }),
                const SizedBox(height: 16),

                // Delivery Date (mandatory)
                const _FieldLabel('Delivery Date *'),
                const SizedBox(height: 6),
                TextField(
                  controller: _deliveryDateCtrl,
                  readOnly: true,
                  onTap: _pickDeliveryDate,
                  decoration: _decoration(hint: 'yyyy-MM-dd').copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickDeliveryDate,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Place of Supply
                const _FieldLabel('Place Of Supply'),
                const SizedBox(height: 6),
                TextField(
                  controller: _supplyPlaceCtrl,
                  decoration: _decoration(),
                ),
                const SizedBox(height: 14),

                // Position of Payment
                const _FieldLabel('Position Of Payment'),
                const SizedBox(height: 6),
                TextField(
                  controller: _paymentPosCtrl,
                  decoration: _decoration(),
                ),
                const SizedBox(height: 14),

                // Estimated Payment Date (no past)
                const _FieldLabel('Estimated Payment Date'),
                const SizedBox(height: 6),
                TextField(
                  controller: _paymentDateCtrl,
                  readOnly: true,
                  onTap: _pickPaymentDate,
                  decoration: _decoration(hint: 'yyyy-MM-dd').copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickPaymentDate,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Closure Type
                const _FieldLabel('Closure Type'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _closureType,
                  items: const [
                    DropdownMenuItem(value: 'Primary', child: Text('Primary')),
                    DropdownMenuItem(value: 'Secondary', child: Text('Secondary')),
                  ],
                  onChanged: (v) => setState(() => _closureType = v),
                  decoration: _decoration(hint: 'Select'),
                ),
                const SizedBox(height: 14),

                // Deal Rejected ? (Yes/No -> 1/0)
                const _FieldLabel('Deal Rejected ?'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _lostVal,
                  items: const [
                    DropdownMenuItem(value: 'No',  child: Text('No')),
                    DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                  ],
                  onChanged: (v) => setState(() => _lostVal = v),
                  decoration: _decoration(hint: 'Select'),
                ),
                const SizedBox(height: 14),

                // Remarks
                const _FieldLabel('Remarks :'),
                const SizedBox(height: 6),
                TextField(
                  controller: _remarksCtrl,
                  minLines: 3,
                  maxLines: 5,
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
          )),
        ),

        // Saving overlay
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

// ----- Models -----
class _ItemOpt {
  final String id;
  final String name;
  _ItemOpt({required this.id, required this.name});
}

class _LineData {
  String? itemId;
  String? size;
  String? mm;
  final TextEditingController qtyCtrl = TextEditingController();
}

// ----- UI bits -----
class _LineRow extends StatelessWidget {
  final int idx;
  final _LineData line;
  final List<_ItemOpt> items;
  final List<String> sizes;
  final List<String> mms;

  const _LineRow({
    super.key,
    required this.idx,
    required this.line,
    required this.items,
    required this.sizes,
    required this.mms,
  });

  @override
  Widget build(BuildContext context) {
    // Each line: Item (id) | Size | MM | Qty
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Item
          Expanded(
            flex: 9,
            child: DropdownButtonFormField<String>(
              value: line.itemId,
              isDense: true,
              isExpanded: true, // <-- important
              items: items
                  .map((e) => DropdownMenuItem(
                value: e.id,
                child: Text(
                  e.name,
                  overflow: TextOverflow.ellipsis, // <-- avoid overflow
                ),
              ))
                  .toList(),
              onChanged: (v) => line.itemId = v,
              decoration: _cellDecor('Item'),
            ),
          ),
          const SizedBox(width: 6),

          // Size
          Expanded(
            flex: 7,
            child: DropdownButtonFormField<String>(
              value: line.size,
              isDense: true,
              isExpanded: true, // <-- important
              items: sizes
                  .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s,
                  overflow: TextOverflow.ellipsis, // <-- avoid overflow
                ),
              ))
                  .toList(),
              onChanged: (v) => line.size = v,
              decoration: _cellDecor('Size'),
            ),
          ),
          const SizedBox(width: 6),

          // MM
          Expanded(
            flex: 6,
            child: DropdownButtonFormField<String>(
              value: line.mm,
              isDense: true,
              isExpanded: true, // <-- important
              items: mms
                  .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s,
                  overflow: TextOverflow.ellipsis, // <-- avoid overflow
                ),
              ))
                  .toList(),
              onChanged: (v) => line.mm = v,
              decoration: _cellDecor('MM'),
            ),
          ),
          const SizedBox(width: 6),

          // Qty
          Expanded(
            flex: 6,
            child: TextField(
              controller: line.qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLines: 1,
              decoration: _cellDecor('Qty'),
            ),
          ),
        ],
      ),
    );
  }


  InputDecoration _cellDecor(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ),
    );
  }
}
