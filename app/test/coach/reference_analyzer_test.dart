import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/coach/composition_math.dart';
import 'package:gudory/features/coach/reference_analyzer.dart';
import 'package:image/image.dart' as img;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('pure reference composition', () {
    for (final (framing, span) in [
      (Framing.chestUp, 0.15),
      (Framing.waistUp, 0.45),
      (Framing.kneeUp, 0.65),
      (Framing.fullBody, 0.75),
    ]) {
      test(
        '$framing uses the lowest visible pair and shared Step 2 formulas',
        () {
          final points = landmarks(through: framing);
          final target = targetFrom(points);
          expect(target.framing, framing);
          expect(target.personHeightRatio, closeTo(span, 1e-12));
          expect(target.personCenterX, closeTo(0.4, 1e-12));
          expect(target.personCenterY, closeTo(0.18, 1e-12));
          expect(target.source, 'reference');
          expect(target.horizonY, isNull);
          expect(target.tolHeight, 0.10);
          expect(target.tolX, 0.08);
          expect(target.tolY, 0.08);
          expect(target.tolRollDeg, 3);
          final live = PoseFrame(
            landmarks: points,
            imageWidth: 480,
            imageHeight: 640,
            rollDeg: 0,
            pitchDeg: 0,
            at: DateTime.utc(2026, 10, 31),
          );
          final measured = measureComposition(live, framing: framing)!;
          expect(target.personHeightRatio, measured.personHeightRatio);
          expect(target.personCenterX, measured.personCenterX);
          expect(target.personCenterY, measured.personCenterY);
          expect(measured.estimated, isFalse);
        },
      );

      test('$framing anchor visibility 0.5 is accepted', () {
        expect(
          targetFrom(
            landmarks(through: framing, anchorVisibility: 0.5),
          ).framing,
          framing,
        );
      });
    }

    for (final (lower, upper) in [
      (Framing.fullBody, Framing.kneeUp),
      (Framing.kneeUp, Framing.waistUp),
      (Framing.waistUp, Framing.chestUp),
    ]) {
      test(
        '$lower anchor below 0.5 selects $upper, never extrapolated full body',
        () {
          expect(
            targetFrom(
              landmarks(through: lower, anchorVisibility: 0.49),
            ).framing,
            upper,
          );
        },
      );
    }

    for (final index in [0, 2, 5, 11, 12]) {
      test(
        'required joint $index needs visibility, finite coordinates and image bounds',
        () {
          for (final invalid in [
            const Landmark(x: 0.4, y: 0.2, visibility: 0.49),
            const Landmark(x: double.nan, y: 0.2, visibility: 1),
            const Landmark(x: 0.4, y: double.infinity, visibility: 1),
            const Landmark(x: 0.4, y: 0.2, visibility: double.nan),
            const Landmark(x: -0.01, y: 0.2, visibility: 1),
            const Landmark(x: 0.4, y: 1.01, visibility: 1),
          ]) {
            final points = landmarks();
            points[index] = invalid;
            expect(() => targetFrom(points), throwsA(isA<NoPersonException>()));
          }
        },
      );

      test('required joint $index visibility exactly 0.5 is accepted', () {
        final points = landmarks();
        final old = points[index];
        points[index] = Landmark(x: old.x, y: old.y, visibility: 0.5);
        expect(targetFrom(points).framing, Framing.fullBody);
      });
    }

    test('null, empty or short landmark lists throw NoPersonException', () {
      for (final points in <List<Landmark>?>[
        null,
        [],
        landmarks().sublist(0, 12),
      ]) {
        expect(() => targetFrom(points), throwsA(isA<NoPersonException>()));
      }
    });

    test('hidden or outside ankles do not make a full-body reference', () {
      final points = landmarks();
      points[27] = const Landmark(x: 0.4, y: 1.1, visibility: 1);
      expect(targetFrom(points).framing, Framing.kneeUp);
    });

    test('degenerate pose geometry is rejected', () {
      final points = landmarks();
      points[0] = const Landmark(x: 0.4, y: 0.5, visibility: 1);
      expect(() => targetFrom(points), throwsA(isA<NoPersonException>()));
    });

    test('invalid target span is rejected rather than silently clamped', () {
      final points = landmarks();
      points[0] = const Landmark(x: 0.4, y: 0.01, visibility: 1);
      expect(() => targetFrom(points), throwsFormatException);
    });

    for (final (width, height, expected) in [
      (480, 640, ShotOrientation.portrait),
      (640, 480, ShotOrientation.landscape),
      (640, 640, ShotOrientation.portrait),
    ]) {
      test('corrected image $width x $height determines orientation', () {
        expect(
          targetFrom(landmarks(), width: width, height: height).orientation,
          expected,
        );
      });
    }

    test('invalid dimensions are an argument error', () {
      expect(() => targetFrom(landmarks(), width: 0), throwsArgumentError);
    });
  });

  group('EXIF, native input and file lifecycle', () {
    late ReferenceHarness h;
    setUp(() async {
      h = await ReferenceHarness.create(binding);
    });
    tearDown(() => h.close());

    // Independent expected corner order A/B/C/D after each EXIF transform.
    const cornerOrders = [
      ['A', 'B', 'C', 'D'],
      ['B', 'A', 'D', 'C'],
      ['D', 'C', 'B', 'A'],
      ['C', 'D', 'A', 'B'],
      ['A', 'C', 'B', 'D'],
      ['C', 'A', 'D', 'B'],
      ['D', 'B', 'C', 'A'],
      ['B', 'D', 'A', 'C'],
    ];
    for (var exif = 1; exif <= 8; exif++) {
      test(
        'EXIF $exif is baked once, including reflections, with original preserved',
        () async {
          final file = await h.writeJpeg(exif: exif);
          final original = await file.readAsBytes();
          final width = exif <= 4 ? 80 : 120;
          final height = exif <= 4 ? 120 : 80;
          h.detect = (input) async {
            expect(input.image.width, width);
            expect(input.image.height, height);
            expect(input.image.exif.imageIfd.hasOrientation, isFalse);
            expect(cornerLabels(input.image), cornerOrders[exif - 1]);
            expect((input.arguments['options'] as Map)['mode'], 'single');
            final data = input.arguments['imageData'] as Map;
            expect(data['type'], 'file');
            expect(data['metadata'], isNull);
            expect(File(input.path).existsSync(), isTrue);
            return nativePose(width, height);
          };
          final result = await h.analyzer.analyze(file.path);
          expect(
            result.orientation,
            exif <= 4 ? ShotOrientation.portrait : ShotOrientation.landscape,
          );
          expect(result.framing, Framing.fullBody);
          expect(result.personHeightRatio, closeTo(0.75, 1e-10));
          // Asymmetric x must not be mirrored or recentered by preview cropping.
          expect(result.personCenterX, closeTo(0.4, 1e-10));
          expect(result.personCenterY, closeTo(0.18, 1e-10));
          expect(await file.readAsBytes(), orderedEquals(original));
          expect(h.cache.listSync(), isEmpty);
          expect(File(h.paths.single).existsSync(), isFalse);
        },
      );
    }

    for (final (width, height, orientation) in [
      (64, 96, ShotOrientation.portrait),
      (96, 64, ShotOrientation.landscape),
      (96, 96, ShotOrientation.portrait),
    ]) {
      test(
        'PNG without EXIF $width x $height keeps the entire image and aspect',
        () async {
          final file = await h.writePng(width: width, height: height);
          h.detect = (input) async {
            expect(input.image.width, width);
            expect(input.image.height, height);
            expect(cornerLabels(input.image), ['A', 'B', 'C', 'D']);
            return nativePose(width, height);
          };
          final result = await h.analyzer.analyze(file.path);
          expect(result.orientation, orientation);
          expect(result.personCenterX, closeTo(0.4, 1e-12));
        },
      );
    }

    test(
      'native no-person result throws and still removes its temp files',
      () async {
        final file = await h.writePng();
        h.detect = (_) async => [];
        await expectLater(
          h.analyzer.analyze(file.path),
          throwsA(isA<NoPersonException>()),
        );
        expect(h.cache.listSync(), isEmpty);
        expect(File(file.path).existsSync(), isTrue);
      },
    );

    for (final missing in [0, 2, 5, 11, 12]) {
      test(
        'missing native joint $missing becomes NoPersonException and cleans up',
        () async {
          final file = await h.writePng();
          h.detect = (input) async => nativePose(
            input.image.width,
            input.image.height,
            omit: {missing},
          );
          await expectLater(
            h.analyzer.analyze(file.path),
            throwsA(isA<NoPersonException>()),
          );
          expect(h.cache.listSync(), isEmpty);
        },
      );
    }

    test('missing all lower joints is a valid chest-up reference', () async {
      final file = await h.writePng();
      h.detect = (input) async => nativePose(
        input.image.width,
        input.image.height,
        omit: {23, 24, 25, 26, 27, 28},
      );
      expect((await h.analyzer.analyze(file.path)).framing, Framing.chestUp);
    });

    test(
      'missing file errors are preserved and detector is not called',
      () async {
        await expectLater(
          h.analyzer.analyze('${h.root.path}/absent.jpg'),
          throwsA(isA<FileSystemException>()),
        );
        expect(h.paths, isEmpty);
        expect(h.cache.listSync(), isEmpty);
      },
    );

    test(
      'unsupported image is distinct from no-person and original is unchanged',
      () async {
        final file = await File(
          '${h.root.path}/broken.bin',
        ).writeAsBytes([1, 2, 3, 4]);
        await expectLater(h.analyzer.analyze(file.path), throwsFormatException);
        expect(await file.readAsBytes(), [1, 2, 3, 4]);
        expect(h.paths, isEmpty);
        expect(h.cache.listSync(), isEmpty);
      },
    );

    test(
      'native detector failure cleans up and does not poison the next job',
      () async {
        final file = await h.writePng();
        final original = await file.readAsBytes();
        var calls = 0;
        h.detect = (input) async {
          calls++;
          if (calls == 1) throw PlatformException(code: 'pose-failed');
          return nativePose(input.image.width, input.image.height);
        };
        await expectLater(
          h.analyzer.analyze(file.path),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'pose-failed',
            ),
          ),
        );
        expect(h.cache.listSync(), isEmpty);
        expect((await h.analyzer.analyze(file.path)).source, 'reference');
        expect(h.paths.toSet().length, 2);
        expect(h.cache.listSync(), isEmpty);
        expect(await file.readAsBytes(), orderedEquals(original));
      },
    );

    test(
      'bad cache path reports filesystem failure without touching original',
      () async {
        final file = await h.writePng();
        final blocker = await File(
          '${h.root.path}/not-a-directory',
        ).writeAsString('keep');
        final other = MlKitReferenceAnalyzer(
          temporaryDirectory: () async => Directory(blocker.path),
        );
        try {
          await expectLater(
            other.analyze(file.path),
            throwsA(isA<FileSystemException>()),
          );
          expect(await blocker.readAsString(), 'keep');
          expect(File(file.path).existsSync(), isTrue);
          expect(h.paths, isEmpty);
        } finally {
          await other.dispose();
        }
      },
    );

    test(
      'concurrent requests serialize and use unique temporary directories',
      () async {
        final file = await h.writePng();
        final gate = Completer<Object?>();
        final started = Completer<DetectionInput>();
        h.detect = (input) async {
          if (!started.isCompleted) {
            started.complete(input);
            return gate.future;
          }
          return nativePose(input.image.width, input.image.height);
        };
        final first = h.analyzer.analyze(file.path);
        final second = h.analyzer.analyze(file.path);
        final input = await started.future;
        try {
          expect(h.paths.length, 1);
          expect(File(input.path).existsSync(), isTrue);
        } finally {
          gate.complete(nativePose(input.image.width, input.image.height));
        }
        final results = await Future.wait([first, second]);
        expect(results.length, 2);
        expect(h.paths.toSet().length, 2);
        expect(h.paths.map((p) => File(p).parent.path).toSet().length, 2);
        expect(h.cache.listSync(), isEmpty);
      },
    );

    test(
      'dispose waits for accepted jobs, rejects new jobs and closes exactly once',
      () async {
        final file = await h.writePng();
        final gate = Completer<Object?>();
        final started = Completer<DetectionInput>();
        h.detect = (input) async {
          if (!started.isCompleted) {
            started.complete(input);
            return gate.future;
          }
          return nativePose(input.image.width, input.image.height);
        };
        final first = h.analyzer.analyze(file.path);
        final queued = h.analyzer.analyze(file.path);
        final input = await started.future;
        final closing = h.analyzer.dispose();
        try {
          expect(h.closeCalls, 0);
          await expectLater(h.analyzer.analyze(file.path), throwsStateError);
        } finally {
          gate.complete(nativePose(input.image.width, input.image.height));
        }
        await Future.wait([first, queued]);
        await closing;
        await h.analyzer.dispose();
        expect(h.closeCalls, 1);
        expect(h.cacheEmptyAtClose, isTrue);
        expect(h.paths.length, 2);
        expect(h.cache.listSync(), isEmpty);
      },
    );

    test('dispose also closes an unused detector only once', () async {
      await h.analyzer.dispose();
      await h.analyzer.dispose();
      expect(h.closeCalls, 1);
      await expectLater(h.analyzer.analyze('anything'), throwsStateError);
    });
  });
}

