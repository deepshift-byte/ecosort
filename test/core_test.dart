import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ecosort/models/detection.dart';
import 'package:ecosort/models/scan_record.dart';
import 'package:ecosort/models/waste_category.dart';
import 'package:ecosort/services/time_service.dart';
import 'package:ecosort/services/video_analyzer.dart';
import 'package:ecosort/services/waste_advisor.dart';
import 'package:ecosort/services/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a channels-first YOLO output [1, 4 + C, N].
Float32List yolo(List<List<double>> anchors, int classes) {
  final n = anchors.length, ch = 4 + classes;
  final out = Float32List(ch * n);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < ch; c++) {
      out[c * n + i] = anchors[i][c];
    }
  }
  return out;
}

void main() {
  group('YOLO decoder', () {
    test('decodes, thresholds and applies NMS', () {
      final out = yolo([
        [100, 100, 40, 40, 0.9, 0.1], // class 0
        [102, 101, 42, 40, 0.8, 0.1], // overlaps -> suppressed
        [250, 250, 30, 30, 0.1, 0.7], // class 1
        [50, 280, 20, 20, 0.2, 0.1], // below threshold
      ], 2);
      final boxes = decodeYolo(out, shape: [1, 6, 4], inputSize: 320, numClasses: 2);
      expect(boxes.length, 2);
      expect(boxes.first.classIndex, 0);
      expect(boxes.first.rect.left, closeTo(80, 1e-3));
      expect(boxes[1].classIndex, 1);
    });

    test('handles normalised coordinates and channels-last layout', () {
      // [1, N, 4 + C], coords 0..1
      final n = 10;
      final cl = Float32List(n * 6);
      cl.setAll(0, [0.5, 0.5, 0.25, 0.25, 0.95, 0.0]);
      final b2 = decodeYolo(cl, shape: [1, n, 6], inputSize: 320, numClasses: 2);
      expect(b2.length, 1);
      expect(b2.first.rect.width, closeTo(80, 1e-3));
    });

    test('allowed classes and per-class thresholds', () {
      final out = yolo([
        [100, 100, 40, 40, 0.9, 0.0, 0.0],
        [250, 250, 30, 30, 0.0, 0.0, 0.3],
      ], 3);
      final b = decodeYolo(out,
          shape: [1, 7, 2], inputSize: 320, numClasses: 3, allowed: {2}, classThreshold: {2: 0.25});
      expect(b.length, 1);
      expect(b.first.classIndex, 2);
    });

    test('letterbox maps boxes back to source pixels', () {
      final lb = Letterbox.compute(640, 480, 320); // scale .5, padY 40
      final r = lb.toSource(const Rect.fromLTRB(10, 50, 110, 150));
      expect(r, const Rect.fromLTRB(20, 20, 220, 220));
    });
  });

  group('IoU tracker', () {
    Detection det(double x, WasteCategory c) =>
        Detection(box: Rect.fromLTWH(x, 10, 50, 50), label: c.id, category: c, score: 0.8);

    test('same item across frames counts once', () {
      final t = IouTracker();
      for (var f = 0; f < 5; f++) {
        t.update([det(10.0 + f * 3, WasteCategory.plastic), det(300, WasteCategory.metal)], f * 500);
      }
      final tracks = t.confirmed();
      expect(tracks.length, 2);
      expect(tracks.map((e) => e.category).toSet(), {WasteCategory.plastic, WasteCategory.metal});
    });

    test('flicker (single sighting) is not confirmed', () {
      final t = IouTracker();
      t.update([det(10, WasteCategory.glass)], 0);
      t.update([], 500);
      expect(t.confirmed(), isEmpty);
      expect(t.confirmed(minHits: 1).length, 1);
    });
  });

  group('Waste advisor (text / voice)', () {
    final advisor = WasteAdvisor.fromJson(
        File('assets/data/waste_knowledge.json').readAsStringSync());

    WasteCategory? top(String q) {
      final r = advisor.ask(q);
      return r.isEmpty ? null : r.first.item.category;
    }

    test('single items', () {
      expect(top('old AA batteries'), WasteCategory.hazardous);
      expect(top('a plastic water bottle'), WasteCategory.plastic);
      expect(top('Banana peels'), WasteCategory.organic);
      expect(top('my broken cell phone'), WasteCategory.ewaste);
      expect(top('empty jam jar'), WasteCategory.glass);
      expect(top('coke can'), WasteCategory.metal);
      expect(top('cardboard box'), WasteCategory.paper);
    });

    test('multiple items in one sentence', () {
      final cats = advisor
          .ask('I have a soda can, some banana peels and a dead battery')
          .map((m) => m.item.category)
          .toSet();
      expect(cats, containsAll([WasteCategory.metal, WasteCategory.organic, WasteCategory.hazardous]));
    });

    test('typos from speech recognition', () {
      expect(top('newspapper'), WasteCategory.paper);
      expect(top('bateries'), WasteCategory.hazardous);
    });

    test('fallback category guess', () {
      expect(advisor.ask('weird toxic goo'), isEmpty);
      expect(advisor.guessCategory('weird toxic goo'), WasteCategory.hazardous);
    });

    test('every item has handling and where-to-put text', () {
      for (final i in advisor.items) {
        expect(i.handling, isNotEmpty);
        expect(i.where, isNotEmpty);
      }
    });
  });

  group('Time service', () {
    test('parses offsets', () {
      expect(TimeService.parseOffset('+03:00'), const Duration(hours: 3));
      expect(TimeService.parseOffset('-05:30'), -const Duration(hours: 5, minutes: 30));
    });

    test('next collection day', () {
      final wed = DateTime(2026, 11, 4, 10); // Wednesday
      expect(TimeService.nextCollection(wed, DateTime.friday), DateTime(2026, 11, 6, 7));
      expect(TimeService.nextCollection(wed, DateTime.wednesday), DateTime(2026, 11, 11, 7));
      final early = DateTime(2026, 11, 4, 6);
      expect(TimeService.nextCollection(early, DateTime.wednesday), DateTime(2026, 11, 4, 7));
    });

    test('falls back to device clock when offline', () {
      final t = TimeService().now();
      expect(t.verified, isFalse);
      expect(t.utc.difference(DateTime.now().toUtc()).inSeconds.abs(), lessThan(2));
    });
  });

  test('scan record JSON round-trip', () {
    final r = ScanRecord(
      id: '1',
      timestamp: DateTime.utc(2026, 11, 4, 9),
      source: ScanSource.video,
      counts: {WasteCategory.plastic: 2, WasteCategory.hazardous: 1},
      timeVerified: true,
      timezone: 'Africa/Kampala',
    );
    final back = ScanRecord.fromJson(r.toJson());
    expect(back.total, 3);
    expect(back.source, ScanSource.video);
    expect(back.counts[WasteCategory.hazardous], 1);
  });
}
