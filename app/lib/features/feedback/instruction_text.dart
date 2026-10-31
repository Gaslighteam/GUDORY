// Instruction strings (body-relative wording, no photography jargon).
import '../../core/models.dart';

enum ArrowDirection { none, left, right, up, down, back, forward }

abstract final class InstructionText {
  /// Sentence for [key] with [amount] (steps or fists, 0.5 units).
  /// Only Korean for now; other languages arrive with the LLM api (Should).
  static String of(InstructionKey key, double amount, [String lang = 'ko']) {
    final steps = _steps(amount);
    final fists = _fists(amount);
    return switch (key) {
      InstructionKey.holdPhoneUpright => '폰을 똑바로 세워 주세요',
      InstructionKey.stepBack => '$steps 뒤로 가 주세요',
      InstructionKey.stepForward => '$steps 앞으로 와 주세요',
      InstructionKey.stepLeft => '$steps 왼쪽으로 가 주세요',
      InstructionKey.stepRight => '$steps 오른쪽으로 가 주세요',
      // Spoken to the photographer, who relays it; "screen" side avoids the
      // subject-facing-camera mirror problem.
      InstructionKey.subjectLeft => '모델분이 화면 왼쪽으로 $steps 가게 해 주세요',
      InstructionKey.subjectRight => '모델분이 화면 오른쪽으로 $steps 가게 해 주세요',
      InstructionKey.phoneUp => '폰을 $fists 위로 올려 주세요',
      InstructionKey.phoneDown => '폰을 $fists 아래로 내려 주세요',
      InstructionKey.oppositeWay => '반대쪽이에요!',
      InstructionKey.fitWholeBody => '사람 전체가 화면에 들어오게 해 주세요',
      InstructionKey.noPerson => '사람이 화면에 보이게 해 주세요',
      InstructionKey.aligned => '좋아요! 그대로 멈춰 주세요',
      InstructionKey.turnLandscape => '폰을 가로로 돌려 주세요',
      InstructionKey.turnPortrait => '폰을 세로로 세워 주세요',
      InstructionKey.addReference => '레퍼런스 사진을 추가해 주세요',
    };
  }

  static ArrowDirection arrowOf(InstructionKey key) => switch (key) {
    InstructionKey.stepBack => ArrowDirection.back,
    InstructionKey.stepForward => ArrowDirection.forward,
    InstructionKey.stepLeft ||
    InstructionKey.subjectLeft => ArrowDirection.left,
    InstructionKey.stepRight ||
    InstructionKey.subjectRight => ArrowDirection.right,
    InstructionKey.phoneUp => ArrowDirection.up,
    InstructionKey.phoneDown => ArrowDirection.down,
    _ => ArrowDirection.none,
  };

  static const _native = [
    '',
    '한',
    '두',
    '세',
    '네',
    '다섯',
    '여섯',
    '일곱',
    '여덟',
    '아홉',
    '열',
  ];

  static String _count(int n) => n < _native.length ? _native[n] : '$n';

  /// 0.5 → 반 걸음, 1 → 한 걸음, 1.5 → 한 걸음 반, 2 → 두 걸음
  static String _steps(double amount) {
    final halves = (amount * 2).round().clamp(1, 40);
    final whole = halves ~/ 2;
    final half = halves.isOdd;
    if (whole == 0) return '반 걸음';
    return half ? '${_count(whole)} 걸음 반' : '${_count(whole)} 걸음';
  }

  /// 0.5 → 주먹 반 개만큼, 1 → 주먹 하나만큼, 2 → 주먹 두 개만큼
  static String _fists(double amount) {
    final halves = (amount * 2).round().clamp(1, 40);
    final whole = halves ~/ 2;
    final half = halves.isOdd;
    if (whole == 0) return '주먹 반 개만큼';
    if (whole == 1 && !half) return '주먹 하나만큼';
    return half ? '주먹 ${_count(whole)} 개 반만큼' : '주먹 ${_count(whole)} 개만큼';
  }
}
