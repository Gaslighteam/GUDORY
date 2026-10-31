import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'person_mask.dart';
import 'preprocess.dart';
import 'scene_test_frames.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'actual plugin channel receives packed NV21 and sensor rotation metadata',
    () async {
      const channel = MethodChannel('google_mlkit_selfie_segmenter');
      final data = stripeNv21(rowStride: 12, rotation: 270, mirror: true);
      var closed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            if (call.method == 'vision#closeSelfieSegmenter') {
              closed = true;
              return null;
            }
            expect(call.method, 'vision#startSelfieSegmenter');
            expect(args['isStream'], isFalse);
            expect(args['enableRawSizeMask'], isTrue);
            final image = args['imageData'] as Map;
            expect(image['bytes'], orderedEquals(stripeNv21().bytes));
            final meta = image['metadata'] as Map;
            expect(meta['rotation'], 270);
            expect(meta['width'], 8);
            expect(meta['height'], 8);
            expect(meta['bytes_per_row'], 8);
            expect(meta['image_format'], 17);
            return {
              'width': 2,
              'height': 1,
              'confidences': [1.0, 0.0],
            };
          });
      final masker = PersonMasker();
      try {
        final mask = await masker.maskFor(cameraFrameFixture(data));
        expect(mask?.isUsable, isTrue);
        expect(mask?.confidences, [1, 0]);
        expect(masker.lastStatus, 'ok 2x1');
      } finally {
        await masker.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
      expect(closed, isTrue);
    },
  );

  test(
    'plugin exceptions and missing plugin fall back without blocking RGB preprocessing',
    () async {
      for (final error in [
        PlatformException(code: 'failed'),
        MissingPluginException('not available'),
        StateError('bad native result'),
      ]) {
        final masker = PersonMasker(process: (_) async => throw error);
        final mask = await masker.maskData(stripeNv21());
        expect(mask, isNull);
        expect(masker.lastStatus, 'segmentation-failed');
        final result = await preprocessData(stripeNv21(), mask: mask);
        expect(result.maskApplied, isFalse);
        expect(result.pixels.length, 150528);
        await masker.close();
      }
    },
  );

  test('null and invalid native masks are discarded', () async {
    for (final result in [
      null,
      SegmentationMask(width: 0, height: 2, confidences: []),
      SegmentationMask(width: 2, height: 2, confidences: [1]),
      SegmentationMask(width: 1, height: 1, confidences: [double.nan]),
      SegmentationMask(width: 1, height: 1, confidences: [double.infinity]),
      SegmentationMask(width: 1, height: 1, confidences: [2]),
    ]) {
      final masker = PersonMasker(process: (_) async => result);
      expect(await masker.maskData(stripeNv21()), isNull);
      expect(masker.lastStatus, result == null ? 'no-mask' : 'invalid-mask');
      await masker.close();
    }
  });

  test(
    'busy calls are dropped and close waits for active native processing',
    () async {
      final completed = Completer<SegmentationMask?>();
      var calls = 0, closeCalls = 0;
      final masker = PersonMasker(
        process: (_) {
          calls++;
          return completed.future;
        },
        close: () async {
          closeCalls++;
        },
      );
      final first = masker.maskData(stripeNv21());
      expect(await masker.maskData(stripeNv21()), isNull);
      expect(calls, 1);
      final closing = masker.close();
      expect(closeCalls, 0);
      completed.complete(null);
      await first;
      await closing;
      expect(closeCalls, 1);
      expect(await masker.maskData(stripeNv21()), isNull);
      await masker.close();
      expect(closeCalls, 1);
    },
  );

  test('invalid camera layout returns no mask', () async {
    var calls = 0;
    final masker = PersonMasker(
      process: (_) async {
        calls++;
        return null;
      },
    );
    expect(
      await masker.maskFor(cameraFrameFixture(stripeNv21(), format: 35)),
      isNull,
    );
    expect(calls, 0);
    expect(masker.lastStatus, 'invalid-frame');
    await masker.close();
  });
}
