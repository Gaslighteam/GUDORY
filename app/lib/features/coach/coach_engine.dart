import '../../core/contracts.dart';
import '../../core/models.dart';
import 'axes.dart';

typedef CoachClock = Duration Function();

/// Stateful instruction selection; the injected clock must be monotonic.
///
/// oppositeWay is one state transition per axis activation, not a per-frame
/// event. Consumers should announce on key/axis transitions, not object identity:
/// errors and amounts are live snapshots even while a key is held.
/// PoseSource supplies the whole shot frame; coaching.dart alone applies the
/// preview crop. The engine never crops or rotates landmarks again.
class DefaultCoachEngine implements CoachEngine {
  DefaultCoachEngine({
    CoachClock? clock,
    this.minInstructionHold = const Duration(milliseconds: 1500),
  }) : _clock = clock ?? _stopwatchClock() {
    if (minInstructionHold.isNegative) {
      throw ArgumentError.value(minInstructionHold, 'minInstructionHold');
    }
  }

  static const _enter = 1.0;
  static const _exit = 0.8;
  static const _growth = 0.3;
  static const _growthWindow = Duration(seconds: 1);
  static const _precision = 1e-9;
  static const _thresholdPrecision = 1e-12;

  final Duration minInstructionHold;
  final CoachClock _clock;
  Object? _targetValues;
  CoachAxis? _activeAxis;
  InstructionKey? _shownKey;
  Duration? _shownAt;
  bool _warned = false;
  final List<_ErrorSample> _history = [];

  static CoachClock _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  @override
  CoachInstruction update(PoseFrame frame, TargetComposition target) {
    final now = _clock();
    // Structural equality deliberately ignores TargetComposition identity.
    // Different reference files with identical values cannot be distinguished
    // by this contract; the caller must reset() when replacing such a file.
    final values = (
      height: target.personHeightRatio,
      x: target.personCenterX,
      y: target.personCenterY,
      horizon: target.horizonY,
      tolHeight: target.tolHeight,
      tolX: target.tolX,
      tolY: target.tolY,
      tolRoll: target.tolRollDeg,
      source: target.source,
      framing: target.framing,
      orientation: target.orientation,
    );
    if (_targetValues != values) {
      _clearGuidance();
      _targetValues = values;
    }

    // Orientation has priority over person detection, level reliability and
    // every held movement/warning. Coordinates in unlike shot spaces must not
    // be compared. Spatial zeroes here mean unmeasured, not aligned.
    if (frame.orientation != target.orientation) {
      return _interrupt(
        target.orientation == ShotOrientation.landscape
            ? InstructionKey.turnLandscape
            : InstructionKey.turnPortrait,
        _unmeasuredErrors(frame, target),
      );
    }

    final current = measureComposition(frame, framing: target.framing);
    if (current == null) {
      return _interrupt(
        InstructionKey.noPerson,
        _unmeasuredErrors(frame, target),
      );
    }
    final axes = calculateAxisErrors(
      current,
      target,
      // A zero level error denotes a skipped/unmeasurable axis while flat;
      // it must never imply global alignment (raisePhone below handles this).
      rollDeg: frame.rollReliable ? frame.rollDeg : 0,
    );
    final errors = axes.errors;
    if (!frame.rollReliable && _activeAxis == CoachAxis.level) {
      // Also interrupts oppositeWay when it belongs to the level axis. Other
      // axes retain their holds, hysteresis and warning history.
      _clearGuidance();
    }
    // Degenerate geometry cannot yield a finite movement estimate.
    if (axes.currentRatio <= 0) {
      return _interrupt(InstructionKey.noPerson, errors);
    }
    // An unmeasurable level can never permit aligned/automatic capture.
    // Both aligned and raisePhone interrupt obsolete movement immediately.
    if (_eligibleAxes(
      frame.rollReliable,
    ).every((axis) => !_outsideEntry(errors[axis]!))) {
      return frame.rollReliable
          ? _interrupt(InstructionKey.aligned, errors)
          : _interrupt(
              InstructionKey.raisePhone,
              errors,
              amount: 0,
              error: 1.0,
            );
    }

    if (_activeAxis == null ||
        (_canChange(now) &&
            errors[_activeAxis]!.abs() < _exit - _thresholdPrecision)) {
      _activate(_firstOutside(errors, frame.rollReliable), errors, now);
    }
    final axis = _activeAxis!;
    final error = errors[axis]!;
    final worseningNow = _recordError(error, now);
    if (_canChange(now)) {
      final direction = _direction(axis, error);
      if (_shownKey == InstructionKey.oppositeWay || _shownKey != direction) {
        _show(direction, now);
      } else if (!_warned && worseningNow) {
        // No queued warning is carried over from the hold period: the live
        // one-second window and latest movement must still show worsening.
        _warned = true;
        _show(InstructionKey.oppositeWay, now);
      }
    }

    final amount = switch (axis) {
      CoachAxis.level => 0.5,
      CoachAxis.distance => distanceSteps(
        axes.currentRatio,
        axes.targetRatio,
        framing: axes.framing,
        orientation: axes.orientation,
      ),
      CoachAxis.horizontal => horizontalSteps(
        current.personCenterX - target.personCenterX,
        estimateDistanceMeters(
          axes.currentRatio,
          framing: axes.framing,
          orientation: axes.orientation,
        ),
        orientation: axes.orientation,
      ),
      CoachAxis.height => heightFists(
        current.personCenterY - target.personCenterY,
        estimateDistanceMeters(
          axes.currentRatio,
          framing: axes.framing,
          orientation: axes.orientation,
        ),
        orientation: axes.orientation,
      ),
    };
    return _instruction(_shownKey!, errors, axis: axis, amount: amount);
  }

