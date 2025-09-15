import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solidplyaug25/globals.dart' as globals;

// ============================ MODELS ============================
class ExpenseHead {
  final String id;
  final String name;
  ExpenseHead({required this.id, required this.name});
  factory ExpenseHead.fromJson(Map<String, dynamic> j) =>
      ExpenseHead(id: j['id'].toString(), name: j['name'].toString());
}

class ExpenseLine {
  String item;        // head id
  String itemName;    // head name
  String qty;         // always "1"
  String rate;        // user input
  String imgUrl;      // server file name
  String description; // user input
  ExpenseLine({
    required this.item,
    required this.itemName,
    this.qty = '1',
    required this.rate,
    required this.imgUrl,
    required this.description,
  });
  Map<String, String> toMap() => {
    'item': item,
    'item_name': itemName,
    'qty': qty,
    'rate': rate,
    'img_url': imgUrl,
    'description': description,
  };
}

// ============================ SCREEN ============================
class Exp extends StatefulWidget {
  static const String id = 'exp';
  const Exp({super.key});

  @override
  State<Exp> createState() => _ExpState();
}

class _ExpState extends State<Exp> {
  // Heads & lines
  List<ExpenseHead> _heads = [];
  final List<ExpenseLine> _lines = [];

  // Overall fields
  final _dateCtrl = TextEditingController(); // yyyy-MM-dd
  final _descCtrl = TextEditingController();

  // Flags
  bool _loadingInit = true;
  bool _busy = false;   // image pick/upload busy
  bool _saving = false; // final save busy

  // Auth
  String? _userId;
  String? _mob;

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _initLoad();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ------------------------- URL helpers -------------------------
  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _endpoint(String base, String fileWithQuery) {
    final hasNative = RegExp(r'/native_app/?$').hasMatch(base) || base.contains('/native_app/');
    final root = hasNative ? base : '$base/native_app';
    return '$root/$fileWithQuery';
  }

  // ------------------------- Init heads -------------------------
  Future<void> _initLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('user_id');
      _mob = prefs.getString('mob');

      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';

