import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/detection.dart';

/// Draws colour-coded rounded outlines and label chips for detections.
///
/// [imageSize] is the coordinate space of the detection boxes. The image is
/// assumed to be drawn with [fit] inside the paint area (cover for the live
/// camera preview, contain for photos).
class DetectionPainter extends CustomPainter {
  DetectionPainter({
    required this.detections,
    required this.imageSize,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.showConfidence = true,
    this.highlight,
  });

  final List<Detection> detections;
  final Size imageSize;
  final BoxFit fit;
  final bool mirror;
  final bool showConfidence;
  final Detection? highlight;

  /// Maps image coordinates into the canvas for the given [fit].
  static Rect mapRect(Rect r, Size imageSize, Size canvas, BoxFit fit, {bool mirror = false}) {
    final sx = canvas.width / imageSize.width;
    final sy = canvas.height / imageSize.height;
    final s = fit == BoxFit.cover ? math.max(sx, sy) : math.min(sx, sy);
    final dx = (canvas.width - imageSize.width * s) / 2;
    final dy = (canvas.height - imageSize.height * s) / 2;
    var out = Rect.fromLTRB(r.left * s + dx, r.top * s + dy, r.right * s + dx, r.bottom * s + dy);
    if (mirror) {
      out = Rect.fromLTRB(canvas.width - out.right, out.top, canvas.width - out.left, out.bottom);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;
    canvas.clipRect(Offset.zero & size);
    for (final d in detections) {
      final rect = mapRect(d.box, imageSize, size, fit, mirror: mirror);
      final color = d.category.color;
      final selected = identical(d, highlight);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(14));

      // Soft tinted fill.
      canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: selected ? 0.22 : 0.10));
      // Dark halo keeps the outline visible on bright backgrounds.
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 6 : 5
          ..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 4 : 3
          ..color = color,
      );
      _corners(canvas, rect, color);
      _label(canvas, rect, d, size);
    }
  }

  void _corners(Canvas canvas, Rect r, Color color) {
    final len = math.min(22.0, math.min(r.width, r.height) / 3);
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (o, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      final c = o + Offset(dx * 4, dy * 4);
      canvas.drawLine(c, c + Offset(dx * len, 0), p);
      canvas.drawLine(c, c + Offset(0, dy * len), p);
    }
  }

  void _label(Canvas canvas, Rect r, Detection d, Size size) {
    final text = showConfidence
        ? '${d.category.label} · ${(d.score * 100).round()}%'
        : d.category.label;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: d.category.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padH = 9.0, padV = 4.0;
    final w = tp.width + padH * 2, h = tp.height + padV * 2;
    final left = r.left.clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    var top = r.top - h - 4;
    if (top < 0) top = r.top + 4; // put inside when no room above
    final chip = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(10));
    canvas.drawRRect(chip.shift(const Offset(0, 1.5)), Paint()..color = Colors.black26);
    canvas.drawRRect(chip, Paint()..color = d.category.color);
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections ||
      old.imageSize != imageSize ||
      old.highlight != highlight ||
      old.mirror != mirror;
}

/// Image with detection overlay; tapping a box reports the detection.
class AnnotatedImage extends StatelessWidget {
  const AnnotatedImage({
    super.key,
    required this.image,
    required this.result,
    this.onTapDetection,
    this.highlight,
    this.showConfidence = true,
  });

  final ImageProvider image;
  final DetectionResult result;
  final ValueChanged<Detection>? onTapDetection;
  final Detection? highlight;
  final bool showConfidence;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: result.imageSize.width / result.imageSize.height,
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onTapUp: (e) {
            if (onTapDetection == null) return;
            for (final d in result.detections.reversed) {
              final r = DetectionPainter.mapRect(d.box, result.imageSize, size, BoxFit.contain);
              if (r.contains(e.localPosition)) {
                onTapDetection!(d);
                return;
              }
            }
          },
          child: Stack(fit: StackFit.expand, children: [
            Image(image: image, fit: BoxFit.contain),
            CustomPaint(
              painter: DetectionPainter(
                detections: result.detections,
                imageSize: result.imageSize,
                highlight: highlight,
                showConfidence: showConfidence,
              ),
            ),
          ]),
        );
      }),
    );
  }
}
