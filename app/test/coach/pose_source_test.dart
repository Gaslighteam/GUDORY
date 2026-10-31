import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/fakes/fake_frame_bus.dart';
import 'package:gudory/features/coach/pose_geometry.dart';
import 'package:gudory/features/coach/pose_source.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late PoseHarness h;
  setUp(() async {
    h = PoseHarness(binding);
    await h.start();
  });
  tearDown(() => h.close());

  for (final front in [false, true]) {
    for (final (q, rotation, x, y) in [
      (0, front ? 270 : 90, front ? 0.8 : 0.2, 0.3),
      (1, 0, front ? 0.7 : 0.3, 0.8),
      (-1, 180, front ? 0.3 : 0.7, 0.2),
    ]) {
      test(
        'real channel conversion q=$q front=$front preserves shot coordinates',
        () async {
          await h.tilt(q * 90.0);
          h.push(front: front);
          await flush();
          expect(h.requests.length, 1);
          final request = h.requests.single.arguments as Map;
          expect((request['options'] as Map)['mode'], 'stream');
          final image = request['imageData'] as Map;
          final metadata = image['metadata'] as Map;
          expect(metadata['rotation'], rotation);
          expect(metadata['image_format'], 17);
          expect(metadata['bytes_per_row'], 672);
          expect(metadata['width'], 640);
          expect(metadata['height'], 480);
          expect(image['bytes'], isA<Uint8List>());
          final width = q == 0 ? 480 : 640;
          final height = q == 0 ? 640 : 480;
          h.pending.single.complete(poseResult(x * width, y * height));
          await flush();
          expect(h.errors, isEmpty);
          final frame = h.frames.single as CoachPoseFrame;
          expect(frame.imageWidth, width);
          expect(frame.imageHeight, height);
          expect(
            frame.orientation,
            q == 0 ? ShotOrientation.portrait : ShotOrientation.landscape,
          );
          expect(frame.attitude.quarterTurns, q);
          expect(frame.rollReliable, isTrue);
          expect(frame.rollDeg, closeTo(0, 1e-9));
          expect(frame.landmarks!.length, 33);
          final nose = frame.landmarks![0];
          expect(
            nose.x,
            closeTo(
              q == 0
                  ? 0.2
                  : q == 1
                  ? 0.3
                  : 0.7,
              1e-9,
            ),
          );
          expect(nose.y, closeTo(y, 1e-9));
          // The native response is reversed: output must still follow ML Kit order.
          expect(
            frame.landmarks![11].x,
            closeTo(front ? 1 - 22 / width : 22 / width, 1e-9),
          );
          expect(frame.landmarks![11].visibility, 0.8);
        },
      );
    }
  }

  test(
    'unmeasured and flat Roll remain unreliable with last reliable value held',
    () async {
      h.push();
      await flush();
      h.pending.last.complete([]);
      await flush();
      expect(h.frames.last.rollReliable, isFalse);
      await h.tilt(100);
      await h.accel(0.2, 0.3, 9.81);
      await frameInterval();
      h.push();
      await flush();
      h.pending.last.complete([]);
      await flush();
      final frame = h.frames.last as CoachPoseFrame;
      expect(frame.rollReliable, isFalse);
      expect(frame.rollDeg, closeTo(10, 1e-9));
      expect(frame.orientation, ShotOrientation.landscape);
      expect(frame.attitude.quarterTurns, 1);
      expect(frame.landmarks, isNull);
    },
  );

  test(
    'in-flight frame keeps its original orientation and reliability snapshot',
    () async {
      await h.tilt(10);
      h.push();
      await flush();
      await h.tilt(-90);
      await h.accel(0, 0, 9.81);
      h.pending.last.complete(poseResult(96, 192));
      await flush();
      final first = h.frames.single as CoachPoseFrame;
      expect(first.orientation, ShotOrientation.portrait);
      expect(first.rollReliable, isTrue);
      expect(first.rollDeg, closeTo(10, 1e-9));
      expect(first.attitude.quarterTurns, 0);
      expect(first.landmarks!.first.x, closeTo(0.2, 1e-9));
      await frameInterval();
      h.push();
      await flush();
      final metadata =
          ((h.requests.last.arguments as Map)['imageData'] as Map)['metadata']
              as Map;
      expect(metadata['rotation'], 180);
      h.pending.last.complete([]);
      await flush();
      final second = h.frames.last as CoachPoseFrame;
      expect(second.orientation, ShotOrientation.landscape);
      expect(second.attitude.quarterTurns, -1);
      expect(second.rollReliable, isFalse);
      expect(second.rollDeg, closeTo(0, 1e-9));
    },
  );

  test('frames arriving while detector is busy are dropped', () async {
    await h.tilt(0);
    h.push();
    await flush();
    for (var i = 0; i < 10; i++) {
      h.push();
    }
    await flush();
    expect(h.requests.length, 1);
    h.pending.single.complete([]);
    await flush();
    expect(h.frames.length, 1);
    expect(h.requests.length, 1);
  });

  test('non-NV21 images produce an error without invoking detector', () async {
    h.bus.add(
      CameraFrame(
        image: TestImage(format: TestFormat(ImageFormatGroup.yuv420)),
        sensorOrientation: 90,
        isFrontCamera: false,
      ),
    );
    await flush();
    expect(h.errors.single, isA<StateError>());
    expect(h.requests, isEmpty);
  });

  test('cancelled detector work emits no late frame', () async {
    h.push();
    await flush();
    final cancellation = h.subscription.cancel();
    h.pending.single.complete(poseResult(96, 192));
    await cancellation;
    await flush();
    expect(h.frames, isEmpty);
  });
}

Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> frameInterval() =>
    Future<void>.delayed(const Duration(milliseconds: 75));

