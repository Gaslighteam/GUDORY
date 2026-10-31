"""Synthetic fixtures only: no photos, model downloads, or per-photo output."""
import math
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace as NS
from unittest.mock import patch, Mock

from PIL import Image

from pose_analysis import (
    ANCHORS, Analysis, InvalidPose, Landmark, MediaPipePhotoAnalyzer,
    PersonBox, PhotoPoseAnalyzer, analyze_detections, load_photo, measure_pose,
    analyze_photo_detections, center_crop_rect, source_orientation,
)


def fixture(framing="fullBody"):
    points = [None] * 33
    points[0] = Landmark(0.5, 0.2, 0.5)
    points[2], points[5] = Landmark(0.4, 0.16, 1), Landmark(0.6, 0.18, 1)
    for (name, (left, right)), y in zip(ANCHORS, (0.4, 0.6, 0.75, 0.9)):
        points[left], points[right] = Landmark(0.3, y - 0.02, 0.5), Landmark(0.7, y + 0.02, 0.5)
        if name == framing:
            break
    return points


BOX = PersonBox(0.9, 0, 0, 1, 1)


class MeasurementTests(unittest.TestCase):
    def test_four_framings_and_exact_measurements(self):
        for framing, expected in zip(
                ("chestUp", "waistUp", "kneeUp", "fullBody"), (0.3, 0.5, 0.65, 0.8)):
            with self.subTest(framing=framing):
                result = measure_pose(fixture(framing))
                self.assertEqual(result.f, framing)
                self.assertAlmostEqual(result.h, expected)
                self.assertAlmostEqual(result.s, 0.3)
                self.assertAlmostEqual(result.cx, 0.5)
                self.assertAlmostEqual(result.cy, 0.17)
                self.assertIsNone(result.hy)

    def test_one_eye_or_nose_fallback(self):
        for left, right, expected in ((True, False, .16), (False, True, .18), (False, False, .2)):
            with self.subTest(left=left, right=right):
                points = fixture()
                if not left:
                    points[2] = None
                if not right:
                    points[5] = Landmark(.6, math.nan, 1)
                self.assertAlmostEqual(measure_pose(points).cy, expected)

    def test_back_view_head_estimates_ignore_visibility(self):
        points = fixture()
        points[0] = Landmark(.5, .2, 0)
        points[2], points[5] = Landmark(.4, .16, 0), Landmark(.6, .18, .01)
        result = measure_pose(points)
        self.assertAlmostEqual(result.s, .3)
        self.assertAlmostEqual(result.cy, .17)

    def test_head_or_face_outside_frame_rejects(self):
        for nose, reason in ((Landmark(.5, .1, 1), "head_cut"),  # head top .1 - .15 < 0
                             (Landmark(-.1, .3, 1), "face_out_of_frame"),
                             (Landmark(.5, -.01, 0), "face_out_of_frame")):
            with self.subTest(nose=nose):
                points = fixture()
                points[0] = nose
                with self.assertRaisesRegex(InvalidPose, reason):
                    measure_pose(points)

    def test_invalid_optional_landmarks_are_ignored(self):
        for index in (2, 5, 23, 24, 25, 26, 27, 28):
            for attr in ("x", "y", "visibility"):
                for value in (math.nan, math.inf, -math.inf):
                    with self.subTest(index=index, attr=attr, value=value):
                        points = fixture()
                        data = dict(x=.5, y=.7, visibility=1)
                        data[attr] = value
                        points[index] = Landmark(**data)
                        self.assertTrue(math.isfinite(measure_pose(points).h))

    def test_required_landmarks_missing_low_or_nonfinite_reject(self):
        for index in (0, 11, 12):
            for point in (None, Landmark(.5, .3, .499), Landmark(math.nan, .3, 1),
                          Landmark(.5, math.inf, 1), Landmark(.5, .3, math.nan)):
                if index == 0 and point is not None and math.isfinite(point.x) and math.isfinite(point.y):
                    continue  # the nose only needs finite coordinates
                with self.subTest(index=index, point=point):
                    points = fixture()
                    points[index] = point
                    with self.assertRaisesRegex(InvalidPose, "missing_required"):
                        measure_pose(points)
        with self.assertRaises(InvalidPose):
            measure_pose([])

    def test_pair_requires_both_but_no_contiguous_anchor_requirement(self):
        for index in (27, 28):
            points = fixture()
            points[index] = Landmark(.5, .9, .499)
            self.assertEqual(measure_pose(points).f, "kneeUp")
        points = fixture()
        for index in (23, 24, 25, 26):
            points[index] = None
        self.assertEqual(measure_pose(points).f, "fullBody")

    def test_clamp_before_midpoints_and_eye_mean(self):
        points = fixture("chestUp")
        points[11], points[12] = Landmark(-2, .4, 1), Landmark(.6, .4, 1)
        points[2], points[5] = Landmark(.4, -3, 1), Landmark(.6, .2, 1)
        result = measure_pose(points)
        self.assertAlmostEqual(result.cx, .3)  # clamp each, then average
        self.assertAlmostEqual(result.cy, .1)
        points[2], points[5] = Landmark(.4, 2, 1), None
        self.assertEqual(measure_pose(points).cy, 1)

    def test_head_near_top_edge_is_kept_exactly(self):
        points = fixture("chestUp")
        points[0] = Landmark(.5, .14, 1)
        # noseY=.14, shoulderMidY=.4, headTop=.01: exact s=h=.39
        result = measure_pose(points)
        self.assertAlmostEqual(result.h, .39)
        self.assertAlmostEqual(result.s, .39)

    def test_reject_invalid_final_spans(self):
        for nose_y, shoulder_y, ankle_y in ((.6, .4, .9), (.4, .4, .9), (.2, .4, .15)):
            with self.subTest(nose=nose_y, shoulder=shoulder_y, ankle=ankle_y):
                points = fixture()
                points[0] = Landmark(.5, nose_y, 1)
                points[11] = points[12] = Landmark(.5, shoulder_y, 1)
                points[27] = points[28] = Landmark(.5, ankle_y, 1)
                with self.assertRaisesRegex(InvalidPose, "invalid_measurements"):
                    measure_pose(points)


