import '../../core/models.dart';

/// Scores are suitability heuristics, not aesthetic quality probabilities.
class ScoredLayoutCandidate {
  const ScoredLayoutCandidate({
    required this.id,
    required this.recommendation,
    required this.score,
    this.canChallenge = true,
  });
  final String id;
  final Recommendation recommendation;
  final double score;
  final bool canChallenge;
}

class CandidateContext {
  const CandidateContext(this.level, this.orientation, this.mode);
  final int level;
  final ShotOrientation orientation;
  final ShootMode mode;
  @override
  bool operator ==(Object other) =>
      other is CandidateContext &&
      level == other.level &&
      orientation == other.orientation &&
      mode == other.mode;
  @override
  int get hashCode => Object.hash(level, orientation, mode);
}

class CandidateStabilityConfig {
  const CandidateStabilityConfig({
    this.minimumHold = const Duration(seconds: 6),
    this.switchMargin = .08,
  });
  final Duration minimumHold;
  final double switchMargin;
}

/// Keeps a target snapshot, not just an ID, until a justified switch.
/// Re-score the incumbent against the CURRENT input before applying margin.
class CandidateSelector {
  CandidateSelector({
    Duration Function()? clock,
    this.config = const CandidateStabilityConfig(),
  }) : _clock = clock ?? _monotonicClock() {
    if (config.minimumHold.isNegative ||
        !config.switchMargin.isFinite ||
        config.switchMargin <= 0) {
      throw ArgumentError('Invalid candidate stability configuration');
    }
  }
  final Duration Function() _clock;
  final CandidateStabilityConfig config;
  CandidateContext? _context;
  ScoredLayoutCandidate? _selected;
  Duration? _selectedAt;
  Duration? get selectedAt => _selectedAt;
  String? get selectedId => _selected?.id;
  CandidateContext? get context => _context;
  Recommendation? get selected => _selected?.recommendation;

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  void useContext(CandidateContext context) {
    if (_context == context) return;
    reset();
    _context = context;
  }

  Recommendation? update(
    CandidateContext context,
    List<ScoredLayoutCandidate> candidates,
  ) {
    useContext(context);
    if (context.mode != ShootMode.recommend) return null;
    final valid = candidates
        .where(
          (c) =>
              c.score.isFinite &&
              c.score >= 0 &&
              c.score <= 1 &&
              c.id.isNotEmpty &&
              c.recommendation.neighbors >= 3 &&
              c.recommendation.target.orientation == context.orientation &&
              c.recommendation.target.source == 'recommend:${context.level}',
        )
        .toList();
    final challengers = valid.where((c) => c.canChallenge).toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : a.id.compareTo(b.id);
      });
    // Failed/unsupported analysis never displaces a previously good target.
    if (challengers.isEmpty) return selected;
    final best = challengers.first;
    final current = _selected;
    final now = _clock();
    if (current == null) return _adopt(best, now);
    // Same ID keeps both the original target and original selection time.
    if (current.id == best.id) return selected;
    final elapsed = now - _selectedAt!;
    if (elapsed.isNegative || elapsed < config.minimumHold) return selected;
    final incumbent = valid.where((c) => c.id == current.id);
    // A candidate outside the current positive-cosine set has score zero.
    final currentScore = incumbent.isEmpty ? 0.0 : incumbent.first.score;
    if (best.score - currentScore < config.switchMargin - 1e-12) {
      return selected;
    }
    return _adopt(best, now);
  }

  Recommendation _adopt(ScoredLayoutCandidate candidate, Duration now) {
    _selected = candidate;
    _selectedAt = now;
    return candidate.recommendation;
  }

  void reset() {
    _context = null;
    _selected = null;
    _selectedAt = null;
  }
}
