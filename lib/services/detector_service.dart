import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../models/waste_category.dart';
import 'image_utils.dart';
import 'yolo_decoder.dart';

/// Loads the local `.tflite` model and turns images into [Detection]s.
///
/// Model contract (see training/README.md):
///  * input  `float32 [1, S, S, 3]` (NHWC) or `[1, 3, S, S]` (NCHW, LiteRT
///    export default), RGB, 0..1
///  * output `float32 [1, 4 + C, N]` (YOLOv8/YOLO11 head, no NMS)
///  * `assets/models/labels.txt`        – C class names, one per line
///  * `assets/models/category_map.json` – class name → category id
class DetectorService extends ChangeNotifier {
  static const modelAsset = 'assets/models/ecosort.tflite';
  static const labelsAsset = 'assets/models/labels.txt';
  static const mapAsset = 'assets/models/category_map.json';

  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  late List<String> _labels;
  final Map<int, WasteCategory> _classToCategory = {};
  int _inputSize = 320;
  bool _nchw = false;
  List<int> _outputShape = const [];
  bool _busy = false;
  String? error;

  double scoreThreshold = 0.35;

  /// Hazardous items are costly to miss, so they get a lower threshold.
  double hazardousThreshold = 0.25;

  bool get isReady => _interpreter != null;
  int get inputSize => _inputSize;
  String get modelDescription =>
      isReady ? '${_labels.length} classes · ${_inputSize}px' : 'not loaded';

  Future<void>? _loading;

  /// Loads the model once; concurrent callers share the same future.
  Future<void> ensureLoaded() => isReady ? Future.value() : (_loading ??= load());

  Future<void> load({bool useGpu = false}) {
    final f = _load(useGpu);
    _loading = f;
    return f;
  }

  Future<void> _load(bool useGpu) async {
    try {
      await close();
      final options = InterpreterOptions()..threads = 4;
      if (useGpu) {
        if (Platform.isAndroid) {
          options.addDelegate(GpuDelegateV2());
        } else if (Platform.isIOS) {
          options.addDelegate(GpuDelegate());
        }
      }
      final interpreter = await Interpreter.fromAsset(modelAsset, options: options);
      interpreter.allocateTensors();
      final inShape = interpreter.getInputTensor(0).shape;
      _nchw = inShape.length == 4 && inShape[1] == 3 && inShape[3] != 3;
      _inputSize = _nchw ? inShape[2] : inShape[1];
      _outputShape = interpreter.getOutputTensor(0).shape;

      _labels = (await rootBundle.loadString(labelsAsset))
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final map = jsonDecode(await rootBundle.loadString(mapAsset))
          as Map<String, dynamic>;
      _classToCategory.clear();
      for (var i = 0; i < _labels.length; i++) {
        final label = _labels[i];
        // Identity mapping when the model already predicts our 7 categories.
        final target = map[label] as String? ?? label;
        final cat = WasteCategory.fromId(target);
        if (cat != null) _classToCategory[i] = cat;
      }
      _interpreter = interpreter;
      _isolate = await IsolateInterpreter.create(address: interpreter.address);
      error = null;
    } catch (e) {
      error = 'Could not load model: $e';
      debugPrint(error);
    }
    notifyListeners();
  }

  Future<void> close() async {
    await _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
  }

  Map<int, double> get _classThresholds => {
        for (final e in _classToCategory.entries)
          if (e.value == WasteCategory.hazardous)
            e.key: hazardousThreshold < scoreThreshold
                ? hazardousThreshold
                : scoreThreshold,
      };

  Future<List<Detection>> _run(PreparedInput input) async {
    final isolate = _isolate;
    if (isolate == null) return const [];
    final count = _outputShape.fold<int>(1, (a, b) => a * b);
    final output = Float32List(count);
    final tensor = _nchw ? hwcToChw(input.tensor, _inputSize) : input.tensor;
    await isolate.runForMultipleInputs([tensor], {0: output.buffer});
    final raw = decodeYolo(
      output,
      shape: _outputShape,
      inputSize: _inputSize,
      numClasses: _labels.length,
      scoreThreshold: scoreThreshold,
      allowed: _classToCategory.keys.toSet(),
      classThreshold: _classThresholds,
    );
    return [
      for (final r in raw)
        Detection(
          box: input.letterbox.toSource(r.rect),
          label: _labels[r.classIndex],
          category: _classToCategory[r.classIndex]!,
          score: r.score,
        ),
    ].where((d) => d.box.width > 2 && d.box.height > 2).toList();
  }

  /// Detects items in an encoded image file (photo / video frame).
  Future<DetectionResult> detectBytes(Uint8List bytes) async {
    final sw = Stopwatch()..start();
    final size = _inputSize;
    // Decoding + resizing is CPU heavy: do it off the UI isolate.
    final prepared = await compute(_decodeAndPrepare, (bytes, size));
    if (prepared == null) {
      throw const FormatException('Unsupported image format');
    }
    final (input, w, h) = prepared;
    final dets = await _run(input);
    return DetectionResult(
      detections: dets,
      imageSize: Size(w.toDouble(), h.toDouble()),
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  /// Detects items in a live camera frame. Returns null when a previous frame
  /// is still being processed (frames are dropped, not queued).
  Future<DetectionResult?> detectCameraFrame(
    CameraImage frame, {
    required int rotation,
  }) async {
    if (_busy || !isReady) return null;
    _busy = true;
    try {
      final sw = Stopwatch()..start();
      final input = prepareCameraImage(frame, _inputSize, rotation);
      final dets = await _run(input);
      final lb = input.letterbox;
      return DetectionResult(
        detections: dets,
        imageSize: Size(lb.srcWidth.toDouble(), lb.srcHeight.toDouble()),
        inferenceMs: sw.elapsedMilliseconds,
      );
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

(PreparedInput, int, int)? _decodeAndPrepare((Uint8List, int) args) {
  final (bytes, size) = args;
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  decoded = img.bakeOrientation(decoded); // respect EXIF rotation
  return (prepareImage(decoded, size), decoded.width, decoded.height);
}