class CountTests(unittest.TestCase):
    def test_accept_requires_independent_evidence_and_one_pose(self):
        self.assertTrue(analyze_detections([fixture()], [BOX], 400, 600).accepted)
        for evidence in (None, [], [PersonBox(.299, 0, 0, 1, 1)], [BOX, BOX],
                         [BOX, PersonBox(.2, 0, 0, .2, .15)]):
            with self.subTest(evidence=evidence):
                self.assertFalse(analyze_detections([fixture()], evidence, 400, 600).accepted)
        self.assertTrue(analyze_detections([fixture()], [PersonBox(.3, 0, 0, 1, 1)], 400, 600).accepted)

    def test_small_bystanders_do_not_count_as_a_second_subject(self):
        bystander = PersonBox(.9, 0, 0, .1, .149)  # under 15% of the main height
        result = analyze_detections([fixture()], [BOX, bystander], 400, 600)
        self.assertTrue(result.accepted)
        self.assertEqual(result.person, BOX)  # main = highest score

    def test_person_too_small_and_hand_dominant(self):
        small = PersonBox(.9, .2, .15, .8, .34)  # 19% of the frame height
        points = [None if p is None else Landmark(p.x, .15 + p.y * .1, p.visibility) for p in fixture("chestUp")]
        self.assertEqual(analyze_detections([points], [small], 400, 600).reason, "person_too_small")
        points = fixture()
        points[15], points[19] = Landmark(.3, .3, 1), Landmark(.3, .95, 1)  # 390 px hand, 180 px head
        self.assertEqual(analyze_detections([points], [BOX], 400, 600).reason, "hand_dominant")
        points[19] = Landmark(.3, .35, 1)
        self.assertTrue(analyze_detections([points], [BOX], 400, 600).accepted)

    def test_zero_or_second_pose_reject_even_if_second_is_invalid(self):
        for poses in ([], [fixture(), []], [fixture(), fixture()]):
            self.assertEqual(analyze_detections(poses, [BOX], 400, 600).reason, "pose_count_mismatch")

    def test_invalid_person_evidence_and_pose_box_disagreement(self):
        for box in (PersonBox(math.nan, 0, 0, 1, 1), PersonBox(2, 0, 0, 1, 1),
                    PersonBox(.9, .8, 0, .2, 1), PersonBox(.9, 0, 0, math.inf, 1)):
            self.assertEqual(analyze_detections([fixture()], [box], 400, 600).reason, "invalid_person_evidence")
        self.assertEqual(analyze_detections([fixture()], [PersonBox(.9, 0, .5, 1, 1)], 400, 600).reason,
                         "person_pose_mismatch")


