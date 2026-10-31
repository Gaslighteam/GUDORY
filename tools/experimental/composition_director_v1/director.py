"""Stateful feature -> candidate -> action flow. No production imports."""
from .actions import acceptable, decide, hold
from .candidates import Weights, error, generate, select
from .features import analyze, scene_change
from .types import Context, Decision, Features


class Director:
    def __init__(self, weights=Weights(), cooldown=1.5, target_hold=6.):
        self.weights, self.cooldown, self.target_hold = weights, cooldown, target_hold
        self.target = self.baseline = self.last_features = None
        self.key = self.at = self.selected_at = None
        self.pending = None  # (action, issued_at, total_error, intended_error)
        self.blocked = False
        self.settled = False
        self.generation = 0

    def reset(self):
        self.target = self.baseline = self.last_features = None
        self.pending = None
        self.blocked = self.settled = False
        self.key = self.at = self.selected_at = None

    def update(self, frame, context=Context()):
        try:
            features = analyze(frame)
        except (ValueError, TypeError, OverflowError):
            self.reset()
            features = Features((), (), None, 0., False, "invalid-input")
            return Decision(features, None, hold("invalid-input"), self.generation, "unavailable")
        if (frame.person is None or not frame.person.valid or not features.valid):
            self.reset()
            return Decision(features, None, hold("person-or-mask-unavailable"), self.generation, "unavailable")
        if self.at is not None and frame.at <= self.at:
            return Decision(features, self.target, hold("non-monotonic-observation"), self.generation, "unavailable")
        self.at = frame.at
        key = (frame.orientation, frame.level, frame.geometry_id, frame.width, frame.height)
        changed = self.key != key or (self.baseline is not None and scene_change(self.baseline, features) > .28)
        if changed:
            self.target = self.baseline = None
            self.pending = None
            self.blocked = self.settled = False
        self.key = key
        if self.target is None:
            self.target = select(generate(frame, features, self.weights))
            self.selected_at, self.baseline = frame.at, features
            self.generation += 1
        self.last_features = features
        target = self.target
        if target is None:
            return Decision(features, None, hold("no-visible-feasible-candidate"), self.generation, "unavailable")
        if features.confidence < .12:
            self.pending = None
            return Decision(features, target, hold("weak-scene-evidence"), self.generation, "unavailable")
        # Entry/exit hysteresis prevents adjusting an acceptable composition.
        if acceptable(frame.person, target, 1.3 if self.settled else 1.):
            self.pending = None
            self.settled = True
            return Decision(features, target, hold("composition-acceptable", True), self.generation, "acceptable")
        self.settled = False
        progress = "new-observation"
        if self.pending is not None:
            action, issued_at, prior_error, prior_axis = self.pending
            elapsed = frame.at - issued_at
            if elapsed < self.cooldown:
                # Do not reissue an actionable sentence before observing the
                # result; the last instruction remains in the caller's history.
                return Decision(features, target, hold("awaiting-movement-observation"), self.generation, "waiting")
            gain = min(prior_error - error(frame.person, target),
                       prior_axis - _intended_error(frame.person, target, action))
            if gain < .15:
                self.blocked = True
                progress = "worsened" if gain < -.15 else "no-confirmed-progress"
            else:
                progress = "improved"
            self.pending = None
        if self.blocked:
            # No immediate opposite-way command or repeated unconfirmed action.
            # A significant scene/geometry change or explicit reset is required.
            return Decision(features, target, hold("movement-needs-reassessment"), self.generation, progress)
        if frame.at - self.selected_at >= self.target_hold and progress != "improved":
            alternative = select(generate(frame, features, self.weights))
            # Only replace a stable target after a meaningful score advantage;
            # small image noise alone cannot trigger target churn.
            current = [c for c in generate(frame, features, self.weights)
                       if abs(c.x - target.x) < .001 and abs(c.eye_y - target.eye_y) < .001
                       and abs(c.scale - target.scale) < .001 and c.framing == target.framing]
            current_score = current[0].score if current else target.score
            if alternative is not None and alternative.score > current_score + .8:
                self.target, self.selected_at = alternative, frame.at
                self.generation += 1
                target = alternative
        action = decide(frame, target, features, context)
        if action.valid and action.direction != "capture":
            self.pending = (action, frame.at, error(frame.person, target),
                            _intended_error(frame.person, target, action))
        return Decision(features, target, action, self.generation, progress)


def _intended_error(person, target, action):
    if action.direction in ("left", "right"):
        return abs(person.x - target.x) / .08
    if action.direction in ("up", "down"):
        return abs(person.eye_y - target.eye_y) / .08
    return abs(person.scale - target.scale) / max(.012, target.scale * .10)
