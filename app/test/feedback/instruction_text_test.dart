import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/core/models.dart';
import 'package:gudory/features/feedback/instruction_text.dart';

void main() {
  test('every key has a sentence in every language', () {
    for (final lang in photographerLanguages.keys) {
      for (final key in InstructionKey.values) {
        expect(
          InstructionText.of(key, 1, lang),
          isNotEmpty,
          reason: '$lang $key',
        );
      }
    }
  });

  test('amounts read naturally', () {
    expect(InstructionText.of(InstructionKey.stepBack, 1.5), '한 걸음 반 뒤로 가 주세요');
    expect(
      InstructionText.of(InstructionKey.stepBack, 0.5, 'en'),
      'Take half a step back',
    );
    expect(
      InstructionText.of(InstructionKey.stepBack, 2, 'en'),
      'Take two steps back',
    );
    expect(
      InstructionText.of(InstructionKey.phoneDown, 1, 'en'),
      'Lower the phone by one fist',
    );
    expect(InstructionText.of(InstructionKey.stepBack, 1, 'ja'), '一歩下がってください');
    expect(
      InstructionText.of(InstructionKey.phoneUp, 0.5, 'ja'),
      'スマホをこぶし半分上げてください',
    );
  });

  test('unknown language falls back to Korean', () {
    expect(
      InstructionText.of(InstructionKey.aligned, 1, 'fr'),
      '좋아요! 지금 셔터를 눌러 주세요',
    );
  });
}
