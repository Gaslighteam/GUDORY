import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../core/contracts.dart';
import '../../../../core/models.dart';

/// Diagnostic-only camera owner. The production CameraService stays unchanged.
/// Medium resolution avoids feeding full-resolution still buffers to both ML
/// models for a two-Hz diagnostic, and preview uses this exact stream aspect.
class DiagnosticCamera extends ChangeNotifier implements FrameBus {
  final _frames = StreamController<CameraFrame>.broadcast();
  CameraController? _controller;
  Future<void> _operation = Future.value();
  bool _disposed = false;
  Object? error;
  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;
  @override
  Stream<CameraFrame> get frames => _frames.stream;
  Future<void> start() => _operation = _operation.then((_) => _start());
  Future<void> stop() => _operation = _operation.then((_) => _stop());
  Future<void> _start() async {
    if (_disposed || isReady) return;
    CameraController? created;
    try {
      final cameras = await availableCameras();
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (back.isEmpty) throw CameraException('NoRearCamera', '후면 카메라가 필요해요');
      final description = back.first;
      created = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await created.initialize();
      if (_disposed) {
        await created.dispose();
        return;
      }
      _controller = created;
      await created.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await created.setFlashMode(FlashMode.off);
      await created.startImageStream((image) {
        if (_frames.isClosed || !_frames.hasListener || _disposed) return;
        _frames.add(
          CameraFrame(
            image: image,
            sensorOrientation: description.sensorOrientation,
            isFrontCamera: false,
          ),
        );
      });
      error = null;
      debugPrint(
        'DIRECTOR_CAMERA preset=medium preview=${created.value.previewSize} sensor=${description.sensorOrientation}',
      );
    } catch (e) {
      error = e;
      _controller = null;
      await created?.dispose();
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    _controller = null;
    if (!_disposed) notifyListeners();
    if (controller == null) return;
    if (controller.value.isStreamingImages) await controller.stopImageStream();
    await controller.dispose();
  }

  Future<void> shutdown() async {
    _disposed = true;
    await stop();
    await _frames.close();
    super.dispose();
  }
}
