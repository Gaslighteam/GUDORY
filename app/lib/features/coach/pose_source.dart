import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'pose_geometry.dart';

/// One active consumer per instance. Cancel the subscription before reuse.
class MlKitPoseSource implements PoseSource {
  MlKitPoseSource()
    : _detector = ml.PoseDetector(
        options: ml.PoseDetectorOptions(mode: ml.PoseDetectionMode.stream),
      );

  final ml.PoseDetector _detector;
  final Stopwatch _clock = Stopwatch()..start();
  StreamSubscription<CameraFrame>? _frames;
  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamController<PoseFrame>? _output;
  Future<void>? _pending;
  bool _active = false;
  bool _disposed = false;
  int? _lastStarted;
  ShotAttitude _attitude = const ShotAttitude.initial();

  @override
  Stream<PoseFrame> poses(FrameBus bus) {
    if (_disposed) throw StateError('PoseSource has been disposed');
    if (_active) throw StateError('PoseSource already has an active stream');
    _active = true;
    late final StreamController<PoseFrame> output;
    output = StreamController<PoseFrame>(
      onListen: () {
        _accelerometer =
            accelerometerEventStream(
              samplingPeriod: SensorInterval.gameInterval,
            ).listen((event) {
              _attitude = updateShotAttitude(
                _attitude,
                ax: event.x,
                ay: event.y,
                az: event.z,
              );
            }, onError: output.addError);
        _frames = bus.frames.listen(
          (frame) {
            final now = _clock.elapsedMicroseconds;
            if (_pending != null ||
                (_lastStarted != null && now - _lastStarted! < 66667)) {
              return;
            }
            _lastStarted = now;
            _pending = _process(
              frame,
              output,
            ).whenComplete(() => _pending = null);
          },
          onError: output.addError,
          onDone: output.close,
        );
      },
      onCancel: _stop,
    );
    _output = output;
    return output.stream;
  }

  Future<void> _process(
    CameraFrame frame,
    StreamController<PoseFrame> output,
  ) async {
    try {
      final attitude = _attitude;
      final at = DateTime.now();
      final image = frame.image;
      final geometry = shotImageGeometry(
        sensorOrientation: frame.sensorOrientation,
        isFrontCamera: frame.isFrontCamera,
        quarterTurns: attitude.quarterTurns,
        rawWidth: image.width,
        rawHeight: image.height,
      );
      final rotation = ml.InputImageRotationValue.fromRawValue(
        geometry.rotationDegrees,
      );
      if (rotation == null ||
          image.format.group != ImageFormatGroup.nv21 ||
          image.planes.length != 1) {
        throw StateError(
          'PoseSource requires single-plane NV21 and valid rotation',
        );
      }
      final input = ml.InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: ml.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: ml.InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      final width = geometry.width;
      final height = geometry.height;
      final detected = await _detector.processImage(input);
      List<Landmark>? landmarks;
      if (detected.isNotEmpty) {
        final pose = detected.first;
        landmarks = ml.PoseLandmarkType.values
            .map((type) {
              final point = pose.landmarks[type];
              if (point == null) {
                return const Landmark(x: 0, y: 0, visibility: 0);
              }
              return normalizeShotLandmark(
                x: point.x,
                y: point.y,
                shotWidth: width,
                shotHeight: height,
                isFrontCamera: frame.isFrontCamera,
                visibility: point.likelihood,
              );
            })
            .toList(growable: false);
      }
      if (!output.isClosed && output.hasListener && !_disposed) {
        output.add(
          CoachPoseFrame(
            landmarks: landmarks,
            imageWidth: width,
            imageHeight: height,
            attitude: attitude,
            at: at,
          ),
        );
      }
    } catch (error, stack) {
      if (!output.isClosed && output.hasListener) output.addError(error, stack);
    }
  }

  Future<void> _stop() async {
    await _frames?.cancel();
    await _accelerometer?.cancel();
    await _pending;
    _frames = null;
    _accelerometer = null;
    _active = false;
    _lastStarted = null;
    _attitude = const ShotAttitude.initial();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stop();
    // Do not await close: a paused downstream listener may delay completion.
    unawaited(_output?.close());
    await _detector.close();
    _clock.stop();
  }
}
