import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'actions.dart';
import 'compositions.dart';
import 'director.dart';
import 'director_models.dart';
import 'background_features.dart';

void main() {
  final records =
      (jsonDecode(
                File(
                  'lib/features/scene/experimental/composition_director_v1/parity_fixtures.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  MovementContext simulated(
    DirectorFrame f, {
    String actor = 'subject',
    double dx = .2,
  }) => MovementContext(
    motions: [
      MeasuredMotion(
        actor,
        'horizontal',
        dx,
        0,
        0,
        .9,
        f.at,
        f.geometry,
        preservation: .95,
      ),
    ],
    safe: {'$actor/left', '$actor/right'},
    safetyAt: f.at,
    geometry: f.geometry,
  );
  DirectorFrame withPerson(
    DirectorFrame f,
    DirectorPerson? p,
    double at, {
    List<double>? mask,
    String? geometry,
  }) => DirectorFrame(
    f.width,
    f.height,
    f.gray,
    mask ?? f.mask,
    p,
    at,
    orientation: f.orientation,
    level: f.level,
    geometry: geometry ?? f.geometry,
  );
  for (final r in records) {
    test('Python parity: ${r['name']}', () {
      final frame = DirectorFrame.fromJson(r['frame'] as Map<String, dynamic>);
      final actual = CompositionDirector().update(frame, simulated(frame));
      final expected = r['expected'] as Map<String, dynamic>,
          features = expected['features'] as Map<String, dynamic>;
      expect(actual.features.lines.length, (features['lines'] as List).length);
      expect(
        actual.features.confidence,
        closeTo(features['confidence'] as num, 1e-8),
      );
      for (var i = 0; i < 9; i++) {
        final cell = (features['cells'] as List)[i] as Map<String, dynamic>;
        expect(
          actual.features.cells[i].coverage,
          closeTo(cell['coverage'] as num, 1e-10),
        );
        expect(
          actual.features.cells[i].texture,
          closeTo(cell['texture'] as num, 1e-8),
        );
      }
      final target = expected['target'] as Map<String, dynamic>;
      expect(actual.target!.x, closeTo(target['x'] as num, 1e-8));
      expect(actual.target!.eyeY, closeTo(target['eye_y'] as num, 1e-8));
      expect(actual.target!.scale, closeTo(target['scale'] as num, 1e-8));
      expect(actual.target!.score, closeTo(target['score'] as num, 1e-8));
      expect(actual.target!.framing, target['framing']);
      expect(actual.action.text, (expected['action'] as Map)['text']);
      expect(actual.action.direction, (expected['action'] as Map)['direction']);
    });
  }
  final f = DirectorFrame.fromJson(records[1]['frame'] as Map<String, dynamic>);
  test('No calibration or expired safety cannot issue a movement', () {
    final features = analyzeScene(f),
        target = selectCandidate(generateCandidates(f, features))!;
    expect(
      decideAction(f, target, features, const MovementContext()).direction,
      'hold',
    );
    final old = MovementContext(
      motions: simulated(f).motions,
      safe: simulated(f).safe,
      safetyAt: -4,
      geometry: f.geometry,
    );
    expect(decideAction(f, target, features, old).direction, 'hold');
  });
  test(
    'Actor-specific response keeps camera and subject directions separate',
    () {
      final features = analyzeScene(f),
          target = selectCandidate(generateCandidates(f, features))!;
      expect(
        decideAction(f, target, features, simulated(f)).direction,
        'right',
      );
      expect(
        decideAction(
          f,
          target,
          features,
          simulated(f, actor: 'photographer', dx: -.2),
        ).direction,
        'left',
      );
    },
  );
  test('No progress blocks repeated instructions; cooldown holds', () {
    final director = CompositionDirector();
    expect(director.update(f, simulated(f)).action.direction, 'right');
    expect(
      director.update(withPerson(f, f.person, .5), simulated(f)).progress,
      'waiting',
    );
    final unchanged = withPerson(f, f.person, 2);
    expect(
      director.update(unchanged, simulated(unchanged)).action.reason,
      'movement-needs-reassessment',
    );
    expect(
      director.update(withPerson(f, f.person, 4)).action.direction,
      'hold',
    );
  });
  test('Observed improvement keeps target and stops when acceptable', () {
    final director = CompositionDirector();
    final first = director.update(f, simulated(f));
    final moved = withPerson(f, f.person!.shifted(.10, 0, 0), 2);
    final next = director.update(moved, simulated(moved));
    expect(next.generation, first.generation);
    expect(next.target, same(first.target));
    expect(next.action.direction, 'capture');
  });
  test('Person loss, bad mask and geometry changes reset safely', () {
    final director = CompositionDirector();
    final first = director.update(f);
    expect(director.update(withPerson(f, null, 1)).action.direction, 'hold');
    expect(
      director
          .update(
            withPerson(f, f.person, 2, mask: List.filled(f.mask.length, 1)),
          )
          .action
          .direction,
      'hold',
    );
    expect(
      director
          .update(withPerson(f, f.person, 3, geometry: 'different-crop'))
          .generation,
      greaterThan(first.generation),
    );
  });
  test('Korean and low-visibility head landmarks preserve the contract', () {
    expect(
      koreanSentence('photographer', 'backward'),
      '촬영자님, 뒤로 반 걸음 이동해 주세요.',
    );
    final points = List<(double, double, double)>.filled(33, (0, 0, 0));
    points[0] = (.5, .2, 0);
    points[2] = (.48, .18, 0);
    points[5] = (.52, .18, 0);
    points[11] = (.45, .3, 1);
    points[12] = (.55, .3, 1);
    expect(DirectorPerson.fromPoints(points)!.headY, closeTo(.15, 1e-10));
    points[11] = (.45, .3, .1);
    expect(DirectorPerson.fromPoints(points), isNull);
  });
}
