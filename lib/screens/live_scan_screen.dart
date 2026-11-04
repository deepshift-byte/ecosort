import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/detection.dart';
import '../models/scan_record.dart';
import '../models/waste_category.dart';
import '../services/detector_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import '../widgets/detection_painter.dart';

/// Real-time camera detection with colour-coded outlines.
class LiveScanScreen extends StatefulWidget {
  const LiveScanScreen({super.key});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  DetectionResult? _result;
  bool _paused = false;
  bool _torch = false;
  String? _error;
  int _fps = 0;
  int _frames = 0;
  DateTime _fpsWindow = DateTime.now();

  late final DetectorService _detector = context.read<DetectorService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _start();
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _start() async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      await old.dispose();
    }
    final c = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    await c.startImageStream(_onFrame);
    setState(() {
      _controller = c;
      _result = null;
      _torch = false;
    });
  }

  /// Rotation needed to make the sensor image upright in portrait.
  int get _rotation {
    if (!Platform.isAndroid) return 0;
    return _cameras[_cameraIndex].sensorOrientation;
  }

  Future<void> _onFrame(CameraImage frame) async {
    if (_paused || !_detector.isReady) return;
    final res = await _detector.detectCameraFrame(frame, rotation: _rotation);
    if (res == null || !mounted || _paused) return;
    _frames++;
    final now = DateTime.now();
    if (now.difference(_fpsWindow).inMilliseconds >= 1000) {
      _fps = _frames;
      _frames = 0;
      _fpsWindow = now;
    }
    setState(() => _result = res);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
      setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final r = _result;
    if (r == null || r.detections.isEmpty) return;
    await context.read<HistoryService>().add(ScanSource.live, r.counts);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${r.detections.length} items to history')),
    );
  }

  void _tap(TapUpDetails e, Size size) {
    final r = _result;
    if (r == null) return;
    for (final d in r.detections.reversed) {
      final rect = DetectionPainter.mapRect(d.box, r.imageSize, size, BoxFit.cover, mirror: _mirror);
      if (rect.contains(e.localPosition)) {
        showCategorySheet(context, d.category, itemLabel: d.label);
        return;
      }
    }
  }

  bool get _mirror =>
      _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final showConf = context.watch<SettingsService>().showConfidence;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_error != null)
          Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
        else if (c == null || !c.value.isInitialized)
          const Center(child: CircularProgressIndicator())
        else
          LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            final preview = c.value.previewSize!;
            // previewSize is reported in landscape.
            final pw = preview.height, ph = preview.width;
            return GestureDetector(
              onTapUp: (e) => _tap(e, size),
              child: Stack(fit: StackFit.expand, children: [
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(width: pw, height: ph, child: CameraPreview(c)),
                  ),
                ),
                if (_result != null)
                  CustomPaint(
                    painter: DetectionPainter(
                      detections: _result!.detections,
                      imageSize: _result!.imageSize,
                      fit: BoxFit.cover,
                      mirror: _mirror,
                      showConfidence: showConf,
                    ),
                  ),
              ]),
            );
          }),
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _GlassButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
              const Spacer(),
              _Pill(text: _paused ? 'Paused' : '$_fps fps · ${_result?.inferenceMs ?? 0} ms'),
              const Spacer(),
              _GlassButton(
                icon: _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                onTap: () async {
                  final ctrl = _controller;
                  if (ctrl == null) return;
                  _torch = !_torch;
                  await ctrl.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                  setState(() {});
                },
              ),
            ]),
          ),
        ),
        // Bottom panel
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _LiveSummary(result: _result),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _GlassButton(
                    icon: Icons.cameraswitch_rounded,
                    onTap: _cameras.length < 2
                        ? null
                        : () {
                            _cameraIndex = (_cameraIndex + 1) % _cameras.length;
                            _start();
                          },
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _paused = !_paused),
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _paused ? Colors.white24 : const Color(0xFF10B981),
                      ),
                      child: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                  _GlassButton(icon: Icons.bookmark_add_rounded, onTap: _save),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _LiveSummary extends StatelessWidget {
  const _LiveSummary({required this.result});
  final DetectionResult? result;

  @override
  Widget build(BuildContext context) {
    final counts = result?.counts ?? const <WasteCategory, int>{};
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
      child: counts.isEmpty
          ? const Text('Point the camera at waste items', style: TextStyle(color: Colors.white))
          : Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final e in counts.entries) CategoryBadge(e.key, count: e.value, compact: true),
            ]),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: onTap == null ? Colors.white30 : Colors.white),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
