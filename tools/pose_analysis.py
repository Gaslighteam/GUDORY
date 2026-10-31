"""Four-framing photo analysis, per AGENTS.md §4 and team-lead decisions.

All landmarks are normalized image coordinates AFTER EXIF correction: x right,
y down. No portrait rotation, front-camera mirroring, or world coordinates.
Per-photo results stay in memory; the CLI prints aggregate counts only.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, replace
import math
from pathlib import Path
from typing import Callable, Sequence

# MediaPipe Pose landmark order (not left/right eye inner/outer indices).
NOSE, LEFT_EYE, RIGHT_EYE = 0, 2, 5
SHOULDERS, HIPS, KNEES, ANKLES = (11, 12), (23, 24), (25, 26), (27, 28)
ANCHORS = (("chestUp", SHOULDERS), ("waistUp", HIPS),
           ("kneeUp", KNEES), ("fullBody", ANKLES))
VISIBILITY = 0.5
PERSON_CANDIDATE_SCORE = 0.2
PERSON_ACCEPT_SCORE = 0.5


@dataclass(frozen=True)
class Landmark:
    x: float
    y: float
    visibility: float


@dataclass(frozen=True)
class Composition:
    f: str
    h: float
    s: float
    cx: float
    cy: float
    hy: None = None


@dataclass(frozen=True)
class PersonBox:
    """One person detection; box normalized to the corrected image."""
    score: float
    left: float
    top: float
    right: float
    bottom: float


@dataclass(frozen=True)
class Analysis:
    reason: str
    composition: Composition | None = None
    orientation: str | None = None
    width: int = 0
    height: int = 0
    source_orientation: str | None = None
    crop: str = "none"

    @property
    def accepted(self) -> bool:
        return self.composition is not None


class InvalidPose(ValueError):
    pass


def _clamp(value: float) -> float:
    return min(1.0, max(0.0, value))


def _point(points: Sequence[Landmark | None], index: int) -> tuple[float, float] | None:
    if index >= len(points) or (point := points[index]) is None:
        return None
    if not all(math.isfinite(v) for v in (point.x, point.y, point.visibility)):
        return None
    if point.visibility < VISIBILITY:
        return None
    return _clamp(point.x), _clamp(point.y)


def measure_pose(points: Sequence[Landmark | None]) -> Composition:
    """Pure coordinate math; does NOT establish person count.

    Validate finite coordinates/visibility before clamping each landmark x/y.
    Midpoints use those clamped coordinates. Head top is the exact derived
    formula, without a second clamp; reject final spans outside (0, 1] rather
    than silently changing their values. Both members are required for anchors.
    """
    nose = _point(points, NOSE)
    shoulders = [_point(points, i) for i in SHOULDERS]
    if nose is None or any(p is None for p in shoulders):
        raise InvalidPose("missing_required_landmarks")
    sx = (shoulders[0][0] + shoulders[1][0]) / 2
    sy = (shoulders[0][1] + shoulders[1][1]) / 2
    head_top = nose[1] - (sy - nose[1]) / 2
    framing, anchor_y = "chestUp", sy
    for name, pair in ANCHORS[1:]:
        left, right = (_point(points, i) for i in pair)
        if left is not None and right is not None:
            framing, anchor_y = name, (left[1] + right[1]) / 2
    eyes = [_point(points, i) for i in (LEFT_EYE, RIGHT_EYE)]
    eye_ys = [p[1] for p in eyes if p is not None]
    cy = sum(eye_ys) / len(eye_ys) if eye_ys else nose[1]
    h, scale = anchor_y - head_top, sy - head_top
    if (not all(math.isfinite(v) for v in (h, scale, sx, cy))
            or not 0 < scale <= h <= 1 or not 0 <= sx <= 1 or not 0 <= cy <= 1):
        raise InvalidPose("invalid_measurements")
    return Composition(framing, h, scale, sx, cy)


def analyze_detections(
    poses: Sequence[Sequence[Landmark | None]],
    people: Sequence[PersonBox] | None,
    width: int,
    height: int,
) -> Analysis:
    """Fail closed on absent/ambiguous person evidence, even for one pose.

    Detector contract: return ALL post-NMS person boxes scoring >= 0.2,
    without a top-1 cap; None means unavailable. Scores 0.2..<0.5 are
    ambiguous, including any additional box. No duplicate-box merging here.
    """
    if width <= 0 or height <= 0:
        return Analysis("invalid_image")
    orientation = "portrait" if height > width else "landscape"

    def result(reason, composition=None):
        return Analysis(reason, composition, orientation, width, height)

    if people is None:
        return result("person_count_unavailable")
    candidates = []
    for box in people:
        if (not all(math.isfinite(v) for v in (
                box.score, box.left, box.top, box.right, box.bottom))
                or not 0 <= box.score <= 1
                or not _clamp(box.left) < _clamp(box.right)
                or not _clamp(box.top) < _clamp(box.bottom)):
            return result("invalid_person_evidence")
        if box.score >= PERSON_CANDIDATE_SCORE:
            candidates.append(box)
    if len(candidates) != 1 or candidates[0].score < PERSON_ACCEPT_SCORE:
        return result("ambiguous_person_count")
    # Count all returned poses BEFORE landmark filtering: an invalid second pose
    # is still evidence of another person, not something to discard first.
    if len(poses) != 1:
        return result("pose_count_mismatch")
    try:
        composition = measure_pose(poses[0])
    except InvalidPose as error:
        return result(str(error))
    box = candidates[0]
    for i in (NOSE, *SHOULDERS):
        x, y = _point(poses[0], i)
        if not (_clamp(box.left) <= x <= _clamp(box.right)
                and _clamp(box.top) <= y <= _clamp(box.bottom)):
            return result("person_pose_mismatch")
    return result("accepted", composition)


def load_photo(path: Path):
    """Decode fully, apply all EXIF rotations/reflections, and detach RGB data."""
    from PIL import Image, ImageOps
    with Image.open(path) as raw:
        image = ImageOps.exif_transpose(raw).convert("RGB")
        image.load()
    return image


def source_orientation(width: int, height: int) -> str:
    if 9 * height <= 10 * width <= 11 * height:
        return "near_square"
    return "portrait" if height > width else "landscape"


def center_crop_rect(width: int, height: int, portrait: bool):
    """Integer, exact 3:4/4:3 crop centred on the IMAGE, never the person.

    Floor the largest scale fitting the image; place the extra odd pixel on the
    right/bottom. The centre differs by at most half a pixel on either axis.
    """
    a, b = (3, 4) if portrait else (4, 3)
    scale = min(width // a, height // b)
    if scale < 1:
        raise ValueError("Image too small for aspect crop")
    cw, ch = a * scale, b * scale
    left, top = (width - cw) // 2, (height - ch) // 2
    return left, top, left + cw, top + ch


def analyze_photo_detections(poses, people, width: int, height: int) -> Analysis:
    """Check people in the ORIGINAL frame before trying in-memory square crops.

    Reproject normalized landmarks into the crop; landmarks cut off by the crop
    become unavailable, so framing is recomputed from the retained anchors.
    Both detectors run on the full image: cropping cannot hide a second person.
    """
    original = analyze_detections(poses, people, width, height)
    source = source_orientation(width, height)
    if not original.accepted or source != "near_square":
        return replace(original, source_orientation=source)
    for portrait in (True, False):
        left, top, right, bottom = center_crop_rect(width, height, portrait)
        cw, ch = right - left, bottom - top
        required = [_point(poses[0], i) for i in (NOSE, *SHOULDERS)]
        if not all(left <= x * width <= right and top <= y * height <= bottom
                   for x, y in required):
            continue
        cropped_points = []
        for index in range(len(poses[0])):
            point = _point(poses[0], index)
            if point is None:
                cropped_points.append(None)
                continue
            x, y = point[0] * width, point[1] * height
            if not (left <= x <= right and top <= y <= bottom):
                cropped_points.append(None)
            else:
                cropped_points.append(Landmark(
                    (x - left) / cw, (y - top) / ch, poses[0][index].visibility))
        cropped_boxes = [PersonBox(
            box.score, (_clamp(box.left) * width - left) / cw,
            (_clamp(box.top) * height - top) / ch,
            (_clamp(box.right) * width - left) / cw,
            (_clamp(box.bottom) * height - top) / ch) for box in people]
        result = analyze_detections([cropped_points], cropped_boxes, cw, ch)
        return replace(result, source_orientation=source,
                       crop="portrait_3_4" if portrait else "landscape_4_3")
    return replace(original, reason="square_crop_cuts_person", composition=None,
                   source_orientation=source, crop="rejected")


class PhotoPoseAnalyzer:
    """Injectable detector boundary; both callbacks see the same corrected RGB."""

    def __init__(self, pose_detector: Callable, person_detector: Callable):
        self.pose_detector = pose_detector
        self.person_detector = person_detector

    def analyze(self, path: Path) -> Analysis:
        from PIL import Image
        try:
            image = load_photo(path)
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombError):
            return Analysis("invalid_image")
        try:
            poses = self.pose_detector(image)
            people = self.person_detector(image)
            return analyze_photo_detections(poses, people, image.width, image.height)
        except Exception:
            # Native/model failures and malformed detector results reject the
            # candidate. Do not write exception messages/paths as public data.
            return Analysis("detector_error", orientation=(
                "portrait" if image.height > image.width else "landscape"),
                width=image.width, height=image.height,
                source_orientation=source_orientation(image.width, image.height))
        finally:
            image.close()


class MediaPipePhotoAnalyzer(PhotoPoseAnalyzer):
    """PoseLandmarker(num_poses=2) + independent person ObjectDetector.

    Requires local Tasks-compatible pose and object-detection models. Object
    model metadata must label the human category exactly 'person' (e.g.
    EfficientDet Lite0). No model or photo downloads occur here.
    """

    def __init__(self, pose_model: Path, person_model: Path):
        for path in (pose_model, person_model):
            if not path.is_file():
                raise FileNotFoundError("Required local MediaPipe model is missing")
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions
        from mediapipe.tasks.python import vision
        self.mp = mp
        self.pose = vision.PoseLandmarker.create_from_options(
            vision.PoseLandmarkerOptions(
                base_options=BaseOptions(model_asset_path=str(pose_model)),
                running_mode=vision.RunningMode.IMAGE, num_poses=2))
        try:
            self.person = vision.ObjectDetector.create_from_options(
                vision.ObjectDetectorOptions(
                    base_options=BaseOptions(model_asset_path=str(person_model)),
                    running_mode=vision.RunningMode.IMAGE,
                    category_allowlist=["person"], max_results=-1,
                    score_threshold=PERSON_CANDIDATE_SCORE))
        except Exception:
            self.pose.close()
            raise
        super().__init__(self._poses, self._people)

    def _image(self, image):
        import numpy as np
        return self.mp.Image(image_format=self.mp.ImageFormat.SRGB,
                             data=np.ascontiguousarray(image, dtype=np.uint8))

    def _poses(self, image):
        result = self.pose.detect(self._image(image))
        return [[Landmark(p.x, p.y, p.visibility) for p in pose]
                for pose in result.pose_landmarks]

    def _people(self, image):
        result = self.person.detect(self._image(image))
        boxes = []
        for detection in result.detections:
            categories = [c for c in detection.categories if c.category_name == "person"]
            if not categories:
                raise ValueError("Unexpected detector category")
            box = detection.bounding_box
            boxes.append(PersonBox(
                max(c.score for c in categories),
                box.origin_x / image.width, box.origin_y / image.height,
                (box.origin_x + box.width) / image.width,
                (box.origin_y + box.height) / image.height))
        return boxes

    def close(self):
        try:
            self.pose.close()
        finally:
            self.person.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--photos", type=Path, required=True)
    parser.add_argument("--pose-model", type=Path, required=True)
    parser.add_argument("--person-model", type=Path, required=True)
    args = parser.parse_args(argv)
    if not args.photos.is_dir():
        parser.error("Photo directory is missing")
    analyzer = MediaPipePhotoAnalyzer(args.pose_model, args.person_model)
    counts = Counter()
    try:
        for path in sorted(args.photos.rglob("*")):
            if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}:
                result = analyzer.analyze(path)
                counts["total"] += 1
                counts[f"source/{result.source_orientation or 'undecodable'}"] += 1
                counts[f"crop/{result.crop}"] += 1
                counts["accepted_total" if result.accepted else "rejected_total"] += 1
                key = (f"accepted/{result.orientation}/{result.composition.f}"
                       if result.accepted else f"rejected/{result.reason}")
                counts[key] += 1
    finally:
        analyzer.close()
    for key, count in sorted(counts.items()):
        print(f"{key}: {count}")


if __name__ == "__main__":
    main()
