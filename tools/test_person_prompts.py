"""Synthetic only: no photos or models."""
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from background_clip import DIM, PersonPrompts
from pose_analysis import PersonBox


def unit(i):
    v = np.zeros(DIM, dtype=np.float32)
    v[i] = 1
    return v


class PersonPromptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "p.npz"
        np.savez(self.path, emb=np.stack([unit(0), unit(1), unit(2)]), real=2,
                 labels=np.array(["real a", "real b", "statue"]))

    def tearDown(self):
        self.temp.cleanup()

    def test_probability_from_person_crop(self):
        prompts = PersonPrompts(self.path)
        image = Image.new("RGB", (400, 600))
        seen = []

        def encoder(crop):
            seen.append(crop.size)
            return unit(2)

        box = PersonBox(.9, .25, .25, .75, .75)
        self.assertGreater(prompts.not_real_probability(image, box, encoder), .99)
        self.assertEqual(seen, [(260, 360)])  # box 200x300 padded by 30 px each side
        self.assertLess(prompts.not_real_probability(image, box, lambda _: unit(0)), .01)

    def test_degenerate_box_counts_as_real(self):
        prompts = PersonPrompts(self.path)
        box = PersonBox(.9, .5, .5, .5001, .5001)
        self.assertEqual(prompts.not_real_probability(Image.new("RGB", (40, 40)), box, lambda _: unit(2)), 0.0)

    def test_rejects_bad_embeddings(self):
        np.savez(self.path, emb=np.zeros((3, 10)), real=2)
        with self.assertRaises(ValueError):
            PersonPrompts(self.path)


if __name__ == "__main__":
    unittest.main()
