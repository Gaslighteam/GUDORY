"""Evidence-gated movement selection and constrained Korean construction."""
from math import isfinite
from .candidates import error
from .types import Action


def hold(reason, aligned=False):
    return Action("photographer", "capture" if aligned else "hold", 0., "none",
                  "촬영자님, 그대로 유지하고 셔터를 눌러 주세요." if aligned else
                  "촬영자님, 잠시 그대로 유지해 주세요.",
                  .8 if aligned else 0., aligned, reason)


def acceptable(p, t, multiplier=1.):
    return (abs(p.x - t.x) <= .06 * multiplier
            and abs(p.eye_y - t.eye_y) <= .06 * multiplier
            and abs(p.scale - t.scale) <= max(.012, t.scale * .10) * multiplier)


def decide(frame, target, features, context):
    p = frame.person
    if features.confidence < .12:
        return hold("weak-scene-evidence")
    if acceptable(p, target):
        return hold("composition-acceptable", aligned=True)
    if (context.geometry_id != frame.geometry_id
            or not isfinite(context.safety_at) or not 0 <= frame.at - context.safety_at <= 2):
        return hold("fresh-safety-evidence-required")
    choices = []
    for motion in context.motions:
        if (motion.actor not in ("subject", "photographer")
                or motion.axis not in ("horizontal", "height", "distance")
                or motion.axis == "height" and motion.actor != "photographer"
                or motion.axis == "distance" and motion.actor != "photographer"
                or motion.geometry_id != frame.geometry_id
                or not all(isfinite(v) for v in (motion.dx, motion.dy, motion.dscale,
                       motion.at, motion.confidence, motion.structure_preservation))
                or not .7 <= motion.confidence <= 1
                or not 0 <= frame.at - motion.at <= 5
                or motion.actor == "photographer" and not .8 <= motion.structure_preservation <= 1):
            continue
        # Local linear response only. It does not make camera translation and
        # subject movement interchangeable. Reject cross-axis-heavy responses.
        vector = (motion.dx, motion.dy, motion.dscale)
        norm = sum(v * v for v in vector)
        if norm < .0001 or max(abs(v) for v in vector) > .4:
            continue
        delta = (target.x - p.x, target.eye_y - p.eye_y, target.scale - p.scale)
        amount = sum(a * b for a, b in zip(delta, vector)) / norm
        if abs(amount) < .25:
            continue
        sign = 1 if amount > 0 else -1
        direction = {"horizontal": ("left", "right"), "height": ("down", "up"),
                     "distance": ("backward", "forward")}[motion.axis][sign > 0]
        if (motion.actor, direction) not in context.safe_directions:
            continue
        # One small, approximately half-step or half-fist observation at a time.
        # No accumulated large movements from a photograph-derived distance.
        from dataclasses import replace
        predicted = replace(p, x=p.x + motion.dx * sign * .5,
                            eye_y=p.eye_y + motion.dy * sign * .5,
                            head_y=p.head_y + motion.dy * sign * .5,
                            scale=p.scale + motion.dscale * sign * .5)
        if not predicted.valid or not .04 <= predicted.x <= .96:
            continue
        if predicted.head_y + predicted.span(target.framing) > .98:
            continue
        gain = error(p, target) - error(predicted, target)
        if gain <= .12:
            continue
        text = sentence(motion.actor, direction)
        action = Action(motion.actor, direction, .5,
                        "fist" if motion.axis == "height" else "step", text,
                        min(motion.confidence, max(.3, features.confidence)), True,
                        "measured-response-and-safe-direction")
        choices.append((gain, action))
    return max(choices, key=lambda item: item[0])[1] if choices else hold("movement-effect-unconfirmed")


def sentence(actor, direction):
    who = "촬영자님" if actor == "photographer" else "모델님"
    if direction in ("left", "right"):
        side = "왼쪽" if direction == "left" else "오른쪽"
        relative = "촬영자 기준 " if actor == "subject" else ""
        return f"{who}, {relative}{side}으로 반 걸음 이동해 주세요."
    if direction in ("forward", "backward"):
        side = "앞으로" if direction == "forward" else "뒤로"
        return f"{who}, {side} 반 걸음 이동해 주세요."
    side = "올려" if direction == "up" else "내려"
    return f"{who}, 폰을 반 주먹만큼 {side} 주세요."
