import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_record.dart';
import '../models/waste_category.dart';
import 'time_service.dart';

class HistoryService extends ChangeNotifier {
  HistoryService(this._time);

  final TimeService _time;
  static const _key = 'scan_history_v1';
  static const _maxRecords = 500;
  final List<ScanRecord> _records = [];

  List<ScanRecord> get records => List.unmodifiable(_records);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _records
      ..clear()
      ..addAll(raw.map((s) {
        try {
          return ScanRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<ScanRecord>());
    notifyListeners();
  }

  Future<ScanRecord?> add(ScanSource source, Map<WasteCategory, int> counts) async {
    if (counts.values.fold(0, (a, b) => a + b) == 0) return null;
    final t = _time.now();
    final rec = ScanRecord(
      id: t.utc.microsecondsSinceEpoch.toString(),
      timestamp: t.utc,
      source: source,
      counts: counts,
      timeVerified: t.verified,
      timezone: t.timezone,
    );
    _records.insert(0, rec);
    if (_records.length > _maxRecords) _records.removeRange(_maxRecords, _records.length);
    await _save();
    notifyListeners();
    return rec;
  }

  Future<void> clear() async {
    _records.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _records.map((r) => jsonEncode(r.toJson())).toList());
  }

  int get totalItems => _records.fold(0, (a, r) => a + r.total);

  Map<WasteCategory, int> get totals {
    final m = <WasteCategory, int>{};
    for (final r in _records) {
      r.counts.forEach((k, v) => m[k] = (m[k] ?? 0) + v);
    }
    return m;
  }

  /// Consecutive days (ending today or yesterday) with at least one scan,
  /// computed in the user's timezone from trusted time.
  int streak(TrustedTime now) {
    final offset = now.utcOffset;
    DateTime day(DateTime utc) {
      final l = utc.add(offset);
      return DateTime.utc(l.year, l.month, l.day);
    }

    final days = _records.map((r) => day(r.timestamp)).toSet();
    var cursor = day(now.utc);
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(cursor)) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }
}
