import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/contracts.dart';
import '../../core/models.dart';
import 'candidate_stability.dart';
import 'recommendation_data.dart';
import 'scene_embedding.dart';
import 'spatial_layout.dart';

/// Experimental-only entry point. No production provider imports this class.
/// Callers explicitly supply optional sidecars and the existing shot geometry.
class ExperimentalSpatialRecommender implements Recommender {
  ExperimentalSpatialRecommender({
    required this.loadPhaseA,
    this.loadPhaseB,
    Future<String> Function()? loadLegacy,
    SceneEmbedder? embedder,
    required this.viewForFrame,
    // Initial held-out evidence did not justify activating the spatial term.
    // Explicit experiment callers can opt in with SpatialScoring(beta: .8).
    this.scoring = const SpatialScoring(beta: 0),
    this.cacheDuration = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
    Duration Function()? candidateClock,
  }) : _loadLegacy =
           loadLegacy ?? (() => rootBundle.loadString('assets/recommend.json')),
       _embedder =
           embedder ?? NativeSceneEmbedder(includeSpatial: scoring.beta > 0),
       _now = now ?? DateTime.now,
       _selector = CandidateSelector(clock: candidateClock);

  final Future<String> Function() loadPhaseA, _loadLegacy;
  final Future<String> Function()? loadPhaseB;
  final SceneView Function(CameraFrame, ShotOrientation) viewForFrame;
  final SpatialScoring scoring;
  final Duration cacheDuration, requestTimeout;
  final SceneEmbedder _embedder;
  final DateTime Function() _now;
  final CandidateSelector _selector;
  RecommendationData _legacy = RecommendationData.empty();
  SpatialLayoutData? _data;
  Future<void>? _loading;
  bool _disposed = false;
  ShootMode _mode = ShootMode.recommend;
  CandidateContext? _context;
  int _epoch = 0, _serial = 0, _embeddingEpoch = 0, _inferences = 0;
  SceneEmbedding? _cache;
  DateTime? _cacheAt;
  List<Object>? _cacheKey, _pendingKey;
  Future<SceneEmbedding?>? _pending;
  String status = 'not-run';
  int get inferences => _inferences;
  String? get selectedId => _selector.selectedId;
  Duration? get selectedAt => _selector.selectedAt;

  Future<void> _assets() => _loading ??= _load();
  Future<void> _load() async {
    try {
      _legacy = await compute(
        RecommendationData.parse,
        await _loadLegacy().timeout(requestTimeout),
      );
    } catch (_) {
      /* embedded safe baseline */
    }
    try {
      final a = await loadPhaseA().timeout(requestTimeout);
      String? b;
      try {
        b = await loadPhaseB?.call().timeout(requestTimeout);
      } catch (_) {
        /* Phase A only */
      }
      final data = await compute(_parseSpatial, (a, b)).timeout(requestTimeout);
      if (!_disposed) _data = data;
    } catch (_) {
      /* legacy only */
    }
  }

  @override
  Future<void> warmUp() async {
    if (_disposed) return;
    await _assets();
    try {
      await _embedder.warmUp().timeout(requestTimeout);
    } catch (_) {
      /* optional native model */
    }
  }

  void setMode(ShootMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _epoch++;
    _serial++;
    _context = null;
    _selector.reset();
    invalidateEmbedding();
  }

  /// Explicit integration hook for lens/zoom/preview/lifecycle changes.
  void invalidateEmbedding() {
    _embeddingEpoch++;
    _cache = null;
    _cacheAt = null;
    _cacheKey = null;
  }

  Recommendation _fallback(int level, ShotOrientation orientation) =>
      (_data?.base ?? _legacy).fallback(level, orientation);

  Recommendation _heldOrFallback(int level, ShotOrientation orientation) {
    final c = _selector.context;
    return c?.level == level &&
            c?.orientation == orientation &&
            c?.mode == _mode
        ? _selector.selected ?? _fallback(level, orientation)
        : _fallback(level, orientation);
  }

