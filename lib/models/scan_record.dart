import 'waste_category.dart';

enum ScanSource { live, photo, video }

/// A saved scan in the history list.
class ScanRecord {
  ScanRecord({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.counts,
    required this.timeVerified,
    this.timezone,
  });

  final String id;

  /// Network-verified (when [timeVerified]) UTC time of the scan.
  final DateTime timestamp;
  final ScanSource source;
  final Map<WasteCategory, int> counts;
  final bool timeVerified;
  final String? timezone;

  int get total => counts.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': timestamp.toUtc().toIso8601String(),
        'src': source.name,
        'counts': {for (final e in counts.entries) e.key.id: e.value},
        'verified': timeVerified,
        'tz': timezone,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> j) {
    final counts = <WasteCategory, int>{};
    (j['counts'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final c = WasteCategory.fromId(k);
      if (c != null) counts[c] = (v as num).toInt();
    });
    return ScanRecord(
      id: j['id'] as String,
      timestamp: DateTime.parse(j['ts'] as String),
      source: ScanSource.values.firstWhere(
        (s) => s.name == j['src'],
        orElse: () => ScanSource.photo,
      ),
      counts: counts,
      timeVerified: j['verified'] as bool? ?? false,
      timezone: j['tz'] as String?,
    );
  }
}
