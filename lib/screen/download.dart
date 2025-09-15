import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solidplyaug25/globals.dart' as globals;

/// ----- Model -----
class DownloadItem {
  final String id;
  final String name;
  final String url; // absolute url from server

  DownloadItem({required this.id, required this.name, required this.url});

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    url: (j['img_url'] ?? '').toString(),
  );
}

/// ----- Screen -----
class Download extends StatefulWidget {
  static const String id = 'download';
  const Download({super.key});

  @override
  State<Download> createState() => _DownloadState();
}

class _DownloadState extends State<Download> {
  bool _loading = true;
  String? _error;
  List<DownloadItem> _items = [];

  // per-item progress (0..1)
  final Map<String, double> _progress = {};

  // debug
  String? _lastUrl;
  Map<String, String>? _lastFields;
  int? _lastStatus;
  String? _lastBody;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _log(Object? m) => debugPrint('DOWNLOADS: $m');

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

  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

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
      if (base.isEmpty) throw 'Base URL not set.';

      final endpoint =
      _endpoint(base, 'download_load.php?subject=exp&action=init');
      final url = Uri.parse(endpoint);
      final fields = {'user_id': userId, 'mob': mob};

      _lastUrl = endpoint;
      _lastFields = fields;
      _lastStatus = null;
      _lastBody = null;

      _log('POST -> $endpoint');
      _log('fields: $fields');

      final resp = await http
          .post(url,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: fields)
          .timeout(const Duration(seconds: 30));

      _lastStatus = resp.statusCode;
      _lastBody = resp.body;
      _log('HTTP ${resp.statusCode}');

      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = _safeJson(resp.body);
      if (map == null) throw 'Invalid JSON';
      if (map['status'] != true) {
        throw (map['message'] ?? 'Failed to load').toString();
      }

      final List list = (map['ms_item'] as List? ?? []);
      final items = list.map((e) => DownloadItem.fromJson(e)).toList();

      setState(() => _items = items);
    } on TimeoutException {
      setState(() => _error = 'Network timeout. Please try again.');
    } on SocketException catch (e) {
      setState(() => _error = 'Network error: $e');
    } catch (e, st) {
      _log('ERROR: $e\n$st');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _localPathForUrl(String url) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'downloads'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    String filename = Uri.tryParse(url)?.pathSegments.last ?? 'file.pdf';
    if (!filename.toLowerCase().endsWith('.pdf')) {
      filename = '$filename.pdf';
    }
    filename = filename.replaceAll(RegExp(r'[^\w\-.]+'), '_');
    return p.join(dir.path, filename);
  }

  Future<File> _downloadToFile(String url, String savePath, String itemId) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);

      if (resp.statusCode != 200) {
        throw 'Download failed: HTTP ${resp.statusCode}';
      }

      final contentLen = resp.contentLength ?? 0;
      int received = 0;

      final file = File(savePath);
      final sink = file.openWrite();

      await resp.stream.listen(
            (chunk) {
          sink.add(chunk);
          if (contentLen > 0) {
            received += chunk.length;
            setState(() => _progress[itemId] = received / contentLen);
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
        },
        onError: (err) async {
          await sink.flush();
          await sink.close();
          if (await file.exists()) {
            await file.delete();
          }
          throw err;
        },
        cancelOnError: true,
      ).asFuture();

      setState(() => _progress.remove(itemId));
      return file;
    } finally {
      client.close();
    }
  }

  Future<void> _openExternally(File f) async {
    // Hint the MIME; many viewers (Acrobat, Drive, etc.) will pick this up
    final result = await OpenFilex.open(f.path, type: 'application/pdf');
    if (result.type != ResultType.done) {
      throw 'Open failed: ${result.message}';
    }
  }

  Future<void> _openItem(DownloadItem item) async {
    try {
      final savePath = await _localPathForUrl(item.url);
      File f = File(savePath);

      if (!await f.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloading "${item.name}"…')),
        );
        f = await _downloadToFile(item.url, savePath, item.id);
      }

      await _openExternally(f);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
      setState(() => _progress.remove(item.id));
    }
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
              style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last Request',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('URL:\n${_lastUrl ?? '(none)'}'),
                  const SizedBox(height: 8),
                  Text('Fields:\n${_lastFields ?? {}}'),
                  const Divider(height: 22),
                  const Text('Last Response',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF104270),
          iconTheme: const IconThemeData(color: Colors.white),
          title:
          const Text('Downloads', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'Debug',
              icon: const Icon(Icons.bug_report, color: Colors.white),
              onPressed: _showDebugDialog,
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loading ? null : _fetch,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 34, color: Colors.red),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
          child:
          Text('No files found', style: TextStyle(color: Colors.black54)));
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final it = _items[i];
          final prog = _progress[it.id];

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E8EE)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
              ],
            ),
            child: ListTile(
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF104270).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFF104270)),
              ),
              title: Text(it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(it.url,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: prog == null
                  ? ElevatedButton.icon(
                onPressed: () => _openItem(it),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )
                  : SizedBox(
                width: 84,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        value: prog.isFinite ? prog : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${((prog) * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              onTap: prog == null ? () => _openItem(it) : null,
            ),
          );
        },
      ),
    );
  }
}
