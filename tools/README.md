# tools/ — pose-recognition milestone

`build_assets.py --pose-only` validates local photos using the four framings in
AGENTS.md §4. It reports aggregate counts and never generates recommendation
assets. `pose_analysis.py` exposes the reusable measurement and detector APIs.
See [the completion report](POSE_RECOGNITION_COMPLETION.md) for exact formulas,
real-image results, model hashes, and the human review still required.

## Environment and tests

Run from the repository root (or the `feat/tools` worktree root), with Python 3.12
and uv. The pinned packages below were approved for the Tools environment; Flutter
dependencies are unchanged. On Windows:

```powershell
uv venv --python 3.12 tools/.venv
uv pip install --python tools/.venv/Scripts/python.exe -r tools/requirements-pose.txt
uv run --no-project --python tools/.venv/Scripts/python.exe python -m unittest discover -s tools -p 'test_*.py' -v
```

## Native pose validation

Place the local Pose Landmarker Lite `.task` and EfficientDet Lite0 `.tflite`
models in ignored `tools/.cache/`. Download links and verified SHA-256 hashes
are recorded in the report. The object model must have the `person` label.

```powershell
uv run --no-project --python tools/.venv/Scripts/python.exe python tools/build_assets.py --pose-only --photos data/photos/team --pose-model tools/.cache/pose_landmarker_lite.task --person-model tools/.cache/efficientdet_lite0.tflite
```

The independent person detector and multi-pose detector must agree. Ambiguous
counts reject the image; a single pose alone does not prove there is one person.
EXIF is corrected before detection. Near-square images try an image-centred 3:4
crop then 4:3, with landmarks remeasured in crop coordinates. Originals are read
only; all crop computations and per-photo results stay in memory.

## Local dataset import

`import_photos.py` inspects ZIP contents before importing. It preserves `team/`
and `openimages/` sources in unique import directories and stores attribution
locally. Without `--photos-root`, the command only inspects the archive:

```powershell
uv run --no-project --python tools/.venv/Scripts/python.exe python tools/import_photos.py LOCAL_ARCHIVE.zip
uv run --no-project --python tools/.venv/Scripts/python.exe python tools/import_photos.py LOCAL_ARCHIVE.zip --photos-root data/photos
```

Use `--verify-batch IMPORT_BATCH --photos-root data/photos` to audit image bytes,
EXIF and source orientations against the ZIP, with aggregate output only.
Neither photos, attribution CSVs, per-photo measurements nor downloaded model
weights may be committed or uploaded. Local caches are ignored.

Existing `fetch_models.py` and `unsplash_candidates.py` remain separate utilities.
CLIP clustering, weighted recommendation levels and `recommend.json` generation
are outside this milestone.