  bool _canChange(Duration now) =>
      _shownAt == null || now - _shownAt! >= minInstructionHold;

  Iterable<CoachAxis> _eligibleAxes(bool rollReliable) =>
      CoachAxis.values.where((axis) => rollReliable || axis != CoachAxis.level);

  // Tolerate only floating-point roundoff at the exact 1.0 / 0.8 boundaries.
  bool _outsideEntry(double error) =>
      error.abs() > _enter + _thresholdPrecision;

  CoachAxis _firstOutside(Map<CoachAxis, double> errors, bool rollReliable) =>
      _eligibleAxes(
        rollReliable,
      ).firstWhere((axis) => _outsideEntry(errors[axis]!));

  Map<CoachAxis, double> _unmeasuredErrors(
    PoseFrame frame,
    TargetComposition target,
  ) => {
    CoachAxis.level:
        frame.rollReliable &&
            frame.rollDeg.isFinite &&
            target.tolRollDeg.isFinite &&
            target.tolRollDeg > 0
        ? frame.rollDeg / target.tolRollDeg
        : 0,
    CoachAxis.distance: 0,
    CoachAxis.horizontal: 0,
    CoachAxis.height: 0,
  };

  void _activate(CoachAxis axis, Map<CoachAxis, double> errors, Duration now) {
    _clearGuidance();
    _activeAxis = axis;
    _show(_direction(axis, errors[axis]!), now);
  }

  InstructionKey _direction(CoachAxis axis, double error) => switch (axis) {
    CoachAxis.level => InstructionKey.holdPhoneUpright,
    CoachAxis.distance =>
      error > 0 ? InstructionKey.stepBack : InstructionKey.stepForward,
    CoachAxis.horizontal =>
      error > 0 ? InstructionKey.stepRight : InstructionKey.stepLeft,
    CoachAxis.height =>
      error > 0 ? InstructionKey.phoneDown : InstructionKey.phoneUp,
  };

  void _show(InstructionKey key, Duration now) {
    _shownKey = key;
    _shownAt = now;
  }

  bool _recordError(double error, Duration now) {
    if (_history.isNotEmpty &&
        (_history.last.error.sign != error.sign ||
            error.abs() < _history.last.error.abs() - _precision)) {
      // Improvement invalidates earlier worsening evidence. A tiny rebound
      // must not resurrect a warning caused by the previous wrong movement.
      _history.clear();
    }
    _history.removeWhere((sample) => now - sample.at > _growthWindow);
    final previous = _history.isEmpty ? null : _history.last;
    final worsening =
        previous != null &&
        now > previous.at &&
        error.abs() > previous.error.abs() + _precision &&
        _history.any(
          (sample) =>
              now > sample.at &&
              error.abs() - sample.error.abs() >= _growth - _precision,
        );
    // Repeated updates at the same instant do not create temporal evidence.
    _history.removeWhere((sample) => sample.at == now);
    _history.add(_ErrorSample(now, error));
    return worsening;
  }

  CoachInstruction _interrupt(
    InstructionKey key,
    Map<CoachAxis, double> errors, {
    double amount = 0.5,
    double? error,
  }) {
    _clearGuidance();
    return _instruction(key, errors, amount: amount, error: error);
  }

  CoachInstruction _instruction(
    InstructionKey key,
    Map<CoachAxis, double> errors, {
    CoachAxis? axis,
    double amount = 0.5,
    double? error,
  }) => CoachInstruction(
    key: key,
    axis: axis,
    who: Who.camera,
    amount: amount,
    error: error ?? (axis == null ? 0 : errors[axis]!),
    aligned: key == InstructionKey.aligned,
    errors: Map.unmodifiable(errors),
  );

  void _clearGuidance() {
    _activeAxis = null;
    _shownKey = null;
    _shownAt = null;
    _warned = false;
    _history.clear();
  }

  @override
  void reset() {
    _targetValues = null;
    _clearGuidance();
  }
}

class _ErrorSample {
  const _ErrorSample(this.at, this.error);
  final Duration at;
  final double error;
}
