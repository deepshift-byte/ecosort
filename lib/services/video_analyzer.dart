import 'dart:typed_data';
import 'dart:ui';

import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

import '../models/detection.dart';
import '../models/waste_category.dart';
import 'detector_service.dart';
import 'yolo_decoder.dart';

/// One analysed frame of a video.
class VideoFrameResult {
  VideoFrameResult(this.timeMs, this.image, this.result);
  final int timeMs;
  final Uint8List image;
  final DetectionResult result;
}

class VideoTrack {
  VideoTrack(this.id, this.category, this.label, this.box, this.firstMs);
  final int id;
  final WasteCategory category;
  String label;
  Rect box;
  final int firstMs;
  int lastMs = 0;
  int hits = 1;
  int missed = 0;
  double bestScore = 0;
}

/// Greedy IoU tracker that merges the same physical item across frames so a
/// bottle visible for 5 seconds is counted once, not 10 times.
class IouTracker {
  IouTracker({this.iouThreshold = 0.3, this.maxMissed = 3});

  final double iouThreshold;
  final int maxMissed;
  final List<VideoTrack> _active = [];
  final List<VideoTrack> all = [];
  int _nextId = 1;

  /// Returns [dets] annotated with track ids.
  List<Detection> update(List<Detection> dets, int timeMs) {
    final assigned = <Detection>[];
    final used = <VideoTrack>{};
    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    for (final d in sorted) {
      VideoTrack? best;
      var bestIou = iouThreshold;
      for (final t in _active) {
        if (used.contains(t) || t.category != d.category) continue;
        final v = iou(t.box, d.box);
        if (v >= bestIou) {
          bestIou = v;
          best = t;
        }
      }
      if (best == null) {
        best = VideoTrack(_nextId++, d.category, d.label, d.box, timeMs);
        _active.add(best);
        all.add(best);
      } else {
        best
          ..box = d.box
          ..hits += 1
          ..missed = 0;
      }
      best.lastMs = timeMs;
      if (d.score > best.bestScore) {
        best.bestScore = d.score;
        best.label = d.label;
      }
      used.add(best);
      assigned.add(d.copyWith(trackId: best.id));
    }
    for (final t in _active) {
      if (!used.contains(t)) t.missed += 1;
    }
    _active.removeWhere((t) => t.missed > maxMissed);
    return assigned;
  }

  /// Tracks confirmed in at least [minHits] frames.
  List<VideoTrack> confirmed({int minHits = 2}) =>
      all.where((t) => t.hits >= minHits).toList();
}

class VideoAnalysis {
  VideoAnalysis(this.frames, this.tracks, this.duration);
  final List<VideoFrameResult> frames;
  final List<VideoTrack> tracks;
  final Duration duration;

  Map<WasteCategory, int> get counts {
    final m = <WasteCategory, int>{};
    for (final t in tracks) {
      m[t.category] = (m[t.category] ?? 0) + 1;
    }
    return m;
  }
}

class VideoAnalyzer {
  VideoAnalyzer(this.detector);
  final DetectorService detector;

  static const maxDuration = Duration(seconds: 60);

  Future<Duration> probeDuration(String path) async {
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      return c.value.duration;
    } finally {
      await c.dispose();
    }
  }

  /// Samples the video every [intervalMs] and detects items in each frame.
  /// [onProgress] receives 0..1.
  Future<VideoAnalysis> analyze(
    String path, {
    int intervalMs = 500,
    void Function(double progress, VideoFrameResult? frame)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var duration = await probeDuration(path);
    if (duration > maxDuration) duration = maxDuration;
    final totalMs = duration.inMilliseconds;
    // Keep the number of frames reasonable for long clips.
    final step = totalMs / intervalMs > 120 ? totalMs ~/ 120 : intervalMs;
    final tracker = IouTracker();
    final frames = <VideoFrameResult>[];
    for (var t = 0; t <= totalMs; t += step) {
      if (isCancelled?.call() ?? false) break;
      final Uint8List bytes;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 720,
          timeMs: t,
          quality: 80,
        );
      } catch (_) {
        continue; // frame could not be decoded (e.g. past the end)
      }
      final res = await detector.detectBytes(bytes);
      final tracked = tracker.update(res.detections, t);
      final frame = VideoFrameResult(
        t,
        bytes,
        DetectionResult(
          detections: tracked,
          imageSize: res.imageSize,
          inferenceMs: res.inferenceMs,
        ),
      );
      frames.add(frame);
      onProgress?.call(totalMs == 0 ? 1 : t / totalMs, frame);
    }
    onProgress?.call(1, null);
    // Very short clips yield few frames: accept single sightings then.
    final minHits = frames.length < 4 ? 1 : 2;
    return VideoAnalysis(frames, tracker.confirmed(minHits: minHits), duration);
  }
}