class SquareCropTests(unittest.TestCase):
    def test_near_square_inclusive_boundaries(self):
        for width in (90, 100, 110):
            self.assertEqual(source_orientation(width, 100), "near_square")
        self.assertEqual(source_orientation(89, 100), "portrait")
        self.assertEqual(source_orientation(111, 100), "landscape")

    def test_centered_exact_aspects_and_odd_dimensions(self):
        for portrait, a, b in ((True, 3, 4), (False, 4, 3)):
            left, top, right, bottom = center_crop_rect(101, 103, portrait)
            self.assertEqual((right-left)*b, (bottom-top)*a)
            self.assertLessEqual(abs((left+right)/2 - 101/2), .5)
            self.assertLessEqual(abs((top+bottom)/2 - 103/2), .5)

    def test_portrait_first_and_reproject_x(self):
        result = analyze_photo_detections([fixture()], [BOX], 400, 400)
        self.assertTrue(result.accepted)
        self.assertEqual((result.width, result.height), (300, 400))
        self.assertEqual(result.orientation, "portrait")
        self.assertEqual(result.crop, "portrait_3_4")
        self.assertAlmostEqual(result.composition.h, .8)
        self.assertAlmostEqual(result.composition.cx, .5)

    def test_landscape_fallback_recomputes_framing_and_measurements(self):
        points = fixture()
        points[0] = Landmark(.5, .3, .1)  # low visibility: still the head reference
        points[2], points[5] = Landmark(.4, .26, 1), Landmark(.6, .28, 1)
        points[11], points[12] = Landmark(.05, .4, 1), Landmark(.95, .4, 1)
        result = analyze_photo_detections([points], [BOX], 400, 400)
        self.assertTrue(result.accepted)
        self.assertEqual(result.crop, "landscape_4_3")
        self.assertEqual(result.composition.f, "kneeUp")  # ankles outside crop
        y = lambda v: (v - .125) / .75
        head = y(.3) - (y(.4) - y(.3)) / 2
        self.assertAlmostEqual(result.composition.s, y(.4) - head)
        self.assertAlmostEqual(result.composition.h, y(.75) - head)
        self.assertAlmostEqual(result.composition.cy, y(.27))

    def test_reject_if_both_crops_cut_required_landmark(self):
        points = fixture()
        points[0] = Landmark(.5, .1, 1)  # head top exactly 0, above the 4:3 crop
        points[11], points[12] = Landmark(.05, .3, 1), Landmark(.95, .3, 1)
        result = analyze_photo_detections([points], [BOX], 400, 400)
        self.assertFalse(result.accepted)
        self.assertEqual(result.reason, "square_crop_cuts_person")

    def test_small_bystander_outside_the_crop_is_dropped(self):
        result = analyze_photo_detections([fixture()], [BOX, PersonBox(.6, 0, 0, .1, .1)], 400, 400)
        self.assertTrue(result.accepted)
        self.assertEqual(result.crop, "portrait_3_4")

    def test_second_person_cannot_be_hidden_by_crop(self):
        result = analyze_photo_detections([fixture()], [BOX, PersonBox(.6, 0, 0, .1, .3)], 400, 400)
        self.assertFalse(result.accepted)
        self.assertEqual(result.reason, "ambiguous_person_count")


class ImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_exif_all_eight_transforms_before_both_detectors(self):
        image = Image.new("RGB", (40, 60), "red")
        for orientation in range(1, 9):
            with self.subTest(exif=orientation):
                path = self.root / "fixture.png"
                exif = image.getexif()
                exif[274] = orientation
                image.save(path, exif=exif)
                expected = (60, 40) if orientation >= 5 else (40, 60)
                seen = []
                def poses(rgb):
                    seen.append((id(rgb), rgb.size, rgb.mode))
                    return [fixture()]
                def people(rgb):
                    seen.append((id(rgb), rgb.size, rgb.mode))
                    return [BOX]
                result = PhotoPoseAnalyzer(poses, people).analyze(path)
                self.assertTrue(result.accepted)
                self.assertEqual(seen[0], seen[1])
                self.assertEqual(seen[0][1:], (expected, "RGB"))
                self.assertEqual((result.width, result.height), expected)
                self.assertEqual(result.orientation, "landscape" if orientation >= 5 else "portrait")
                self.assertAlmostEqual(result.composition.h, .8)

    def test_exif_rotation_pixel_direction(self):
        image = Image.new("RGB", (2, 3), "black")
        image.putpixel((0, 0), (255, 0, 0))
        exif = image.getexif()
        exif[274] = 6
        path = self.root / "rotated.png"
        image.save(path, exif=exif)
        with load_photo(path) as corrected:
            self.assertEqual(corrected.size, (3, 2))
            self.assertEqual(corrected.getpixel((2, 0)), (255, 0, 0))

    def test_invalid_missing_and_truncated_images_do_not_call_detectors(self):
        pose, person = Mock(), Mock()
        analyzer = PhotoPoseAnalyzer(pose, person)
        for name, data in (("bad.jpg", b"invalid"), ("truncated.png", b"\x89PNG\r\n\x1a\n")):
            path = self.root / name
            path.write_bytes(data)
            self.assertEqual(analyzer.analyze(path).reason, "invalid_image")
        self.assertEqual(analyzer.analyze(self.root / "absent.jpg").reason, "invalid_image")
        pose.assert_not_called()
        person.assert_not_called()

    def test_detector_errors_and_malformed_results_reject(self):
        path = self.root / "fixture.png"
        Image.new("RGB", (20, 20)).save(path)
        for pose, person in ((Mock(side_effect=RuntimeError), Mock()),
                             (lambda _: [fixture()], lambda _: None),
                             (lambda _: None, lambda _: [BOX])):
            self.assertFalse(PhotoPoseAnalyzer(pose, person).analyze(path).accepted)


class AdapterTests(unittest.TestCase):
    def test_production_options_mapping_and_cleanup(self):
        from mediapipe.tasks.python import vision
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "synthetic.task"
            model.touch()
            pose, person = Mock(), Mock()
            pose.detect.return_value = NS(pose_landmarks=[[
                NS(x=p.x, y=p.y, visibility=p.visibility) if p else NS(x=0, y=0, visibility=0)
                for p in fixture()]])
            person.detect.return_value = NS(detections=[NS(
                categories=[NS(category_name="person", score=.9)],
                bounding_box=NS(origin_x=0, origin_y=0, width=40, height=60))])
            with patch.object(vision.PoseLandmarker, "create_from_options", return_value=pose) as pc, \
                 patch.object(vision.ObjectDetector, "create_from_options", return_value=person) as dc:
                analyzer = MediaPipePhotoAnalyzer(model, model)
                self.assertEqual(pc.call_args.args[0].num_poses, 2)
                options = dc.call_args.args[0]
                self.assertEqual(options.max_results, -1)
                self.assertEqual(options.category_allowlist, ["person"])
                self.assertEqual(options.score_threshold, .2)
                path = Path(directory) / "fixture.png"
                Image.new("RGB", (40, 60)).save(path)
                self.assertTrue(analyzer.analyze(path).accepted)
                analyzer.close()
                pose.close.assert_called_once()
                person.close.assert_called_once()

    def test_missing_models_fail_explicitly(self):
        with self.assertRaises(FileNotFoundError):
            MediaPipePhotoAnalyzer(Path("nonexistent-pose.task"), Path("nonexistent-person.tflite"))


if __name__ == "__main__":
    unittest.main()
