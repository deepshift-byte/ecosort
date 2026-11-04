import 'dart:ui';

import 'waste_category.dart';

/// One detected item. [box] is in *source image pixel* coordinates.
class Detection {
  const Detection({
    required this.box,
    required this.label,
    required this.category,
    required this.score,
    this.trackId,
  });

  final Rect box;

  /// Raw model class name (e.g. "bottle" or "plastic").
  final String label;
  final WasteCategory category;
  final double score;

  /// Set by the video tracker when this detection belongs to a track.
  final int? trackId;

  Detection copyWith({int? trackId}) => Detection(
        box: box,
        label: label,
        category: category,
        score: score,
        trackId: trackId ?? this.trackId,
      );

  @override
  String toString() =>
      'Detection(${category.id}:$label ${score.toStringAsFixed(2)} $box)';
}

/// Detections for one image together with the image size they refer to.
class DetectionResult {
  const DetectionResult({
    required this.detections,
    required this.imageSize,
    required this.inferenceMs,
  });

  final List<Detection> detections;
  final Size imageSize;
  final int inferenceMs;

  Map<WasteCategory, int> get counts {
    final m = <WasteCategory, int>{};
    for (final d in detections) {
      m[d.category] = (m[d.category] ?? 0) + 1;
    }
    return m;
  }
}
