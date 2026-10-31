"""The submitted entry point must route only the approved pose milestone."""
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

    def test_asset_generation_is_not_exposed(self):
        with patch.object(build_assets, "pose_main") as run, \
                contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                build_assets.main(["--photos", "fixture"])
        self.assertEqual(error.exception.code, 2)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