      final url = Uri.parse(_endpoint(base, 'exp_head_init.php?subject=exp&action=init'));
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'user_id': _userId ?? '',
          'mob': _mob ?? '',
        },
      );
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = _safeJson(resp.body);
      if (map == null || map['status'] != true) throw (map?['message'] ?? 'Failed to load');
      final List list = (map['ms_item'] as List? ?? []);
      _heads = list.map((e) => ExpenseHead.fromJson(e)).toList();
    } catch (e) {
      _showSnack('Init error: $e');
    } finally {
      if (mounted) setState(() => _loadingInit = false);
    }
  }

  // ------------------------- Image helpers -------------------------
  /// REQUIREMENT: final image must have height = 450px (width auto by aspect ratio).
  /// We let ImagePicker scale natively to maxHeight: 450 (keeps aspect), then
  /// run a light flutter_image_compress pass for size/quality and EXIF angle.
  Future<String?> _pickAndCompress(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: source,
      maxHeight: 450,         // <— exact height target
      imageQuality: 100,      // no quality loss at this stage
    );
    if (x == null) return null;

    // Compress for upload size, keep orientation correct
    Uint8List raw = await x.readAsBytes();
    Uint8List out = await FlutterImageCompress.compressWithList(
      raw,
      quality: 88,
      format: CompressFormat.jpeg,
      autoCorrectionAngle: true,
      keepExif: false,
    );

    // Keep under ~<= 250KB if possible
    const int targetBytes = 250 * 1024;
    int q = 80;
    while (out.length > targetBytes && q >= 40) {
      out = await FlutterImageCompress.compressWithList(
        out,
        format: CompressFormat.jpeg,
        quality: q,
      );
      q -= 10;
    }

    final tmp = await getTemporaryDirectory();
    final path = '${tmp.path}/exp_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(out, flush: true);
    return path;
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
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          filePath,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200) {
      _showSnack('Upload failed (${resp.statusCode})');
      return null;
    }
    final map = _safeJson(body);
    final ok = (map?['success'] == true) || (map?['status'] == true);
    if (map == null || !ok) {
      _showSnack((map?['message'] ?? 'Upload failed').toString());
      return null;
    }
    if (map['uploaded_files'] is List && map['uploaded_files'].isNotEmpty) {
      return map['uploaded_files'][0].toString();
    }
    _showSnack('No file name returned');
    return null;
  }

  // ------------------------- Add line (stateful bottom sheet) -------------------------
  Future<void> _addExpenseDialog() async {
    if (_heads.isEmpty) {
      _showSnack('No expense heads loaded');
      return;
    }

    final formKey = GlobalKey<FormState>();
    ExpenseHead? selHead;
    final rateCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    String? localPath;
    String? serverFile;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> _pickUpload(ImageSource src) async {
              setState(() => _busy = true);
              setModalState(() {});
              try {
                final lp = await _pickAndCompress(src);
                if (lp == null) return;
                localPath = lp;

                final sf = await _uploadSingle(lp);
                if (sf == null) return;
                serverFile = sf;

                setModalState(() {});
              } catch (e) {
                _showSnack(e.toString());
              } finally {
                if (mounted) {
                  setState(() => _busy = false);
                  setModalState(() {});
                }
              }
            }

            Future<void> _chooseSource() async {
              await showModalBottomSheet(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => SafeArea(
                  child: Wrap(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera),
                        title: const Text('Camera'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _pickUpload(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library),
                        title: const Text('Gallery'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _pickUpload(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add Expense', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 14),

                        const _FieldLabel('Select Expense Head *'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<ExpenseHead>(
                          value: selHead,
                          items: _heads
                              .map((h) => DropdownMenuItem(value: h, child: Text(h.name)))
                              .toList(),
                          onChanged: (v) => selHead = v,
                          validator: (v) => v == null ? 'Required' : null,
                        ),

                        const SizedBox(height: 14),
                        const _FieldLabel('Enter Amount *'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          decoration: _decoration(hint: 'e.g. 150'),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return 'Amount is required';
                            final n = double.tryParse(s);
                            if (n == null || n <= 0) return 'Enter a valid amount';
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),
                        const _FieldLabel('Description'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: descCtrl,
                          maxLines: 2,
                          decoration: _decoration(hint: 'Optional note'),
                        ),

                        const SizedBox(height: 14),
                        const _FieldLabel('Image (height 450px, aspect kept) *'),
                        const SizedBox(height: 8),
                        _ImagePickerTile(
                          title: serverFile == null ? 'Pick & Upload' : 'Replace',
                          localPath: localPath,
                          uploading: _busy,
                          onPick: _chooseSource,
                          requiredHint: true,
                        ),

                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              if (serverFile == null || serverFile!.isEmpty) {
                                _showSnack('Please upload an image');
                                return;
                              }
                              final line = ExpenseLine(
                                item: selHead!.id,
                                itemName: selHead!.name,
                                rate: rateCtrl.text.trim(),
                                imgUrl: serverFile!,
                                description: descCtrl.text.trim(),
                              );
                              setState(() => _lines.add(line));
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add to List'),
                          ),
                        ),
                        const SizedBox(height: 25),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ------------------------- Save -------------------------
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

  Future<void> _save() async {
    if (_lines.isEmpty) {
      _showSnack('Please add at least one expense line');
      return;
    }

    setState(() => _saving = true);
    try {
      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';
      if ((_userId ?? '').isEmpty || (_mob ?? '').isEmpty) throw 'Missing user_id or mob.';

      final pos = await _getPosition();
      if (pos == null) throw 'Location unavailable. Enable GPS & permission.';

      final url = Uri.parse(_endpoint(base, 'exp_save.php?subject=exp&action=save'));

      final payload = {
        'user_id': _userId,
        'mob': _mob,
        'lat': pos.latitude.toString(),
        'lon': pos.longitude.toString(),
        'entry_date': _dateCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'arr': _lines.map((e) => e.toMap()).toList(),
      };

      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';

      final map = _safeJson(resp.body);
      if (map == null) throw 'Invalid JSON from server';
      if (map['status'] == true) {
        _showAnimatedResult(success: true, text: (map['message'] ?? 'Saved Successfully').toString());
        setState(() {
          _lines.clear();
          _descCtrl.clear();
          _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
        });
      } else {
        throw (map['message'] ?? 'Save failed').toString();
      }
    } catch (e) {
      _showAnimatedResult(success: false, text: e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------- UI helpers -------------------------
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day), // disable future
    );
    if (selected != null) {
      final yyyy = selected.year.toString().padLeft(4, '0');
      final mm = selected.month.toString().padLeft(2, '0');
      final dd = selected.day.toString().padLeft(2, '0');
      _dateCtrl.text = '$yyyy-$mm-$dd';
      setState(() {});
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

  void _removeLine(int i) => setState(() => _lines.removeAt(i));

  void _showAnimatedResult({required bool success, required String text}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'result',
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, __, ___) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Transform.scale(
          scale: scale.value,
          child: Opacity(
            opacity: anim.value,
            child: Center(
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(blurRadius: 20, spreadRadius: 4, color: Colors.black12)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(success ? Icons.check_circle : Icons.error, size: 64, color: success ? Colors.green : Colors.red),
                    const SizedBox(height: 12),
                    Text(success ? 'Success' : 'Failed', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(text, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: () => Navigator.of(ctx).maybePop(), child: const Text('OK')),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------- BUILD -------------------------
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF104270),
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Expense', style: TextStyle(color: Colors.white)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text('Save', style: TextStyle(color: Colors.white)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
          floatingActionButton: _loadingInit
              ? null
              : FloatingActionButton.extended(
            onPressed: _addExpenseDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Expense'),
          ),
          body: _loadingInit
              ? const Center(child: CircularProgressIndicator())
              : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Expense Date'),
                const SizedBox(height: 6),
                TextField(
                  controller: _dateCtrl,
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

                const _FieldLabel('Description'),
                const SizedBox(height: 6),
                TextField(
                  controller: _descCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: _decoration(hint: 'Optional overall description'),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: _lines.isEmpty
                      ? const Center(child: Text('No expenses added yet. Tap "Add Expense".'))
                      : ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final it = _lines[i];
                      return Dismissible(
                        key: ValueKey('line_$i'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _removeLine(i),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black12)],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                child: Text(it.itemName.isNotEmpty ? it.itemName[0].toUpperCase() : '?'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.itemName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₹ ${it.rate} • ${it.description.isEmpty ? 'No description' : it.description}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text('img: ${it.imgUrl}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                ),
                              ),
                              IconButton(onPressed: () => _removeLine(i), icon: const Icon(Icons.close)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),

        // Global progress overlays
        if (_busy)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.black.withOpacity(0.25),
                child: const Center(
                  child: SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3)),
                ),
              ),
            ),
          ),
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
                        BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3)),
                        SizedBox(height: 12),
                        Text('Saving your entry…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('Please hold on a moment.', style: TextStyle(color: Colors.black54)),
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
}

// ============================ WIDGETS ============================
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87));
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
        key: ValueKey(localPath),
        width: 90,
        height: 70,
        fit: BoxFit.cover,
        cacheWidth: 180,
        cacheHeight: 140,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6))
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
