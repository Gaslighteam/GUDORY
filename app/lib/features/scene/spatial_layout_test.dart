// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../core/models.dart';
import 'spatial_layout.dart';
import 'spatial_asset_digest.dart';
import 'spatial_test_fixtures.dart';
import 'recommendation_test_fixtures.dart';

void main() {
  final fixture = spatialParityFixture(),
      selection = fixture['selection'] as Map<String, dynamic>;
  final a = selection['phase_a_text'] as String,
      b = jsonEncode(selection['phase_b']);
  test('Content link SHA256 known vectors and actual Phase A asset', () {
    expect(
      spatialAssetDigest(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      spatialAssetDigest('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      spatialAssetDigest(a),
      (selection['phase_b'] as Map)['phase_a_sha256'],
    );
    expect(
      spatialAssetDigest(
        File('../tools/layout_prototypes.experimental.json').readAsStringSync(),
      ),
      'd069c3356e9fe3f25416076f885a3f9b41f045bea73c2c54cdeb37df029a9f82',
    );
  });
  for (final raw in selection['queries'] as List) {
    final q = raw as Map<String, dynamic>;
    test('Python/Dart candidate parity: beta=${q['beta']} ${q['side']}', () {
      final data = SpatialLayoutData.parse(a, b);
      final candidates = data.rank(
        embeddingFixture(),
        1,
        ShotOrientation.portrait,
        spatialPatternFeature(q['side'] as String),
        config: SpatialScoring(beta: (q['beta'] as num).toDouble()),
      );
      expect(candidates.first.prototype.id, q['id']);
      expect(
        candidates.first.score,
        closeTo((q['score'] as num).toDouble(), 1e-9),
      );
      expect(
        candidates.first.spatialWeight,
        closeTo((q['spatial_weight'] as num).toDouble(), 1e-9),
      );
    });
  }
  test(
    'Invalid/missing/older B sidecars retain Phase A, and all ten fallbacks',
    () {
      for (final raw in [
        null,
        '{}',
        a,
        jsonEncode({...selection['phase_b'] as Map, 'version': 99}),
      ]) {
        final data = SpatialLayoutData.parse(a, raw);
        expect(data.records, isEmpty);
        final answer = data.rank(
          embeddingFixture(),
          3,
          ShotOrientation.portrait,
          spatialPatternFeature('right'),
        );
        final baseline = SpatialLayoutData.parse(a, null).rank(
          embeddingFixture(),
          3,
          ShotOrientation.portrait,
          null,
          config: const SpatialScoring(beta: 0),
        );
        expect(answer.first.prototype.id, baseline.first.prototype.id);
        for (final o in ShotOrientation.values) {
          for (var lv = 1; lv <= 5; lv++) {
            expect(data.base.fallback(lv, o).target.orientation, o);
          }
        }
      }
    },
  );
  test(
    'Unknown/private fields, unsupported n and wrong content links disable B',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['photo_id'] = 'forbidden',
        (m) => (m['records'] as Map).values.first['n'] = 2,
        (m) => m['phase_a_sha256'] = '0' * 64,
        (m) => (m['records'] as Map).values.first['grid'] = [1.1],
      ]) {
        final m = jsonDecode(b) as Map<String, dynamic>;
        mutate(m);
        expect(SpatialLayoutData.parse(a, jsonEncode(m)).records, isEmpty);
      }
    },
  );
  test('Unknown Phase A fields are rejected before matching', () {
    final m = jsonDecode(a) as Map<String, dynamic>..['photo_id'] = 'forbidden';
    expect(
      () => SpatialLayoutData.parse(jsonEncode(m), b),
      throwsFormatException,
    );
  });
  test(
    'Missing spatial statistics cannot create a normalization advantage',
    () {
      final partial = jsonDecode(b) as Map<String, dynamic>;
      (partial['records'] as Map).remove('p-0-1-1');
      final data = SpatialLayoutData.parse(a, jsonEncode(partial));
      final actual = data.rank(
        embeddingFixture(),
        1,
        ShotOrientation.portrait,
        spatialPatternFeature('left'),
        config: const SpatialScoring(beta: 5),
      );
      final expected = data.rank(
        embeddingFixture(),
        1,
        ShotOrientation.portrait,
        null,
        config: const SpatialScoring(beta: 0),
      );
      expect(actual.first.prototype.id, expected.first.prototype.id);
      expect(actual.every((c) => c.spatialWeight == 0), isTrue);
    },
  );
  test('Spatial compatibility cannot promote a weak CLIP background', () {
    final weak = fixture['weak_clip'] as Map<String, dynamic>;
    final data = SpatialLayoutData.parse(
      weak['phase_a_text'] as String,
      jsonEncode(weak['phase_b']),
    );
    final ranked = data.rank(
      embeddingFixture(),
      1,
      ShotOrientation.portrait,
      spatialPatternFeature('right'),
      config: const SpatialScoring(beta: 100),
    );
    expect(ranked.first.prototype.id, weak['winner']);
    expect(
      ranked
          .where((c) => c.prototype.id.startsWith('p-1-'))
          .every((c) => !c.canChallenge),
      isTrue,
    );
  });
  test(
    'Incumbent outside the current pool is rescored but cannot challenge',
    () {
      final data = SpatialLayoutData.parse(a, b);
      final incumbent = data.rescoreIncumbent(
        embeddingFixture(),
        ShotOrientation.portrait,
        null,
        [],
        'p-0-1-0',
        config: const SpatialScoring(beta: 0),
      );
      expect(incumbent, isNotNull);
      expect(incumbent!.score, greaterThan(.8));
      expect(incumbent.score, lessThanOrEqualTo(1));
      expect(incumbent.canChallenge, isFalse);
      expect(
        data.rescoreIncumbent(
          embeddingFixture(),
          ShotOrientation.portrait,
          null,
          [incumbent],
          incumbent.prototype.id,
        ),
        isNull,
      );
      expect(
        data.rescoreIncumbent(
          embeddingFixture(),
          ShotOrientation.landscape,
          null,
          [],
          incumbent.prototype.id,
        ),
        isNull,
      );
    },
  );
  test(
    'Full real aggregate sidecar parses without touching production assets',
    () {
      final aFile = File('../tools/layout_prototypes.experimental.json'),
          bFile = File('../tools/layout_spatial.experimental.json');
      final data = SpatialLayoutData.parse(
        aFile.readAsStringSync(),
        bFile.readAsStringSync(),
      );
      expect(data.prototypes.length, 414);
      expect(data.records, isNotEmpty);
      final answer = data.rank(
        data.parents.first.center,
        3,
        ShotOrientation.portrait,
        spatialPatternFeature('right'),
      );
      expect(answer, isNotEmpty);
      for (final c in answer) {
        expect(c.score, inInclusiveRange(0, 1));
        expect(c.prototype.composition.n, greaterThanOrEqualTo(3));
      }
    },
  );
}
