import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/contracts.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/coach_engine.dart';

void main() {
  late FakeClock clock;
  late DefaultCoachEngine engine;
  setUp(() {
    clock = FakeClock();
    engine = DefaultCoachEngine(clock: clock.read);
  });

  CoachInstruction update(PoseFrame frame, [TargetComposition? target]) =>
      engine.update(frame, target ?? makeTarget());

  group('selection and amounts', () {
    test('implements the unchanged CoachEngine contract', () {
      expect(engine, isA<CoachEngine>());
    });

    test('priority is level, distance, horizontal, height', () {
      final cases = [
        (
          pose(level: 2, distance: 2, horizontal: 2, height: 2),
          CoachAxis.level,
        ),
        (pose(distance: 2, horizontal: 2, height: 2), CoachAxis.distance),
        (pose(horizontal: 2, height: 2), CoachAxis.horizontal),
        (pose(height: 2), CoachAxis.height),
      ];
      for (final (frame, axis) in cases) {
        engine.reset();
        expect(update(frame).axis, axis);
      }
    });

    test('all corrective directions preserve Step 2 signs', () {
      final cases = [
        (pose(level: 2), InstructionKey.holdPhoneUpright),
        (pose(level: -2), InstructionKey.holdPhoneUpright),
        (pose(distance: 2), InstructionKey.stepBack),
        (pose(distance: -2), InstructionKey.stepForward),
        (pose(horizontal: 2), InstructionKey.stepRight),
        (pose(horizontal: -2), InstructionKey.stepLeft),
        (pose(height: 2), InstructionKey.phoneDown),
        (pose(height: -2), InstructionKey.phoneUp),
      ];
      for (final (frame, key) in cases) {
        engine.reset();
        expect(update(frame).key, key);
      }
    });

    test(
      'movement amounts reuse the specified geometry and half-unit rounding',
      () {
        for (final (frame, amount) in [
          (pose(level: 2), 0.5),
          (pose(distance: 2), 1.0),
          (pose(horizontal: 2), 0.5),
          (pose(height: 2), 4.0),
        ]) {
          engine.reset();
          final result = update(frame);
          expect(result.amount, amount);
          expect(result.who, Who.camera);
        }
      },
    );

    test('errors contain all axes and remain current during a hold', () {
      update(pose(level: 2));
      clock.ms = 100;
      final result = update(
        pose(level: 0.5, distance: -2, horizontal: 3, height: -2),
      );
      expect(result.key, InstructionKey.holdPhoneUpright);
      expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
      expect(result.error, closeTo(0.5, 1e-10));
      expect(result.errors[CoachAxis.distance], closeTo(-2, 1e-10));
      expect(result.errors[CoachAxis.horizontal], closeTo(3, 1e-10));
      expect(result.errors[CoachAxis.height], closeTo(-2, 1e-10));
      expect(() => result.errors[CoachAxis.level] = 99, throwsUnsupportedError);
    });
  });

  group('Roll reliability and raisePhone', () {
    test(
      'flat with a person and aligned spatial axes returns exact raisePhone fields',
      () {
        final result = update(pose(level: 10, rollReliable: false));
        expect(result.key, InstructionKey.raisePhone);
        expect(result.axis, isNull);
        expect(result.amount, 0);
        expect(result.error, 1.0);
        expect(result.who, Who.camera);
        expect(result.aligned, isFalse);
        expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
        expect(result.errors[CoachAxis.level], 0);
        expect(
          () => result.errors[CoachAxis.level] = 1,
          throwsUnsupportedError,
        );
      },
    );

    test(
      'flat never aligns even with a zero stale Roll and tolerance-boundary spatial errors',
      () {
        for (final sign in [-1, 1]) {
          engine.reset();
          final result = update(
            pose(
              distance: sign * 1.0,
              horizontal: sign * 1.0,
              height: sign * 1.0,
              rollReliable: false,
            ),
          );
          expect(result.key, InstructionKey.raisePhone);
          expect(result.aligned, isFalse);
        }
      },
    );

    test(
      'unreliable Roll interrupts held level immediately and selects distance',
      () {
        update(pose(level: 2));
        clock.ms = 1;
        final result = update(pose(level: 2, distance: 2, rollReliable: false));
        expect(result.axis, CoachAxis.distance);
        expect(result.key, InstructionKey.stepBack);
      },
    );

    test(
      'unreliable Roll interrupts held level immediately into raisePhone',
      () {
        update(pose(level: 2));
        clock.ms = 1;
        expect(
          update(pose(level: 2, rollReliable: false)).key,
          InstructionKey.raisePhone,
        );
      },
    );

    test(
      'all spatial directions continue while even a large stale Roll is ignored',
      () {
        for (final (frame, key) in [
          (
            pose(level: 10, distance: 2, rollReliable: false),
            InstructionKey.stepBack,
          ),
          (
            pose(level: 10, distance: -2, rollReliable: false),
            InstructionKey.stepForward,
          ),
          (
            pose(level: 10, horizontal: 2, rollReliable: false),
            InstructionKey.stepRight,
          ),
          (
            pose(level: 10, horizontal: -2, rollReliable: false),
            InstructionKey.stepLeft,
          ),
          (
            pose(level: 10, height: 2, rollReliable: false),
            InstructionKey.phoneDown,
          ),
          (
            pose(level: 10, height: -2, rollReliable: false),
            InstructionKey.phoneUp,
          ),
        ]) {
          engine.reset();
          final result = update(frame);
          expect(result.key, key);
          expect(result.axis, isNot(CoachAxis.level));
          expect(result.aligned, isFalse);
          expect(result.errors[CoachAxis.level], 0);
        }
      },
    );

    test('eligible priority remains distance then horizontal then height', () {
      expect(
        update(
          pose(
            level: 10,
            distance: 2,
            horizontal: 2,
            height: 2,
            rollReliable: false,
          ),
        ).axis,
        CoachAxis.distance,
      );
      clock.ms = 1500;
      expect(
        update(
          pose(level: 10, horizontal: 2, height: 2, rollReliable: false),
        ).axis,
        CoachAxis.horizontal,
      );
      clock.ms = 3000;
      expect(
        update(pose(level: 10, height: 2, rollReliable: false)).axis,
        CoachAxis.height,
      );
    });

    test('active spatial hold and hysteresis survive a reliability change', () {
      update(pose(distance: 2));
      clock.ms = 100;
      expect(
        update(pose(distance: 0.5, horizontal: 2, rollReliable: false)).axis,
        CoachAxis.distance,
      );
      clock.ms = 1500;
      expect(
        update(pose(distance: 0.8, horizontal: 2, rollReliable: false)).axis,
        CoachAxis.distance,
      );
      clock.ms = 1501;
      expect(
        update(pose(distance: 0.79, horizontal: 2, rollReliable: false)).axis,
        CoachAxis.horizontal,
      );
    });

    test(
      'spatial alignment enters raisePhone without waiting for the hold',
      () {
        update(pose(distance: 2, rollReliable: false));
        clock.ms = 1;
        expect(
          update(pose(rollReliable: false)).key,
          InstructionKey.raisePhone,
        );
      },
    );

    test('recovery resumes level immediately', () {
      update(pose(level: 2));
      clock.ms = 100;
      expect(
        update(pose(level: 2, rollReliable: false)).key,
        InstructionKey.raisePhone,
      );
      clock.ms = 101;
      expect(update(pose(level: 2)).key, InstructionKey.holdPhoneUpright);
      clock.ms = 1601;
      expect(update(pose(level: 3)).key, InstructionKey.holdPhoneUpright);
    });

    test('recovery with all axes aligned returns aligned immediately', () {
      expect(update(pose(rollReliable: false)).key, InstructionKey.raisePhone);
      clock.ms = 1;
      final result = update(pose());
      expect(result.key, InstructionKey.aligned);
      expect(result.aligned, isTrue);
    });

    test('recovery does not preempt an existing spatial-axis hold', () {
      update(pose(distance: 2, rollReliable: false));
      clock.ms = 100;
      expect(update(pose(level: 2, distance: 0.5)).axis, CoachAxis.distance);
      clock.ms = 1500;
      expect(update(pose(level: 2, distance: 0.5)).axis, CoachAxis.level);
    });

    test('no person remains noPerson, never raisePhone or aligned', () {
      final result = update(noPerson(rollReliable: false));
      expect(result.key, InstructionKey.noPerson);
      expect(result.aligned, isFalse);
      expect(result.errors.length, 4);
    });

    test('raisePhone does not hide reset behavior', () {
      update(pose(rollReliable: false));
      engine.reset();
      expect(update(pose(level: 2)).key, InstructionKey.holdPhoneUpright);
    });
  });

  group('shot orientation has highest priority', () {
    test('portrait to landscape mismatch precedes every corrective axis', () {
      final result = update(
        pose(level: 3, distance: 2, horizontal: 2, height: 2),
        makeTarget(orientation: ShotOrientation.landscape),
      );
      expect(result.key, InstructionKey.turnLandscape);
      expect(result.axis, isNull);
      expect(result.aligned, isFalse);
      expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
    });

    test('landscape to portrait mismatch returns turnPortrait', () {
      final result = update(pose(orientation: ShotOrientation.landscape));
      expect(result.key, InstructionKey.turnPortrait);
      expect(result.axis, isNull);
      expect(result.aligned, isFalse);
    });

    test('orientation mismatch precedes both noPerson and raisePhone', () {
      final target = makeTarget(orientation: ShotOrientation.landscape);
      expect(
        update(noPerson(rollReliable: false), target).key,
        InstructionKey.turnLandscape,
      );
      expect(
        update(pose(rollReliable: false), target).key,
        InstructionKey.turnLandscape,
      );
    });

    test(
      'orientation mismatch interrupts a held movement and matching resumes fresh',
      () {
        update(pose(distance: 2));
        clock.ms = 1;
        expect(
          update(pose(orientation: ShotOrientation.landscape)).key,
          InstructionKey.turnPortrait,
        );
        clock.ms = 2;
        expect(update(pose(horizontal: 2)).key, InstructionKey.stepRight);
      },
    );

    test('matched orientation may align immediately or enter raisePhone', () {
      final target = makeTarget(orientation: ShotOrientation.landscape);
      update(pose(), target);
      clock.ms = 1;
      expect(
        update(pose(orientation: ShotOrientation.landscape), target).key,
        InstructionKey.aligned,
      );
      clock.ms = 2;
      final flat = update(
        pose(orientation: ShotOrientation.landscape, rollReliable: false),
        target,
      );
      expect(flat.key, InstructionKey.raisePhone);
      expect(flat.amount, 0);
      expect(flat.error, 1.0);
      expect(flat.aligned, isFalse);
    });
  });

  group('hold, hysteresis and immediate alignment', () {
    test('switches at 1500ms, not at 1499ms', () {
      update(pose(level: 2));
      clock.ms = 1499;
      expect(update(pose(level: 0.5, distance: 2)).axis, CoachAxis.level);
      clock.ms = 1500;
      expect(update(pose(level: 0.5, distance: 2)).axis, CoachAxis.distance);
    });

    test('0.8 retains the active axis; below 0.8 releases it', () {
      update(pose(level: 2));
      clock.ms = 1500;
      expect(update(pose(level: 0.8, distance: 2)).axis, CoachAxis.level);
      clock.ms = 1501;
      expect(update(pose(level: 0.799, distance: 2)).axis, CoachAxis.distance);
    });

    test('negative errors use the same 0.8 exit boundary', () {
      update(pose(level: -2));
      clock.ms = 1500;
      expect(update(pose(level: -0.8, distance: 2)).axis, CoachAxis.level);
      clock.ms = 1501;
      expect(update(pose(level: -0.799, distance: 2)).axis, CoachAxis.distance);
    });

    test('0.9 stays active when another axis is outside tolerance', () {
      update(pose(level: 2));
      clock.ms = 2000;
      expect(update(pose(level: 0.9, distance: 2)).axis, CoachAxis.level);
    });

    test('new higher-priority error does not preempt an active axis', () {
      update(pose(distance: 2));
      clock.ms = 2000;
      expect(update(pose(level: 2, distance: 2)).axis, CoachAxis.distance);
    });

    test('aligned overrides both the 1.5s hold and the 0.8 exit rule', () {
      update(pose(level: 2));
      clock.ms = 10;
      final result = update(pose(level: 0.9));
      expect(result.key, InstructionKey.aligned);
      expect(result.aligned, isTrue);
      expect(result.axis, isNull);
      expect(result.errors[CoachAxis.level], closeTo(0.9, 1e-10));
    });

    test('exactly 1.0 is aligned, just above 1.0 activates', () {
      expect(update(pose(level: 1)).key, InstructionKey.aligned);
      expect(update(pose(level: 1.001)).axis, CoachAxis.level);
    });

    test('aligned does not delay the next corrective instruction', () {
      update(pose(level: 2));
      clock.ms = 100;
      update(pose());
      clock.ms = 101;
      expect(update(pose(distance: 2)).key, InstructionKey.stepBack);
    });

    test('direction changes respect the minimum hold', () {
      update(pose(horizontal: 2));
      clock.ms = 1499;
      expect(update(pose(horizontal: -2)).key, InstructionKey.stepRight);
      clock.ms = 1500;
      expect(update(pose(horizontal: -2)).key, InstructionKey.stepLeft);
    });

    test('custom hold uses the injected clock, not PoseFrame.at', () {
      engine = DefaultCoachEngine(
        clock: clock.read,
        minInstructionHold: const Duration(milliseconds: 200),
      );
      update(pose(level: 2));
      clock.ms = 199;
      expect(update(pose(distance: 2)).axis, CoachAxis.level);
      clock.ms = 200;
      expect(update(pose(distance: 2)).axis, CoachAxis.distance);
    });
  });

  group('growing error', () {
    test(
      'keeps the direction instruction; there is no opposite-way warning',
      () {
        update(pose(level: 1.2));
        clock.ms = 500;
        update(pose(level: 1.5));
        clock.ms = 1000;
        update(pose(level: 1.7));
        clock.ms = 1500;
        expect(update(pose(level: 2.01)).key, InstructionKey.holdPhoneUpright);
        clock.ms = 3000;
        expect(update(pose(level: 3)).key, InstructionKey.holdPhoneUpright);
      },
    );

    test('a growing spatial error keeps its direction', () {
      update(pose(distance: 1.2));
      clock.ms = 1000;
      update(pose(distance: 1.2));
      clock.ms = 1500;
      expect(update(pose(distance: 1.6)).key, InstructionKey.stepBack);
    });
  });

  group('missing person, framing and target changes', () {
    test('noPerson immediately stops movement and includes four errors', () {
      update(pose(distance: 2));
      clock.ms = 1;
      final result = update(noPerson());
      expect(result.key, InstructionKey.noPerson);
      expect(result.axis, isNull);
      expect(result.aligned, isFalse);
      expect(result.errors.keys.toSet(), CoachAxis.values.toSet());
      expect(result.errors.values.every((value) => value.isFinite), isTrue);
      clock.ms = 2;
      expect(update(pose(horizontal: 2)).axis, CoachAxis.horizontal);
    });

    test(
      'cropped full-body target continues distance coaching with estimated span',
      () {
        final result = update(pose(distance: 6, fullBody: false));
        expect(result.key, InstructionKey.stepBack);
        expect(result.axis, CoachAxis.distance);
        expect(result.errors[CoachAxis.distance], closeTo(6, 1e-10));
        expect(result.amount, 1.5);
        expect(result.aligned, isFalse);
      },
    );

    test(
      'all four target framings use head-to-anchor spans without a resolver',
      () {
        for (final (framing, span) in [
          (Framing.chestUp, 0.10838709677419356),
          (Framing.waistUp, 0.3096774193548387),
          (Framing.kneeUp, 0.4451612903225806),
          (Framing.fullBody, 0.6),
        ]) {
          engine.reset();
          final result = update(
            pose(fullBody: false),
            makeTarget(framing: framing, height: span),
          );
          expect(result.key, InstructionKey.aligned);
          expect(result.errors[CoachAxis.distance], closeTo(0, 1e-10));
        }
      },
    );

    test('waist-up conversion uses the 0.80m real span', () {
      final result = update(
        pose(distance: 1.75, fullBody: false),
        makeTarget(framing: Framing.waistUp, height: 0.2),
      );
      expect(result.key, InstructionKey.stepBack);
      expect(result.errors[CoachAxis.distance], closeTo(2, 1e-10));
      expect(result.amount, 2.5);
    });

    test('equal-valued new target objects preserve hold time', () {
      final first = makeTarget();
      final second = makeTarget();
      expect(identical(first, second), isFalse);
      update(pose(level: 2), first);
      clock.ms = 1499;
      expect(update(pose(distance: 2), second).axis, CoachAxis.level);
      clock.ms = 1500;
      expect(update(pose(distance: 2), makeTarget()).axis, CoachAxis.distance);
    });

    test('changing any target value clears the old active axis and hold', () {
      final targets = [
        makeTarget(height: 0.7),
        makeTarget(x: 0.4),
        makeTarget(y: 0.5),
        makeTarget(horizon: 0.4),
        makeTarget(tolHeight: 0.2),
        makeTarget(tolX: 0.1),
        makeTarget(tolY: 0.1),
        makeTarget(tolRoll: 6),
        makeTarget(source: 'reference'),
        makeTarget(framing: Framing.waistUp, height: 0.2),
        makeTarget(orientation: ShotOrientation.landscape),
      ];
      for (final target in targets) {
        engine.reset();
        clock.ms = 0;
        update(pose(level: 2));
        clock.ms = 100;
        expect(
          update(
            pose(distance: 3, orientation: target.orientation),
            target,
          ).axis,
          CoachAxis.distance,
        );
      }
    });

    test('landscape movement conversion uses the rotated FOV', () {
      final result = update(
        pose(distance: -3, orientation: ShotOrientation.landscape),
        makeTarget(orientation: ShotOrientation.landscape),
      );
      expect(result.key, InstructionKey.stepForward);
      expect(result.amount, 4.5);
    });

    test('reset clears active axis and minimum hold immediately', () {
      update(pose(level: 2));
      engine.reset();
      clock.ms = 1;
      expect(update(pose(distance: 2)).axis, CoachAxis.distance);
    });

    test(
      'degenerate body geometry yields noPerson instead of infinite amounts',
      () {
        final result = update(pose(distance: -6));
        expect(result.key, InstructionKey.noPerson);
        expect(result.aligned, isFalse);
        expect(result.errors.length, 4);
      },
    );
  });
}

