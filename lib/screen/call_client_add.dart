// call_client_add.dart  (Add + Edit in one screen)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidplyaug25/globals.dart' as globals;

import 'call_client_det.dart'; // for ClientDetailScreen + ClientDetailArgs

class AddEditClientArgs {
  final String mode; // 'add' or 'edit'
  final int? clientId;

  AddEditClientArgs.add() : mode = 'add', clientId = null;
  AddEditClientArgs.edit({required this.clientId}) : mode = 'edit';
}

class AddEditClientScreen extends StatefulWidget {
  static const String id = 'AddEditClientScreen';

  const AddEditClientScreen({super.key});

  @override
  State<AddEditClientScreen> createState() => _AddEditClientScreenState();
}

class _AddEditClientScreenState extends State<AddEditClientScreen> {
  final _formKey = GlobalKey<FormState>();

  // dropdowns
  final List<String> _clientTypes = const [
    'Architect',
    'Contractor',
    'Interior Designer',
    'Carpenter',
    'Consumer',
    'Distributor',
    'Sub Dealer',
    'Third Party',
  ];
  String? _selectedClientType;

  List<_StateItem> _states = [];
  String? _selectedStateId;

  // controllers
  final _companyNameCtrl = TextEditingController();
  final _nameCtrl        = TextEditingController();
  final _mobileCtrl      = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _pinCtrl         = TextEditingController();
  final _gstinCtrl       = TextEditingController();
  final _bankNameCtrl    = TextEditingController();
  final _bankBranchCtrl  = TextEditingController();
  final _ifscCtrl        = TextEditingController();
  final _acNoCtrl        = TextEditingController();

  bool _loading = true;
  bool _saving  = false;
  String? _error;

