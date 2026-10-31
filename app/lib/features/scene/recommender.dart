import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'recommendation_data.dart';
import 'scene_embedding.dart';

export 'scene_embedding.dart' show SceneView;

class SceneRecommendationDiagnostics {
  const SceneRecommendationDiagnostics(
    this.cacheHit,
    this.inferences,
    this.duration,
    this.cosine,
    this.selectedLevel,
    this.status,
    this.trace,
    this.clusterCount,
  );
  final bool cacheHit;
  final int inferences;
  final Duration duration;
  final double? cosine;
  final int? selectedLevel;
  final String status;
  final SceneEmbeddingTrace? trace;
  final int clusterCount;
}

class _EmbeddingAttempt {
  const _EmbeddingAttempt(this.embedding, this.status, [this.trace]);
  final SceneEmbedding? embedding;
  final String status;
  final SceneEmbeddingTrace? trace;
}

/// Owns one model/masker and one short-lived in-memory background embedding.
/// No providers, camera controllers, photos or per-photo persistence are owned.
class SceneRecommender implements Recommender {
  SceneRecommender({
    SceneEmbedder? embedder,
    AssetBundle? bundle,
    Future<String> Function()? loadAsset,
    SceneView Function(CameraFrame, ShotOrientation)? viewForFrame,
    this.cacheDuration = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _embedder = embedder ?? NativeSceneEmbedder(),
       _loadAsset =
           loadAsset ??
           (() => (bundle ?? rootBundle).loadString('assets/recommend.json')),
       _viewForFrame = viewForFrame ?? _portraitView,
       _now = now ?? DateTime.now;

  final SceneEmbedder _embedder;
  final Future<String> Function() _loadAsset;
  final SceneView Function(CameraFrame, ShotOrientation) _viewForFrame;
  final DateTime Function() _now;
  final Duration cacheDuration, requestTimeout;
  RecommendationData _data = RecommendationData.empty();
  Future<void>? _loading;
  bool _disposed = false, _timedOut = false;
  int _assetGeneration = 0, _generation = 0, _inferences = 0;
  Future<_EmbeddingAttempt>? _pending;
  List<Object>? _pendingKey, _cacheKey;
  SceneEmbedding? _cache;
  DateTime? _cacheAt;
  String _assetStatus = 'asset/not-loaded';
  SceneRecommendationDiagnostics? lastDiagnostics;

  static SceneView _portraitView(CameraFrame _, ShotOrientation orientation) {
    // The shared CameraFrame does not encode landscape direction or preview
    // crop. Integration supplies both; never guess the clockwise side.
    if (orientation != ShotOrientation.portrait) {
      throw StateError('Shot geometry required');
    }
    return const SceneView();
  }

  Future<void> _assets() => _loading ??= _load(_assetGeneration);
  Future<void> _load(int generation) async {
    try {
      final text = await _loadAsset().timeout(requestTimeout);
      final data = await compute(
        RecommendationData.parse,
        text,
      ).timeout(requestTimeout);
      if (!_disposed && generation == _assetGeneration) {
        _data = data;
        _assetStatus = 'loaded';
      }
    } catch (_) {
      if (generation == _assetGeneration) {
        _assetStatus = 'asset/load-or-parse-failed';
      }
    }
  }

  @override
  Future<void> warmUp() async {
    if (_disposed) return;
    await _assets();
    try {
      await _embedder.warmUp().timeout(requestTimeout);
    } catch (_) {
      /* Optional CLIP. */
    }
  }

  /// Reload after an approved asset update; compiled assets normally update
  /// on app restart. Never reads any old JSON statistics as training input.
  Future<void> reloadAssets() async {
    if (_disposed) return;
    _assetGeneration++;
    _data = RecommendationData.empty();
    _loading = null;
    invalidateEmbedding();
    await _assets();
  }

  /// Call on pause/resume, lens/zoom/preview changes or a deliberate refresh.
  void invalidateEmbedding() {
    _generation++;
    _cache = null;
    _cacheKey = null;
    _cacheAt = null;
  }

  @override
  Future<Recommendation> recommend(
    CameraFrame frame,
    int requested,
    ShotOrientation orientation,
  ) async {
    final watch = Stopwatch()..start();
    final level = recommendationLevel(requested);
    final generation = _generation;
    bool hit = false;
    SceneMatch? match;
    SceneEmbeddingTrace? trace;
    var clusterCount = 0;
    var status = 'fallback';
    var stage = 'asset';
    try {
      if (_disposed) return _data.fallback(level, orientation);
      await _assets();
      clusterCount = _data.clusters
          .where((c) => c.orientation == orientation)
          .length;
      if (_disposed || clusterCount == 0) {
        status = _disposed
            ? 'fallback/disposed'
            : 'fallback/${_assetStatus == 'loaded' ? 'matching/no-clusters' : _assetStatus}';
        return _data.fallback(level, orientation);
      }
      stage = 'geometry';
      final view = _viewForFrame(frame, orientation);
      view.validate(orientation);
      stage = 'camera';
      final key = _key(frame, view);
      final at = _cacheAt;
      final age = at == null ? null : _now().difference(at);
      final useCache =
          _cache != null &&
          listEquals(_cacheKey, key) &&
          age != null &&
          !age.isNegative &&
          age < cacheDuration;
      SceneEmbedding? embedding;
      if (useCache) {
        embedding = _cache;
        hit = true;
      } else {
        stage = 'embedding';
        final attempt = await _embedding(frame, view, key);
        embedding = attempt.embedding;
        status = attempt.status;
        trace = attempt.trace;
      }
      trace ??= embedding?.trace;
      if (_disposed || embedding == null) {
        return _data.fallback(level, orientation);
      }
      stage = 'matching';
      match = await compute(_score, (
        _data,
        embedding,
        level,
        orientation,
      )).timeout(requestTimeout);
      if (_disposed || generation != _generation) {
        status = 'fallback/invalidated';
        return _data.fallback(level, orientation);
      }
      status = match.recommendation.neighbors > 0
          ? 'matched'
          : 'fallback/no-positive-neighbors';
      return match.recommendation;
    } catch (error) {
      // Includes synchronous plugin/format Errors, model/load failures, invalid
      // data and deadlines. No diagnostic callback can make this future throw.
      status = error is SceneFailure
          ? 'fallback/${error.code}'
          : 'fallback/$stage/error-or-timeout';
      if (error is SceneFailure) trace = error.trace;
      return _data.fallback(level, orientation);
    } finally {
      lastDiagnostics = SceneRecommendationDiagnostics(
        hit,
        _inferences,
        watch.elapsed,
        match?.cosine,
        match?.selectedLevel,
        status,
        trace,
        clusterCount,
      );
    }
  }

  List<Object> _key(CameraFrame frame, SceneView view) {
    final image = frame.image;
    if (image.planes.length != 1) {
      throw const FormatException('Invalid camera planes');
    }
    return [
      view,
      frame.sensorOrientation,
      frame.isFrontCamera,
      image.width,
      image.height,
      image.format.raw,
      image.format.group,
      image.planes.single.bytesPerRow,
      image.planes.single.bytesPerPixel ?? -1,
      image.planes.single.bytes.length,
    ];
  }

  Future<_EmbeddingAttempt> _embedding(
    CameraFrame frame,
    SceneView view,
    List<Object> key,
  ) async {
    if (_pending != null && (!listEquals(_pendingKey, key) || _timedOut)) {
      return const _EmbeddingAttempt(null, 'fallback/embedding/busy');
    }
    if (_pending == null) {
      _pendingKey = key;
      _timedOut = false;
      final generation = _generation;
      _pending = Future<_EmbeddingAttempt>.microtask(
        () => _capture(frame, view, key, generation),
      );
    }
    return _pending!.timeout(
      requestTimeout,
      onTimeout: () {
        // A deadline is not native cancellation. Keep the job alive and occupied
        // until it completes; invalidate late results instead of overlapping runs.
        _timedOut = true;
        invalidateEmbedding();
        return const _EmbeddingAttempt(null, 'fallback/embedding/timeout');
      },
    );
  }

  Future<_EmbeddingAttempt> _capture(
    CameraFrame frame,
    SceneView view,
    List<Object> key,
    int generation,
  ) async {
    _inferences++;
    try {
      final capturedAt = _now();
      final embedding = await _embedder.embed(frame, view);
      if (embedding.variant != 'q8' && embedding.variant != 'fp16') {
        return _EmbeddingAttempt(
          null,
          'fallback/model/invalid-variant',
          embedding.trace,
        );
      }
      if (!_disposed && generation == _generation) {
        _cache = embedding;
        _cacheKey = key;
        _cacheAt = capturedAt;
        return _EmbeddingAttempt(embedding, 'embedded', embedding.trace);
      }
      return const _EmbeddingAttempt(null, 'fallback/invalidated');
    } catch (error) {
      return error is SceneFailure
          ? _EmbeddingAttempt(null, 'fallback/${error.code}', error.trace)
          : const _EmbeddingAttempt(null, 'fallback/embedding/error');
    } finally {
      _pending = null;
      _pendingKey = null;
      _timedOut = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _assetGeneration++;
    invalidateEmbedding();
    try {
      await _pending; // never release a session still executing native code
      await _embedder.dispose();
    } catch (_) {
      /* Cleanup must not crash the screen. */
    }
  }
}

SceneMatch _score(
  (RecommendationData, SceneEmbedding, int, ShotOrientation) job,
) => job.$1.match(job.$2.values, job.$3, job.$4, job.$2.variant);
