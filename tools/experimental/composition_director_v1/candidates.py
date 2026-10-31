"""Explainable observable placements, not an aesthetic preference predictor."""
from dataclasses import dataclass
from math import hypot
from .types import Candidate, SPANS


@dataclass(frozen=True)
class Weights:
    overlap: float = 4.
    space: float = 1.4
    structure: float = .8
    balance: float = .45
    emphasis: float = 3.
    feasibility: float = 1.2
    unknown: float = 2.


def _inside(line, box):
    # Segment sampling tests the head/torso box, not an infinite line.
    left, top, right, bottom = box
    return sum(left <= line.x1 + (line.x2 - line.x1) * t / 24 <= right
               and top <= line.y1 + (line.y2 - line.y1) * t / 24 <= bottom
               for t in range(25)) / 25


def generate(frame, features, weights=Weights()):
    p = frame.person
    if p is None or not p.valid or not features.valid:
        return ()
    # Continuous local alternatives + grid-region centers + exact current
    # location. No universal centering/thirds bonus. Stay in observed geometry.
    xs = sorted({p.x, max(.12, p.x - .16), min(.88, p.x + .16), .22, .5, .78})
    ys = sorted({p.eye_y, max(.12, p.eye_y - .07), min(.68, p.eye_y + .07)})
    desired_scale = (.22, .16, .10, .075, .05)[frame.level - 1]
    scales = sorted({p.scale, p.scale * .8, p.scale * 1.2})
    framings = (p.framing,)
    # Candidate framing changes only when the needed anchor is already visible.
    if p.framing != "chestUp":
        framings = tuple(f for f in SPANS if SPANS[f] <= SPANS[p.framing])
    result = []
    for x in xs:
        for y in ys:
            for scale in scales:
                for framing in framings:
                    factor = scale / p.scale
                    head = y - (p.eye_y - p.head_y) * factor
                    width = p.width * factor
                    bottom = head + scale * SPANS[framing] / .28
                    fitting = [f for f in framings if head + scale * SPANS[f] / .28 <= .97]
                    if not fitting or framing != fitting[-1]:
                        continue
                    if head < .035 or bottom > .97 or x - width / 2 < .035 or x + width / 2 > .965:
                        continue
                    row, col = min(2, int(y * 3)), min(2, int(x * 3))
                    cell = features.cells[row * 3 + col]
                    box = (x - width / 2 - .045, max(0., head - .04), x + width / 2 + .045, min(bottom, head + scale * 2.))
                    overlap = sum(l.strength * min(1., _inside(l, box) * 5)
                                  for l in features.lines)
                    neighborhood = [features.cells[r * 3 + c]
                                    for r in range(max(0, row - 1), min(3, row + 2))
                                    for c in range(max(0, col - 1), min(3, col + 2))]
                    observed = [c for c in neighborhood if c.coverage >= .5]
                    # Moderate space/clutter relationship; zero texture has no
                    # unconditional quality bonus. Unknown mask != empty space.
                    complexity = sum(c.texture for c in observed) / max(1, len(observed))
                    space = (max(0., cell.texture - complexity) + max(0., cell.edges - .25) * .4) if cell.coverage >= .5 else .4
                    structure = sum(l.strength * _inside(l, (x - width / 2, head,
                                    x + width / 2, bottom)) for l in features.lines)
                    mass = sum(c.texture * c.coverage for c in features.cells)
                    mass_x = (sum(((i % 3 + .5) / 3) * c.texture * c.coverage
                                  for i, c in enumerate(features.cells)) / mass) if mass > .05 else .5
                    # Balance the COMBINED masses, not person placement alone;
                    # disable this heuristic for approximately structureless scenes.
                    balance = abs((x + mass_x) / 2 - .5) if mass > .15 else 0.
                    effort = abs(x - p.x) + abs(y - p.eye_y) + abs(scale / p.scale - 1.)
                    emphasis = abs(scale - desired_scale) / max(.05, desired_scale)
                    # Prefer retaining the currently visible body span unless
                    # the selected emphasis makes a tighter framing useful.
                    framing_cost = abs((SPANS[framing] / 1.55) - (frame.level / 5)) * .25
                    terms = dict(overlap=overlap, space=space, structure=structure,
                                 balance=balance, emphasis=emphasis + framing_cost,
                                 feasibility=effort, unknown=max(0., .5 - cell.coverage))
                    score = -sum(getattr(weights, name) * value for name, value in terms.items())
                    result.append(Candidate(x, y, scale, framing, head, width, score, terms))
    return tuple(result)


def select(candidates):
    # Pick ONE alternative. Stable generation order breaks exact score ties.
    return max(candidates, key=lambda c: c.score, default=None)


def error(person, target):
    return hypot((person.x - target.x) / .08, (person.eye_y - target.eye_y) / .08) + abs(person.scale - target.scale) / max(.012, target.scale * .10)


