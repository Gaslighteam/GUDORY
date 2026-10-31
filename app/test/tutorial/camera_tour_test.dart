import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/features/tutorial/camera_tour.dart';

void main() {
  testWidgets('blocks touches outside the hole and advances on use', (
    tester,
  ) async {
    final tryKey = GlobalKey();
    final showKey = GlobalKey();
    var tried = 0, shown = 0, done = 0, left = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  key: tryKey,
                  onPressed: () => tried++,
                  child: const Text('try'),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  key: showKey,
                  onPressed: () => shown++,
                  child: const Text('show'),
                ),
              ),
              Positioned.fill(
                child: CameraTour(
                  onDone: () => done++,
                  steps: [
                    const TourStep(title: 'intro', body: 'b'),
                    TourStep(
                      target: tryKey,
                      title: 'try step',
                      body: 'b',
                      tryIt: true,
                      advanceOnUse: true,
                      onLeave: () => left++,
                    ),
                    TourStep(target: showKey, title: 'show step', body: 'b'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Intro: everything is blocked.
    await tester.tap(find.text('try'), warnIfMissed: false);
    expect(tried, 0);
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('try step'), findsOneWidget);

    // Try-it step: the hole works, the rest is blocked, use moves on.
    await tester.tap(find.text('show'), warnIfMissed: false);
    expect(shown, 0);
    await tester.tap(find.text('try'));
    expect(tried, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(left, 1);
    expect(find.text('show step'), findsOneWidget);

    // Show-only step: even the highlighted control is blocked.
    await tester.tap(find.text('show'), warnIfMissed: false);
    expect(shown, 0);
    await tester.tap(find.text('시작하기'));
    expect(done, 1);
  });

  testWidgets('skips steps whose control is not on screen', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraTour(
          onDone: () => done++,
          steps: [
            const TourStep(title: 'intro', body: 'b'),
            TourStep(target: GlobalKey(), title: 'missing', body: 'b'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('missing'), findsNothing);
    expect(done, 1);
  });
}