  late AddEditClientArgs _args;
  bool _didInit = false; // prevents reloading on every rebuild

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final a = ModalRoute.of(context)?.settings.arguments;
    _args = (a is AddEditClientArgs) ? a : AddEditClientArgs.add();
    _loadInit();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _pinCtrl.dispose();
    _gstinCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankBranchCtrl.dispose();
    _ifscCtrl.dispose();
    _acNoCtrl.dispose();
    super.dispose();
  }

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

      if (_args.mode == 'edit' && (_args.clientId ?? 0) > 0) {
        // EDIT: load values + states
        final url = Uri.parse(_endpoint(base, 'call_client_edit_load.php?subject=call&action=load'));
        final resp = await http.post(url, body: {
          'user_id': userId,
          'mob': mob,
          'client': (_args.clientId!).toString(),
        });
        if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
        final map = jsonDecode(resp.body);
        if (map['status'] != true) throw (map['message'] ?? 'Failed').toString();

        final List<dynamic> stateArr = (map['ms_state'] ?? []) as List<dynamic>;
        _states = stateArr
            .map((e) => _StateItem(id: (e['id'] ?? '').toString(), name: (e['name'] ?? '').toString()))
            .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
            .toList();

        final List<dynamic> cArr = (map['client_data'] ?? []) as List<dynamic>;
        if (cArr.isNotEmpty) {
          final d = cArr.first as Map<String, dynamic>;
          _selectedClientType = (d['client_type'] ?? '').toString().isEmpty
              ? null
              : (d['client_type'] ?? '').toString();
          _companyNameCtrl.text = (d['company_name'] ?? '').toString();
          _nameCtrl.text        = (d['name'] ?? '').toString();
          _mobileCtrl.text      = (d['mobile'] ?? '').toString();
          _addressCtrl.text     = (d['address'] ?? '').toString();
          _cityCtrl.text        = (d['city'] ?? '').toString();
          _pinCtrl.text         = (d['pin'] ?? '').toString();
          _gstinCtrl.text       = (d['gstin'] ?? '').toString();
          _bankNameCtrl.text    = (d['bank_name'] ?? '').toString();
          _bankBranchCtrl.text  = (d['bank_branch'] ?? '').toString();
          _ifscCtrl.text        = (d['ifsc'] ?? '').toString();
          _acNoCtrl.text        = (d['ac_no'] ?? '').toString();

          _selectedStateId      = (d['state'] ?? '').toString().isEmpty ? null : (d['state'] ?? '').toString();
        }

        if (_states.isNotEmpty &&
            (_selectedStateId == null || !_states.any((s) => s.id == _selectedStateId))) {
          _selectedStateId = _states.first.id;
        }
      } else {
        // ADD: load states only
        final url = Uri.parse(_endpoint(base, 'call_client_init.php?subject=call&action=init'));
        final resp = await http.post(url, body: {'user_id': userId, 'mob': mob});
        if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
        final map = jsonDecode(resp.body);
        if (map['status'] != true) throw (map['message'] ?? 'Failed').toString();

        final List<dynamic> arr = (map['ms_state'] ?? []) as List<dynamic>;
        _states = arr
            .map((e) => _StateItem(id: (e['id'] ?? '').toString(), name: (e['name'] ?? '').toString()))
            .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
            .toList();

        if (_states.isNotEmpty) {
          _selectedStateId = _states.first.id;
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClientType == null) {
      _showSnack('Please select Client Type');
      return;
    }
    if (_selectedStateId == null || _selectedStateId!.isEmpty) {
      _showSnack('Please select State');
      return;
    }

    setState(() => _saving = true);

    try {
      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob    = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      final url = Uri.parse(_endpoint(base, 'call_client_add_edit.php?subject=call&action=save'));
      final body = {
        'user_id'     : userId,
        'mob'         : mob,
        'type'        : _args.mode == 'edit' ? 'edit' : 'add',
        'id'          : _args.mode == 'edit' ? (_args.clientId?.toString() ?? '') : '',
        'name'        : _nameCtrl.text.trim(),
        'mobile'      : _mobileCtrl.text.trim(),
        'address'     : _addressCtrl.text.trim(),
        'city'        : _cityCtrl.text.trim(),
        'pin'         : _pinCtrl.text.trim(),
        'state'       : _selectedStateId!,
        'gstin'       : _gstinCtrl.text.trim(),
        'bank_name'   : _bankNameCtrl.text.trim(),
        'bank_branch' : _bankBranchCtrl.text.trim(),
        'ifsc'        : _ifscCtrl.text.trim(),
        'ac_no'       : _acNoCtrl.text.trim(),
        'company_name': _companyNameCtrl.text.trim(),
        'client_type' : _selectedClientType!,
      };

      final resp = await http.post(url, body: body);
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = jsonDecode(resp.body);

      if (map['status'] == true) {
        // API now returns: { "status": true, "message": "...", "id": "48750" }
        int? targetId;
        final dynamic idVal = map['id'];
        if (idVal != null) {
          if (idVal is int) {
            targetId = idVal;
          } else {
            targetId = int.tryParse(idVal.toString());
          }
        }
        // Fallback for edit (in case id isn't returned)
        targetId ??= _args.clientId;

        if (!mounted) return;

        if (targetId != null && targetId > 0) {
          // Go straight to details with the specific id
          Navigator.pushReplacementNamed(
            context,
            ClientDetailScreen.id,
            arguments: ClientDetailArgs(clientId: targetId, name: _nameCtrl.text.trim()),
          );
        } else {
          // If somehow no id, just show a message and pop
          _showSnack(map['message']?.toString() ?? 'Saved Successfully');
          Navigator.pop(context, true);
        }
      } else {
        throw (map['message'] ?? 'Save failed').toString();
      }
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final isEdit = _args.mode == 'edit';
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Client' : 'New Client')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
          ? _ErrorState(message: _error!, onRetry: _loadInit)
          : _buildForm()),
    );
  }

  Widget _buildForm() {
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FieldLabel('Client Type :'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedClientType,
              items: _clientTypes
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedClientType = v),
              decoration: _decoration(),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            _FieldLabel('Company Name :'),
            const SizedBox(height: 6),
            TextFormField(controller: _companyNameCtrl, decoration: _decoration()),
            const SizedBox(height: 14),

            _FieldLabel('Client Name :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration: _decoration(),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            _FieldLabel('Client Contact :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _mobileCtrl,
              decoration: _decoration(hint: 'Max 12 digits'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return 'Required';
                if (!RegExp(r'^\d{1,12}$').hasMatch(s)) return 'Only numbers, max 12 digits';
                return null;
              },
            ),
            const SizedBox(height: 14),

            _FieldLabel('Address :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _addressCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: _decoration(),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            _FieldLabel('City :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _cityCtrl,
              decoration: _decoration(),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            _FieldLabel('PIN Code :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _pinCtrl,
              decoration: _decoration(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 14),

            _FieldLabel('State :'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedStateId,
              items: _states
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedStateId = v),
              decoration: _decoration(),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),

            _FieldLabel('GSTIN :'),
            const SizedBox(height: 6),
            TextFormField(controller: _gstinCtrl, decoration: _decoration()),
            const SizedBox(height: 14),

            _FieldLabel('Bank Name :'),
            const SizedBox(height: 6),
            TextFormField(controller: _bankNameCtrl, decoration: _decoration()),
            const SizedBox(height: 14),

            _FieldLabel('Branch :'),
            const SizedBox(height: 6),
            TextFormField(controller: _bankBranchCtrl, decoration: _decoration()),
            const SizedBox(height: 14),

            _FieldLabel('IFSC Details :'),
            const SizedBox(height: 6),
            TextFormField(controller: _ifscCtrl, decoration: _decoration()),
            const SizedBox(height: 14),

            _FieldLabel('A/C No :'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _acNoCtrl,
              decoration: _decoration(),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      ),
    );
  }
}

class _StateItem {
  final String id;
  final String name;
  _StateItem({required this.id, required this.name});
}
