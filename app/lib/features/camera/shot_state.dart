// Shooting state: references, category selection.
import 'dart:convert';

import 'package:flutter/services.dart';
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

// ---- Category (auto guess + suggestions + manual pin) ----

class CategoryState {
  const CategoryState({
    this.categories = const [],
    this.hashtagLabels = const {},
    this.guess,
    this.manualId,
  });

  final List<CategoryInfo> categories;
  final Map<String, String> hashtagLabels;
  final CategoryGuess? guess;
  final String? manualId;

  String? get selectedId => manualId ?? guess?.primaryId;

  String labelOf(String id) =>
      categories.where((c) => c.id == id).firstOrNull?.label ?? id;

  CategoryState copyWith({
    List<CategoryInfo>? categories,
    Map<String, String>? hashtagLabels,
    CategoryGuess? guess,
    String? Function()? manualId,
  }) => CategoryState(
    categories: categories ?? this.categories,
    hashtagLabels: hashtagLabels ?? this.hashtagLabels,
    guess: guess ?? this.guess,
    manualId: manualId != null ? manualId() : this.manualId,
  );
}

final categoryProvider = NotifierProvider<CategoryNotifier, CategoryState>(
  CategoryNotifier.new,
);

class CategoryNotifier extends Notifier<CategoryState> {
  @override
  CategoryState build() {
    _load();
    return const CategoryState();
  }

  /// TODO(lead): take categories from Seojun's CompositionLibrary and the
  /// guess from SceneClassifier when feat/scene lands.
  Future<void> _load() async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/categories.json'))
            as Map<String, dynamic>;
    final categories = [
      for (final c in raw['categories'] as List)
        CategoryInfo(
          id: c['id'] as String,
          label: c['label'] as String,
          prompts: List<String>.from(c['prompts'] as List),
          hashtagIds: List<String>.from(c['hashtagIds'] as List),
        ),
    ];
    final hashtags = {
      for (final h in raw['hashtags'] as List)
        h['id'] as String: h['label'] as String,
    };
    state = state.copyWith(
      categories: categories,
      hashtagLabels: hashtags,
      guess: categories.isEmpty
          ? null
          : CategoryGuess(
              primaryId: categories.first.id,
              suggestedIds: [for (final c in categories.skip(1).take(2)) c.id],
              hashtagIds: categories.first.hashtagIds,
              confidence: 0,
              modelVariant: 'fake',
            ),
    );
  }

  void updateGuess(CategoryGuess guess) => state = state.copyWith(guess: guess);

  /// Tap a chip: pin it, or unpin when it is already pinned.
  void tap(String id) =>
      state = state.copyWith(manualId: () => state.manualId == id ? null : id);

  void clearManual() => state = state.copyWith(manualId: () => null);
}
