import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/contracts.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/debug_pose_page.dart';
import 'package:gudory/features/coach/pose_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (q, shot) in [
    (0, const Offset(0.2, 0.3)),
    (1, const Offset(0.3, 0.8)),
    (-1, const Offset(0.7, 0.2)),
  ]) {
    test(
      'painter maps q=$q shot dot onto the same portrait preview pixel',
      () async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        PoseDotsPainter(
          debugFrame(q, shot),
        ).paint(canvas, const Size(100, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 200);
        final bytes = (await image.toByteData())!;
        // Each shot must land at portrait (.2,.3), not landscape (.3,.8)/(.7,.2).
        expect(bytes.getUint8((60 * 100 + 20) * 4 + 3), greaterThan(0));
        expect(bytes.getUint8((160 * 100 + 30) * 4 + 3), 0);
        image.dispose();
        picture.dispose();
      },
    );
  }

  test('low-visibility joints are not drawn', () async {
    final recorder = ui.PictureRecorder();
    final frame = debugFrame(1, const Offset(0.3, 0.8), visibility: 0.49);
    PoseDotsPainter(frame).paint(Canvas(recorder), const Size(100, 200));
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 200);
    final bytes = (await image.toByteData())!;
    expect(bytes.getUint8((60 * 100 + 20) * 4 + 3), 0);
    image.dispose();
    picture.dispose();
  });

  for (final q in [0, 1, -1]) {
    testWidgets(
      'debug page q=$q keeps portrait preview and shows orientation/reliability',
      (tester) async {
        final controller = PreviewController();
        final stream = StreamController<PoseFrame>();
        addTearDown(stream.close);
        addTearDown(controller.dispose);
        const bus = DebugFrameBus();
        final source = DebugPoseSource(stream.stream);
        await tester.pumpWidget(
          MaterialApp(
            home: DebugPosePage(
              controller: controller,
              frameBus: bus,
              poseSource: source,
            ),
          ),
        );
        stream.add(debugFrame(q, const Offset(0.5, 0.5)));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(q == 0 ? '세로' : '가로'), findsOneWidget);
        expect(find.textContaining('회전 $q'), findsOneWidget);
        expect(find.textContaining('Roll 유효'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox &&
                widget.width == 480 &&
                widget.height == 640,
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('preview-placeholder')), findsOneWidget);
        stream.add(debugFrame(q, const Offset(0.5, 0.5), reliable: false));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('Roll 유지'), findsOneWidget);
        expect(source.calls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

CoachPoseFrame debugFrame(
  int quarterTurns,
  Offset point, {
  double visibility = 1,
  bool reliable = true,
}) {
  var attitude = updateShotAttitude(
    const ShotAttitude.initial(),
    ax: quarterTurns * 9.81,
    ay: quarterTurns == 0 ? 9.81 : 0,
    az: 0,
  );
  if (!reliable) {
    attitude = updateShotAttitude(attitude, ax: 0, ay: 0, az: 9.81);
  }
  return CoachPoseFrame(
    landmarks: [Landmark(x: point.dx, y: point.dy, visibility: visibility)],
    imageWidth: quarterTurns == 0 ? 480 : 640,
    imageHeight: quarterTurns == 0 ? 640 : 480,
    attitude: attitude,
    at: DateTime.utc(2026, 10, 31),
  );
}

class DebugPoseSource implements PoseSource {
  DebugPoseSource(this.stream);
  final Stream<PoseFrame> stream;
  int calls = 0;
  @override
  Stream<PoseFrame> poses(FrameBus bus) {
    calls++;
    return stream;
  }
}

class PreviewController extends CameraController {
  PreviewController()
    : super(
        const CameraDescription(
          name: 'debug-test',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('preview-placeholder'), color: Colors.black);
}

class DebugFrameBus implements FrameBus {
  const DebugFrameBus();
  @override
  Stream<CameraFrame> get frames => const Stream.empty();
}
