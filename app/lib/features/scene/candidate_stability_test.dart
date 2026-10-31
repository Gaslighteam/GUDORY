// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../coach/coach_engine.dart';
import 'candidate_stability.dart';

ScoredLayoutCandidate candidate(
  String id,
  double score, {
  double x = .3,
  int level = 3,
  ShotOrientation orientation = ShotOrientation.portrait,
  bool challenge = true,
}) => ScoredLayoutCandidate(
  id: id,
  score: score,
  canChallenge: challenge,
  recommendation: Recommendation(
    target: TargetComposition(
      personHeightRatio: .6,
      personCenterX: x,
      personCenterY: .18,
      orientation: orientation,
      source: 'recommend:$level',
    ),
    neighbors: 6,
    modelVariant: 'q8',
  ),
);

void main() {
  var time = Duration.zero;
  late CandidateSelector selector;
  const context = CandidateContext(
    3,
    ShotOrientation.portrait,
    ShootMode.recommend,
  );
  setUp(() {
    time = Duration.zero;
    selector = CandidateSelector(clock: () => time);
  });

  test(
    '5.9 seconds holds a much better candidate; exactly 6 seconds switches',
    () {
      final a = candidate('A', .5), b = candidate('B', .9, x: .7);
      selector.update(context, [a]);
      time = const Duration(milliseconds: 5900);
      expect(selector.update(context, [a, b]), same(a.recommendation));
      time = const Duration(seconds: 6);
      expect(selector.update(context, [a, b]), same(b.recommendation));
      expect(selector.selectedAt, time);
    },
  );
  test('after 6 seconds insufficient score advantage keeps incumbent', () {
    selector.update(context, [candidate('A', .8)]);
    time = const Duration(seconds: 20);
    selector.update(context, [candidate('A', .8), candidate('B', .87)]);
    expect(selector.selectedId, 'A');
  });
  test(
    'same candidate does not reset selection time or update target snapshot',
    () {
      final a = candidate('A', .5);
      selector.update(context, [a]);
      time = const Duration(seconds: 3);
      expect(
        selector.update(context, [candidate('A', .7, x: .31)]),
        same(a.recommendation),
      );
      expect(selector.selectedAt, Duration.zero);
      time = const Duration(seconds: 6);
      selector.update(context, [candidate('A', .5), candidate('B', .9)]);
      expect(selector.selectedId, 'B');
    },
  );
  test('hysteresis re-scores incumbent on the same current input', () {
    selector.update(context, [candidate('A', .95)]);
    time = const Duration(seconds: 6);
    selector.update(context, [candidate('A', .2), candidate('B', .5)]);
    expect(selector.selectedId, 'B');
  });
  test(
    'noise and alternating small advantages cannot cause side ping-pong',
    () {
      selector.update(context, [candidate('A', .8)]);
      for (var i = 1; i <= 20; i++) {
        time = Duration(seconds: i * 3);
        selector.update(context, [
          candidate('A', i.isEven ? .8 : .83),
          candidate('B', .85),
        ]);
        expect(selector.selectedId, 'A');
      }
    },
  );
  test(
    'failure/empty results preserve a good candidate without resetting time',
    () {
      final a = candidate('A', .8);
      selector.update(context, [a]);
      time = const Duration(seconds: 30);
      expect(selector.update(context, []), same(a.recommendation));
      expect(selector.selectedAt, Duration.zero);
      expect(CandidateSelector().update(context, []), isNull);
    },
  );
  test(
    'level and orientation changes immediately reselect; no stale fallback',
    () {
      selector.update(context, [candidate('A', .9)]);
      time = const Duration(seconds: 1);
      const level = CandidateContext(
        4,
        ShotOrientation.portrait,
        ShootMode.recommend,
      );
      expect(selector.update(level, []), isNull);
      selector.update(level, [candidate('B', .5, level: 4)]);
      expect(selector.selectedId, 'B');
      const landscape = CandidateContext(
        4,
        ShotOrientation.landscape,
        ShootMode.recommend,
      );
      selector.update(landscape, [
        candidate('C', .5, level: 4, orientation: ShotOrientation.landscape),
      ]);
      expect(selector.selectedId, 'C');
    },
  );
  test(
    'explicit custom mode invalidates; return to recommend selects fresh',
    () {
      selector.update(context, [candidate('A', .9)]);
      expect(
        selector.update(
          const CandidateContext(3, ShotOrientation.portrait, ShootMode.custom),
          [],
        ),
        isNull,
      );
      selector.update(context, [candidate('B', .5)]);
      expect(selector.selectedId, 'B');
    },
  );
  test('clock rollback cannot shorten minimum hold; tunable values work', () {
    selector = CandidateSelector(
      clock: () => time,
      config: const CandidateStabilityConfig(
        minimumHold: Duration(seconds: 2),
        switchMargin: .2,
      ),
    );
    time = const Duration(seconds: 4);
    selector.update(context, [candidate('A', .5)]);
    time = Duration.zero;
    selector.update(context, [candidate('A', .5), candidate('B', 1)]);
    expect(selector.selectedId, 'A');
    time = const Duration(seconds: 6);
    selector.update(context, [candidate('A', .5), candidate('B', .7)]);
    expect(selector.selectedId, 'B');
  });
  test('out-of-top-three incumbent is scored, but cannot challenge itself', () {
    selector.update(context, [candidate('A', .9)]);
    time = const Duration(seconds: 6);
    selector.update(context, [
      candidate('A', .85, challenge: false),
      candidate('B', .9),
    ]);
    expect(selector.selectedId, 'A');
  });
  test('invalid candidates are ignored and ties are deterministic', () {
    selector.update(context, [
      candidate('bad', double.nan),
      candidate('wrong-level', 1, level: 4),
      candidate('B', .8),
      candidate('A', .8),
    ]);
    expect(selector.selectedId, 'A');
    expect(
      () => CandidateSelector(
        config: const CandidateStabilityConfig(switchMargin: 0),
      ),
      throwsArgumentError,
    );
  });
  test(
    'new target resets CoachEngine hold without changing its implementation',
    () {
      final engine = DefaultCoachEngine(clock: () => time);
      final a = candidate('A', .5, x: .2), b = candidate('B', .9, x: .7);
      final first = selector.update(context, [a])!;
      final points = List.filled(
        33,
        const Landmark(x: .4, y: .5, visibility: 1),
      );
      points[0] = const Landmark(x: .4, y: .25, visibility: 1);
      for (final i in [2, 5]) {
        points[i] = const Landmark(x: .4, y: .18, visibility: 1);
      }
      for (final i in [11, 12]) {
        points[i] = const Landmark(x: .4, y: .35, visibility: 1);
      }
      for (final i in [27, 28]) {
        points[i] = const Landmark(x: .4, y: .8, visibility: 1);
      }
      final pose = PoseFrame(
        landmarks: points,
        imageWidth: 480,
        imageHeight: 640,
        rollDeg: 0,
        pitchDeg: 0,
        at: DateTime(2026),
      );
      time = const Duration(milliseconds: 5900);
      expect(engine.update(pose, first.target).key, InstructionKey.stepRight);
      time = const Duration(seconds: 6);
      final second = selector.update(context, [a, b])!;
      expect(engine.update(pose, second.target).key, InstructionKey.stepLeft);
      final unreliable = PoseFrame(
        landmarks: points,
        imageWidth: 480,
        imageHeight: 640,
        rollDeg: 10,
        pitchDeg: 0,
        rollReliable: false,
        at: DateTime(2026),
      );
      final aligned = candidate('aligned', 1, x: .4).recommendation.target;
      expect(engine.update(unreliable, aligned).key, InstructionKey.raisePhone);
    },
  );
}
