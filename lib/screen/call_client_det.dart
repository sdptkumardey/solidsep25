// call_client_det.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidplyaug25/globals.dart' as globals;

import 'call_client_add.dart';                // add/edit screen
import 'call_client_select_stage.dart';       // stage select (args + screen)

class ClientDetailArgs {
  final int clientId;
  final String? name;
  ClientDetailArgs({required this.clientId, this.name});
}

class ClientDetailScreen extends StatefulWidget {
  static const String id = '/calls/client-det';
  const ClientDetailScreen({super.key});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  bool _loading = true;
  String? _error;

  int _clientId = 0;
  bool _didInit = false;

  // client_data (single)
  String clientType = '';
  String companyName = '';
  String name = '';
  String mobile = '';
  String address = '';
  String city = '';
  String pin = '';

  // ms_call list
  List<_CallItem> calls = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ClientDetailArgs) {
      _clientId = args.clientId;
      // optional: prefill name from args if you want immediate header
      if (args.name != null && args.name!.isNotEmpty) name = args.name!;
    } else if (args is Map) {
      _clientId = int.tryParse('${args['clientId']}') ?? 0;
    }
    _fetchDetail();
  }

  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _endpoint(String base, String fileWithQuery) {
    final hasNative =
        RegExp(r'/native_app/?$').hasMatch(base) || base.contains('/native_app/');
    final root = hasNative ? base : '$base/native_app';
    return '$root/$fileWithQuery';
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      final url = Uri.parse(
          _endpoint(base, 'call_client_call_det.php?subject=call&action=det'));
      final resp = await http.post(url, body: {
        'user_id': userId,
        'mob': mob,
        'client': '$_clientId',
      });
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';

      final map = jsonDecode(resp.body);
      if (map['status'] != true) throw (map['message'] ?? 'Failed').toString();

      final List<dynamic> clientArr = (map['client_data'] ?? []) as List<dynamic>;
      if (clientArr.isNotEmpty) {
        final d = clientArr.first as Map<String, dynamic>;
        clientType = (d['client_type'] ?? '').toString();
        companyName = (d['company_name'] ?? '').toString();
        name = (d['name'] ?? '').toString();
        mobile = (d['mobile'] ?? '').toString();
        address = (d['address'] ?? '').toString();
        city = (d['city'] ?? '').toString();
        pin = (d['pin'] ?? '').toString();
      }

      final List<dynamic> callArr = (map['ms_call'] ?? []) as List<dynamic>;
      calls = callArr.map((e) => _CallItem.fromJson(e)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editClient() async {
    final changed = await Navigator.pushNamed(
      context,
      AddEditClientScreen.id,
      arguments: AddEditClientArgs.edit(clientId: _clientId),
    );
    if (changed == true) {
      await _fetchDetail();
    }
  }

  Future<void> _launchTel() async {
    if (mobile.isEmpty) return;
    final uri = Uri.parse('tel:$mobile');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchSms() async {
    if (mobile.isEmpty) return;
    final uri = Uri.parse('sms:$mobile');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchWhatsApp() async {
    if (mobile.isEmpty) return;
    final wa = Uri.parse('https://wa.me/$mobile');
    final alt = Uri.parse('whatsapp://send?phone=$mobile');
    if (!await launchUrl(alt, mode: LaunchMode.externalApplication)) {
      await launchUrl(wa, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (name.isNotEmpty)
        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      if (companyName.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(companyName, style: const TextStyle(fontSize: 15)),
      ],
      if (mobile.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Contact: ', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(mobile),
            const Spacer(),
            IconButton(onPressed: _launchTel, icon: const Icon(Icons.call)),
            IconButton(
              onPressed: _launchWhatsApp,
              icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.green),
            ),
            IconButton(onPressed: _launchSms, icon: const Icon(Icons.sms)),
          ],
        ),
      ],
      if (address.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(address),
      ],
      if (city.isNotEmpty || pin.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('City: ${city.isNotEmpty ? city : '-'}'
            '${pin.isNotEmpty ? '   •   Pin: $pin' : ''}'),
      ],
    ];

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Client Details'),
          actions: [
            IconButton(
              tooltip: 'Edit Client',
              onPressed: _loading ? null : _editClient,
              icon: const Icon(Icons.edit),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null
            ? _ErrorState(message: _error!, onRetry: _fetchDetail)
            : RefreshIndicator(
          onRefresh: _fetchDetail,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Details card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E6ED)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...items,
                    const SizedBox(height: 12),
                    if (clientType.isNotEmpty)
                      Text('Client Type: $clientType',
                          style: const TextStyle(color: Colors.black87)),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // + New Call
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      CallClientSelectStageScreen.id,
                      arguments: CallClientSelectStageArgs(
                        clientId: _clientId,   // <-- FIX: use state field
                        clientName: name,      // <-- FIX: use loaded name
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text(' New Call'),
                ),
              ),

              const SizedBox(height: 16),
              const Text('Previous Call Details',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),

              if (calls.isEmpty)
                const Text('No previous calls.')
              else
                ...calls.map((c) => _CallTile(item: c)),
            ],
          ),
        )),
      ),
    );
  }
}

