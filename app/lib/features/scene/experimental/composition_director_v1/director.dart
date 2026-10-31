import 'dart:math' as math;
import 'director_models.dart';
import 'background_features.dart';
import 'compositions.dart';
import 'actions.dart';

class CompositionDirector {
  CompositionDirector({
    this.weights = const ScoringWeights(),
    this.cooldown = 1.5,
    this.targetHold = 6,
  });
  final ScoringWeights weights;
  final double cooldown, targetHold;
  CompositionCandidate? target;
  SceneFeatures? baseline;
  String? key;
  double? at, selectedAt;
  (DirectorAction, double, double, double)? pending;
  bool blocked = false, settled = false;
  int generation = 0;
  void reset() {
    target = null;
    baseline = null;
    key = null;
    at = selectedAt = null;
    pending = null;
    blocked = settled = false;
  }

  DirectorDecision update(
    DirectorFrame f, [
    MovementContext context = const MovementContext(),
  ]) {
    final features = analyzeScene(f);
    DirectorDecision result(DirectorAction action, String progress) =>
        DirectorDecision(features, target, action, generation, progress);
    if (!features.valid || f.person == null || !f.person!.valid) {
      reset();
      return result(
        holdAction(f.valid ? 'person-or-mask-unavailable' : 'invalid-input'),
        'unavailable',
      );
    }
    if (at != null && f.at <= at!) {
      return result(holdAction('non-monotonic-observation'), 'unavailable');
    }
    at = f.at;
    if (key != f.key ||
        baseline != null && sceneChange(baseline!, features) > .28) {
      target = null;
      baseline = null;
      pending = null;
      blocked = settled = false;
    }
    key = f.key;
    if (target == null) {
      target = selectCandidate(generateCandidates(f, features, weights));
      selectedAt = f.at;
      baseline = features;
      generation++;
    }
    var t = target;
    if (t == null) {
      return result(holdAction('no-visible-feasible-candidate'), 'unavailable');
    }
    if (features.confidence < .12) {
      pending = null;
      return result(holdAction('weak-scene-evidence'), 'unavailable');
    }
    if (acceptableComposition(f.person!, t, settled ? 1.3 : 1)) {
      pending = null;
      settled = true;
      return result(holdAction('composition-acceptable', true), 'acceptable');
    }
    settled = false;
    var progress = 'new-observation';
    if (pending case final previous?) {
      if (f.at - previous.$2 < cooldown) {
        return result(holdAction('awaiting-movement-observation'), 'waiting');
      }
      final gain = math.min(
        previous.$3 - compositionError(f.person!, t),
        previous.$4 - _intended(f.person!, t, previous.$1),
      );
      if (gain < .15) {
        blocked = true;
        progress = gain < -.15 ? 'worsened' : 'no-confirmed-progress';
      } else {
        progress = 'improved';
      }
      pending = null;
    }
    if (blocked) {
      return result(holdAction('movement-needs-reassessment'), progress);
    }
    if (f.at - selectedAt! >= targetHold && progress != 'improved') {
      final candidates = generateCandidates(f, features, weights),
          alternative = selectCandidate(
            generateCandidates(f, features, weights),
          );
      final current = candidates
          .where(
            (c) =>
                (c.x - t!.x).abs() < .001 &&
                (c.eyeY - t.eyeY).abs() < .001 &&
                (c.scale - t.scale).abs() < .001 &&
                c.framing == t.framing,
          )
          .toList();
      final score = current.isEmpty ? t.score : current.first.score;
      if (alternative != null && alternative.score > score + .8) {
        target = t = alternative;
        selectedAt = f.at;
        generation++;
      }
    }
    final action = decideAction(f, t, features, context);
    if (action.valid && action.direction != 'capture') {
      pending = (
        action,
        f.at,
        compositionError(f.person!, t),
        _intended(f.person!, t, action),
      );
    }
    return result(action, progress);
  }

  double _intended(
    DirectorPerson p,
    CompositionCandidate t,
    DirectorAction action,
  ) {
    if (['left', 'right'].contains(action.direction)) {
      return (p.x - t.x).abs() / .08;
    }
    if (['up', 'down'].contains(action.direction)) {
      return (p.eyeY - t.eyeY).abs() / .08;
    }
    return (p.scale - t.scale).abs() / math.max(.012, t.scale * .1);
  }
}
