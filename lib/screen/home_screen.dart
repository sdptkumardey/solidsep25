// home_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'attendance_service.dart';
import 'app_drawer.dart';
import 'call_client_det.dart';
import 'call_manage.dart';
import 'check_in_screen.dart';
import 'download.dart';
import 'route_observer.dart'; // RouteObserver<PageRoute>
import 'package:solidplyaug25/globals.dart' as globals; // for base url

// ---------- Models for Home Dashboard ----------
class StageStat {
  final String stage;
  final int num;
  StageStat({required this.stage, required this.num});
  factory StageStat.fromJson(Map<String, dynamic> j) => StageStat(
    stage: (j['stage'] ?? '').toString(),
    num: int.tryParse((j['num'] ?? '0').toString()) ?? 0,
  );
}

class FollowupItem {
  final String client;
  final String callEntry;
  final String companyName;
  final String name;
  final String mobile;
  final String followUpDate;
  FollowupItem({
    required this.client,
    required this.callEntry,
    required this.companyName,
    required this.name,
    required this.mobile,
    required this.followUpDate,
  });
  factory FollowupItem.fromJson(Map<String, dynamic> j) => FollowupItem(
    client: (j['client'] ?? '').toString(),
    callEntry: (j['call_entry'] ?? '').toString(),
    companyName: (j['company_name'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    mobile: (j['mobile'] ?? '').toString(),
    followUpDate: (j['follow_up_date'] ?? '').toString(),
  );
}

class HomeScreen extends StatefulWidget {
  static String id = 'home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  String _name = '';
  String _mob = '';
  bool _loading = true;
  bool _attendancePending = true;

  // Check-in details
  String _attImgFile = '';
  String _attDateTime = '';
  String _attLat = '';
  String _attLon = '';

  // Check-out details
  String _outDateTime = '';
  String _outLat = '';
  String _outLon = '';

  // Dashboard (stages + followups)
  bool _dashLoading = false;
  String? _dashError;
  List<StageStat> _stages = [];
  List<FollowupItem> _followups = [];

  // Debug for dashboard request
  String? _lastDashUrl;
  Map<String, String>? _lastDashFields;
  int? _lastDashStatus;
  String? _lastDashBody;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when a pushed route above this one is popped (we came back).
  @override
  void didPopNext() {
    _refreshAttendance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAttendance();
    }
  }

  Future<void> _boot() async {
    await _loadUser();
    await _refreshAttendance();
    // If user already checked in, load dashboard immediately
    if (!_attendancePending) {
      _fetchHomeDashboard();
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('name') ?? '';
      _mob = prefs.getString('mob') ?? '';
    });
  }

