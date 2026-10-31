"""Small deterministic behavioral checks, using procedural scenes only."""
from dataclasses import replace
import math
import random
import unittest

from .actions import decide
from .adapter import from_visible_rgb
from .candidates import generate, select
from .director import Director
from .features import analyze, _vanishing
from .fixtures import scene, simulated_context
from .types import Context, Line, Person, person_from_landmarks


class SceneTests(unittest.TestCase):
    def test_extraction_retains_six_supported_lines_not_two(self):
        frame = scene("weak")
        gray = tuple(235. if x % 12 in (4, 5) else 120.
                     for y in range(frame.height) for x in range(frame.width))
        mask = tuple(float(x == 36 and y == 45)
                     for y in range(frame.height) for x in range(frame.width))
        features = analyze(replace(frame, gray=gray, mask=mask))
        self.assertEqual(len(features.lines), 6)

    def test_sixth_line_and_actual_grid_values_influence_scoring(self):
        from .types import Cell, Features
        frame = scene("symmetric")
        cells = (Cell(.9, .1, .2, .5),) * 9
        first = tuple(Line(x, .05, x, .95, .8, 90) for x in (.05, .10, .15, .8, .9))
        sixth = Line(.5, .05, .5, .95, 1., 90)
        def current(features):
            return next(c for c in generate(frame, features)
                        if c.x == .5 and c.eye_y == .2 and c.scale == .1)
        a = current(Features(cells, first, None, .9, True, "ok"))
        b = current(Features(cells, first + (sixth,), None, .9, True, "ok"))
        self.assertGreater(b.terms["overlap"], a.terms["overlap"])
        self.assertGreater(b.terms["structure"], a.terms["structure"])
        changed = list(cells)
        changed[1] = Cell(.9, .6, .9, .5)
        c = current(Features(tuple(changed), first, None, .9, True, "ok"))
        self.assertNotEqual(c.terms["space"], a.terms["space"])

    def test_deterministic_selection_both_orientations_all_levels(self):
        for orientation in ("portrait", "landscape"):
            for level in range(1, 6):
                for kind in ("diagonal", "asymmetric", "symmetric", "weak"):
                    frame = scene(kind, orientation=orientation, level=level)
                    features = analyze(frame)
                    self.assertEqual(select(generate(frame, features)), select(generate(frame, features)))
                    for candidate in generate(frame, features):
                        self.assertGreaterEqual(candidate.head_y, .035)
                        self.assertLessEqual(candidate.x + candidate.width / 2, .965)

    def test_diagonal_features_and_avoided_head_overlap(self):
        frame = scene("diagonal")
        features = analyze(frame)
        self.assertGreaterEqual(len(features.lines), 2)
        self.assertTrue(any(10 < l.angle_deg < 80 or 100 < l.angle_deg < 170 for l in features.lines))
        candidates = generate(frame, features)
        current = next(c for c in candidates if c.x == frame.person.x and c.eye_y == frame.person.eye_y and c.scale == frame.person.scale)
        best = select(candidates)
        self.assertLess(best.terms["overlap"], current.terms["overlap"])
        self.assertNotEqual(best.x, frame.person.x)

    def test_asymmetric_clutter_uses_available_region(self):
        frame = scene("asymmetric", x=.3)
        features = analyze(frame)
        self.assertGreater(features.cells[0].edges, features.cells[2].edges)
        self.assertGreater(select(generate(frame, features)).x, frame.person.x)

    def test_symmetric_and_already_offcenter_do_not_force_placement(self):
        for x in (.3, .5):
            frame = scene("symmetric", x=x)
            decision = Director().update(frame)
            self.assertEqual(decision.target.x, x)
            self.assertEqual(decision.action.direction, "capture")

    def test_framing_matches_deepest_observed_anchor_that_fits(self):
        frame = scene("symmetric")
        for c in generate(frame, analyze(frame)):
            self.assertEqual(c.framing, "fullBody")
        from .types import SPANS
        larger = replace(frame, person=replace(frame.person, scale=.15))
        candidates = generate(larger, analyze(larger))
        self.assertTrue(any(c.framing != "fullBody" for c in candidates))
        for c in candidates:
            fitting = [f for f in SPANS if c.head_y + c.scale * SPANS[f] / .28 <= .97]
            self.assertEqual(c.framing, fitting[-1])

    def test_weak_structure_does_not_invent_horizon_or_movement(self):
        frame = scene("weak")
        decision = Director().update(frame, simulated_context(frame))
        self.assertEqual(decision.features.lines, ())
        self.assertIsNone(decision.features.vanishing_point)
        self.assertEqual(decision.action.direction, "hold")
        self.assertFalse(decision.action.valid)

    def test_mask_does_not_create_edges_or_false_empty_cells(self):
        frame = scene("weak")
        features = analyze(frame)
        altered = replace(frame, gray=tuple(255 if m else v for v, m in zip(frame.gray, frame.mask)))
        self.assertEqual(analyze(altered), features)
        self.assertTrue(any(c.coverage < .8 for c in features.cells))
        self.assertTrue(all(c.edges == 0 for c in features.cells))
        for mask in ((0.,) * len(frame.mask), (1.,) * len(frame.mask)):
            self.assertFalse(Director().update(replace(frame, mask=mask)).features.valid)

    def test_fully_occluded_grid_cell_does_not_create_false_contrast(self):
        frame = scene("weak")
        mask = tuple(float(.2 < (x + .5) / frame.width < .8 and .1 < (y + .5) / frame.height < .8)
                     for y in range(frame.height) for x in range(frame.width))
        flat = replace(frame, mask=mask, gray=(120.,) * len(frame.gray))
        features = analyze(flat)
        self.assertTrue(features.valid)
        self.assertTrue(any(c.coverage == 0 for c in features.cells))
        self.assertEqual(features.confidence, 0.)
        self.assertEqual(Director().update(flat).action.direction, "hold")

    def test_random_texture_cannot_claim_vanishing_point(self):
        frame = scene("weak")
        rng = random.Random(83)
        noisy = replace(frame, gray=tuple(rng.randrange(256) for _ in frame.gray))
        features = analyze(noisy)
        self.assertEqual(features.lines, ())
        self.assertIsNone(features.vanishing_point)

    def test_vanishing_point_requires_three_supported_nonparallel_lines(self):
        lines = (Line(0, 1, .5, .3, .9, 125), Line(1, 1, .5, .3, .9, 55),
                 Line(.5, 1, .5, .3, .9, 90))
        self.assertIsNone(_vanishing(lines[:2], .75))
        point = _vanishing(lines, .75)
        self.assertAlmostEqual(point[0], .5)
        self.assertAlmostEqual(point[1], .3)

    def test_level_emphasis_changes_scale_penalty(self):
        low = scene("symmetric", level=1)
        high = replace(low, level=5)
        for f, want_greater in ((low, True), (high, False)):
            rows = generate(f, analyze(f))
            small = min(rows, key=lambda c: c.scale)
            large = next(c for c in rows if c.x == small.x and c.eye_y == small.eye_y and c.framing == small.framing and c.scale > small.scale)
            self.assertEqual(large.terms["emphasis"] < small.terms["emphasis"], want_greater)