TargetComposition targetFrom(
  List<Landmark>? points, {
  int width = 480,
  int height = 640,
}) => referenceTargetFromLandmarks(
  landmarks: points,
  imageWidth: width,
  imageHeight: height,
);

List<Landmark> landmarks({
  Framing through = Framing.fullBody,
  double anchorVisibility = 1,
}) {
  final points = List.filled(33, const Landmark(x: 0, y: 0, visibility: 0));
  void point(int index, double x, double y, [double visibility = 1]) {
    points[index] = Landmark(x: x, y: y, visibility: visibility);
  }

  point(0, 0.4, 0.2);
  point(2, 0.33, 0.17);
  point(5, 0.47, 0.19);
  double visibility(int index) => index > through.index
      ? 0
      : index == through.index
      ? anchorVisibility
      : 1;
  point(11, 0.2, 0.28, visibility(0));
  point(12, 0.6, 0.32, visibility(0));
  point(23, 0.5, 0.58, visibility(1));
  point(24, 0.7, 0.62, visibility(1));
  point(25, 0.4, 0.78, visibility(2));
  point(26, 0.6, 0.82, visibility(2));
  point(27, 0.4, 0.88, visibility(3));
  point(28, 0.6, 0.92, visibility(3));
  return points;
}

List<Object> nativePose(int width, int height, {Set<int> omit = const {}}) => [
  [
    for (final entry in landmarks().asMap().entries)
      if (!omit.contains(entry.key))
        <String, Object>{
          'type': entry.key,
          'x': entry.value.x * width,
          'y': entry.value.y * height,
          'z': 0.0,
          'likelihood': entry.value.visibility,
        },
  ].reversed.toList(),
];

