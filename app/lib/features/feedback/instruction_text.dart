// Instruction strings (body-relative wording, no photography jargon) for the
// photographer's language: 'ko' (default), 'en', 'ja'.
import '../../core/models.dart';

enum ArrowDirection { none, left, right, up, down, back, forward }

/// Languages a photographer can pick when the phone is handed over.
const photographerLanguages = {'ko': '한국어', 'en': 'English', 'ja': '日本語'};

abstract final class InstructionText {
  /// Sentence for [key] with [amount] (steps or fists, 0.5 units).
  static String of(InstructionKey key, double amount, [String lang = 'ko']) =>
      switch (lang) {
        'en' => _en(key, amount),
        'ja' => _ja(key, amount),
        _ => _ko(key, amount),
      };

  /// Shown when the phone is handed over, before the first instruction.
  static String handoverGuide(String lang) => switch (lang) {
    'en' =>
      'Just follow the text on screen.\nPress the shutter when it lines up.',
    'ja' => '画面の文字に従ってください。\n合ったらシャッターを押してください。',
    _ => '화면 글자만 따라 해 주세요.\n맞으면 셔터를 눌러 주세요',
  };

  /// Shown to the photographer after a shot in hand-over mode.
  static String handoverDone(String lang) => switch (lang) {
    'en' => 'Done! Please hand the phone back.',
    'ja' => '撮れました！持ち主に返してください。',
    _ => '다 찍었어요! 주인에게 돌려주세요',
  };

  static ArrowDirection arrowOf(InstructionKey key) => switch (key) {
    InstructionKey.stepBack => ArrowDirection.back,
    InstructionKey.stepForward => ArrowDirection.forward,
    InstructionKey.stepLeft ||
    InstructionKey.subjectLeft => ArrowDirection.left,
    InstructionKey.stepRight ||
    InstructionKey.subjectRight => ArrowDirection.right,
    InstructionKey.phoneUp || InstructionKey.raisePhone => ArrowDirection.up,
    InstructionKey.phoneDown => ArrowDirection.down,
    _ => ArrowDirection.none,
  };

  // ---- Korean ----

