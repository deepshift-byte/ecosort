import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/detector_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/time_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final detector = context.watch<DetectorService>();
    final time = context.watch<TimeService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Detection confidence'),
              subtitle: Text('${(s.confidence * 100).round()}% — lower finds more items, with more mistakes'),
            ),
            Slider(
              value: s.confidence,
              min: 0.15,
              max: 0.8,
              divisions: 13,
              label: '${(s.confidence * 100).round()}%',
              onChanged: (v) {
                s.setConfidence(v);
                detector.scoreThreshold = v;
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.percent_rounded),
              title: const Text('Show confidence on labels'),
              value: s.showConfidence,
              onChanged: s.setShowConfidence,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.memory_rounded),
              title: const Text('Use GPU acceleration'),
              subtitle: const Text('Faster on most phones; turn off if detection fails'),
              value: s.useGpu,
              onChanged: (v) async {
                await s.setUseGpu(v);
                await detector.load(useGpu: v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.model_training_rounded),
              title: const Text('On-device model'),
              subtitle: Text(detector.error ?? detector.modelDescription),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.local_shipping_rounded),
              title: const Text('Collection day'),
              trailing: DropdownButton<int>(
                value: s.collectionWeekday,
                underline: const SizedBox(),
                items: [
                  for (var d = 1; d <= 7; d++)
                    DropdownMenuItem(value: d, child: Text(DateFormat('EEEE').format(DateTime(2024, 1, d)))),
                ],
                onChanged: (v) => v == null ? null : s.setCollectionWeekday(v),
              ),
            ),
            ListTile(
              leading: Icon(time.isVerified ? Icons.verified_rounded : Icons.schedule_rounded),
              title: const Text('Time source'),
              subtitle: Text(time.isVerified
                  ? '${time.source} · ${time.timezone}'
                  : 'Device clock (time API unreachable)'),
              trailing: IconButton(icon: const Icon(Icons.sync_rounded), onPressed: time.sync),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            title: const Text('Clear history'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear all scan history?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true && context.mounted) await context.read<HistoryService>().clear();
            },
          ),
        ),
      ]),
    );
  }
}