List<Object> poseResult(double noseX, double noseY) => [
  List.generate(
    33,
    (index) => <String, Object>{
      'type': index,
      'x': index == 0 ? noseX : index * 2.0,
      'y': index == 0 ? noseY : index * 3.0,
      'z': 0.0,
      'likelihood': 0.8,
    },
  ).reversed.toList(),
];

class PoseHarness {
  PoseHarness(this.binding);
  final TestWidgetsFlutterBinding binding;
  final bus = FakeFrameBus();
  final source = MlKitPoseSource();
  final frames = <PoseFrame>[];
  final errors = <Object>[];
  final requests = <MethodCall>[];
  final pending = <Completer<Object?>>[];
  late StreamSubscription<PoseFrame> subscription;
  static const detector = MethodChannel('google_mlkit_pose_detector');
  static const sensor = MethodChannel(
    'dev.fluttercommunity.plus/sensors/method',
  );
  static const accelChannel = MethodChannel(
    'dev.fluttercommunity.plus/sensors/accelerometer',
  );

  Future<void> start() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sensor,
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      accelChannel,
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(detector, (
      call,
    ) async {
      if (call.method == 'vision#startPoseDetector') {
        requests.add(call);
        final result = Completer<Object?>();
        pending.add(result);
        return result.future;
      }
      return null;
    });
    subscription = source
        .poses(bus)
        .listen(frames.add, onError: (Object error) => errors.add(error));
    await flush();
  }

  Future<void> accel(double ax, double ay, double az) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      accelChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope([ax, ay, az, 0.0]),
      (_) {},
    );
    await flush();
  }

  Future<void> tilt(double degrees) {
    final radians = degrees * math.pi / 180;
    return accel(9.81 * math.sin(radians), 9.81 * math.cos(radians), 0);
  }

  void push({bool front = false}) => bus.add(
    CameraFrame(
      image: TestImage(),
      sensorOrientation: front ? 270 : 90,
      isFrontCamera: front,
    ),
  );

  Future<void> close() async {
    for (final call in pending) {
      if (!call.isCompleted) call.complete([]);
    }
    await subscription.cancel();
    await source.dispose();
    await bus.close();
    for (final channel in [detector, sensor, accelChannel]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  }
}

class TestImage implements CameraImage {
  TestImage({this.format = const TestFormat(ImageFormatGroup.nv21)});
  @override
  final ImageFormat format;
  @override
  int get width => 640;
  @override
  int get height => 480;
  @override
  List<Plane> get planes => [TestPlane()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestFormat implements ImageFormat {
  const TestFormat(this.group);
  @override
  final ImageFormatGroup group;
  @override
  int get raw => 17;
}

class TestPlane implements Plane {
  @override
  Uint8List get bytes => Uint8List(640 * 480 * 3 ~/ 2);
  @override
  int get bytesPerRow => 672;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
