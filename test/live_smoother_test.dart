import 'dart:ui';

import 'package:ecosort/models/detection.dart';
import 'package:ecosort/models/waste_category.dart';
import 'package:ecosort/services/live_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

Detection det(double x, WasteCategory c, [double score = 0.6]) =>
    Detection(box: Rect.fromLTWH(x, 50, 100, 100), label: c.id, category: c, score: score);

void main() {
  test('one-frame false positives are hidden', () {
    final s = LiveSmoother();
    expect(s.update([det(10, WasteCategory.glass)]), isEmpty);
    expect(s.update([]), isEmpty);
    expect(s.update([]), isEmpty);
  });

  test('item appears after minHits frames and survives brief misses', () {
    final s = LiveSmoother(minHits: 3, maxMissed: 2);
    s.update([det(10, WasteCategory.plastic)]);
    s.update([det(12, WasteCategory.plastic)]);
    final shown = s.update([det(14, WasteCategory.plastic)]);
    expect(shown.length, 1);
    expect(s.update([]).length, 1, reason: 'kept through one missed frame');
    expect(s.update([]).length, 1);
    expect(s.update([]), isEmpty, reason: 'dropped after maxMissed');
  });

  test('category is decided by majority vote, not the latest frame', () {
    final s = LiveSmoother();
    for (var i = 0; i < 6; i++) {
      s.update([det(10.0 + i, WasteCategory.plastic, 0.7)]);
    }
    final out = s.update([det(16, WasteCategory.glass, 0.5)]);
    expect(out.single.category, WasteCategory.plastic);
  });

  test('boxes are smoothed', () {
    final s = LiveSmoother(minHits: 1, alpha: 0.5);
    s.update([det(0, WasteCategory.metal)]);
    final out = s.update([det(20, WasteCategory.metal)]);
    expect(out.single.box.left, closeTo(10, 1e-6));
  });

  test('two separate items are tracked separately', () {
    final s = LiveSmoother(minHits: 2);
    s.update([det(0, WasteCategory.metal), det(400, WasteCategory.organic)]);
    final out = s.update([det(2, WasteCategory.metal), det(402, WasteCategory.organic)]);
    expect(out.map((d) => d.category).toSet(), {WasteCategory.metal, WasteCategory.organic});
  });
}
