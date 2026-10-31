"""Adapter for synchronized RGB/mask/pose already in visible saved-shot space."""
from .types import Frame, person_from_landmarks


def from_visible_rgb(image, mask, landmarks, *, at, orientation, level=3,
                     geometry_id, max_side=96):
    from PIL import Image  # existing tools dependency; no model creation
    import math
    if not 24 <= max_side <= 128:
        raise ValueError("max_side must be 24..128")
    if len(mask) != image.height or any(len(row) != image.width for row in mask):
        raise ValueError("mask and RGB must have identical visible geometry")
    if any(not math.isfinite(v) or not 0 <= v <= 1 for row in mask for v in row):
        raise ValueError("invalid mask confidence")
    scale = min(1., max_side / max(image.size))
    w, h = max(12, round(image.width * scale)), max(12, round(image.height * scale))
    rgb = image.convert("L").resize((w, h), Image.Resampling.BOX)
    # Max-pool the person mask so thin foreground cannot become background.
    pooled = tuple(max(mask[sy][sx]
                       for sy in range(y * image.height // h, max(y * image.height // h + 1, (y + 1) * image.height // h))
                       for sx in range(x * image.width // w, max(x * image.width // w + 1, (x + 1) * image.width // w)))
                   for y in range(h) for x in range(w))
    frame = Frame(w, h, tuple(rgb.tobytes()), pooled, person_from_landmarks(landmarks),
                  at, orientation, level, geometry_id)
    frame.validate()
    return frame
