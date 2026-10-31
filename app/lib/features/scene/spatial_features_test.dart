// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'spatial_features.dart';
import 'spatial_test_fixtures.dart';
import 'scene_embedding.dart';
import 'scene_test_frames.dart';
import 'person_mask.dart';
import 'nv21_frame.dart';

void main() {
  final fixture = spatialParityFixture();
  for (final raw in fixture['feature_cases'] as List) {
    final c = raw as Map<String, dynamic>;
    test('Python/Dart feature parity: ${c['name']}', () {
      final w = c['width'] as int, h = c['height'] as int;
      final (rgb, mask) = spatialPattern(
        width: w,
        height: h,
        side: c['side'] as String,
        maskX: c['mask_x'] as int,
        personValue: c['person_value'] as int,
      );
      final f = extractSpatial(rgb, w, h, mask, w, h);
      expect(f.reason, c['reason']);
      expect(f.grid.length, (c['grid'] as List).length);
      for (final pair in [
        (f.grid, c['grid'] as List),
        (f.centroid, c['centroid'] as List),
        (f.asymmetry, c['asymmetry'] as List),
      ]) {
        for (var i = 0; i < pair.$1.length; i++) {
          expect(pair.$1[i], closeTo((pair.$2[i] as num).toDouble(), 1e-9));
        }
      }
      expect(f.confidence, closeTo((c['confidence'] as num).toDouble(), 1e-9));
      expect(f.coverage, closeTo((c['coverage'] as num).toDouble(), 1e-9));
    });
  }
  test('Invalid/full masks are unavailable, never negative space', () {
    final (rgb, _) = spatialPattern();
    expect(extractSpatial(rgb, 96, 96, [double.nan], 1, 1).valid, isFalse);
    expect(
      extractSpatial(rgb, 96, 96, List.filled(96 * 96, 1), 96, 96).valid,
      isFalse,
    );
  });
  test(
    'Opt-in spatial extraction leaves all legacy CLIP tensors unchanged',
    () {
      for (final rotation in [0, 90, 180, 270]) {
        for (final mirror in [false, true]) {
          for (final q in [-1, 0, 1]) {
            final frame = stripeNv21(rotation: rotation, mirror: mirror);
            final mask = PersonMask(
              width: 2,
              height: 2,
              confidences: [1, 0, 1, 0],
            );
            final job = (frame, mask, SceneView(quarterTurns: q));
            final old = prepareRecommendationInput(job),
                experiment = prepareSpatialRecommendationInput(job);
            expect(experiment.pixels, orderedEquals(old.pixels));
            expect(old.spatial, isNull);
            expect(experiment.spatial, isNotNull);
          }
        }
      }
    },
  );
  test(
    'Mask and spatial coordinates follow the same portrait/crop/landscape transform',
    () {
      const w = 384, h = 512;
      final bytes = Uint8List(w * h * 3 ~/ 2)
        ..fillRange(w * h, w * h * 3 ~/ 2, 128);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          bytes[y * w + x] = x >= w * 2 ~/ 3
              ? ((x ~/ 16 + y ~/ 16) % 2 == 1 ? 220 : 30)
              : 100;
        }
      }
      final mask = PersonMask(
        width: 96,
        height: 128,
        confidences: List.generate(
          96 * 128,
          (i) => ((i % 96 - 48).abs() < 5 && i ~/ 96 >= 50 && i ~/ 96 < 80)
              ? 1
              : 0,
        ),
      );
      Nv21FrameData frame(bool mirror) => Nv21FrameData(
        bytes: bytes,
        width: w,
        height: h,
        rowStride: w,
        rotation: 0,
        mirror: mirror,
      );
      final right = prepareSpatialRecommendationInput((
        frame(false),
        mask,
        const SceneView(),
      )).spatial!;
      final left = prepareSpatialRecommendationInput((
        frame(true),
        mask,
        const SceneView(),
      )).spatial!;
      expect(right.valid, isTrue);
      expect(left.valid, isTrue);
      expect(right.centroid[0], greaterThan(.65));
      expect(left.centroid[0], lessThan(.35));
      final top = prepareSpatialRecommendationInput((
        frame(false),
        mask,
        const SceneView(quarterTurns: 1),
      )).spatial!;
      final bottom = prepareSpatialRecommendationInput((
        frame(false),
        mask,
        const SceneView(quarterTurns: -1),
      )).spatial!;
      expect(top.valid, isTrue);
      expect(bottom.valid, isTrue);
      expect(top.centroid[1], lessThan(.35));
      expect(bottom.centroid[1], greaterThan(.65));
      final cropped = prepareSpatialRecommendationInput((
        frame(false),
        mask,
        const SceneView(width: .5),
      )).spatial!;
      expect(cropped.valid, isFalse);
    },
  );
  test('Host-only spatial extraction timing, not an Android latency claim', () {
    final (rgb, mask) = spatialPattern();
    final samples = <int>[];
    for (var i = 0; i < 40; i++) {
      final watch = Stopwatch()..start();
      extractSpatial(rgb, 96, 96, mask, 96, 96);
      watch.stop();
      if (i >= 10) samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    // ignore: avoid_print
    print(
      'PHASE_B_HOST_ONLY feature_us p50=${samples[15]} p95=${samples[28]} typed_work_arrays_bytes=${96 * 96 * 5}',
    );
  });
}