class ActionTests(unittest.TestCase):
    def setUp(self):
        self.frame = scene("symmetric")
        self.features = analyze(self.frame)
        self.target = select(generate(self.frame, self.features))

    def test_horizontal_actor_directions_are_separate_measured_responses(self):
        target = replace(self.target, x=.7)
        for actor, response, expected in (("subject", .2, "right"), ("photographer", -.2, "left")):
            action = decide(self.frame, target, self.features, simulated_context(self.frame, actor, response=response))
            self.assertEqual((action.actor, action.direction), (actor, expected))
            self.assertEqual(action.magnitude, .5)
            self.assertIn("모델님" if actor == "subject" else "촬영자님", action.text)

    def test_distance_and_height_signs_follow_observed_geometry(self):
        for axis, target, response, expected in (
            ("distance", replace(self.target, scale=.14), .06, "forward"),
            ("distance", replace(self.target, scale=.06), .06, "backward"),
            ("height", replace(self.target, eye_y=.35), .2, "up"),
            ("height", replace(self.target, eye_y=.10), .2, "down")):
            frame = replace(self.frame, person=replace(self.frame.person, framing="chestUp"))
            # Span validation uses the target framing; keep the test inside view.
            target = replace(target, framing="chestUp")
            action = decide(frame, target, self.features, simulated_context(frame, "photographer", axis, response))
            self.assertEqual(action.direction, expected)

    def test_no_motion_or_unsafe_stale_evidence_means_hold(self):
        target = replace(self.target, x=.7)
        good = simulated_context(self.frame)
        cases = (Context(), replace(good, safe_directions=frozenset()),
                 replace(good, safety_at=-3), replace(good, geometry_id="old-view"),
                 replace(good, motions=(replace(good.motions[0], at=-9),)),
                 replace(good, motions=(replace(good.motions[0], confidence=.2),)),
                 replace(good, motions=(replace(good.motions[0], dx=math.nan),)))
        for context in cases:
            self.assertFalse(decide(self.frame, target, self.features, context).valid)

    def test_korean_distance_phrasing(self):
        from .actions import sentence
        self.assertEqual(sentence("photographer", "backward"), "촬영자님, 뒤로 반 걸음 이동해 주세요.")
        self.assertEqual(sentence("photographer", "forward"), "촬영자님, 앞으로 반 걸음 이동해 주세요.")

    def test_camera_motion_requires_background_preservation_evidence(self):
        good = simulated_context(self.frame, "photographer", response=-.2)
        context = replace(good, motions=(replace(good.motions[0], structure_preservation=.2),))
        self.assertEqual(decide(self.frame, replace(self.target, x=.7), self.features, context).direction, "hold")

    def test_overshoot_does_not_generate_movement(self):
        frame = replace(self.frame, person=replace(self.frame.person, x=.625))
        target = replace(self.target, x=.7)
        context = simulated_context(frame, response=.4)
        self.assertEqual(decide(frame, target, self.features, context).direction, "hold")


