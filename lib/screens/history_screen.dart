import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/scan_record.dart';
import '../services/history_service.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _icons = {
    ScanSource.live: Icons.center_focus_strong_rounded,
    ScanSource.photo: Icons.photo_rounded,
    ScanSource.video: Icons.movie_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryService>();
    final theme = Theme.of(context);
    final records = history.records;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text('Your impact', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${history.totalItems} items sorted',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            CategoryBreakdown(history.totals),
          ]),
        ),
        const SizedBox(height: 20),
        Text('Recent scans', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No scans yet — try the live scanner!')),
          ),
        for (final r in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_icons[r.source], size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(DateFormat('EEE d MMM, HH:mm').format(r.timestamp.toLocal()),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    if (r.timeVerified)
                      Tooltip(
                        message: 'Timestamp verified by time API (${r.timezone ?? ''})',
                        child: Icon(Icons.verified_rounded, size: 16, color: theme.colorScheme.primary),
                      ),
                    const Spacer(),
                    Text('${r.total} items', style: theme.textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in r.counts.entries) CategoryBadge(e.key, count: e.value, compact: true),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
