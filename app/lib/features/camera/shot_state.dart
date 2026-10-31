// Per-shot state: optional reference, category selection, last result.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/models.dart';

// ---- Reference (one shot only; cleared after capture) ----

enum ReferenceStatus { none, analyzing, set }

class ReferenceState {
  const ReferenceState(this.status, {this.path, this.target});
  const ReferenceState.none() : this(ReferenceStatus.none);

  final ReferenceStatus status;
  final String? path;
  final TargetComposition? target;
}

final referenceProvider = NotifierProvider<ReferenceNotifier, ReferenceState>(
  ReferenceNotifier.new,
);

class ReferenceNotifier extends Notifier<ReferenceState> {
  @override
  ReferenceState build() => const ReferenceState.none();

  /// Returns a user-facing error message, or null on success/cancel.
  Future<String?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
    );
    if (file == null) return null;
    state = ReferenceState(ReferenceStatus.analyzing, path: file.path);
    try {
      final target = await ref
          .read(referenceAnalyzerProvider)
          .analyze(file.path);
      state = ReferenceState(
        ReferenceStatus.set,
        path: file.path,
        target: target,
      );
      return null;
    } on NoPersonException catch (e) {
      state = const ReferenceState.none();
      return e.message;
    } catch (_) {
      state = const ReferenceState.none();
      return '레퍼런스 사진을 분석하지 못했어요';
    }
  }

  void clear() => state = const ReferenceState.none();
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

// ---- Last shot ----

class ShotResult {
  const ShotResult({
    required this.path,
    this.referencePath,
    this.categoryId,
    this.hashtagIds = const [],
    required this.savedToGallery,
  });

  final String path;
  final String? referencePath;
  final String? categoryId;
  final List<String> hashtagIds;
  final bool savedToGallery;
}

final lastShotProvider = NotifierProvider<LastShotNotifier, ShotResult?>(
  LastShotNotifier.new,
);

class LastShotNotifier extends Notifier<ShotResult?> {
  @override
  ShotResult? build() => null;

  void set(ShotResult shot) => state = shot;
}