class LoopTests(unittest.TestCase):
    def test_confirm_progress_keep_target_and_stop_when_acceptable(self):
        director = Director()
        f = scene("asymmetric", x=.3)
        first = director.update(f, simulated_context(f))
        self.assertEqual(first.action.direction, "right")
        waiting = director.update(replace(f, at=.5), simulated_context(replace(f, at=.5)))
        self.assertEqual(waiting.action.direction, "hold")
        after = scene("asymmetric", at=2, x=.4)
        improved = director.update(after, simulated_context(after))
        self.assertEqual(improved.progress, "acceptable")
        self.assertEqual(first.target, improved.target)
        self.assertEqual(improved.action.direction, "capture")
        # Exit tolerance is larger than entry; no tiny corrective instruction.
        jitter = scene("asymmetric", at=2.1, x=.39)
        stable = director.update(jitter, simulated_context(jitter))
        self.assertEqual(stable.action.direction, "capture")

    def test_progress_requires_improvement_on_the_instructed_axis(self):
        director = Director()
        f = scene("diagonal")
        before = director.update(f, simulated_context(f))
        expected = "right" if before.target.x > f.person.x else "left"
        self.assertEqual(before.action.direction, expected)
        after = scene("diagonal", at=2, x=f.person.x + (.1 if expected == "right" else -.1))
        result = director.update(after, simulated_context(after))
        self.assertEqual(result.progress, "improved")
        self.assertEqual(result.target, before.target)
        self.assertEqual(result.action.direction, expected)

    def test_no_progress_blocks_repetition(self):
        director = Director()
        f = scene("asymmetric", x=.3)
        self.assertEqual(director.update(f, simulated_context(f)).action.direction, "right")
        for at in (2., 4., 10.):
            still = replace(f, at=at)
            result = director.update(still, simulated_context(still))
            self.assertEqual(result.action.direction, "hold")
            self.assertEqual(result.action.reason, "movement-needs-reassessment")

    def test_worsening_does_not_reverse_instruction(self):
        director = Director()
        f = scene("asymmetric", x=.3)
        before = director.update(f, simulated_context(f))
        wrong = scene("asymmetric", at=2., x=.23)
        after = director.update(wrong, simulated_context(wrong))
        self.assertEqual(after.progress, "worsened")
        self.assertEqual(after.action.direction, "hold")
        self.assertEqual(after.target, before.target)

    def test_small_changes_keep_target_and_large_scene_change_recomputes(self):
        director = Director()
        f = scene("diagonal")
        first = director.update(f)
        noisy = replace(f, at=.2, gray=tuple(min(255, v + .2) for v in f.gray))
        next_ = director.update(noisy)
        self.assertEqual(first.target_generation, next_.target_generation)
        self.assertEqual(first.target, next_.target)
        changed = replace(scene("asymmetric", at=3), gray=tuple(v * .2 for v in scene("asymmetric").gray))
        self.assertGreater(director.update(changed).target_generation, first.target_generation)

    def test_geometry_orientation_and_level_invalidate_target(self):
        for modified in (replace(scene(), at=1, geometry_id="new-lens"),
                         scene(at=1, orientation="landscape"), scene(at=1, level=5)):
            director = Director()
            before = director.update(scene())
            after = director.update(modified)
            self.assertGreater(after.target_generation, before.target_generation)

    def test_bad_frames_and_person_loss_clear_pending_movement(self):
        director = Director()
        f = scene("asymmetric", x=.3)
        director.update(f, simulated_context(f))
        for broken in (replace(f, at=1, person=None), replace(f, gray=(math.nan,) * len(f.gray)),
                       replace(f, width=0), replace(f, person=replace(f.person, scale=math.nan))):
            self.assertEqual(director.update(broken).action.direction, "hold")
            self.assertIsNone(director.pending)
        good = replace(f, at=2.)
        self.assertEqual(director.update(good).action.direction, "hold")

    def test_out_of_order_observation_cannot_issue_action(self):
        director = Director()
        f = scene("diagonal", at=2)
        director.update(f)
        self.assertFalse(director.update(replace(f, at=1), simulated_context(f)).action.valid)


