import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/camera/widgets/mode_controls.dart';

void main() {
  testWidgets('tapping anywhere on the pill switches to the other mode', (
    tester,
  ) async {
    final changes = <ShootMode>[];
    Future<void> show(ShootMode mode) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ModeToggle(mode: mode, onChanged: changes.add),
          ),
        ),
      ),
    );

    await show(ShootMode.recommend);
    await tester.tap(find.text('추천')); // the selected label itself
    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    final box = tester.getRect(find.byType(ModeToggle));
    await tester.tapAt(box.centerLeft + const Offset(2, 0)); // the pill edge
    expect(changes, [ShootMode.custom, ShootMode.custom, ShootMode.custom]);

    changes.clear();
    await show(ShootMode.custom);
    await tester.tap(find.text('맞춤'));
    expect(changes, [ShootMode.recommend]);
  });

  testWidgets('mode notice names the mode and what it does', (tester) async {
    for (final (mode, title, detail) in [
      (ShootMode.recommend, '추천 모드', '배경에 어울리는 구도를 추천해요'),
      (ShootMode.custom, '맞춤 모드', '레퍼런스 사진의 구도로 안내해요'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ModeNotice(mode: mode)),
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(detail), findsOneWidget);
    }
  });
}