  static String _ko(InstructionKey key, double amount) {
    final steps = _koSteps(amount);
    final fists = _koFists(amount);
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
      InstructionKey.aligned => '좋아요! 지금 셔터를 눌러 주세요',
      InstructionKey.turnLandscape => '폰을 가로로 돌려 주세요',
      InstructionKey.turnPortrait => '폰을 세로로 세워 주세요',
      InstructionKey.addReference => '레퍼런스 사진을 추가해 주세요',
      InstructionKey.raisePhone => '폰을 조금 세워 주세요',
    };
  }

  static const _koNative = [
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

  static String _koCount(int n) => n < _koNative.length ? _koNative[n] : '$n';

  /// 0.5 → 반 걸음, 1 → 한 걸음, 1.5 → 한 걸음 반, 2 → 두 걸음
  static String _koSteps(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return '반 걸음';
    return half ? '${_koCount(whole)} 걸음 반' : '${_koCount(whole)} 걸음';
  }

  /// 0.5 → 주먹 반 개만큼, 1 → 주먹 하나만큼, 2 → 주먹 두 개만큼
  static String _koFists(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return '주먹 반 개만큼';
    if (whole == 1 && !half) return '주먹 하나만큼';
    return half ? '주먹 ${_koCount(whole)} 개 반만큼' : '주먹 ${_koCount(whole)} 개만큼';
  }

  // ---- English ----

  static String _en(InstructionKey key, double amount) {
    final steps = _enSteps(amount);
    final fists = _enFists(amount);
    return switch (key) {
      InstructionKey.holdPhoneUpright => 'Hold the phone straight',
      InstructionKey.stepBack => 'Take $steps back',
      InstructionKey.stepForward => 'Take $steps forward',
      InstructionKey.stepLeft => 'Take $steps to your left',
      InstructionKey.stepRight => 'Take $steps to your right',
      InstructionKey.subjectLeft =>
        'Ask the model to move $steps to the screen\'s left',
      InstructionKey.subjectRight =>
        'Ask the model to move $steps to the screen\'s right',
      InstructionKey.phoneUp => 'Raise the phone by $fists',
      InstructionKey.phoneDown => 'Lower the phone by $fists',
      InstructionKey.oppositeWay => 'Other way!',
      InstructionKey.fitWholeBody => 'Get the whole person on screen',
      InstructionKey.noPerson => 'Point the camera at the person',
      InstructionKey.aligned => 'Perfect! Press the shutter now',
      InstructionKey.turnLandscape => 'Turn the phone sideways',
      InstructionKey.turnPortrait => 'Hold the phone upright',
      InstructionKey.addReference => 'Add a reference photo',
      InstructionKey.raisePhone => 'Tilt the phone up a little',
    };
  }

  static const _enNum = [
    '',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
  ];

  static String _enCount(int n) => n < _enNum.length ? _enNum[n] : '$n';

  /// 0.5 → half a step, 1 → one step, 1.5 → one and a half steps
  static String _enSteps(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return 'half a step';
    if (whole == 1 && !half) return 'one step';
    return half
        ? '${_enCount(whole)} and a half steps'
        : '${_enCount(whole)} steps';
  }

  /// 0.5 → half a fist, 1 → one fist, 2 → two fists
  static String _enFists(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return 'half a fist';
    if (whole == 1 && !half) return 'one fist';
    return half
        ? '${_enCount(whole)} and a half fists'
        : '${_enCount(whole)} fists';
  }

  // ---- Japanese ----

  static String _ja(InstructionKey key, double amount) {
    final steps = _jaSteps(amount);
    final fists = _jaFists(amount);
    return switch (key) {
      InstructionKey.holdPhoneUpright => 'スマホをまっすぐにしてください',
      InstructionKey.stepBack => '$steps下がってください',
      InstructionKey.stepForward => '$steps前に出てください',
      InstructionKey.stepLeft => '左に$steps動いてください',
      InstructionKey.stepRight => '右に$steps動いてください',
      InstructionKey.subjectLeft => 'モデルさんに画面の左へ$steps動いてもらってください',
      InstructionKey.subjectRight => 'モデルさんに画面の右へ$steps動いてもらってください',
      InstructionKey.phoneUp => 'スマホを$fists上げてください',
      InstructionKey.phoneDown => 'スマホを$fists下げてください',
      InstructionKey.oppositeWay => '逆です！',
      InstructionKey.fitWholeBody => '全身が画面に入るようにしてください',
      InstructionKey.noPerson => '人が画面に入るようにしてください',
      InstructionKey.aligned => 'いいですね！今シャッターを押してください',
      InstructionKey.turnLandscape => 'スマホを横にしてください',
      InstructionKey.turnPortrait => 'スマホを縦にしてください',
      InstructionKey.addReference => '参考写真を追加してください',
      InstructionKey.raisePhone => 'スマホを少し立ててください',
    };
  }

  static const _jaNum = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

  static String _jaCount(int n) => n < _jaNum.length ? _jaNum[n] : '$n';

  /// 0.5 → 半歩, 1 → 一歩, 1.5 → 一歩半, 2 → 二歩
  static String _jaSteps(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return '半歩';
    return half ? '${_jaCount(whole)}歩半' : '${_jaCount(whole)}歩';
  }

  /// 0.5 → こぶし半分, 1 → こぶし一つ分, 2 → こぶし二つ分
  static String _jaFists(double amount) {
    final (whole, half) = _split(amount);
    if (whole == 0) return 'こぶし半分';
    return half ? 'こぶし${_jaCount(whole)}つ半分' : 'こぶし${_jaCount(whole)}つ分';
  }

  /// amount in 0.5 units → (whole, has half). Minimum 0.5.
  static (int, bool) _split(double amount) {
    final halves = (amount * 2).round().clamp(1, 40);
    return (halves ~/ 2, halves.isOdd);
  }
}
