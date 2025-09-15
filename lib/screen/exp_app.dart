import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solidplyaug25/globals.dart' as globals;

/// ---------- Models ----------
class ExpDetail {
  final String name;
  final String description;
  final String rate; // server sends string
  ExpDetail({required this.name, required this.description, required this.rate});
  factory ExpDetail.fromJson(Map<String, dynamic> j) => ExpDetail(
    name: (j['name'] ?? '').toString(),
    description: (j['description'] ?? '').toString(),
    rate: (j['rate'] ?? '0').toString(),
  );
}

class ExpEntry {
  final String entryDate; // "19/08/2025"
  final String description;
  final String st; // "0"/"1"/...
  final String stName; // "Pending"/"Approved"/"Rejected"
  final List<ExpDetail> details;

  ExpEntry({
    required this.entryDate,
    required this.description,
    required this.st,
    required this.stName,
    required this.details,
  });

  factory ExpEntry.fromJson(Map<String, dynamic> j) => ExpEntry(
    entryDate: (j['entry_date'] ?? '').toString(),
    description: (j['description'] ?? '').toString(),
    st: (j['st'] ?? '').toString(),
    stName: (j['st_name'] ?? '').toString(),
    details: (j['ms_exp_det'] as List? ?? [])
        .map((e) => ExpDetail.fromJson(e))
        .toList(),
  );

  num get total {
    num t = 0;
    for (final d in details) {
      final v = num.tryParse(d.rate.trim()) ?? 0;
      t += v;
    }
    return t;
  }
}

/// ---------- Screen ----------
class ExpApp extends StatefulWidget {
  static const String id = 'exp_app';
  const ExpApp({super.key});

  @override
  State<ExpApp> createState() => _ExpAppState();
}

class _ExpAppState extends State<ExpApp> {
  bool _loading = true;
  String? _error;
  List<ExpEntry> _items = [];

  // Last request/response for on-screen debugging
  String? _lastUrl;
  Map<String, String>? _lastFields;
  int? _lastStatus;
  String? _lastBody;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  // ---------- Logger helpers ----------
  void _log(Object? m) => debugPrint('EXP_APP: $m');

  String _clip(String s, {int max = 2000}) =>
      s.length <= max ? s : '${s.substring(0, max)}\n... [clipped ${s.length - max} chars]';

  // ---------- URL helpers ----------
  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    _log('raw ipAddress: "$raw"');
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _endpoint(String base, String fileWithQuery) {
    final hasNative = RegExp(r'/native_app/?$').hasMatch(base) || base.contains('/native_app/');
    final root = hasNative ? base : '$base/native_app';
    return '$root/$fileWithQuery';
  }

  // ---------- API ----------
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      final base = _baseUrl();
      _log('base url resolved: "$base"');
      if (base.isEmpty) throw 'Base URL not set.';

      final endpoint = _endpoint(base, 'exp_st.php?subject=exp&action=init');
      final url = Uri.parse(endpoint);
      final fields = {'user_id': userId, 'mob': mob};

      _lastUrl = endpoint;
      _lastFields = fields;
      _lastStatus = null;
      _lastBody = null;

      _log('POST -> $endpoint');
      _log('POST fields: $fields');

