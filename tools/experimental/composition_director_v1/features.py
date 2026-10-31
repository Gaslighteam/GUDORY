"""Bounded central-gradient + Hough features; person pixels are unknown."""
from math import atan2, cos, degrees, hypot, pi, sin
from .types import Cell, Features, Line


def analyze(frame):
    frame.validate()
    w, h = frame.width, frame.height
    known = [False] * (w * h)
    edge = [0.] * (w * h)
    gradients = []
    # Dilate unknown mask by one pixel. Never create a person silhouette edge
    # by filling the mask with mean color; masked neighborhoods are excluded.
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            i = y * w + x
            if any(frame.mask[(y + dy) * w + x + dx] >= .35
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                continue
            known[i] = True
            gx = (frame.gray[i + 1] - frame.gray[i - 1]) / 2
            gy = (frame.gray[i + w] - frame.gray[i - w]) / 2
            strength = hypot(gx, gy)
            edge[i] = strength
            if strength >= 28:
                gradients.append((x, y, gx, gy))
    cells = []
    for row in range(3):
        for col in range(3):
            ids = [y * w + x for y in range(row * h // 3, (row + 1) * h // 3)
                   for x in range(col * w // 3, (col + 1) * w // 3)]
            usable = [i for i in ids if known[i]]
            n = len(usable)
            cells.append(Cell(n / len(ids),
                sum(edge[i] >= 28 for i in usable) / n if n else 0.,
                min(1., sum(edge[i] for i in usable) / n / 64) if n else 0.,
                sum(frame.gray[i] for i in usable) / n / 255 if n else 0.))
    mask_n = sum(v >= .5 for v in frame.mask)
    observed = sum(known) / len(known)
    valid = 0 < mask_n < len(known) and observed >= .35
    lines = _lines(gradients, w, h) if valid else ()
    # Weak and saturated texture both reduce confidence. Openness alone is
    # never treated as quality, and a flat wall needs no invented horizon.
    density = len(gradients) / max(1, sum(known))
    means = [c.mean for c in cells if c.coverage >= .4]
    contrast = max(means) - min(means) if len(means) >= 2 else 0.
    confidence = min(1., .75 * max((l.strength for l in lines), default=0.)
                     + .8 * contrast + min(.25, density)) if valid else 0.
    if density > .4:
        lines = ()
        confidence *= .25
    return Features(tuple(cells), lines, _vanishing(lines, w / h), confidence,
                    valid, "ok" if valid else "mask-or-background-unavailable")


def _lines(points, w, h):
    diagonal = hypot(w, h)
    if len(points) < 12:
        return ()
    peaks = []
    # Twelve normal orientations, 2px rho bins. Vote only where the gradient
    # agrees with the line normal; deterministic tie breaking throughout.
    for k in range(12):
        theta = k * pi / 12
        c, s = cos(theta), sin(theta)
        bins = {}
        for x, y, gx, gy in points:
            if abs(gx * c + gy * s) < .93 * hypot(gx, gy):
                continue
            rho = round((x * c + y * s) / 2)
            bins.setdefault(rho, []).append((x, y))
        for rho, support in bins.items():
            if len(support) < max(10, diagonal * .12):
                continue
            ts = sorted(-x * s + y * c for x, y in support)
            # Extract a contiguous run; do not join unrelated collinear edges.
            runs, run = [], [ts[0]]
            for t in ts[1:]:
                if t - run[-1] > 4:
                    runs.append(run)
                    run = []
                run.append(t)
            runs.append(run)
            best = max(runs, key=lambda r: r[-1] - r[0])
            span = best[-1] - best[0]
            occupancy = len({round(t) for t in best}) / max(1, span)
            if span < diagonal * .30 or occupancy < .45:
                continue
            r = sum(x * c + y * s for x, y in support) / len(support)
            x1, y1 = r * c - best[0] * s, r * s + best[0] * c
            x2, y2 = r * c - best[-1] * s, r * s + best[-1] * c
            strength = min(1., span / diagonal * 1.8) * min(1., occupancy)
            peaks.append(Line(x1 / (w - 1), y1 / (h - 1),
                              x2 / (w - 1), y2 / (h - 1), strength,
                              degrees(atan2(y2 - y1, x2 - x1)) % 180))
    chosen = []
    for line in sorted(peaks, key=lambda l: (-l.strength, l.angle_deg, l.x1, l.y1)):
        # Merge the two sides of a thick edge and near-identical Hough peaks.
        if any(min(abs(line.angle_deg - p.angle_deg),
                   180 - abs(line.angle_deg - p.angle_deg)) < 17
               and hypot((line.x1 + line.x2 - p.x1 - p.x2) / 2,
                         (line.y1 + line.y2 - p.y1 - p.y2) / 2) < .08
               for p in chosen):
            continue
        chosen.append(line)
        if len(chosen) == 6:
            break
    return tuple(chosen)


def _intersection(a, b):
    ux, uy = a.x2 - a.x1, a.y2 - a.y1
    vx, vy = b.x2 - b.x1, b.y2 - b.y1
    det = ux * vy - uy * vx
    if abs(det) < .04:
        return None
    t = ((b.x1 - a.x1) * vy - (b.y1 - a.y1) * vx) / det
    return a.x1 + t * ux, a.y1 + t * uy


def _vanishing(lines, aspect):
    # At least three nonparallel supported lines must agree on a point inside
    # the observed image; two crossing diagonals alone are insufficient.
    for i, a in enumerate(lines):
        for b in lines[i + 1:]:
            p = _intersection(a, b)
            if p is None or not all(.05 < v < .95 for v in p):
                continue
            supporters = []
            for l in lines:
                dx, dy = (l.x2 - l.x1) * aspect, l.y2 - l.y1
                d = abs(dx * (p[1] - l.y1) - dy * (p[0] - l.x1) * aspect)
                if d / max(1e-6, hypot(dx, dy)) < .035 and l.strength > .4:
                    supporters.append(l)
            if len(supporters) >= 3:
                return p
    return None


def scene_change(a, b):
    """Coverage-aware descriptor; no image or personal identifiers retained."""
    usable = [(x, y) for x, y in zip(a.cells, b.cells)
              if min(x.coverage, y.coverage) >= .4]
    if not usable:
        return 1.
    return sum(abs(x.edges - y.edges) + .5 * abs(x.texture - y.texture)
               + abs(x.mean - y.mean) for x, y in usable) / len(usable)
