// call_client_list.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidplyaug25/globals.dart' as globals;

import 'call_client_det.dart';

class ExistingClientScreen extends StatefulWidget {
  static const String id = 'call_client_list';
  const ExistingClientScreen({super.key});

  @override
  State<ExistingClientScreen> createState() => _ExistingClientScreenState();
}

class _ExistingClientScreenState extends State<ExistingClientScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  List<_ClientItem> _all = [];
  List<_ClientItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _fetchClients();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  Future<void> _fetchClients() async {
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

      final url = Uri.parse(_endpoint(base, 'call_client_load.php?subject=call&action=load'));
      final resp = await http.post(url, body: {'user_id': userId, 'mob': mob});
      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';

      final map = jsonDecode(resp.body);
      if (map['status'] != true) throw (map['message'] ?? 'Failed').toString();

      final List<dynamic> arr = (map['ms_client'] ?? []) as List<dynamic>;
      _all = arr.map((e) => _ClientItem.fromJson(e)).toList();
      _filtered = List.of(_all);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List.of(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((c) {
        return (c.name.toLowerCase().contains(q)) ||
            (c.mobile.toLowerCase().contains(q)) ||
            (c.address.toLowerCase().contains(q)) ||
            (c.city.toLowerCase().contains(q)) ||
            ('${c.id}'.contains(q));
      }).toList();
    });
  }

  Future<void> _openClient(_ClientItem c) async {
    await Navigator.pushNamed(
      context,
      ClientDetailScreen.id,
      arguments: ClientDetailArgs(clientId: c.id, name: c.name),
    );
    // Optional: refresh after return
    // await _fetchClients();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Existing Clients')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name / mobile / city / address',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null
                ? _ErrorState(message: _error!, onRetry: _fetchClients)
                : RefreshIndicator(
              onRefresh: _fetchClients,
              child: _filtered.isEmpty
                  ? const Center(child: Text('No clients found'))
                  : ListView.separated(
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = _filtered[i];
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.mobile.isNotEmpty) Text(c.mobile),
                        if (c.address.isNotEmpty || c.city.isNotEmpty)
                          Text(
                            [c.address, c.city].where((x) => x.isNotEmpty).join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openClient(c),
                  );
                },
              ),
            )),
          ),
        ],
      ),
    );
  }
}

class _ClientItem {
  final int id;
  final String name;
  final String mobile;
  final String address;
  final String city;

  _ClientItem({
    required this.id,
    required this.name,
    required this.mobile,
    required this.address,
    required this.city,
  });

  factory _ClientItem.fromJson(Map<String, dynamic> j) => _ClientItem(
    id: (j['id'] is int) ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
    name: (j['name'] ?? '').toString(),
    mobile: (j['mobile'] ?? '').toString(),
    address: (j['address'] ?? '').toString(),
    city: (j['city'] ?? '').toString(),
  );
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