class FakeClock {
  int ms = 0;
  Duration read() => Duration(milliseconds: ms);
}

TargetComposition makeTarget({
  Framing framing = Framing.fullBody,
  ShotOrientation orientation = ShotOrientation.portrait,
  double height = 0.6,
  double x = 0.5,
  double y = 0.2,
  double? horizon,
  double tolHeight = 0.1,
  double tolX = 0.08,
  double tolY = 0.08,
  double tolRoll = 3,
  String source = 'recommend:3',
}) => TargetComposition(
  framing: framing,
  orientation: orientation,
  personHeightRatio: height,
  personCenterX: x,
  personCenterY: y,
  horizonY: horizon,
  tolHeight: tolHeight,
  tolX: tolX,
  tolY: tolY,
  tolRollDeg: tolRoll,
  source: source,
);

PoseFrame noPerson({
  ShotOrientation orientation = ShotOrientation.portrait,
  bool rollReliable = true,
}) => _frame(null, 0, orientation: orientation, rollReliable: rollReliable);

PoseFrame pose({
  double level = 0,
  double distance = 0,
  double horizontal = 0,
  double height = 0,
  bool fullBody = true,
  bool rollReliable = true,
  ShotOrientation orientation = ShotOrientation.portrait,
}) {
  final points = List.filled(33, const Landmark(x: 0, y: 0, visibility: 0));
  final x = 0.5 + horizontal * 0.08;
  final head = 0.18 + height * 0.08;
  final fullSpan = 0.6 + distance * 0.1;
  final shoulderSpan = fullSpan * 0.28 / 1.55;
  void joint(int index, double y, {double visibility = 1}) {
    points[index] = Landmark(x: x, y: y, visibility: visibility);
  }

  joint(0, head + shoulderSpan / 3);
  joint(2, 0.2 + height * 0.08);
  joint(5, 0.2 + height * 0.08);
  joint(11, head + shoulderSpan);
  joint(12, head + shoulderSpan);
  joint(23, head + fullSpan * 0.80 / 1.55);
  joint(24, head + fullSpan * 0.80 / 1.55);
  joint(25, head + fullSpan * 1.15 / 1.55);
  joint(26, head + fullSpan * 1.15 / 1.55);
  joint(27, head + fullSpan, visibility: fullBody ? 1 : 0.1);
  joint(28, head + fullSpan, visibility: fullBody ? 1 : 0.1);
  return _frame(
    points,
    level * 3,
    orientation: orientation,
    rollReliable: rollReliable,
  );
}

PoseFrame _frame(
  List<Landmark>? points,
  double roll, {
  ShotOrientation orientation = ShotOrientation.portrait,
  bool rollReliable = true,
}) => PoseFrame(
  landmarks: points,
  imageWidth: orientation == ShotOrientation.portrait ? 480 : 640,
  imageHeight: orientation == ShotOrientation.portrait ? 640 : 480,
  orientation: orientation,
  rollDeg: roll,
  pitchDeg: 0,
  rollReliable: rollReliable,
  at: DateTime.utc(2026, 10, 31),
);
