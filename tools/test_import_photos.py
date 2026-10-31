from pathlib import Path
import tempfile
import unittest
import zipfile
from import_photos import import_archive, inspect_archive, verify_import


class ImportTests(unittest.TestCase):
    def test_post_import_audit_and_tamper_detection(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = root / "fixture.jpg"
            Image.new("RGB", (30, 40), "red").save(original)
            archive = root / "photos.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.write(original, "team/fixture.jpg")
            imported = import_archive(archive, root / "photos")
            summary = verify_import(archive, root / "photos", imported["batch"])
            self.assertEqual(summary["originals_unchanged"], 1)
            self.assertEqual(summary["corrected_orientation/portrait"], 1)
            target = root / "photos/team" / imported["batch"] / "fixture.jpg"
            target.write_bytes(b"changed fixture")
            with self.assertRaisesRegex(ValueError, "Original image changed"):
                verify_import(archive, root / "photos", imported["batch"])

    def test_preserves_sources_and_bytes_without_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "photos.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("team/photo.jpg", b"team fixture")
                output.writestr("openimages/photo.jpg", b"supplement fixture")
                output.writestr("openimages_attribution.csv", b"private metadata")
            summary = inspect_archive(archive)
            self.assertEqual(summary["supported_images"], 2)
            first = import_archive(archive, root / "photos")
            second = import_archive(archive, root / "photos")
            self.assertNotEqual(first["batch"], second["batch"])
            self.assertEqual((root / "photos/team" / first["batch"] / "photo.jpg").read_bytes(), b"team fixture")
            self.assertEqual((root / "photos/openimages" / first["batch"] / "photo.jpg").read_bytes(), b"supplement fixture")
            self.assertEqual(len(list((root / "photos").rglob("*.jpg"))), 4)

    def test_rejects_unsafe_paths_before_extraction(self):
        for bad in ("../escaped.jpg", "/absolute.jpg", "C:/drive.jpg", "team/a:stream.jpg",
                    "team/CON.jpg", "team/dir /x.jpg", "team/../x.jpg", "team\\..\\x.jpg"):
            with self.subTest(path=bad), tempfile.TemporaryDirectory() as temp:
                archive = Path(temp) / "photos.zip"
                with zipfile.ZipFile(archive, "w") as output:
                    output.writestr(bad, b"fixture")
                destination = Path(temp) / "photos"
                with self.assertRaises(ValueError):
                    import_archive(archive, destination)
                self.assertFalse(destination.exists())

    def test_rejects_case_collisions_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "photos.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("team/a.jpg", b"one")
                output.writestr("team/A.jpg", b"two")
            with self.assertRaises(ValueError):
                inspect_archive(archive)
            with zipfile.ZipFile(archive, "w") as output:
                link = zipfile.ZipInfo("team/link.jpg")
                link.external_attr = 0o120777 << 16
                output.writestr(link, b"target")
            with self.assertRaises(ValueError):
                inspect_archive(archive)


if __name__ == "__main__":
    unittest.main()
