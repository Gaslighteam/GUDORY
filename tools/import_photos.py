"""Inspect/import a local ZIP; preserve bytes and source grouping, never overwrite.

Only summary counts are printed. ZIP and per-photo metadata remain local.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import uuid
import zipfile

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def inspect_archive(path: Path):
    summary = Counter()
    seen = set()
    with zipfile.ZipFile(path) as archive:
        if len(archive.infolist()) > 20_000:
            raise ValueError("Archive has too many entries")
        for entry in archive.infolist():
            raw = entry.filename.replace("\\", "/")
            parts = raw.rstrip("/").split("/")
            if (raw.startswith("/") or any(p in {"", ".", ".."} or ":" in p
                    or p.endswith((".", " ")) or re.match(
                        r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)", p, re.I)
                    for p in parts)):
                raise ValueError("Unsafe archive path")
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)):
                raise ValueError("Archive contains a non-regular entry")
            if entry.flag_bits & 1:
                raise ValueError("Encrypted archive is not supported")
            key = raw.casefold()
            if key in seen:
                raise ValueError("Duplicate/colliding archive names")
            seen.add(key)
            if entry.is_dir():
                continue
            if entry.file_size > 100_000_000 or entry.file_size > max(entry.compress_size, 1) * 1000:
                raise ValueError("Unsafe archive expansion size/ratio")
            summary["files"] += 1
            summary["uncompressed_bytes"] += entry.file_size
            suffix = PurePosixPath(raw).suffix.lower()
            summary[f"format/{suffix or 'none'}"] += 1
            if suffix in IMAGE_EXTENSIONS:
                summary["supported_images"] += 1
                summary[f"source/{parts[0]}"] += 1
        if summary["uncompressed_bytes"] > 2_000_000_000:
            raise ValueError("Archive is too large")
    return dict(sorted(summary.items()))


def import_archive(path: Path, photos_root: Path):
    summary = inspect_archive(path)  # finish validation before creating targets
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    batch = f"import_{digest[:12]}_{uuid.uuid4().hex[:8]}"
    root = photos_root.resolve()
    plan = []
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            if entry.is_dir():
                continue
            parts = PurePosixPath(entry.filename.replace("\\", "/")).parts
            suffix = PurePosixPath(parts[-1]).suffix.lower()
            if suffix in IMAGE_EXTENSIONS:
                if len(parts) < 2 or parts[0] not in {"team", "openimages"}:
                    raise ValueError("Unknown image source; review archive layout first")
                target = root.joinpath(parts[0], batch, *parts[1:])
            elif len(parts) == 1 and parts[0] in {"README.txt", "openimages_attribution.csv"}:
                target = root / ".imports" / batch / parts[0]
            else:
                continue
            resolved = target.resolve()
            if not resolved.is_relative_to(root) or target.exists():
                raise ValueError("Destination collision or escaped path")
            plan.append((entry, target))
        counts = Counter()
        for entry, target in plan:
            target.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation prevents overwriting even if a race occurs.
            with archive.open(entry) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            # ZipFile validates the entry CRC on read. Verify byte-for-byte SHA
            # against a second archive read; do not persist per-photo hashes.
            with archive.open(entry) as source, target.open("rb") as output:
                if hashlib.file_digest(source, "sha256").digest() != hashlib.file_digest(output, "sha256").digest():
                    raise ValueError("Extracted file integrity mismatch")
            counts["extracted_images" if target.suffix.lower() in IMAGE_EXTENSIONS
                   else "preserved_local_metadata_files"] += 1
    return {"inspection": summary, "import": dict(counts), "batch": batch}


def verify_import(path: Path, photos_root: Path, batch: str):
    """Read-only integrity and EXIF audit; returns aggregates only."""
    from PIL import Image
    from pose_analysis import load_photo, source_orientation
    if not re.fullmatch(r"import_[0-9a-f]{12}_[0-9a-f]{8}", batch):
        raise ValueError("Invalid import batch")
    inspect_archive(path)
    counts = Counter()
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            parts = PurePosixPath(entry.filename.replace("\\", "/")).parts
            if entry.is_dir() or PurePosixPath(parts[-1]).suffix.lower() not in IMAGE_EXTENSIONS:
                continue
            target = photos_root.joinpath(parts[0], batch, *parts[1:])
            if not target.resolve().is_relative_to(photos_root.resolve()):
                raise ValueError("Escaped verification path")
            with archive.open(entry) as source, target.open("rb") as extracted:
                if hashlib.file_digest(source, "sha256").digest() != hashlib.file_digest(extracted, "sha256").digest():
                    raise ValueError("Original image changed")
            counts["originals_unchanged"] += 1
            try:
                with Image.open(target) as raw:
                    exif = raw.getexif().get(274)
                    counts[f"exif/{exif if exif is not None else 'absent'}"] += 1
                    counts[f"decoded_format/{raw.format}"] += 1
                with load_photo(target) as image:
                    counts[f"corrected_orientation/{source_orientation(image.width, image.height)}"] += 1
            except (OSError, ValueError, SyntaxError, Image.DecompressionBombError):
                counts["invalid_image"] += 1
    return dict(sorted(counts.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--photos-root", type=Path)
    parser.add_argument("--verify-batch")
    args = parser.parse_args()
    if args.verify_batch and not args.photos_root:
        parser.error("--verify-batch requires --photos-root")
    result = (verify_import(args.archive, args.photos_root, args.verify_batch) if args.verify_batch
              else import_archive(args.archive, args.photos_root) if args.photos_root
              else inspect_archive(args.archive))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
