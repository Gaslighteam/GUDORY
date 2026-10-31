// Owns the camera controller and publishes analysis frames (FrameBus).
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'shot_orientation.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(service.shutdown);
  return service;
});

class CameraService extends ChangeNotifier implements FrameBus {
  final _frames = StreamController<CameraFrame>.broadcast();
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  CameraController? _controller;
  bool _starting = false;
  bool _disposed = false;

  Object? error;
  double minZoom = 1;
  double maxZoom = 1;
  double zoom = 1;
  FlashMode flashMode = FlashMode.off;
  HeldOrientation _held = HeldOrientation.portrait;

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isFront =>
      _cameras.isNotEmpty &&
      _cameras[_index].lensDirection == CameraLensDirection.front;
  bool get canFlip =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  /// Zoom presets `.6 / 1x / 2 / 3`; only levels the device supports.
  /// (Ultra-wide phones report ~0.6 as the minimum ratio.)
  List<double> get zoomPresets => [
    if (minZoom <= 0.61) 0.6,
    1,
    if (maxZoom >= 2) 2,
    if (maxZoom >= 3) 3,
  ];

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  Future<void> start() async {
    if (_starting || isReady || _disposed) return;
    _starting = true;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _index = back >= 0 ? back : 0;
      }
      if (_cameras.isEmpty) {
        throw CameraException('NoCamera', '카메라를 찾지 못했어요');
      }
      final controller = CameraController(
        _cameras[_index],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      minZoom = await controller.getMinZoomLevel();
      maxZoom = await controller.getMaxZoomLevel();
      zoom = 1.0.clamp(minZoom, maxZoom);
      await controller.setFlashMode(flashMode);
      await _applyCaptureOrientation(controller);
      await _startStream(controller);
      error = null;
    } catch (e) {
      error = e;
    } finally {
      _starting = false;
      _notify();
    }
  }

  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    _notify();
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  Future<void> flip() async {
    if (!canFlip) return;
    final want = isFront ? CameraLensDirection.back : CameraLensDirection.front;
    _index = _cameras.indexWhere((c) => c.lensDirection == want);
    await stop();
    await start();
  }

  Future<void> setZoom(double level) async {
    final controller = _controller;
    if (controller == null) return;
    zoom = level.clamp(minZoom, maxZoom);
    await controller.setZoomLevel(zoom);
    _notify();
  }

  /// The UI is portrait-locked, so the saved photo's orientation follows how
  /// the phone is held (landscape when turned sideways).
  Future<void> setHeldOrientation(HeldOrientation held) async {
    _held = held;
    final controller = _controller;
    if (controller != null) await _applyCaptureOrientation(controller);
  }

  Future<void> _applyCaptureOrientation(CameraController controller) async {
    final orientation = !_held.isLandscape
        ? DeviceOrientation.portraitUp
        // Top of the phone to the left = landscapeLeft (Android ROTATION_90).
        : _held.quarterTurns > 0
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.landscapeRight;
    try {
      await controller.lockCaptureOrientation(orientation);
    } on CameraException {
      // Not fatal: the photo keeps the default orientation.
    }
  }

  Future<void> cycleFlash() async {
    flashMode = switch (flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await _controller?.setFlashMode(flashMode);
    _notify();
  }

  /// Full-resolution still. The analysis stream pauses during capture.
  Future<XFile> takePicture() async {
    final controller = _controller;
    if (controller == null) {
      throw CameraException('NotReady', '카메라가 준비되지 않았어요');
    }
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    try {
      return await controller.takePicture();
    } finally {
      if (_controller == controller) await _startStream(controller);
    }
  }

  Future<void> shutdown() async {
    _disposed = true;
    await stop();
    await _frames.close();
    super.dispose();
  }

  Future<void> _startStream(CameraController controller) async {
    final description = _cameras[_index];
    await controller.startImageStream((image) {
      if (!_frames.hasListener || _frames.isClosed) return;
      _frames.add(
        CameraFrame(
          image: image,
          sensorOrientation: description.sensorOrientation,
          isFrontCamera: description.lensDirection == CameraLensDirection.front,
        ),
      );
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
