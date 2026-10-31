// Owns the camera controller and publishes analysis frames (FrameBus).
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(service.shutdown);
  return service;
});

class CameraService extends ChangeNotifier implements FrameBus {
  CameraService() {
    // The analysis stream copies ~1.4 MB per frame into Dart, so it only
    // runs while some module (pose, scene) is listening.
    _frames = StreamController<CameraFrame>.broadcast(
      onListen: _syncStream,
      onCancel: _syncStream,
    );
  }

  late final StreamController<CameraFrame> _frames;
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

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  bool get isFront =>
      _cameras.isNotEmpty &&
      _cameras[_index].lensDirection == CameraLensDirection.front;
  bool get canFlip =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  /// Zoom presets shown as chips; only levels the device supports.
  List<double> get zoomPresets => [
    if (minZoom <= 0.55) 0.5,
    1,
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
      await _syncStream();
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
      if (_controller == controller) await _syncStream();
    }
  }

  Future<void> shutdown() async {
    _disposed = true;
    await stop();
    await _frames.close();
    super.dispose();
  }

  /// Starts the image stream when someone listens, stops it when nobody does.
  Future<void> _syncStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final want = _frames.hasListener && !_disposed;
    final running = controller.value.isStreamingImages;
    try {
      if (want && !running) {
        await _startStream(controller);
      } else if (!want && running) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // Camera was closed mid-switch; the next start() re-syncs.
    }
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
