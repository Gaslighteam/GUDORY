"""Deterministic synthetic tests; no training-photo records are serialized."""
import base64
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from types import SimpleNamespace

import numpy as np
from PIL import Image

from background_clip import (MEAN, STD, SelfieSegmenter, SegmentationFailure, background_embedding,
                             clip_pixels, mask_person, normalize_embedding)
from pose_analysis import Analysis, Composition
from recommendation_assets import (FRAMINGS, Sample, aggregate, build_asset,
    deterministic_clusters, level_for, quantize_center, serialize_asset,
    validate_asset, weighted_quantile)
from recommendation_pipeline import collect_samples, render_report
from aggregate_baseline import load_baseline, compare_baseline


def sample(orientation="portrait", scale=.2, framing="fullBody", weight=1, axis=0):
    vector = np.zeros(512, dtype=np.float32)
    vector[axis] = 1
    return Sample(orientation, Composition(framing, .8, scale, .5, .2), vector, weight)


def dataset(count=80):
    rows = []
    for o in ("portrait", "landscape"):
        for i in range(count):
            rows.append(sample(o, .05 + i * .004, FRAMINGS[(i // 20) % 4],
                               3 if i % 10 == 0 else 1, i // 20))
    return rows


class ClipTests(unittest.TestCase):
    def test_rgb_normalization_nchw_and_center_crop(self):
        pixels = np.zeros((224, 448, 3), dtype=np.uint8)
        pixels[:, :112] = (255, 0, 0)
        pixels[:, 112:224] = (0, 255, 0)
        pixels[:, 224:336] = (0, 0, 255)
        pixels[:, 336:] = (255, 255, 255)
        tensor = clip_pixels(Image.fromarray(pixels))
        self.assertEqual(tensor.shape, (1, 3, 224, 224))
        self.assertEqual(tensor.dtype, np.float32)
        self.assertTrue(tensor.flags.c_contiguous)
        green = (np.array([0, 1, 0], dtype=np.float32) - MEAN) / STD
        blue = (np.array([0, 0, 1], dtype=np.float32) - MEAN) / STD
        np.testing.assert_allclose(tensor[0, :, :, :112], np.broadcast_to(green[:, None, None], (3, 224, 112)))
        np.testing.assert_allclose(tensor[0, :, :, 112:], np.broadcast_to(blue[:, None, None], (3, 224, 112)))

    def test_portrait_resize_preserves_channels(self):
        tensor = clip_pixels(Image.new("RGB", (100, 300), "red"))
        np.testing.assert_allclose(tensor[0, :, 0, 0], (np.array([1, 0, 0]) - MEAN) / STD, atol=1e-6)

    def test_embedding_direction_shape_and_finite_validation(self):
        vector = np.zeros(512)
        vector[:2] = (3, 4)
        result = normalize_embedding(vector)
        np.testing.assert_allclose(result[:2], [.6, .8])
        self.assertAlmostEqual(float(np.linalg.norm(result)), 1, places=6)
        for invalid in (np.zeros(512), np.ones(511), np.ones((1, 512)),
                        np.full(512, np.nan), np.full(512, np.inf)):
            with self.subTest(shape=invalid.shape), self.assertRaises(ValueError):
                normalize_embedding(invalid)


class MaskTests(unittest.TestCase):
    def test_mean_of_whole_image_and_threshold(self):
        image = Image.fromarray(np.array([[[0, 20, 40], [200, 220, 240]],
                                         [[0, 20, 40], [200, 220, 240]]], dtype=np.uint8))
        before = np.array(image)
        result = np.array(mask_person(image, [[.5, .499], [1, 0]]))
        np.testing.assert_array_equal(result[:, 0], [[100, 120, 140]] * 2)
        np.testing.assert_array_equal(result[:, 1], before[:, 1])
        np.testing.assert_array_equal(np.array(image), before)

    def test_lower_resolution_mask_and_failure_paths(self):
        image = Image.new("RGB", (4, 4))
        self.assertEqual(mask_person(image, [[0, 1], [0, 1]]).size, (4, 4))
        for mask in (None, [], np.zeros((4, 4)), np.ones((4, 4)), [[np.nan]],
                     [[1.1, 0]], [[-.1, 1]], [["bad"]], np.zeros((2, 2, 2))):
            with self.subTest(mask=str(mask)), self.assertRaises(SegmentationFailure):
                mask_person(image, mask)
        encoder = Mock()
        with self.assertRaises(SegmentationFailure):
            background_embedding(image, Mock(side_effect=RuntimeError), encoder)
        encoder.assert_not_called()

    def test_mask_applied_before_inference_and_output_revalidated(self):
        image = Image.new("RGB", (4, 4), "red")
        vector = sample().embedding
        encoder = Mock(return_value=vector)
        result = background_embedding(image, lambda _: np.tile([0, 0, 1, 1], (4, 1)), encoder)
        np.testing.assert_array_equal(result, vector)
        encoder.assert_called_once()
        with self.assertRaises(ValueError):
            background_embedding(image, lambda _: np.tile([0, 1], (2, 1)), lambda _: np.zeros(512))

    def test_selfie_adapter_validates_single_and_two_channel_layouts(self):
        from mediapipe.tasks.python import vision
        with tempfile.TemporaryDirectory() as temp:
            model = Path(temp) / "synthetic.tflite"
            model.touch()
            for labels in (["selfie"], ["background", "person"]):
                with self.subTest(labels=labels):
                    detector = Mock()
                    detector.labels = labels
                    foreground = np.tile([0, 1], (2, 1)).astype(np.float32)[..., None]
                    mask = SimpleNamespace(numpy_view=lambda: foreground)
                    detector.segment.return_value = SimpleNamespace(confidence_masks=[mask] * len(labels))
                    with patch.object(vision.ImageSegmenter, "create_from_options", return_value=detector):
                        segmenter = SelfieSegmenter(model)
                        np.testing.assert_array_equal(segmenter(Image.new("RGB", (2, 2))), foreground[..., 0])
                        detector.segment.side_effect = RuntimeError()
                        with self.assertRaises(SegmentationFailure):
                            segmenter(Image.new("RGB", (2, 2)))
                        segmenter.close()
                        detector.close.assert_called_once()


class AggregationTests(unittest.TestCase):
    def test_weighted_quintiles_and_level_order(self):
        values, weights = [.1, .2, .3, .4, .5], [1, 1, 1, 1, 3]
        edges = [weighted_quantile(values, weights, q) for q in (.8, .6, .4, .2)]
        self.assertEqual(edges, [.5, .5, .3, .2])
        self.assertEqual([level_for(v, edges) for v in values], [5, 4, 3, 3, 1])
        self.assertEqual(weighted_quantile([.1, .5], [1, 3], .5), .5)
        with self.assertRaises(ValueError):
            weighted_quantile([1], [0], .5)

    def test_four_framings_never_mix_spans(self):
        for f in FRAMINGS:
            with self.subTest(framing=f):
                rows = [sample(framing=f, weight=3)] * 3
                rows += [Sample("portrait", Composition("waistUp" if f != "waistUp" else "chestUp",
                                                        .1, .05, .1, .1), sample().embedding, 1)] * 4
                value = aggregate(rows)
                self.assertEqual(value["f"], f)
                self.assertEqual(value["h"], .8)
                self.assertEqual(value["n"], 3)

    def test_weighted_median_and_minimum_actual_support(self):
        rows = [Sample("portrait", Composition("fullBody", h, .1, .5, .2), sample().embedding, w)
                for h, w in ((.2, 1), (.5, 1), (.9, 3))]
        self.assertEqual(aggregate(rows)["h"], .9)
        self.assertIsNone(aggregate([sample(weight=100)]))

    def test_complete_fallbacks_for_ties_and_orientation_separation(self):
        rows = [sample(o, .2, framing="waistUp" if o == "portrait" else "fullBody")
                for o in ("portrait", "landscape") for _ in range(6)]
        asset, info = build_asset(rows)
        for o in ("portrait", "landscape"):
            self.assertEqual(len(asset["fallback"][o]), 5)
            self.assertEqual(len(asset["levels"][o]), 4)
            self.assertEqual(asset["levels"][o], sorted(asset["levels"][o], reverse=True))
        self.assertEqual(asset["fallback"]["portrait"]["5"]["f"], "waistUp")
        self.assertEqual(asset["fallback"]["landscape"]["5"]["f"], "fullBody")
        with self.assertRaises(ValueError):
            build_asset([sample()] * 3)

    def test_cluster_and_serialization_determinism_even_after_reordering(self):
        rows = dataset()
        first, info = build_asset(rows)
        second, _ = build_asset(list(reversed(rows)))
        self.assertEqual(serialize_asset(first), serialize_asset(second))
        self.assertTrue(first["clusters"])
        self.assertLessEqual(len(first["clusters"]), 8)
        self.assertTrue(all(c["n"] >= 3 and all(v["n"] >= 3 for v in c["lv"].values()) for c in first["clusters"]))
        self.assertEqual(json.loads(serialize_asset(first)), first)

    def test_small_clusters_merge_to_avoid_per_photo_centres(self):
        rows = [sample(axis=0)] * 40 + [sample(axis=1)]
        groups = deterministic_clusters(rows)
        self.assertTrue(all(len(g) >= 3 for g in groups))
        self.assertEqual(sum(map(len, groups)), 41)

    def test_quantization_is_int8_512_and_preserves_cosine(self):
        vector = normalize_embedding(np.random.default_rng(0).normal(size=512))
        decoded = np.frombuffer(base64.b64decode(quantize_center(vector)), dtype=np.int8)
        self.assertEqual(decoded.shape, (512,))
        self.assertTrue(np.all(decoded >= -127))
        self.assertGreater(float(np.dot(normalize_embedding(decoded), vector)), .998)

    def test_schema_rejects_per_photo_fields_and_invalid_values(self):
        asset, _ = build_asset(dataset())
        for location in ("top", "cluster", "composition"):
            mutated = copy.deepcopy(asset)
            target = (mutated if location == "top" else mutated["clusters"][0] if location == "cluster"
                      else next(iter(mutated["clusters"][0]["lv"].values())))
            target["photo_id"] = "synthetic forbidden field"
            with self.assertRaises(ValueError):
                validate_asset(mutated)
        for mutate in (lambda a: a["fallback"]["portrait"].pop("5"),
                       lambda a: a["fallback"]["portrait"]["1"].update(h=float("nan")),
                       lambda a: a["levels"].update(portrait=[.1, .2, .3, .4]),
                       lambda a: a["clusters"][0].update(e="invalid")):
            mutated = copy.deepcopy(asset)
            mutate(mutated)
            with self.assertRaises(ValueError):
                validate_asset(mutated)

    def test_report_is_aggregate_only(self):
        asset, info = build_asset(dataset())
        text = render_report({"processed": 160, "pose_accepted": 160, "accepted": 160, "rejected": 0},
                             info, len(serialize_asset(asset)), 3, 1)
        self.assertNotIn("photo_id", text)
        self.assertNotIn(".jpg", text)
        self.assertNotIn("embedding\":", serialize_asset(asset).decode())


class PipelineTests(unittest.TestCase):
    def test_report_only_baseline_is_fixed_and_rejects_per_photo_fields(self):
        path = Path(__file__).with_name("recommendation_baseline.json")
        before = path.read_bytes()
        baseline = load_baseline(path)
        self.assertEqual(baseline["metrics"]["processed"], 797)
        self.assertEqual(baseline["metrics"]["clip_accepted"], 548)
        self.assertEqual(baseline["metrics"]["portrait_clusters"], 8)
        self.assertEqual(baseline["metrics"]["landscape_clusters"], 14)
        self.assertEqual(baseline["metrics"]["json_bytes"], 23478)
        info = {"portrait": {"photos": 206, "clusters": 8}, "landscape": {"photos": 342, "clusters": 14}}
        report = compare_baseline(baseline, {"processed": 800, "pose_accepted": 552, "accepted": 550},
                                  info, 24000, 3, 1, baseline["asset_sha256"])
        self.assertIn("processed | 797 | 800 | +3", report)
        self.assertIn("clip_accepted | 548 | 550 | +2", report)
        self.assertIn("Configuration matches fixed baseline: yes", report)
        self.assertEqual(path.read_bytes(), before)
        with tempfile.TemporaryDirectory() as temp:
            custom = Path(temp) / "baseline.json"
            invalid = copy.deepcopy(baseline)
            invalid["photo_id"] = "synthetic prohibited field"
            custom.write_text(json.dumps(invalid), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_baseline(custom)

    def test_baseline_configuration_change_is_explicit(self):
        baseline = load_baseline(Path(__file__).with_name("recommendation_baseline.json"))
        info = {"portrait": {"photos": 206, "clusters": 8}, "landscape": {"photos": 342, "clusters": 14}}
        report = compare_baseline(baseline, {"processed": 797, "pose_accepted": 552, "accepted": 548},
                                  info, 23478, 1, 1, "0" * 64)
        self.assertIn("Configuration matches fixed baseline: no", report)
        self.assertIn("Aggregate asset SHA-256 matches fixed baseline: no", report)

    def test_full_rebuild_discovers_new_nested_photos_without_appending(self):
        import contextlib
        import io
        import recommendation_pipeline as pipeline
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            photos = root / "photos"
            for source, size in (("team", (40, 60)), ("openimages", (60, 40))):
                folder = photos / source / "nested"
                folder.mkdir(parents=True)
                for i in range(8):
                    Image.new("RGB", size, "red").save(folder / f"fixture{i}.png")
            model = root / "synthetic.model"
            model.write_bytes(b"synthetic model fixture")
            output, report = root / "recommend.json", root / "report.md"
            output.write_bytes(b"obsolete output must never be read as input")
            args = ["--photos", str(photos), "--pose-model", str(model), "--person-model", str(model),
                    "--segmentation-model", str(model), "--clip-model", str(model),
                    "--out", str(output), "--report", str(report)]
            pose = Mock()
            def analyze(path):
                with Image.open(path) as image:
                    o = "portrait" if image.height > image.width else "landscape"
                    return Analysis("accepted", sample(o).composition, o, image.width, image.height)
            pose.analyze.side_effect = analyze
            with patch.object(pipeline, "MediaPipePhotoAnalyzer", return_value=pose), \
                 patch.object(pipeline, "SelfieSegmenter", return_value=Mock(side_effect=lambda _: np.tile([0, 1], (2, 1)))), \
                 patch.object(pipeline, "ClipEncoder", return_value=Mock(return_value=sample().embedding)), \
                 patch.object(pipeline, "build_asset", wraps=build_asset) as build, \
                 contextlib.redirect_stdout(io.StringIO()):
                pipeline.main(args)
                self.assertEqual(len(build.call_args.args[0]), 16)
                extra = photos / "team" / "another" / "deeper"
                extra.mkdir(parents=True)
                new_photo = extra / "fixture_new.png"
                Image.new("RGB", (40, 60), "red").save(new_photo)
                original = new_photo.read_bytes()
                pipeline.main(args)
                second_asset, second_report = output.read_bytes(), report.read_bytes()
                self.assertEqual(len(build.call_args.args[0]), 17)
                self.assertEqual(sum(c["n"] for c in json.loads(second_asset)["clusters"]), 17)
                output.write_bytes(b"stale unrelated statistics")
                pipeline.main(args)
                self.assertEqual(len(build.call_args.args[0]), 17)
                self.assertEqual(output.read_bytes(), second_asset)
                self.assertEqual(report.read_bytes(), second_report)
                self.assertEqual(new_photo.read_bytes(), original)
                self.assertEqual(pose.analyze.call_count, 16 + 17 + 17)

    def test_insufficient_data_preserves_prior_outputs(self):
        import recommendation_pipeline as pipeline
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output, report = root / "recommend.json", root / "report.md"
            output.write_bytes(b"prior asset")
            report.write_bytes(b"prior report")
            args = ["--photos", str(root), "--pose-model", "pose.task", "--person-model", "person.tflite",
                    "--segmentation-model", "segment.tflite", "--clip-model", "clip.onnx",
                    "--out", str(output), "--report", str(report)]
            with patch.object(pipeline, "MediaPipePhotoAnalyzer") as pose, \
                 patch.object(pipeline, "SelfieSegmenter") as segmenter, \
                 patch.object(pipeline, "ClipEncoder"), \
                 patch.object(pipeline, "collect_samples", return_value=([sample()] * 3, {})):
                with self.assertRaises(ValueError):
                    pipeline.main(args)
            pose.return_value.close.assert_called_once()
            segmenter.return_value.close.assert_called_once()
            self.assertEqual(output.read_bytes(), b"prior asset")
            self.assertEqual(report.read_bytes(), b"prior report")

    def test_source_weights_and_segmentation_failure_exclusion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for source in ("team", "openimages"):
                (root / source).mkdir()
                Image.new("RGB", (40, 60), "red").save(root / source / "fixture.png")
            pose = Mock()
            pose.analyze.return_value = Analysis("accepted", sample().composition, "portrait", 40, 60)
            segmenter = lambda _: np.tile([0, 1], (2, 1))
            rows, counts = collect_samples(root, pose, segmenter, lambda _: sample().embedding)
            self.assertEqual(sorted(r.weight for r in rows), [1, 3])
            self.assertEqual(counts["accepted"], 2)
            rows, counts = collect_samples(root, pose, lambda _: None, lambda _: sample().embedding)
            self.assertEqual(rows, [])
            self.assertEqual(counts["rejected/segmentation"], 2)


if __name__ == "__main__":
    unittest.main()
