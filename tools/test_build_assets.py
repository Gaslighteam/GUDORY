"""CLI preserves pose-only validation and routes aggregate asset generation."""
import contextlib
import io
import unittest
from unittest.mock import patch

import build_assets


class EntryPointTests(unittest.TestCase):
    def test_routes_pose_arguments_without_mutating_caller(self):
        args = ["--pose-only", "--photos", "fixture", "--pose-model", "pose.task",
                "--person-model", "person.tflite"]
        original = list(args)
        with patch.object(build_assets, "pose_main", return_value=7) as run:
            self.assertEqual(build_assets.main(args), 7)
        run.assert_called_once_with(original[1:])
        self.assertEqual(args, original)

    def test_missing_model_arguments_fail_before_inference(self):
        with patch.object(build_assets, "pose_main") as run, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                build_assets.main(["--photos", "fixture"])
        self.assertEqual(error.exception.code, 2)
        run.assert_not_called()

    def test_default_routes_to_recommendation_pipeline(self):
        with patch("recommendation_pipeline.main", return_value=8) as run:
            self.assertEqual(build_assets.main(["--photos", "fixture"]), 8)
        run.assert_called_once_with(["--photos", "fixture"])


if __name__ == "__main__":
    unittest.main()
