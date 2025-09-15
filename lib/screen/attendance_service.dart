import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:solidplyaug25/globals.dart' as globals;

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  // Check-in keys
  static const _kAttDateKey   = 'att_date';
  static const _kAttDoneKey   = 'att_done';
  static const _kAttImgKey    = 'att_img_url';
  static const _kAttDTKey     = 'att_send_date_time';
  static const _kAttLatKey    = 'att_lat';
  static const _kAttLonKey    = 'att_lon';

  // Check-out keys (new)
  static const _kOutDateKey   = 'out_date';
  static const _kOutDoneKey   = 'out_done';
  static const _kOutDTKey     = 'out_send_date_time';
  static const _kOutLatKey    = 'out_lat';
  static const _kOutLonKey    = 'out_lon';

  String _todayString() {
    final now = DateTime.now();
    return "${now.year.toString().padLeft(4,'0')}-"
        "${now.month.toString().padLeft(2,'0')}-"
        "${now.day.toString().padLeft(2,'0')}";
  }

  String _baseUrlFromGlobals() {
    final raw = (globals.ipAddress).trim();
    if (raw.isEmpty) return '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _nativeAppEndpoint(String baseUrl, String fileWithQuery) {
    final hasNativeApp = RegExp(r'/native_app/?$').hasMatch(baseUrl) ||
        baseUrl.contains('/native_app/');
    final root = hasNativeApp ? baseUrl : "$baseUrl/native_app";
    return "$root/$fileWithQuery";
  }

  /// Returns true when today's attendance is PENDING (= att_st == false)
  Future<bool> isTodayPending() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();

    final cachedDate = prefs.getString(_kAttDateKey);
    final cachedDone = prefs.getBool(_kAttDoneKey) ?? false;

    if (cachedDate == today) {
      return !cachedDone;
    }

    final done = await _fetchTodayFromServerAndCache(prefs, today);
    return !done;
  }

  Future<bool> _fetchTodayFromServerAndCache(SharedPreferences prefs, String today) async {
    try {
      final baseUrl = _baseUrlFromGlobals();
      if (baseUrl.isEmpty) {
        if (kDebugMode) print('AttendanceService: globals.ipAddress is empty.');
        return false; // pending
      }

      final mob = prefs.getString('mob') ?? '';
      final userId = prefs.getString('user_id') ?? '';
      final url = Uri.parse(_nativeAppEndpoint(baseUrl, 'checkin_chk.php?subject=checkin&action=chk'));

      if (kDebugMode) print('AttendanceService: POST $url (mob=$mob, user_id=$userId)');
      final resp = await http.post(url, body: {'mob': mob, 'user_id': userId});
      if (kDebugMode) print('AttendanceService: response ${resp.statusCode} ${resp.body}');

      if (resp.statusCode != 200) {
        await _cacheCore(prefs, date: today, done: false);
        await _clearDetail(prefs);
        return false;
      }

      final data = jsonDecode(resp.body);
      final bool attSt = _asBool(data['att_st']); // true => checked-in
      final bool done = attSt == true;

      final String imgUrl = (data['img_url'] ?? '').toString();
      final String sendDT = (data['send_date_time'] ?? '').toString();
      final String lat    = (data['lat'] ?? '').toString();
      final String lon    = (data['lon'] ?? '').toString();

      await _cacheCore(prefs, date: today, done: done);
      if (done) {
        await _cacheDetail(prefs, imgUrl: imgUrl, sendDateTime: sendDT, lat: lat, lon: lon);
      } else {
        await _clearDetail(prefs);
      }

      if (kDebugMode) {
        print('AttendanceService: att_st=$attSt (done=$done), cached for $today');
        if (done) print('  img=$imgUrl dt=$sendDT lat=$lat lon=$lon');
      }
      return done;
    } catch (e) {
      if (kDebugMode) print('AttendanceService: check failed: $e');
      return false; // pending
    }
  }

  Future<void> _cacheCore(SharedPreferences prefs, {required String date, required bool done}) async {
    await prefs.setString(_kAttDateKey, date);
    await prefs.setBool(_kAttDoneKey, done);
  }

  Future<void> _cacheDetail(SharedPreferences prefs, {
    required String imgUrl,
    required String sendDateTime,
    required String lat,
    required String lon,
  }) async {
    await prefs.setString(_kAttImgKey, imgUrl);
    await prefs.setString(_kAttDTKey,  sendDateTime);
    await prefs.setString(_kAttLatKey, lat);
    await prefs.setString(_kAttLonKey, lon);
  }

  Future<void> _clearDetail(SharedPreferences prefs) async {
    await prefs.remove(_kAttImgKey);
    await prefs.remove(_kAttDTKey);
    await prefs.remove(_kAttLatKey);
    await prefs.remove(_kAttLonKey);
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

  /// After a successful CHECK-IN (flow stores detail separately)
  Future<void> markTodayDoneLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAttDateKey, _todayString());
    await prefs.setBool(_kAttDoneKey, true);
  }

  // ===== CHECK-OUT CACHE (called after a successful checkout save) =====

  Future<void> markTodayCheckedOutLocally({
    required String dateTime, // dd/MM/yy HH:mm (or server time if you add it)
    required String lat,
    required String lon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOutDateKey, _todayString());
    await prefs.setBool(_kOutDoneKey, true);
    await prefs.setString(_kOutDTKey,  dateTime);
    await prefs.setString(_kOutLatKey, lat);
    await prefs.setString(_kOutLonKey, lon);
  }

  /// Load today's checkout detail (returns nulls if different day or not done)
  Future<Map<String, String>> loadTodayCheckoutDetail() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final outDate = prefs.getString(_kOutDateKey);
    final outDone = prefs.getBool(_kOutDoneKey) ?? false;

    if (outDate == today && outDone) {
      return {
        'dt':  prefs.getString(_kOutDTKey)  ?? '',
        'lat': prefs.getString(_kOutLatKey) ?? '',
        'lon': prefs.getString(_kOutLonKey) ?? '',
      };
    }
    return {'dt': '', 'lat': '', 'lon': ''};
  }
}
