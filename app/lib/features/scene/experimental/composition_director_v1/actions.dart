import 'dart:math' as math;
import 'director_models.dart';
import 'compositions.dart';

DirectorAction holdAction(String reason, [bool aligned = false]) =>
    DirectorAction(
      'photographer',
      aligned ? 'capture' : 'hold',
      0,
      'none',
      aligned ? '촬영자님, 그대로 유지하고 셔터를 눌러 주세요.' : '촬영자님, 잠시 그대로 유지해 주세요.',
      aligned ? .8 : 0,
      aligned,
      reason,
    );
bool acceptableComposition(
  DirectorPerson p,
  CompositionCandidate t, [
  double multiplier = 1,
]) =>
    (p.x - t.x).abs() <= .06 * multiplier &&
    (p.eyeY - t.eyeY).abs() <= .06 * multiplier &&
    (p.scale - t.scale).abs() <= math.max(.012, t.scale * .1) * multiplier;
DirectorAction decideAction(
  DirectorFrame f,
  CompositionCandidate target,
  SceneFeatures features,
  MovementContext context,
) {
  final p = f.person!;
  if (features.confidence < .12) return holdAction('weak-scene-evidence');
  if (acceptableComposition(p, target)) {
    return holdAction('composition-acceptable', true);
  }
  if (context.geometry != f.geometry ||
      !context.safetyAt.isFinite ||
      f.at - context.safetyAt < 0 ||
      f.at - context.safetyAt > 2) {
    return holdAction('fresh-safety-evidence-required');
  }
  DirectorAction? best;
  var bestGain = double.negativeInfinity;
  for (final m in context.motions) {
    if (!['subject', 'photographer'].contains(m.actor) ||
        !['horizontal', 'height', 'distance'].contains(m.axis) ||
        m.axis != 'horizontal' && m.actor != 'photographer' ||
        m.geometry != f.geometry ||
        ![
          m.dx,
          m.dy,
          m.ds,
          m.at,
          m.confidence,
          m.preservation,
        ].every((v) => v.isFinite) ||
        m.confidence < .7 ||
        m.confidence > 1 ||
        f.at - m.at < 0 ||
        f.at - m.at > 5 ||
        m.actor == 'photographer' &&
            (m.preservation < .8 || m.preservation > 1)) {
      continue;
    }
    final norm = m.dx * m.dx + m.dy * m.dy + m.ds * m.ds;
    if (norm < .0001 ||
        [m.dx.abs(), m.dy.abs(), m.ds.abs()].reduce(math.max) > .4) {
      continue;
    }
    final amount =
        ((target.x - p.x) * m.dx +
            (target.eyeY - p.eyeY) * m.dy +
            (target.scale - p.scale) * m.ds) /
        norm;
    if (amount.abs() < .25) continue;
    final sign = amount > 0 ? 1.0 : -1.0;
    final pair = {
      'horizontal': ('left', 'right'),
      'height': ('down', 'up'),
      'distance': ('backward', 'forward'),
    }[m.axis]!;
    final direction = sign > 0 ? pair.$2 : pair.$1;
    if (!context.safe.contains('${m.actor}/$direction')) continue;
    final predicted = p.shifted(
      m.dx * sign * .5,
      m.dy * sign * .5,
      m.ds * sign * .5,
    );
    if (!predicted.valid ||
        predicted.x < .04 ||
        predicted.x > .96 ||
        predicted.headY + predicted.span(target.framing) > .98) {
      continue;
    }
    final gain =
        compositionError(p, target) - compositionError(predicted, target);
    if (gain <= .12 || gain <= bestGain) continue;
    bestGain = gain;
    best = DirectorAction(
      m.actor,
      direction,
      .5,
      m.axis == 'height' ? 'fist' : 'step',
      koreanSentence(m.actor, direction),
      math.min(m.confidence, math.max(.3, features.confidence)),
      true,
      'measured-response-and-safe-direction',
    );
  }
  return best ?? holdAction('movement-effect-unconfirmed');
}

String koreanSentence(String actor, String direction) {
  final who = actor == 'photographer' ? '촬영자님' : '모델님';
  if (['left', 'right'].contains(direction)) {
    final side = direction == 'left' ? '왼쪽' : '오른쪽',
        relative = actor == 'subject' ? '촬영자 기준 ' : '';
    return '$who, $relative$side으로 반 걸음 이동해 주세요.';
  }
  if (['forward', 'backward'].contains(direction)) {
    final side = direction == 'forward' ? '앞으로' : '뒤로';
    return '$who, $side 반 걸음 이동해 주세요.';
  }
  final side = direction == 'up' ? '올려' : '내려';
  return '$who, 폰을 반 주먹만큼 $side 주세요.';
}