class AdapterTests(unittest.TestCase):
    @staticmethod
    def points():
        points = [(0., 0., 0.)] * 33
        points[0] = (.5, .2, 0.)
        points[2], points[5] = (.48, .18, 0.), (.52, .18, 0.)
        for a, b, y in ((11, 12, .3), (23, 24, .5), (25, 26, .7), (27, 28, .9)):
            points[a], points[b] = (.45, y, 1.), (.55, y, 1.)
        return points

    def test_pose_formula_uses_estimated_nose_eyes_and_visible_shoulders(self):
        person = person_from_landmarks(self.points())
        self.assertAlmostEqual(person.head_y, .15)
        self.assertAlmostEqual(person.eye_y, .18)
        self.assertAlmostEqual(person.scale, .15)
        self.assertEqual(person.framing, "fullBody")
        points = self.points()
        points[11] = (.45, .3, .1)
        self.assertIsNone(person_from_landmarks(points))

    def test_adapter_preserves_visible_pose_and_conservatively_pools_mask(self):
        from PIL import Image
        image = Image.new("RGB", (144, 192), (120, 120, 120))
        mask = [[0.] * 144 for _ in range(192)]
        mask[10][10] = 1.
        frame = from_visible_rgb(image, mask, self.points(), at=0., orientation="portrait", geometry_id="test")
        self.assertEqual((frame.width, frame.height), (72, 96))
        self.assertEqual(frame.person, person_from_landmarks(self.points()))
        self.assertEqual(max(frame.mask), 1.)
        with self.assertRaises(ValueError):
            from_visible_rgb(image, [], self.points(), at=0., orientation="portrait", geometry_id="test")


if __name__ == "__main__":
    unittest.main()
