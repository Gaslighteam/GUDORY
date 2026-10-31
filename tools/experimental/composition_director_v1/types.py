"""Internal contracts. All geometry is normalized visible saved-shot space."""
from dataclasses import dataclass, field
from math import isfinite

SPANS = {"chestUp": .28, "waistUp": .80, "kneeUp": 1.15, "fullBody": 1.55}
ANCHORS = {"chestUp": (11, 12), "waistUp": (23, 24),
           "kneeUp": (25, 26), "fullBody": (27, 28)}


@dataclass(frozen=True)
class Person:
    x: float
    eye_y: float
    head_y: float
    scale: float  # head to shoulders / frame height, NOT whole-body height
    width: float
    framing: str = "fullBody"
    confidence: float = 1.

    def span(self, framing):
        return self.scale * SPANS[framing] / SPANS["chestUp"]

    @property
    def valid(self):
        return (all(isfinite(v) for v in (self.x, self.eye_y, self.head_y,
                self.scale, self.width, self.confidence))
                and 0 < self.scale < .6 and 0 < self.width < 1
                and 0 <= self.x <= 1 and 0 <= self.head_y < self.eye_y <= 1
                and self.framing in SPANS and .5 <= self.confidence <= 1)


def person_from_landmarks(points):
    """Already cropped/rotated ML Kit order. No second crop or mirroring.

    Match AGENTS head/eye formula, including low-visibility nose/eyes. Both
    shoulders must be visible. Return None on missing/nonfinite evidence.
    """
    if points is None or len(points) != 33:
        return None

    def finite(i):
        p = points[i]
        return p is not None and len(p) == 3 and all(isfinite(v) for v in p)

    def visible(i):
        return (finite(i) and points[i][2] >= .5
                and all(0 <= v <= 1 for v in points[i][:2]))

    if not all(visible(i) for i in (11, 12)) or not all(finite(i) for i in (0, 2, 5)):
        return None
    sy = (points[11][1] + points[12][1]) / 2
    head = points[0][1] - .5 * (sy - points[0][1])
    framing = next(f for f in reversed(SPANS) if all(visible(i) for i in ANCHORS[f]))
    person = Person((points[11][0] + points[12][0]) / 2,
                    (points[2][1] + points[5][1]) / 2, head, sy - head,
                    max(.04, abs(points[11][0] - points[12][0]) * 1.4), framing)
    return person if person.valid else None


@dataclass(frozen=True)
class Frame:
    width: int
    height: int
    gray: tuple  # luminance [0,255], row-major; bounded analysis image
    mask: tuple  # SAME frame/geometry; person confidence [0,1]
    person: Person | None
    at: float  # monotonic seconds
    orientation: str = "portrait"
    level: int = 3
    geometry_id: str = "synthetic-fixed-view"  # lens/zoom/crop/direction epoch

    def validate(self):
        if (not 12 <= self.width <= 128 or not 12 <= self.height <= 128
                or len(self.gray) != self.width * self.height
                or len(self.mask) != len(self.gray)
                or not all(isfinite(v) and 0 <= v <= 255 for v in self.gray)
                or not all(isfinite(v) and 0 <= v <= 1 for v in self.mask)
                or not isfinite(self.at) or self.level not in range(1, 6)
                or self.orientation not in ("portrait", "landscape")
                or (self.orientation == "portrait") != (self.height > self.width)):
            raise ValueError("invalid-visible-frame")


@dataclass(frozen=True)
class Cell:
    coverage: float  # fraction OBSERVED, not a masked/empty-region score
    edges: float
    texture: float
    mean: float


@dataclass(frozen=True)
class Line:
    x1: float
    y1: float
    x2: float
    y2: float
    strength: float
    angle_deg: float  # measured in pixel geometry, not stretched square space


@dataclass(frozen=True)
class Features:
    cells: tuple[Cell, ...]
    lines: tuple[Line, ...]
    vanishing_point: tuple | None
    confidence: float
    valid: bool
    reason: str


@dataclass(frozen=True)
class Candidate:
    x: float
    eye_y: float
    scale: float
    framing: str
    head_y: float
    width: float
    score: float
    terms: dict = field(default_factory=dict)


@dataclass(frozen=True)
class Motion:
    """Measured local response per step/fist in photographer-relative axes.

    Never derive these from a single photograph. Caller supplies a recent
    calibration in this exact geometry epoch. dx/dy/dscale describe +direction:
    right, forward, up. Negative magnitude means left, backward, down.
    """
    actor: str  # photographer | subject
    axis: str  # horizontal | distance | height
    dx: float
    dy: float
    dscale: float
    confidence: float
    at: float
    geometry_id: str
    structure_preservation: float = 0.


@dataclass(frozen=True)
class Context:
    motions: tuple[Motion, ...] = ()
    safe_directions: frozenset = frozenset()  # (actor, direction), explicitly checked
    safety_at: float = -1.
    geometry_id: str = ""  # safety evidence belongs to this geometry epoch


@dataclass(frozen=True)
class Action:
    actor: str
    direction: str
    magnitude: float
    unit: str
    text: str
    confidence: float
    valid: bool
    reason: str


@dataclass(frozen=True)
class Decision:
    features: Features
    target: Candidate | None
    action: Action
    target_generation: int
    progress: str