  Future<void> _loadAttendanceDetail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _attImgFile = prefs.getString('att_img_url') ?? '';
      _attDateTime = prefs.getString('att_send_date_time') ?? '';
      _attLat = prefs.getString('att_lat') ?? '';
      _attLon = prefs.getString('att_lon') ?? '';
    });
  }

  Future<void> _loadCheckoutDetail() async {
    final out = await AttendanceService.instance.loadTodayCheckoutDetail();
    setState(() {
      _outDateTime = out['dt'] ?? '';
      _outLat = out['lat'] ?? '';
      _outLon = out['lon'] ?? '';
    });
  }

  Future<void> _refreshAttendance() async {
    setState(() => _loading = true);
    final pending = await AttendanceService.instance.isTodayPending();
    if (!mounted) return;

    _attendancePending = pending;

    if (!pending) {
      await _loadAttendanceDetail();
      await _loadCheckoutDetail();
    } else {
      // If pending, clear last shown details in UI (optional)
      setState(() {
        _attImgFile = '';
        _attDateTime = '';
        _attLat = '';
        _attLon = '';
        _outDateTime = '';
        _outLat = '';
        _outLon = '';
        // Also clear dashboard when pending
        _stages = [];
        _followups = [];
        _dashError = null;
      });
    }

    setState(() => _loading = false);
  }

  // ---------- URL helpers ----------
  String _baseUrl() {
    final raw = globals.ipAddress.trim();
    debugPrint('HOME: raw ipAddress: "$raw"');
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _endpoint(String base, String fileWithQuery) {
    final hasNative = RegExp(r'/native_app/?$').hasMatch(base) || base.contains('/native_app/');
    final root = hasNative ? base : '$base/native_app';
    return '$root/$fileWithQuery';
  }

  String _imageUrlFromFile(String file) {
    if (file.isEmpty) return '';
    final base = _baseUrl();
    // Files live in /att_img at project root (same level as native_app)
    return '$base/att_img/$file';
  }

  Future<void> _openMap(String lat, String lon) async {
    if (lat.isEmpty || lon.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* ignore */}
  }

  // --- Actions below card ---
  void _openManageCalls() async {
    try {
      await Navigator.pushNamed(context, CallManage.id);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route "manage_calls" not found. Wire it up to navigate.')),
      );
    }
  }

  void _openDownloads() async {
    try {
      await Navigator.pushNamed(context, Download.id);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route "downloads" not found. Wire it up to navigate.')),
      );
    }
  }

  // ---------- Dashboard API: stages + followups ----------
  Future<void> _fetchHomeDashboard() async {
    setState(() {
      _dashLoading = true;
      _dashError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';
      if (userId.isEmpty || mob.isEmpty) throw 'Missing user_id or mob.';

      final base = _baseUrl();
      if (base.isEmpty) throw 'Base URL not set.';

      final endpoint = _endpoint(base, 'index_st.php?subject=home&action=init');
      final url = Uri.parse(endpoint);
      final fields = {'user_id': userId, 'mob': mob};

      _lastDashUrl = endpoint;
      _lastDashFields = fields;
      _lastDashStatus = null;
      _lastDashBody = null;

      debugPrint('HOME: POST -> $endpoint');
      debugPrint('HOME: fields: $fields');

      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': 'FlutterApp/1.0',
        },
        body: fields,
      );

      _lastDashStatus = resp.statusCode;
      _lastDashBody = resp.body;

      debugPrint('HOME: HTTP ${resp.statusCode}');
      final clipped = resp.body.length <= 1800
          ? resp.body
          : '${resp.body.substring(0, 1800)}\n... [clipped]';
      debugPrint('HOME: Response body (${resp.body.length} chars):\n$clipped');

      if (resp.statusCode != 200) throw 'Server ${resp.statusCode}';
      final map = _safeJson(resp.body);
      if (map == null) throw 'Invalid JSON.';
      if (map['status'] != true) {
        throw (map['message'] ?? 'Failed to load').toString();
      }

      final List msStage = (map['ms_stage'] as List? ?? []);
      final List msFollow = (map['ms_followup'] as List? ?? []);

      final stages =
      msStage.map((e) => StageStat.fromJson(e)).toList().cast<StageStat>();
      final follows =
      msFollow.map((e) => FollowupItem.fromJson(e)).toList().cast<FollowupItem>();

      setState(() {
        _stages = stages;
        _followups = follows;
      });
    } catch (e) {
      setState(() => _dashError = e.toString());
    } finally {
      if (mounted) setState(() => _dashLoading = false);
    }
  }


  // separated small wrapper to keep analyzer happy
  Future<UriResponse> _post(Uri url, Map<String, String> fields) async {
    final client = HttpClient();
    final req = await client.postUrl(url);
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded; charset=utf-8',
    );
    req.write(Uri(queryParameters: fields).query);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join(); // <-- here
    return UriResponse(statusCode: res.statusCode, body: body);
  }


  Map<String, dynamic>? _safeJson(String body) {
    try {
      return body.isEmpty ? null : (JsonDecoder().convert(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final imgUrl = _imageUrlFromFile(_attImgFile);

    return SafeArea(
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: const Color(0xFF104270),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Row(
            children: [
              if (_name.isNotEmpty)
                Text(_name, style: const TextStyle(color: Colors.white, fontSize: 16.0)),
            ],
          ),
          actions: [
            if (!_attendancePending)
              IconButton(
                tooltip: 'Reload dashboard',
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _dashLoading ? null : _fetchHomeDashboard,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_attendancePending
            ? _PendingAttendanceCard(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckInScreen()),
            );

            // If CheckInScreen returned the details map, update UI immediately
            if (result is Map) {
              if (!mounted) return;
              setState(() {
                _attendancePending = false; // hide pending card
                _attImgFile = (result['img_url'] ?? '').toString();
                _attDateTime = (result['send_date_time'] ?? '').toString();
                _attLat = (result['lat'] ?? '').toString();
                _attLon = (result['lon'] ?? '').toString();
              });
              await _loadCheckoutDetail();
              // Now fetch dashboard
              await _fetchHomeDashboard();
            } else if (result == true) {
              // Fallback: in case you still return true
              await _refreshAttendance();
              if (!_attendancePending) {
                await _fetchHomeDashboard();
              }
            }
          },
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CheckedInCard(
                    name: _name,
                    dateTime: _attDateTime,
                    imageUrl: imgUrl,
                    lat: _attLat,
                    lon: _attLon,
                    onViewMap: () => _openMap(_attLat, _attLon),
                    outDateTime: _outDateTime,
                    outLat: _outLat,
                    outLon: _outLon,
                    onViewOutMap: () => _openMap(_outLat, _outLon),
                  ),
                  const SizedBox(height: 20),
                  _InlineActionButtons(
                    onManageCalls: _openManageCalls,
                    onDownloads: _openDownloads,
                  ),
                  const SizedBox(height: 14),

                  // ----- DASHBOARD -----
                  if (_dashLoading) ...[
                    const _SectionHeader(title: 'Dashboard'),
                    const SizedBox(height: 8),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 6),
                  ] else if (_dashError != null) ...[
                    const _SectionHeader(title: 'Dashboard'),
                    const SizedBox(height: 8),
                    _ErrorBox(
                      message: _dashError!,
                      onRetry: _fetchHomeDashboard,
                    ),
                  ] else ...[
                    if (_stages.isNotEmpty) ...[
                      const _SectionHeader(title: 'Stages'),
                      const SizedBox(height: 8),
                      _StagesTable(stages: _stages),
                      const SizedBox(height: 14),
                    ],
                    const _SectionHeader(title: 'Follow-ups'),
                    const SizedBox(height: 8),
                    _FollowupsList(items: _followups),
                  ],
                ],
              ),
            ),
          ),
        )),
      ),
    );
  }
}

