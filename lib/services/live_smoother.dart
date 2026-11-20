import 'dart:ui';

import '../models/detection.dart';
import '../models/waste_category.dart';
import 'yolo_decoder.dart';

class _Track {
  _Track(this.id, Detection d)
      : box = d.box,
        label = d.label,
        score = d.score {
    _vote(d);
  }

  final int id;
  Rect box;
  String label;
  double score;
  int hits = 1;
  int missed = 0;
  final Map<WasteCategory, double> votes = {};

  void _vote(Detection d) {
    // Decay old votes so the category can change if the model changes its mind.
    votes.updateAll((_, v) => v * 0.8);
    votes[d.category] = (votes[d.category] ?? 0) + d.score;
  }

  WasteCategory get category =>
      votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  void update(Detection d, double alpha) {
    box = Rect.lerp(box, d.box, alpha)!;
    score = score + (d.score - score) * alpha;
    label = d.label;
    hits++;
    missed = 0;
    _vote(d);
  }
}

/// Stabilises live-camera detections across frames.
///
/// * An item must be seen in [minHits] frames before it is shown, which hides
///   one-frame false positives.
/// * Its category is a confidence-weighted vote over recent frames, so a
///   bottle that is "plastic" in 9 frames and "glass" in 1 stays plastic.
/// * Boxes are smoothed so outlines don't jitter.
/// * A briefly missed item stays visible for [maxMissed] frames.
class LiveSmoother {
  LiveSmoother({
    this.minHits = 3,
    this.maxMissed = 4,
    this.iouThreshold = 0.3,
    this.alpha = 0.5,
  });

  final int minHits;
  final int maxMissed;
  final double iouThreshold;
  final double alpha;
  final List<_Track> _tracks = [];
  int _nextId = 1;

  void reset() => _tracks.clear();

  List<Detection> update(List<Detection> dets) {
    final used = <_Track>{};
    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    for (final d in sorted) {
      _Track? best;
      var bestIou = iouThreshold;
      for (final t in _tracks) {
        if (used.contains(t)) continue;
        // Match on position regardless of category: the vote decides that.
        final v = iou(t.box, d.box);
        if (v >= bestIou) {
          bestIou = v;
          best = t;
        }
      }
      if (best == null) {
        best = _Track(_nextId++, d);
        _tracks.add(best);
      } else {
        best.update(d, alpha);
      }
      used.add(best);
    }
    for (final t in _tracks) {
      if (!used.contains(t)) t.missed++;
    }
    _tracks.removeWhere((t) => t.missed > maxMissed);
    return [
      for (final t in _tracks)
        if (t.hits >= minHits)
          Detection(
            box: t.box,
            label: t.label,
            category: t.category,
            score: t.score,
            trackId: t.id,
          ),
    ];
  }
}
