import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/scene/composition_model.dart';
import 'package:gudory/features/scene/person_mask.dart';
import 'package:gudory/features/scene/scene_embedding.dart';
import 'package:gudory/features/scene/scene_test_frames.dart';

/// k = 1: the single component reads embedding[0]; features = [z, onehot x10].
Map<String, dynamic> asset({double offsetBias = .1}) {
  List<double> zeros(int n) => List.filled(n, 0.0);
  final component = zeros(512)..[0] = 1;
  final framingCoef = [for (var c = 0; c < 4; c++) zeros(11)];
  framingCoef[3][0] = 5; // a high z picks fullBody
  framingCoef[1][6] = 1; // landscape level 1 leans waistUp
  return {
    'model': 'gudory-recommender-v2',
    'dim': 512,
    'k': 1,
    'photos': 694,
    'framings': ['chestUp', 'waistUp', 'kneeUp', 'fullBody'],
    'mean': zeros(512),
    'components': [component],
    'framing': {'coef': framingCoef, 'intercept': zeros(4)},
    'offset': {
      'coef': zeros(11)..[0] = .2,
      'intercept': offsetBias,
      'max': .35,
    },
    'eyeY': {'coef': zeros(11)..[3] = .1, 'intercept': .3},
    'height': {
      for (final o in ['portrait', 'landscape'])
        o: {
          for (var l = 1; l <= 5; l++)
            '$l': {
              'chestUp': .2 + l / 100,
              'waistUp': .4 + l / 100,
              'kneeUp': .6 + l / 100,
              'fullBody': .8 + l / 100,
            },
        },
    },
  };
}

List<double> embedding(double first) => List.filled(512, 0.0)..[0] = first;

void main() {
  test('predicts framing, offset, eye line and the level height', () {
    final model = CompositionModel.parse(jsonEncode(asset()));
    expect(model.photos, 694);
    final t = model.predict(
      embedding(.5),
      3,
      ShotOrientation.portrait,
      personX: .7,
    );
    expect(t.framing, Framing.fullBody);
    expect(t.personCenterX, closeTo(.5 + (.1 + .2 * .5), 1e-9));
    expect(t.personCenterY, closeTo(.3 + .1, 1e-9)); // one-hot index 2 + 1
    expect(t.personHeightRatio, closeTo(.83, 1e-9));
    expect(t.orientation, ShotOrientation.portrait);
    expect(t.source, 'recommend-v2:3');
  });

  test('keeps the person on the side they stand on', () {
    final model = CompositionModel.parse(jsonEncode(asset()));
    final left = model.predict(
      embedding(0),
      1,
      ShotOrientation.landscape,
      personX: .2,
    );
    expect(left.personCenterX, closeTo(.4, 1e-9));
    expect(left.framing, Framing.waistUp);
    expect(
      model.predict(embedding(0), 1, ShotOrientation.landscape).personCenterX,
      closeTo(.6, 1e-9), // unknown side: right
    );
  });

  test('clamps the offset and rejects malformed assets', () {
    final model = CompositionModel.parse(jsonEncode(asset(offsetBias: 2)));
    expect(
      model
          .predict(embedding(0), 9, ShotOrientation.portrait, personX: .9)
          .personCenterX,
      closeTo(.85, 1e-9),
    );
    for (final broken in [
      {...asset(), 'model': 'other'},
      {...asset(), 'k': 2},
      {...asset(), 'mean': <double>[]},
      {
        ...asset(),
        'framings': ['a', 'b', 'c', 'd'],
      },
    ]) {
      expect(
        () => CompositionModel.parse(jsonEncode(broken)),
        throwsFormatException,
      );
    }
    expect(
      () => model.predict([1, 2], 1, ShotOrientation.portrait),
      throwsFormatException,
    );
  });

  test('bundled asset matches the Python trainer', () {
    final file = File('assets/recommend_v2.json');
    final model = CompositionModel.parse(file.readAsStringSync());
    final golden =
        jsonDecode(
              File('test/scene/recommend_v2_golden.json').readAsStringSync(),
            )
            as List;
    for (final g in golden.cast<Map<String, dynamic>>()) {
      final t = model.predict(
        (g['embedding'] as List).cast<num>().map((v) => v.toDouble()).toList(),
        g['level'] as int,
        ShotOrientation.values.byName(g['orientation'] as String),
        personX: (g['personX'] as num).toDouble(),
      );
      expect(t.framing.name, g['f']);
      expect(t.personHeightRatio, closeTo(g['h'] as num, 1e-6));
      expect(t.personCenterX, closeTo(g['cx'] as num, 1e-5));
      expect(t.personCenterY, closeTo(g['cy'] as num, 1e-5));
    }
  });

  test('the scene trace carries the person centroid in shot space', () {
    final mask = PersonMask(width: 2, height: 2, confidences: [1, 0, 1, 0]);
    double? personX(bool mirror) => prepareRecommendationInput((
      stripeNv21(mirror: mirror),
      mask,
      const SceneView(),
    )).trace.personX;
    final plain = personX(false), mirrored = personX(true);
    expect(plain, isNotNull);
    expect(plain, inInclusiveRange(0, 1));
    expect(mirrored, isNot(closeTo(plain!, 1e-9))); // follows the mirrored shot
    expect(personCentroidX(0, 0, 10), isNull);
  });
}