// ---------- Small helpers ----------
class UriResponse {
  final int statusCode;
  final String body;
  UriResponse({required this.statusCode, required this.body});
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(width: 6),
        Expanded(
          child: Container(height: 1, color: Colors.black12),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorBox({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        border: Border.all(color: const Color(0xFFE57373)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Pending card ----------
class _PendingAttendanceCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PendingAttendanceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF104270), width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.access_time, size: 64),
                SizedBox(height: 12),
                Text(
                  "Today's attendance is pending",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Tap to check in now',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Checked-in card ----------
class _CheckedInCard extends StatelessWidget {
  final String name;
  final String dateTime; // check-in dt (server string)
  final String imageUrl; // selfie
  final String lat; // check-in lat
  final String lon; // check-in lon
  final VoidCallback onViewMap;

  // checkout details
  final String outDateTime; // dd/MM/yy HH:mm (or server)
  final String outLat;
  final String outLon;
  final VoidCallback onViewOutMap;

  const _CheckedInCard({
    required this.name,
    required this.dateTime,
    required this.imageUrl,
    required this.lat,
    required this.lon,
    required this.onViewMap,
    required this.outDateTime,
    required this.outLat,
    required this.outLon,
    required this.onViewOutMap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF104270), width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasImage
                    ? Image.network(
                  imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                )
                    : Container(
                  width: 72,
                  height: 72,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Icon(Icons.person, size: 40),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    if (dateTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              dateTime,
                              style: const TextStyle(fontSize: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (lat.isNotEmpty && lon.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: onViewMap,
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Map (Check-in)', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Divider + CHECKOUT LINE (if available)
          if (outDateTime.isNotEmpty || (outLat.isNotEmpty && outLon.isNotEmpty)) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.logout, size: 18, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outDateTime.isNotEmpty ? "Check Out: $outDateTime" : "Check Out: —",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (outLat.isNotEmpty && outLon.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: onViewOutMap,
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('Map', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline action buttons (directly below the attendance card)
class _InlineActionButtons extends StatelessWidget {
  final VoidCallback onManageCalls;
  final VoidCallback onDownloads;

  const _InlineActionButtons({
    required this.onManageCalls,
    required this.onDownloads,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onManageCalls,
            icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
            label: const Text('Manage Calls'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6A5AE0), // violet/indigo
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onDownloads,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('Downloads'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA6), // teal/green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Stages compact wrap ----------
class _StagesWrap extends StatelessWidget {
  final List<StageStat> stages;
  const _StagesWrap({required this.stages});

  @override
  Widget build(BuildContext context) {
    // A few pleasant colors to rotate
    const colors = <Color>[
      Color(0xFF2962FF), // blue
      Color(0xFFFF6D00), // orange
      Color(0xFF2E7D32), // green
      Color(0xFF6A1B9A), // purple
      Color(0xFF00838F), // teal
      Color(0xFFAD1457), // pink
      Color(0xFF5D4037), // brown
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < stages.length; i++)
          _StagePill(
            label: stages[i].stage,
            count: stages[i].num,
            color: colors[i % colors.length],
          ),
      ],
    );
  }
}

class _StagesTable extends StatelessWidget {
  final List<StageStat> stages;
  const _StagesTable({required this.stages});

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: Colors.black12, width: 0.8),
      columnWidths: const {
        0: FlexColumnWidth(3), // stage name wider
        1: FlexColumnWidth(1), // count narrower
      },
      children: [
        // header row
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFEFEFEF)),
          children: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Stage",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Count",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        // data rows
        for (final s in stages)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(s.stage,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  s.num.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
      ],
    );
  }
}


class _StagePill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StagePill({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------- Follow-ups list ----------
class _FollowupsList extends StatelessWidget {
  final List<FollowupItem> items;
  const _FollowupsList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          border: Border.all(color: const Color(0xFFE4E8EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('No follow-ups', style: TextStyle(color: Colors.black54)),
      );
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        return GestureDetector(
          onTap: (){
            print('click on followup');
            Navigator.pushNamed(
              context,
              ClientDetailScreen.id,
              arguments: ClientDetailArgs(
                clientId: int.tryParse(it.client) ?? 0,
                name: it.companyName,
              ),
            );
     },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE4E8EE)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF104270).withOpacity(0.1),
                foregroundColor: const Color(0xFF104270),
                child: Text((it.companyName.isNotEmpty ? it.companyName[0] : '?').toUpperCase()),
              ),
              title: Text(
                it.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (it.name.isNotEmpty)
                    Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          it.mobile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.event, size: 14),
                      const SizedBox(width: 4),
                      Text(it.followUpDate),
                    ],
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Call',
                icon: const Icon(Icons.call),
                onPressed: () {
                  final tel = Uri.parse('tel:${it.mobile}');
                  launchUrl(tel, mode: LaunchMode.externalApplication);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
