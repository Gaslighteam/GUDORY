import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'background_features.dart';
import 'background_overlay.dart';
import 'compositions.dart';
import 'director.dart';
import 'director_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mask = List<double>.generate(
    60 * 90,
    (i) => (i % 60 >= 26 && i % 60 <= 33 && i ~/ 60 >= 38 && i ~/ 60 <= 51)
        ? 1
        : 0,
  );
  final frame = DirectorFrame(
    60,
    90,
    List.filled(5400, 120),
    mask,
    const DirectorPerson(.5, .2, .15, .1, .15),
    0,
  );
  final cells = List<RegionCell>.generate(
    9,
    (i) => RegionCell(.9, .1, i / 8, .5),
  );
  final lines = [
    for (final x in [.07, .20, .35, .55, .70, .90])
      BackgroundLine(x, .05, x, .95, .8, 90),
  ];
  final features = SceneFeatures(cells, lines, null, .9, true, 'ok');
  final snapshot = BackgroundOverlaySnapshot(frame, features, 0);
  Future<ui.Image> render(BackgroundOverlayPainter painter) async {
    final recorder = ui.PictureRecorder();
    // A dedicated recorder prevents accidental reliance on a previous canvas.
    final target = Canvas(recorder);
    painter.paint(target, const Size(120, 180));
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 180);
    picture.dispose();
    return image;
  }

  Future<List<int>> pixel(ui.Image image, int x, int y) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (y * image.width + x) * 4;
    return [for (var c = 0; c < 4; c++) data.getUint8(i + c)];
  }

  test('Line opacity stays readable while reflecting measured confidence', () {
    const line = BackgroundLine(.2, .05, .2, .95, .5, 90);
    final weak = BackgroundOverlaySnapshot(
      frame,
      SceneFeatures(cells, [line], null, 0, true, 'ok'),
      0,
    );
    final strong = BackgroundOverlaySnapshot(
      frame,
      SceneFeatures(cells, [line], null, 1, true, 'ok'),
      0,
    );
    expect(weak.lineOpacity(line), greaterThanOrEqualTo(.49));
    expect(strong.lineOpacity(line), greaterThan(weak.lineOpacity(line)));
    expect(strong.lineOpacity(line) - weak.lineOpacity(line), lessThan(.22));
  });
  test(
    'Dart extraction retains six supported bars, without a two-line cap',
    () {
      final gray = List<double>.generate(
        72 * 96,
        (i) => [4, 5].contains(i % 72 % 12) ? 235 : 120,
      );
      final mask = List<double>.generate(
        72 * 96,
        (i) => i % 72 == 36 && i ~/ 72 == 45 ? 1 : 0,
      );
      final f = DirectorFrame(72, 96, gray, mask, null, 0);
      expect(analyzeScene(f).lines.length, 6);
    },
  );
  test(
    'All six retained scoring lines are displayed, without fillers',
    () async {
      expect(snapshot.detectedLineCount, 6);
      final image = await render(
        BackgroundOverlayPainter(snapshot, const BackgroundOverlayOptions()),
      );
      for (final line in lines) {
        expect(
          (await pixel(image, (line.x1 * 120).round(), 36))[3],
          greaterThan(0),
        );
      }
      image.dispose();
      final empty = BackgroundOverlaySnapshot(
        frame,
        SceneFeatures(cells, [], null, 0, true, 'ok'),
        0,
      );
      expect(empty.detectedLineCount, 0);
      final noLines = await render(
        BackgroundOverlayPainter(empty, const BackgroundOverlayOptions()),
      );
      expect((await pixel(noLines, 24, 36))[3], 0);
      noLines.dispose();
    },
  );
  test('Sixth line contributes to overlap and structure scoring', () {
    final six = [
      ...lines.take(5),
      const BackgroundLine(.5, .05, .5, .95, 1, 90),
    ];
    CompositionCandidate current(List<BackgroundLine> ls) => generateCandidates(
      frame,
      SceneFeatures(cells, ls, null, .9, true, 'ok'),
    ).firstWhere((c) => c.x == .5 && c.eyeY == .2 && c.scale == .1);
    expect(
      current(six).terms['overlap'],
      greaterThan(current(six.take(5).toList()).terms['overlap']!),
    );
    expect(
      current(six).terms['structure'],
      greaterThan(current(six.take(5).toList()).terms['structure']!),
    );
  });
  test(
    'Heat cells expose actual values and insufficient coverage as unknown',
    () {
      expect(
        snapshot.cells.map((c) => c.value),
        orderedEquals(cells.map((c) => c.texture)),
      );
      final scarce = BackgroundOverlaySnapshot(
        frame,
        SceneFeatures(
          List.filled(9, const RegionCell(.2, .1, .8, .5)),
          [],
          null,
          .9,
          true,
          'ok',
        ),
        0,
      );
      expect(
        scarce.cells.every((c) => c.value == null && c.label.startsWith('—')),
        isTrue,
      );
      final invalid = BackgroundOverlaySnapshot(
        frame,
        SceneFeatures(cells, [], null, 0, false, 'no-mask'),
        0,
      );
      expect(invalid.supportedCellCount, 0);
      expect(invalid.summary, contains('근거 부족'));
      expect(snapshot.summary, contains('낮음 ≠ 좋은 구도'));
    },
  );
  test('Measured low/high values use different translucent colors', () {
    expect(snapshot.cells.first.color, isNot(snapshot.cells.last.color));
    expect(snapshot.cells.first.color.a, closeTo(.14, .01));
    expect(snapshot.cells.last.color.a, closeTo(.28, .01));
    expect(snapshot.cells.first.value, 0);
    expect(snapshot.cells.last.value, 1);
  });
  test(
    'Person pixels and extractor boundary margin are never colored',
    () async {
      final crossing = BackgroundOverlaySnapshot(
        frame,
        SceneFeatures(
          cells,
          [const BackgroundLine(.5, .05, .5, .95, 1, 90)],
          null,
          .9,
          true,
          'ok',
        ),
        0,
      );
      final image = await render(
        BackgroundOverlayPainter(
          crossing,
          const BackgroundOverlayOptions(heatmap: true),
        ),
      );
      expect((await pixel(image, 60, 90))[3], 0);
      expect(snapshot.backgroundPath.contains(const Offset(.5, .5)), isFalse);
      expect(
        snapshot.backgroundPath.contains(const Offset(.5, 37.5 / 90)),
        isFalse,
      );
      expect(snapshot.backgroundPath.contains(const Offset(.2, .2)), isTrue);
      image.dispose();
    },
  );
  test('Overlay rotation uses saved-shot inverse for both landscape sides', () {
    expect(
      shotPointToPreview(const Offset(.2, .3), const Size(100, 200), 0),
      const Offset(20, 60),
    );
    expect(
      shotPointToPreview(const Offset(.2, .3), const Size(100, 200), 1),
      const Offset(70, 40),
    );
    expect(
      shotPointToPreview(const Offset(.2, .3), const Size(100, 200), -1),
      const Offset(30, 160),
    );
    final rotated = shotRectToPreview(
      const Rect.fromLTWH(.1, .2, .3, .4),
      const Size(100, 200),
      1,
    );
    expect(rotated.left, closeTo(40, 1e-9));
    expect(rotated.top, closeTo(20, 1e-9));
    expect(rotated.width, closeTo(40, 1e-9));
    expect(rotated.height, closeTo(60, 1e-9));
    // Already mirrored/cropped normalized data is not flipped/cropped twice.
    expect(
      shotPointToPreview(const Offset(.8, .3), const Size(100, 200), 0),
      const Offset(80, 60),
    );
  });
  testWidgets(
    'The two controls toggle independently through all combinations',
    (tester) async {
      var options = const BackgroundOverlayOptions();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => BackgroundOverlayControls(
                options: options,
                detectedLines: 6,
                onChanged: (next) => setState(() => options = next),
              ),
            ),
          ),
        ),
      );
      expect(find.text('선 검출 6/6 · 표시 6'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('background-heatmap-toggle')));
      await tester.pump();
      expect(options.lines && options.heatmap, isTrue);
      await tester.tap(find.byKey(const ValueKey('background-lines-toggle')));
      await tester.pump();
      expect(!options.lines && options.heatmap, isTrue);
      expect(find.text('선 검출 6/6 · 표시 0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('background-heatmap-toggle')));
      await tester.pump();
      expect(!options.lines && !options.heatmap, isTrue);
      await tester.tap(find.byKey(const ValueKey('background-lines-toggle')));
      await tester.pump();
      expect(options.lines && !options.heatmap, isTrue);
    },
  );
  test(
    'Drawing in all modes never changes candidates, masks or instructions',
    () async {
      final records =
          (jsonDecode(
                    File(
                      'lib/features/scene/experimental/composition_director_v1/parity_fixtures.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      for (final record in records) {
        final f = DirectorFrame.fromJson(
          record['frame'] as Map<String, dynamic>,
        );
        final before = CompositionDirector().update(f),
            maskBefore = [...f.mask];
        final data = BackgroundOverlaySnapshot(f, analyzeScene(f), 1);
        for (final showLines in [false, true]) {
          for (final showHeat in [false, true]) {
            final image = await render(
              BackgroundOverlayPainter(
                data,
                BackgroundOverlayOptions(lines: showLines, heatmap: showHeat),
              ),
            );
            image.dispose();
            final after = CompositionDirector().update(f);
            expect(after.target?.score, before.target?.score);
            expect(after.target?.x, before.target?.x);
            expect(after.target?.eyeY, before.target?.eyeY);
            expect(after.action.text, before.action.text);
            expect(after.generation, before.generation);
            expect(f.mask, orderedEquals(maskBefore));
          }
        }
      }
    },
  );
}