      final resp = await http
          .post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: fields,
      )
          .timeout(const Duration(seconds: 30));

      _lastStatus = resp.statusCode;
      _lastBody = resp.body;

      _log('HTTP ${resp.statusCode}');
      _log('Response body (${resp.body.length} chars):');
      _log(_clip(resp.body));

      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = _safeJson(resp.body);
      if (map == null) throw 'Invalid JSON.';
      if (map['status'] != true) {
        throw (map['message'] ?? 'Failed to load').toString();
      }

      final List list = (map['ms_exp'] as List? ?? []);
      final entries = list.map((e) => ExpEntry.fromJson(e)).toList().cast<ExpEntry>();

      setState(() {
        _items = entries;
      });
    } on TimeoutException {
      _log('ERROR: Request timed out');
      setState(() => _error = 'Network timeout. Please try again.');
    } on SocketException catch (e) {
      _log('ERROR: SocketException $e');
      setState(() => _error = 'Network error: $e');
    } catch (e, st) {
      _log('ERROR: $e');
      _log('STACK: $st');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      _log('JSON decode error: $e');
      return null;
    }
  }

  // ---------- Status UI helpers ----------
  _StatusStyle _styleFor(String stNameRaw) {
    final s = stNameRaw.trim().toLowerCase();
    if (s == 'approved') {
      return _StatusStyle(
        bg: const Color(0xFFEFF7F0),
        stripe: const Color(0xFF2E7D32),
        chipBg: const Color(0xFF2E7D32),
        chipFg: Colors.white,
        icon: Icons.check_circle,
      );
    }
    if (s == 'rejected') {
      return _StatusStyle(
        bg: const Color(0xFFFFF1F1),
        stripe: const Color(0xFFC62828),
        chipBg: const Color(0xFFC62828),
        chipFg: Colors.white,
        icon: Icons.cancel,
      );
    }
    // Pending or others -> Off white
    return _StatusStyle(
      bg: const Color(0xFFFFFCF7),
      stripe: const Color(0xFF9E9E9E),
      chipBg: const Color(0xFF9E9E9E),
      chipFg: Colors.white,
      icon: Icons.hourglass_top,
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF104270),
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Expense Approval', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _fetch);
    }
    if (_items.isEmpty) {
      return const _EmptyView();
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        itemBuilder: (_, i) =>
            _ExpenseCard(entry: _items[i], style: _styleFor(_items[i].stName)),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: _items.length,
      ),
    );
  }

  void _showDebugDialog() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 13.0, color: Colors.black87),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last Request',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('URL:\n${_lastUrl ?? '(none)'}'),
                  const SizedBox(height: 8),
                  Text('Fields:\n${_lastFields ?? {}}'),
                  const Divider(height: 18),
                  const Text('Last Response',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Status: ${_lastStatus ?? '(none)'}'),
                  const SizedBox(height: 8),
                  Text('Body:\n${_lastBody ?? '(none)'}'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ---------- Pretty, compact card for each entry ----------
class _ExpenseCard extends StatelessWidget {
  final ExpEntry entry;
  final _StatusStyle style;

  const _ExpenseCard({required this.entry, required this.style});

  @override
  Widget build(BuildContext context) {
    const stripeW = 4.0;
    final total = entry.total;

    // Card content (padded so the left stripe can sit above it)
    final content = Container(
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.stripe.withOpacity(0.20)),
      ),
      child: Padding(
        // extra left padding so text doesn't sit under the stripe
        padding: const EdgeInsets.fromLTRB(10 + stripeW + 6, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: date + status chip
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14),
                const SizedBox(width: 6),
                Text(
                  entry.entryDate,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Icon(style.icon, size: 14, color: style.chipFg),
                      const SizedBox(width: 5),
                      Text(
                        entry.stName,
                        style: TextStyle(
                          color: style.chipFg,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Description (if any)
            if (entry.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                entry.description.trim(),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF444A57)),
              ),
            ],

            const SizedBox(height: 8),

            // Details rows + total in trailing small chip
            Row(
              children: [
                const Text('Details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('₹ ${_fmtNum(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                )
              ],
            ),

            const SizedBox(height: 6),

            // Details list (dense)
            Column(
              children: [
                for (int i = 0; i < entry.details.length; i++) ...[
                  _DetailRow(detail: entry.details[i]),
                  if (i != entry.details.length - 1)
                    const Divider(height: 10, thickness: 0.6, color: Color(0xFFE6E9EE)),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    // Left stripe pinned from top to bottom (no infinite height issues)
    final stripe = Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: stripeW,
      child: Container(
        decoration: BoxDecoration(
          color: style.stripe,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        content,
        stripe,
      ],
    );
  }

  static String _fmtNum(num n) {
    if (n % 1 == 0) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }
}

class _DetailRow extends StatelessWidget {
  final ExpDetail detail;
  const _DetailRow({required this.detail});

  @override
  Widget build(BuildContext context) {
    final hasDesc = detail.description.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2), // tight
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One-line: name + amount
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹ ${detail.rate}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.0),
              ),
            ],
          ),
          if (hasDesc)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail.description,
                style: const TextStyle(color: Colors.black54, fontSize: 12.0),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final FutureOr<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 30, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87, fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No expenses to show.',
          style: TextStyle(color: Colors.black54, fontSize: 13.5)),
    );
  }
}

class _StatusStyle {
  final Color bg;
  final Color stripe;
  final Color chipBg;
  final Color chipFg;
  final IconData icon;
  _StatusStyle({
    required this.bg,
    required this.stripe,
    required this.chipBg,
    required this.chipFg,
    required this.icon,
  });
}
