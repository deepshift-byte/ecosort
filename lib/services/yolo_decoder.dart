import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A raw box from the model, in *model input* pixel coordinates.
class RawBox {
  RawBox(this.rect, this.classIndex, this.score);
  final Rect rect;
  final int classIndex;
  final double score;
}

/// Letterbox transform used to fit the source image into the square model
/// input while keeping aspect ratio.
class Letterbox {
  const Letterbox({
    required this.scale,
    required this.padX,
    required this.padY,
    required this.srcWidth,
    required this.srcHeight,
  });

  factory Letterbox.compute(int srcW, int srcH, int dst) {
    final scale = math.min(dst / srcW, dst / srcH);
    final newW = srcW * scale;
    final newH = srcH * scale;
    return Letterbox(
      scale: scale,
      padX: (dst - newW) / 2,
      padY: (dst - newH) / 2,
      srcWidth: srcW,
      srcHeight: srcH,
    );
  }

  final double scale;
  final double padX;
  final double padY;
  final int srcWidth;
  final int srcHeight;

  /// Maps a box from model-input coordinates back to source coordinates.
  Rect toSource(Rect r) {
    final l = ((r.left - padX) / scale).clamp(0.0, srcWidth.toDouble());
    final t = ((r.top - padY) / scale).clamp(0.0, srcHeight.toDouble());
    final rr = ((r.right - padX) / scale).clamp(0.0, srcWidth.toDouble());
    final b = ((r.bottom - padY) / scale).clamp(0.0, srcHeight.toDouble());
    return Rect.fromLTRB(l, t, rr, b);
  }
}

double iou(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width <= 0 || inter.height <= 0) return 0;
  final i = inter.width * inter.height;
  final u = a.width * a.height + b.width * b.height - i;
  return u <= 0 ? 0 : i / u;
}

/// Decodes a YOLOv8/YOLO11 detection head.
///
/// [out] is the flat output tensor. Two layouts are supported:
///  * channels-first `[1, 4 + C, N]` (Ultralytics default), and
///  * channels-last  `[1, N, 4 + C]`.
/// Box coordinates may be normalised (0..1) or in pixels; both are handled.
///
/// [numClasses] (from labels.txt) disambiguates the layout.
/// [allowed] optionally restricts which class indices are kept (used to drop
/// non-waste COCO classes such as "person"). [classThreshold] lets individual
/// classes use a lower threshold (e.g. hazardous items).
List<RawBox> decodeYolo(
  Float32List out, {
  required List<int> shape,
  required int inputSize,
  int? numClasses,
  double scoreThreshold = 0.35,
  double iouThreshold = 0.45,
  Set<int>? allowed,
  Map<int, double>? classThreshold,
  int maxDetections = 50,
}) {
  if (shape.length != 3) {
    throw ArgumentError('Unexpected output shape $shape');
  }
  final a = shape[1], b = shape[2];
  // Use the known class count when available; otherwise the smaller
  // dimension is the channel dimension (4 + C << N for real models).
  final channelsFirst = numClasses != null ? a == 4 + numClasses : a < b;
  final channels = channelsFirst ? a : b;
  final n = channelsFirst ? b : a;
  final classCount = channels - 4;
  if (classCount <= 0) throw ArgumentError('No class channels in $shape');

  double at(int c, int i) =>
      channelsFirst ? out[c * n + i] : out[i * channels + c];

  // Detect normalised coordinates by sampling the box widths.
  var maxCoord = 0.0;
  for (var i = 0; i < n; i += math.max(1, n ~/ 64)) {
    maxCoord = math.max(maxCoord, at(2, i));
  }
  final coordScale = maxCoord <= 2.0 ? inputSize.toDouble() : 1.0;

  final candidates = <RawBox>[];
  final minThreshold = classThreshold == null || classThreshold.isEmpty
      ? scoreThreshold
      : math.min(scoreThreshold, classThreshold.values.reduce(math.min));

  for (var i = 0; i < n; i++) {
    var best = -1;
    var bestScore = minThreshold;
    for (var c = 0; c < classCount; c++) {
      if (allowed != null && !allowed.contains(c)) continue;
      final s = at(4 + c, i);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    if (best < 0) continue;
    final thr = classThreshold?[best] ?? scoreThreshold;
    if (bestScore < thr) continue;
    final cx = at(0, i) * coordScale;
    final cy = at(1, i) * coordScale;
    final w = at(2, i) * coordScale;
    final h = at(3, i) * coordScale;
    candidates.add(RawBox(
      Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h),
      best,
      bestScore,
    ));
  }
  return nms(candidates, iouThreshold: iouThreshold, maxDetections: maxDetections);
}

/// Class-wise greedy non-maximum suppression.
List<RawBox> nms(
  List<RawBox> boxes, {
  double iouThreshold = 0.45,
  int maxDetections = 50,
}) {
  boxes.sort((x, y) => y.score.compareTo(x.score));
  final kept = <RawBox>[];
  for (final b in boxes) {
    var keep = true;
    for (final k in kept) {
      if (k.classIndex == b.classIndex && iou(k.rect, b.rect) > iouThreshold) {
        keep = false;
        break;
      }
    }
    if (keep) {
      kept.add(b);
      if (kept.length >= maxDetections) break;
    }
  }
  return kept;
}