  @override
  Future<Recommendation> recommend(
    CameraFrame frame,
    int requested,
    ShotOrientation orientation,
  ) async {
    final level = recommendationLevel(requested),
        context = CandidateContext(
          recommendationLevel(requested),
          orientation,
          _mode,
        );
    if (_context != context) {
      _context = context;
      _epoch++;
      _selector.useContext(context);
    }
    final epoch = _epoch, ticket = ++_serial;
    try {
      if (_disposed || _mode != ShootMode.recommend) {
        return _fallback(level, orientation);
      }
      await _assets();
      if (epoch != _epoch || ticket != _serial || _disposed) {
        return _heldOrFallback(level, orientation);
      }
      final data = _data;
      if (data == null) {
        status = 'legacy/asset-unavailable';
        return _fallback(level, orientation);
      }
      final view = viewForFrame(frame, orientation);
      view.validate(orientation);
      final embedding = await _embedding(frame, view);
      if (epoch != _epoch || ticket != _serial || _disposed) {
        status = 'stale';
        return _heldOrFallback(level, orientation);
      }
      if (embedding == null) {
        status = 'held/embedding-failure';
        return _heldOrFallback(level, orientation);
      }
      if (scoring.beta > 0 &&
          data.records.isNotEmpty &&
          !(embedding.spatial?.valid ?? false) &&
          _selector.selected != null) {
        status = 'held/spatial-unavailable';
        return _selector.selected!;
      }
      final candidates = await compute(_rankSpatial, (
        data,
        embedding,
        level,
        orientation,
        scoring,
        _selector.selectedId,
      )).timeout(requestTimeout);
      if (epoch != _epoch || ticket != _serial || _disposed) {
        status = 'stale';
        return _heldOrFallback(level, orientation);
      }
      final selected = _selector.update(
        context,
        candidates
            .map((c) => c.scored(level, orientation, embedding.variant))
            .toList(),
      );
      status = selected == null
          ? 'legacy/no-candidate'
          : candidates.any((c) => c.spatialWeight > 0)
          ? 'spatial-or-held'
          : 'phase-a-or-held';
      return selected ?? _fallback(level, orientation);
    } catch (_) {
      status = 'held/analysis-failure';
      return _heldOrFallback(level, orientation);
    }
  }

  Future<SceneEmbedding?> _embedding(CameraFrame frame, SceneView view) async {
    final image = frame.image;
    if (image.planes.length != 1) return null;
    final key = <Object>[
      view,
      frame.sensorOrientation,
      frame.isFrontCamera,
      image.width,
      image.height,
      image.format.raw,
      image.planes.single.bytesPerRow,
      image.planes.single.bytes.length,
    ];
    final at = _cacheAt, age = at == null ? null : _now().difference(at);
    if (_cache != null &&
        listEquals(key, _cacheKey) &&
        age != null &&
        !age.isNegative &&
        age < cacheDuration) {
      return _cache;
    }
    if (_pending != null && !listEquals(key, _pendingKey)) return null;
    if (_pending == null) {
      _pendingKey = key;
      _pending = _capture(frame, view, key, _embeddingEpoch);
    }
    return _pending!.timeout(
      requestTimeout,
      onTimeout: () {
        invalidateEmbedding();
        return null;
      },
    );
  }

  Future<SceneEmbedding?> _capture(
    CameraFrame frame,
    SceneView view,
    List<Object> key,
    int generation,
  ) async {
    _inferences++;
    try {
      final at = _now(), result = await _embedder.embed(frame, view);
      if (result.variant != 'q8' && result.variant != 'fp16') return null;
      if (!_disposed && generation == _embeddingEpoch) {
        _cache = result;
        _cacheKey = key;
        _cacheAt = at;
        return result;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _pending = null;
      _pendingKey = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    _serial++;
    invalidateEmbedding();
    _selector.reset();
    try {
      await _pending;
      await _embedder.dispose();
    } catch (_) {
      /* non-throwing teardown */
    }
  }
}

SpatialLayoutData _parseSpatial((String, String?) job) =>
    SpatialLayoutData.parse(job.$1, job.$2);
List<SpatialCandidate> _rankSpatial(
  (
    SpatialLayoutData,
    SceneEmbedding,
    int,
    ShotOrientation,
    SpatialScoring,
    String?,
  )
  job,
) {
  final candidates = job.$1.rank(
    job.$2.values,
    job.$3,
    job.$4,
    job.$2.spatial,
    config: job.$5,
  );
  final incumbent = job.$1.rescoreIncumbent(
    job.$2.values,
    job.$4,
    job.$2.spatial,
    candidates,
    job.$6,
    config: job.$5,
  );
  if (incumbent != null) {
    candidates.add(incumbent);
  }
  return candidates;
}
