// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import 'layout_prototypes.dart';
import 'recommendation_data.dart';
import 'recommendation_test_fixtures.dart';

Map<String, dynamic> layoutMode(
  String id,
  double x, {
  int n = 3,
  double confidence = .5,
}) => {
  'id': id,
  'f': 'fullBody',
  'h': .6,
  'cx': x,
  'cy': .3,
  'hy': null,
  'n': n,
  'spread': .05,
  'confidence': confidence,
};
Map<String, dynamic> layoutFixture(Map<String, dynamic> base) => {
  'version': 1,
  'clusters': [
    for (var i = 0; i < (base['clusters'] as List).length; i++)
      {
        'o': base['clusters'][i]['o'],
        'e': base['clusters'][i]['e'],
        'lv': {
          '3': [
            layoutMode(
              '${base['clusters'][i]['o']}-${i.toRadixString(16).padLeft(24, '0')}-3-0',
              .3,
            ),
            layoutMode(
              '${base['clusters'][i]['o']}-${i.toRadixString(16).padLeft(24, '0')}-3-1',
              .7,
            ),
          ],
        },
      },
  ],
};

void main() {
  late Map<String, dynamic> base, raw;
  late RecommendationData data;
  setUp(() {
    base = recommendationFixture(
      clusters: [
        clusterFixture(levels: {'3': compositionFixture(n: 6)}),
      ],
    );
    data = RecommendationData.parse(jsonEncode(base));
    raw = layoutFixture(base);
  });
  test(
    'both observed sides remain separate and neither target is averaged',
    () {
      final modes = LayoutPrototypeData.parse(
        jsonEncode(raw),
        data,
      ).rank(embeddingFixture(), 3, ShotOrientation.portrait, 'q8');
      expect(modes.map((m) => m.recommendation.target.personCenterX), [.3, .7]);
      expect(modes.every((m) => m.recommendation.neighbors == 3), isTrue);
      expect(modes.every((m) => m.score.isFinite), isTrue);
    },
  );
  test(
    'unknown fields, low support, excess support and unrelated centre reject',
    () {
      final changes = <void Function(Map<String, dynamic>)>[
        (r) => r['photo_id'] = 'private',
        (r) => r['clusters'][0]['lv']['3'][0]['filename'] = 'private',
        (r) => r['clusters'][0]['lv']['3'][0]['n'] = 2,
        (r) => r['clusters'][0]['lv']['3'][0]['n'] = 30,
        (r) => r['clusters'][0]['e'] = clusterFixture(cosine: .4)['e'],
        (r) => r['clusters'][0]['lv']['3'][0]['cx'] = 1.1,
        (r) => r['clusters'][0]['lv']['3'][1]['id'] =
            r['clusters'][0]['lv']['3'][0]['id'],
      ];
      for (final change in changes) {
        final r = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
        change(r);
        expect(
          () => LayoutPrototypeData.parse(jsonEncode(r), data),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'wrong direction, missing level and invalid variant have no candidates',
    () {
      final parsed = LayoutPrototypeData.parse(jsonEncode(raw), data);
      expect(
        parsed.rank(embeddingFixture(), 3, ShotOrientation.landscape, 'q8'),
        isEmpty,
      );
      expect(
        parsed.rank(embeddingFixture(), 2, ShotOrientation.portrait, 'q8'),
        isEmpty,
      );
      expect(
        parsed.rank(embeddingFixture(), 3, ShotOrientation.portrait, 'none'),
        isEmpty,
      );
    },
  );
  test('supports all framing anchors without mixing heights', () {
    for (final f in Framing.values) {
      for (final mode in raw['clusters'][0]['lv']['3']) {
        mode['f'] = f.name;
      }
      final ranked = LayoutPrototypeData.parse(
        jsonEncode(raw),
        data,
      ).rank(embeddingFixture(), 3, ShotOrientation.portrait, 'fp16');
      expect(ranked.every((m) => m.recommendation.target.framing == f), isTrue);
    }
  });
  test('sidecar does not change the old parser or fallback', () {
    final old = data.match(
      embeddingFixture(),
      3,
      ShotOrientation.portrait,
      'q8',
    );
    LayoutPrototypeData.parse(jsonEncode(raw), data);
    expect(old.recommendation.target.personCenterX, .5);
    expect(data.fallback(3, ShotOrientation.portrait).neighbors, 0);
  });
  test(
    'unsupported nearest backgrounds do not promote a distant prototype',
    () {
      base = recommendationFixture(
        clusters: [
          for (final cosine in [1.0, .9, .8, .5])
            clusterFixture(
              cosine: cosine,
              levels: {'3': compositionFixture(n: 6)},
            ),
        ],
      );
      data = RecommendationData.parse(jsonEncode(base));
      raw = layoutFixture(base);
      raw['clusters'] = [raw['clusters'][3]];
      final ranked = LayoutPrototypeData.parse(
        jsonEncode(raw),
        data,
      ).rank(embeddingFixture(), 3, ShotOrientation.portrait, 'q8');
      expect(ranked, isNotEmpty);
      expect(ranked.every((c) => !c.canChallenge), isTrue);
    },
  );
  test('candidate confidence and score weights are adjustable heuristics', () {
    raw['clusters'][0]['lv']['3'][1]['confidence'] = .8;
    final ranked = LayoutPrototypeData.parse(jsonEncode(raw), data).rank(
      embeddingFixture(),
      3,
      ShotOrientation.portrait,
      'q8',
      config: const LayoutScoringConfig(clipWeight: 0, supportWeight: 1),
    );
    expect(ranked[1].score, .8);
    expect(
      () => const LayoutScoringConfig(clipWeight: -1).validate(),
      throwsArgumentError,
    );
  });
}
