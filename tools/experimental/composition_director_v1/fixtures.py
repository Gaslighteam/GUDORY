"""Original procedural fixtures: no private or third-party images."""
from .types import Context, Frame, Motion, Person


def scene(kind="diagonal", at=0., x=.50, orientation="portrait", level=3):
    w, h = (72, 96) if orientation == "portrait" else (96, 72)
    gray = [120.] * (w * h)

    def segment(a, b, color=235):
        for i in range(max(w, h) * 3):
            t = i / (max(w, h) * 3 - 1)
            px, py = round((a[0] + (b[0] - a[0]) * t) * (w - 1)), round((a[1] + (b[1] - a[1]) * t) * (h - 1))
            for dy in (0, 1):
                for dx in (0, 1):
                    if 0 <= px + dx < w and 0 <= py + dy < h:
                        gray[(py + dy) * w + px + dx] = color

    if kind == "diagonal":
        for a, b in [((.03, .95), (.7, .03)), ((.97, .95), (.3, .03)),
                     ((.08, .9), (.9, .12))]:
            segment(a, b)
        segment((.62, .03), (.62, .97))  # observed pole near the head
    elif kind == "asymmetric":
        for y in range(h):
            for px in range(w):
                if px < w * .34:
                    gray[y * w + px] = 60 + ((px // 4 + y // 7) % 2) * 140
        segment((.34, .02), (.34, .97))
    elif kind == "symmetric":
        for px in (.12, .88):
            segment((px, .03), (px, .97))
        segment((.03, .85), (.97, .85))
    elif kind != "weak":
        raise ValueError("unknown synthetic scene")
    person = Person(x, .20, .15, .10, .15)
    mask = tuple(float(abs((px + .5) / w - x) < person.width / 2
                       and person.head_y <= (y + .5) / h <= person.head_y + person.span(person.framing))
                 for y in range(h) for px in range(w))
    for i, foreground in enumerate(mask):
        if foreground:
            gray[i] = 180.
    return Frame(w, h, tuple(gray), mask, person, at, orientation, level)


def simulated_context(frame, actor="subject", axis="horizontal", response=.20):
    # SIMULATED, explicitly safe floor. Never use this for a real camera.
    vector = {"horizontal": (response, 0., 0.), "height": (0., response, 0.),
              "distance": (0., 0., response)}[axis]
    directions = {"horizontal": ("left", "right"), "height": ("up", "down"),
                  "distance": ("forward", "backward")}[axis]
    motion = Motion(actor, axis, *vector, .9, frame.at, frame.geometry_id, .95)
    return Context((motion,), frozenset((actor, d) for d in directions), frame.at, frame.geometry_id)

