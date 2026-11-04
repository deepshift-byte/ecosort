import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'yolo_decoder.dart';

/// Model input tensor plus the letterbox needed to map boxes back.
class PreparedInput {
  PreparedInput(this.tensor, this.letterbox);

  /// float32 NHWC, normalised to 0..1, viewed as bytes.
  final Uint8List tensor;
  final Letterbox letterbox;
}

const _padValue = 114 / 255.0; // Ultralytics letterbox grey.

/// Letterboxes a decoded [image] into a `size x size` float tensor.
PreparedInput prepareImage(img.Image image, int size) {
  final lb = Letterbox.compute(image.width, image.height, size);
  final out = Float32List(size * size * 3)..fillRange(0, size * size * 3, _padValue);
  final newW = (image.width * lb.scale).round();
  final newH = (image.height * lb.scale).round();
  final resized = img.copyResize(
    image,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );
  final ox = lb.padX.round(), oy = lb.padY.round();
  for (var y = 0; y < newH; y++) {
    final ty = y + oy;
    if (ty < 0 || ty >= size) continue;
    for (var x = 0; x < newW; x++) {
      final tx = x + ox;
      if (tx < 0 || tx >= size) continue;
      final p = resized.getPixel(x, y);
      final i = (ty * size + tx) * 3;
      out[i] = p.rNormalized.toDouble();
      out[i + 1] = p.gNormalized.toDouble();
      out[i + 2] = p.bNormalized.toDouble();
    }
  }
  return PreparedInput(out.buffer.asUint8List(), lb);
}

/// Converts a camera frame straight into a letterboxed model tensor,
/// rotating by [rotation] degrees (0/90/180/270, clockwise) so the tensor is
/// upright in display orientation. Uses nearest-neighbour sampling at model
/// resolution, which is fast enough for live preview.
PreparedInput prepareCameraImage(CameraImage frame, int size, int rotation) {
  final srcW = frame.width, srcH = frame.height;
  final rotated = rotation == 90 || rotation == 270;
  final dispW = rotated ? srcH : srcW;
  final dispH = rotated ? srcW : srcH;
  final lb = Letterbox.compute(dispW, dispH, size);
  final out = Float32List(size * size * 3)..fillRange(0, size * size * 3, _padValue);

  final isBgra = frame.format.group == ImageFormatGroup.bgra8888;
  final p0 = frame.planes[0];
  final yBytes = p0.bytes;
  final yRow = p0.bytesPerRow;
  Uint8List? uBytes, vBytes;
  var uvRow = 0, uvPix = 1;
  var nv21 = false;
  if (!isBgra) {
    if (frame.planes.length >= 3) {
      uBytes = frame.planes[1].bytes;
      vBytes = frame.planes[2].bytes;
      uvRow = frame.planes[1].bytesPerRow;
      uvPix = frame.planes[1].bytesPerPixel ?? 1;
    } else if (frame.planes.length == 2) {
      // Android NV21 single interleaved VU plane.
      nv21 = true;
      uBytes = frame.planes[1].bytes;
      uvRow = frame.planes[1].bytesPerRow;
    } else {
      // NV21 delivered as a single buffer (Y followed by VU).
      nv21 = true;
      uBytes = yBytes;
      uvRow = yRow;
    }
  }
  final nv21Offset = frame.planes.length == 1 ? yRow * srcH : 0;

  final newW = (dispW * lb.scale).round();
  final newH = (dispH * lb.scale).round();
  final ox = lb.padX.round(), oy = lb.padY.round();

  for (var ty = 0; ty < newH; ty++) {
    final v = (ty / lb.scale).floor().clamp(0, dispH - 1);
    for (var tx = 0; tx < newW; tx++) {
      final u = (tx / lb.scale).floor().clamp(0, dispW - 1);
      int sx, sy;
      switch (rotation) {
        case 90:
          sx = v;
          sy = srcH - 1 - u;
          break;
        case 180:
          sx = srcW - 1 - u;
          sy = srcH - 1 - v;
          break;
        case 270:
          sx = srcW - 1 - v;
          sy = u;
          break;
        default:
          sx = u;
          sy = v;
      }
      double r, g, b;
      if (isBgra) {
        final i = sy * yRow + sx * 4;
        b = yBytes[i] / 255.0;
        g = yBytes[i + 1] / 255.0;
        r = yBytes[i + 2] / 255.0;
      } else {
        final yv = yBytes[sy * yRow + sx];
        int uu, vv;
        if (nv21) {
          final idx = nv21Offset + (sy >> 1) * uvRow + (sx >> 1) * 2;
          vv = uBytes![idx];
          uu = uBytes[idx + 1];
        } else {
          final idx = (sy >> 1) * uvRow + (sx >> 1) * uvPix;
          uu = uBytes![idx];
          vv = vBytes![idx];
        }
        final c = yv - 16, d = uu - 128, e = vv - 128;
        r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255) / 255.0;
        g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255) / 255.0;
        b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255) / 255.0;
      }
      final i = ((ty + oy) * size + (tx + ox)) * 3;
      out[i] = r;
      out[i + 1] = g;
      out[i + 2] = b;
    }
  }
  return PreparedInput(out.buffer.asUint8List(), lb);
}

/// Converts an NHWC float tensor (as bytes) to NCHW.
Uint8List hwcToChw(Uint8List hwcBytes, int size) {
  final hwc = hwcBytes.buffer.asFloat32List(hwcBytes.offsetInBytes, size * size * 3);
  final chw = Float32List(size * size * 3);
  final plane = size * size;
  for (var p = 0, i = 0; p < plane; p++, i += 3) {
    chw[p] = hwc[i];
    chw[plane + p] = hwc[i + 1];
    chw[2 * plane + p] = hwc[i + 2];
  }
  return chw.buffer.asUint8List();
}