class _CallItem {
  final String id;
  final String callNum;
  final String callDate;
  final String stage;
  final String remarks;
  final String followUpDate;

  _CallItem({
    required this.id,
    required this.callNum,
    required this.callDate,
    required this.stage,
    required this.remarks,
    required this.followUpDate,
  });

  factory _CallItem.fromJson(Map<String, dynamic> j) => _CallItem(
    id: (j['id'] ?? '').toString(),
    callNum: (j['call_num'] ?? '').toString(),
    callDate: (j['call_date'] ?? '').toString(),
    stage: (j['call_stage'] ?? '').toString(),
    remarks: (j['remarks'] ?? '').toString(),
    followUpDate: (j['follow_up_date'] ?? '').toString(),
  );
}

class _CallTile extends StatelessWidget {
  final _CallItem item;
  const _CallTile({super.key, required this.item});

  Color _stageColor(String s) {
    final t = s.toLowerCase();
    if (t.contains('negotiation')) return const Color(0xFFEF6C00);
    if (t.contains('introduction') || t.contains('intro')) return const Color(0xFF1976D2);
    if (t.contains('follow') || t.contains('pending')) return const Color(0xFF8E24AA);
    if (t.contains('won') || t.contains('closed')) return const Color(0xFF2E7D32);
    if (t.contains('lost') || t.contains('drop')) return const Color(0xFFC62828);
    return const Color(0xFF546E7A);
  }

  @override
  Widget build(BuildContext context) {
    final stageClr = _stageColor(item.stage);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xE0E8EDF3), width: 1),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF9FCFF), Color(0xFFFFFFFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Left accent bar
              Positioned.fill(
                left: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: stageClr.withOpacity(0.9),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line 1
                    Text('Call Num : ${item.callNum}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),

                    // Line 2
                    Row(
                      children: [
                        const Icon(Icons.event, size: 18, color: Colors.black54),
                        const SizedBox(width: 6),
                        const Text('Visited : '),
                        Text(item.callDate,
                            style: const TextStyle(
                                fontSize: 13.5, color: Colors.black87)),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Stage chip
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: stageClr.withOpacity(0.10),
                            border: Border.all(color: stageClr.withOpacity(0.35)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.flag_rounded, size: 16, color: stageClr),
                              const SizedBox(width: 6),
                              Text('Stage: ${item.stage}',
                                  style: TextStyle(
                                      color: stageClr,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (item.remarks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.note_alt_outlined,
                              size: 18, color: Colors.black54),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Remarks: ${item.remarks}')),
                        ],
                      ),
                    ],

                    if (item.followUpDate.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              size: 18, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text('Follow Up: ${item.followUpDate}'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }
}
