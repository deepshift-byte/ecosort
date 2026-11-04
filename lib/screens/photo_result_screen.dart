import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection.dart';
import '../models/scan_record.dart';
import '../services/detector_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import '../widgets/detection_painter.dart';

class PhotoResultScreen extends StatefulWidget {
  const PhotoResultScreen({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<PhotoResultScreen> createState() => _PhotoResultScreenState();
}

class _PhotoResultScreenState extends State<PhotoResultScreen> {
  DetectionResult? _result;
  Detection? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final detector = context.read<DetectorService>();
    final history = context.read<HistoryService>();
    try {
      await detector.ensureLoaded();
      final r = await detector.detectBytes(widget.bytes);
      if (!mounted) return;
      setState(() => _result = r);
      await history.add(ScanSource.photo, r.counts);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final showConf = context.watch<SettingsService>().showConfidence;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo results')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : r == null
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Identifying items…'),
                ]))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(
                      color: Colors.black,
                      child: AnnotatedImage(
                        image: MemoryImage(widget.bytes),
                        result: r,
                        highlight: _selected,
                        showConfidence: showConf,
                        onTapDetection: (d) {
                          setState(() => _selected = d);
                          showCategorySheet(context, d.category, itemLabel: d.label);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${r.detections.length} items · ${r.inferenceMs} ms on-device',
                      style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  SectionCard(child: CategoryBreakdown(r.counts)),
                  const SizedBox(height: 16),
                  for (final d in r.detections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          selected: identical(d, _selected),
                          leading: CircleAvatar(backgroundColor: d.category.color, child: Icon(d.category.icon, color: Colors.white)),
                          title: Text(d.label),
                          subtitle: Text('${d.category.label} · ${(d.score * 100).round()}% confidence'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            setState(() => _selected = d);
                            showCategorySheet(context, d.category, itemLabel: d.label);
                          },
                        ),
                      ),
                    ),
                ]),
    );
  }
}