class DetectionInput {
  DetectionInput(this.path, this.image, this.arguments);
  final String path;
  final img.Image image;
  final Map arguments;
}

class ReferenceHarness {
  ReferenceHarness(this.binding, this.root, this.cache) {
    analyzer = MlKitReferenceAnalyzer(temporaryDirectory: () async => cache);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, _handle);
  }
  static const channel = MethodChannel('google_mlkit_pose_detector');
  final TestWidgetsFlutterBinding binding;
  final Directory root;
  final Directory cache;
  late final MlKitReferenceAnalyzer analyzer;
  Future<Object?> Function(DetectionInput)? detect;
  final paths = <String>[];
  int closeCalls = 0;
  bool cacheEmptyAtClose = false;
  int _files = 0;

  static Future<ReferenceHarness> create(
    TestWidgetsFlutterBinding binding,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'gudory-reference-test-',
    );
    final cache = await Directory('${root.path}/cache').create();
    return ReferenceHarness(binding, root, cache);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'vision#closePoseDetector') {
      closeCalls++;
      cacheEmptyAtClose = cache.listSync().isEmpty;
      return null;
    }
    final args = call.arguments as Map;
    final path = (args['imageData'] as Map)['path'] as String;
    paths.add(path);
    final image = img.decodePng(await File(path).readAsBytes())!;
    final input = DetectionInput(path, image, args);
    return detect == null
        ? nativePose(image.width, image.height)
        : detect!(input);
  }

  Future<File> writeJpeg({required int exif}) async {
    final image = colorFixture(80, 120);
    image.exif.imageIfd.orientation = exif;
    return File(
      '${root.path}/input-${_files++}.jpg',
    ).writeAsBytes(img.encodeJpg(image, quality: 100));
  }

  Future<File> writePng({int width = 80, int height = 120}) => File(
    '${root.path}/input-${_files++}.png',
  ).writeAsBytes(img.encodePng(colorFixture(width, height)));

  Future<void> close() async {
    try {
      await analyzer.dispose();
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      if (await root.exists()) await root.delete(recursive: true);
    }
  }
}

img.Image colorFixture(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final top = y < height ~/ 2;
      final left = x < width ~/ 2;
      final (r, g, b) = top
          ? left
                ? (255, 0, 0)
                : (0, 255, 0)
          : left
          ? (0, 0, 255)
          : (255, 255, 0);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

List<String> cornerLabels(img.Image image) => [
  for (final (x, y) in [
    (image.width ~/ 4, image.height ~/ 4),
    (image.width * 3 ~/ 4, image.height ~/ 4),
    (image.width ~/ 4, image.height * 3 ~/ 4),
    (image.width * 3 ~/ 4, image.height * 3 ~/ 4),
  ])
    () {
      final p = image.getPixel(x, y);
      if (p.r > 180 && p.g < 80 && p.b < 80) return 'A';
      if (p.r < 80 && p.g > 180 && p.b < 80) return 'B';
      if (p.r < 80 && p.g < 80 && p.b > 180) return 'C';
      if (p.r > 180 && p.g > 180 && p.b < 80) return 'D';
      throw StateError('Unexpected fixture pixel: ${p.r}, ${p.g}, ${p.b}');
    }(),
];
