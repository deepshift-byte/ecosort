import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan_record.dart';
import '../services/detector_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/video_analyzer.dart';
import '../widgets/common.dart';
import '../widgets/detection_painter.dart';

class VideoResultScreen extends StatefulWidget {
  const VideoResultScreen({super.key, required this.path});
  final String path;

  @override
  State<VideoResultScreen> createState() => _VideoResultScreenState();
}

class _VideoResultScreenState extends State<VideoResultScreen> {
  double _progress = 0;
  VideoFrameResult? _preview;
  VideoAnalysis? _analysis;
  int _frameIndex = 0;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    final detector = context.read<DetectorService>();
    final history = context.read<HistoryService>();
    try {
      await detector.ensureLoaded();
      final a = await VideoAnalyzer(detector).analyze(
        widget.path,
        isCancelled: () => _cancelled,
        onProgress: (p, f) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            if (f != null) _preview = f;
          });
        },
      );
      if (!mounted) return;
      // Jump to the frame with the most detections.
      var best = 0;
      for (var i = 0; i < a.frames.length; i++) {
        if (a.frames[i].result.detections.length > a.frames[best].result.detections.length) best = i;
      }
      setState(() {
        _analysis = a;
        _frameIndex = best;
      });
      await history.add(ScanSource.video, a.counts);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not analyse video: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    final showConf = context.watch<SettingsService>().showConfidence;
    return Scaffold(
      appBar: AppBar(title: const Text('Video analysis')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : a == null
              ? _buildProgress(showConf)
              : _buildResult(a, showConf),
    );
  }

  Widget _buildProgress(bool showConf) {
    final f = _preview;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (f != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AnnotatedImage(image: MemoryImage(f.image), result: f.result, showConfidence: showConf),
        ),
      const SizedBox(height: 20),
      LinearProgressIndicator(value: _progress, minHeight: 10, borderRadius: BorderRadius.circular(8)),
      const SizedBox(height: 10),
      Text('Scanning frames… ${(_progress * 100).round()}%', textAlign: TextAlign.center),
    ]);
  }

  Widget _buildResult(VideoAnalysis a, bool showConf) {
    if (a.frames.isEmpty) {
      return const Center(child: Text('No frames could be read from this video.'));
    }
    final frame = a.frames[_frameIndex];
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: Colors.black,
          child: AnnotatedImage(
            image: MemoryImage(frame.image),
            result: frame.result,
            showConfidence: showConf,
            onTapDetection: (d) => showCategorySheet(context, d.category, itemLabel: d.label),
          ),
        ),
      ),
      Row(children: [
        Text(_fmt(frame.timeMs), style: theme.textTheme.bodySmall),
        Expanded(
          child: Slider(
            value: _frameIndex.toDouble(),
            max: (a.frames.length - 1).toDouble().clamp(0, double.infinity),
            divisions: a.frames.length > 1 ? a.frames.length - 1 : null,
            onChanged: (v) => setState(() => _frameIndex = v.round()),
          ),
        ),
        Text(_fmt(a.duration.inMilliseconds), style: theme.textTheme.bodySmall),
      ]),
      const SizedBox(height: 8),
      Text('${a.tracks.length} unique items in ${a.frames.length} frames',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      SectionCard(child: CategoryBreakdown(a.counts)),
      const SizedBox(height: 16),
      for (final t in a.tracks)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: t.category.color, child: Icon(t.category.icon, color: Colors.white)),
              title: Text(t.label),
              subtitle: Text('${t.category.label} · seen ${_fmt(t.firstMs)}–${_fmt(t.lastMs)}'),
              trailing: Text('${(t.bestScore * 100).round()}%'),
              onTap: () {
                final i = a.frames.indexWhere((f) => f.timeMs == t.firstMs);
                if (i >= 0) setState(() => _frameIndex = i);
              },
            ),
          ),
        ),
    ]);
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
