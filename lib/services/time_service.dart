import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Network-verified time.
class TrustedTime {
  TrustedTime({
    required this.utc,
    required this.utcOffset,
    required this.timezone,
    required this.verified,
    required this.source,
  });

  final DateTime utc;
  final Duration utcOffset;
  final String timezone;

  /// True when the time came from a time API rather than the device clock.
  final bool verified;
  final String source;

  /// Wall-clock time in the user's timezone.
  DateTime get local => utc.add(utcOffset);
}

/// Time-based API integration.
///
/// Uses WorldTimeAPI (timezone detected from IP), falls back to TimeAPI.io and
/// finally to the device clock. After one successful sync the server–device
/// offset is cached, so [now] is instant and works offline.
class TimeService extends ChangeNotifier {
  TimeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Duration? _skew; // server - device
  Duration _utcOffset = DateTime.now().timeZoneOffset;
  String _timezone = DateTime.now().timeZoneName;
  String _source = 'device';
  DateTime? lastSync;

  bool get isVerified => _skew != null;
  String get timezone => _timezone;
  String get source => _source;

  static const _timeout = Duration(seconds: 6);

  Future<bool> sync() async {
    final ok = await _tryWorldTimeApi() || await _tryTimeApiIo();
    notifyListeners();
    return ok;
  }

  Future<bool> _tryWorldTimeApi() async {
    try {
      final sent = DateTime.now();
      final r = await _client
          .get(Uri.parse('https://worldtimeapi.org/api/ip'))
          .timeout(_timeout);
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final utc = DateTime.parse(j['utc_datetime'] as String).toUtc();
      final offset = parseOffset(j['utc_offset'] as String? ?? '+00:00');
      _apply(utc, sent, offset, j['timezone'] as String? ?? 'UTC', 'WorldTimeAPI');
      return true;
    } catch (e) {
      debugPrint('WorldTimeAPI failed: $e');
      return false;
    }
  }

  Future<bool> _tryTimeApiIo() async {
    try {
      final sent = DateTime.now();
      final r = await _client
          .get(Uri.parse('https://timeapi.io/api/time/current/zone?timeZone=UTC'))
          .timeout(_timeout);
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      // TimeAPI returns wall-clock fields for the requested zone (UTC here).
      final utc = DateTime.utc(
        j['year'] as int,
        j['month'] as int,
        j['day'] as int,
        j['hour'] as int,
        j['minute'] as int,
        j['seconds'] as int,
        j['milliSeconds'] as int? ?? 0,
      );
      // Timezone falls back to the device's setting.
      _apply(utc, sent, DateTime.now().timeZoneOffset,
          DateTime.now().timeZoneName, 'TimeAPI.io');
      return true;
    } catch (e) {
      debugPrint('TimeAPI.io failed: $e');
      return false;
    }
  }

  void _apply(DateTime serverUtc, DateTime sentAt, Duration offset, String tz,
      String source) {
    // Compensate for half the round trip.
    final now = DateTime.now();
    final rtt = now.difference(sentAt);
    final corrected = serverUtc.add(rtt ~/ 2);
    _skew = corrected.difference(now.toUtc());
    _utcOffset = offset;
    _timezone = tz;
    _source = source;
    lastSync = now;
  }

  TrustedTime now() {
    final device = DateTime.now().toUtc();
    return TrustedTime(
      utc: device.add(_skew ?? Duration.zero),
      utcOffset: _utcOffset,
      timezone: _timezone,
      verified: _skew != null,
      source: _source,
    );
  }

  /// Parses "+03:00" / "-05:30".
  static Duration parseOffset(String s) {
    final m = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(s.trim());
    if (m == null) return Duration.zero;
    final d = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
    return m[1] == '-' ? -d : d;
  }

  /// Next occurrence of [weekday] (1 = Monday) at [hour]:00 local time,
  /// strictly after [from].
  static DateTime nextCollection(DateTime from, int weekday, {int hour = 7}) {
    var d = DateTime(from.year, from.month, from.day, hour);
    var days = (weekday - d.weekday) % 7;
    d = DateTime(d.year, d.month, d.day + days, hour);
    if (!d.isAfter(from)) d = DateTime(d.year, d.month, d.day + 7, hour);
    return d;
  }

  static String greeting(DateTime local) {
    final h = local.hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
