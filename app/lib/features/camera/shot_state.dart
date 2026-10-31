// Shooting state: references, mode and recommend level.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/models.dart';

// ---- References (several allowed; kept until the user resets them) ----

class ReferenceItem {
  const ReferenceItem(this.path, this.target);

  final String path;
  final TargetComposition target;
}

class ReferenceState {
  const ReferenceState({
    this.items = const [],
    this.activeIndex = 0,
    this.analyzing = false,
  });

  final List<ReferenceItem> items;
  final int activeIndex;
  final bool analyzing;

  bool get isEmpty => items.isEmpty;

  /// The reference whose composition is the coaching target.
  ReferenceItem? get active =>
      items.isEmpty ? null : items[activeIndex.clamp(0, items.length - 1)];
}

final referenceProvider = NotifierProvider<ReferenceNotifier, ReferenceState>(
  ReferenceNotifier.new,
);

class ReferenceNotifier extends Notifier<ReferenceState> {
  @override
  ReferenceState build() => const ReferenceState();

  /// Picks one or more photos. Returns a user-facing message, or null.
  Future<String?> addFromGallery() async {
    final files = await ImagePicker().pickMultiImage(maxWidth: 2048);
    if (files.isEmpty) return null;
    state = ReferenceState(
      items: state.items,
      activeIndex: state.activeIndex,
      analyzing: true,
    );
    final analyzer = ref.read(referenceAnalyzerProvider);
    final added = <ReferenceItem>[];
    var skipped = 0;
    for (final file in files) {
      try {
        added.add(ReferenceItem(file.path, await analyzer.analyze(file.path)));
      } catch (_) {
        skipped++;
      }
    }
    state = ReferenceState(
      items: [...state.items, ...added],
      // The first newly added photo becomes the active target.
      activeIndex: added.isEmpty ? state.activeIndex : state.items.length,
    );
    if (skipped == 0) return null;
    return added.isEmpty ? '사람이 보이는 사진을 골라 주세요' : '$skipped장은 사람을 찾지 못해서 뺐어요';
  }

  void select(int index) =>
      state = ReferenceState(items: state.items, activeIndex: index);

  void remove(int index) {
    final items = [...state.items]..removeAt(index);
    var active = state.activeIndex;
    if (index < active || active >= items.length) active = active - 1;
    state = ReferenceState(items: items, activeIndex: active.clamp(0, 99));
  }

  void clear() => state = const ReferenceState();
}

// ---- Shooting mode (추천 / 맞춤) and recommend level ----

class ModeState {
  const ModeState({this.mode = ShootMode.recommend, this.level = 3});

  final ShootMode mode;

  /// 1 = 인물 중심 (person largest) … 5 = 배경 중심.
  final int level;
}

final modeProvider = NotifierProvider<ModeNotifier, ModeState>(
  ModeNotifier.new,
);

class ModeNotifier extends Notifier<ModeState> {
  @override
  ModeState build() => const ModeState();

  void setMode(ShootMode mode) =>
      state = ModeState(mode: mode, level: state.level);

  void setLevel(int level) =>
      state = ModeState(mode: state.mode, level: level.clamp(1, 5));
}

// ---- Hand-over mode (the phone is with the photographer) ----

class HandoverState {
  const HandoverState({this.active = false, this.lang = 'ko'});

  final bool active;

  /// Photographer's language: 'ko' / 'en' / 'ja'.
  final String lang;
}

final handoverProvider = NotifierProvider<HandoverNotifier, HandoverState>(
  HandoverNotifier.new,
);

class HandoverNotifier extends Notifier<HandoverState> {
  @override
  HandoverState build() => const HandoverState();

  void start(String lang) => state = HandoverState(active: true, lang: lang);

  /// The owner takes the phone back (long press). Keeps the language.
  void stop() => state = HandoverState(lang: state.lang);
}

// ---- Front camera = plain camera (no coaching, no recommendation) ----

final frontCameraProvider = NotifierProvider<FrontCameraNotifier, bool>(
  FrontCameraNotifier.new,
);

class FrontCameraNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool front) => state = front;
}
