# tools/ — local recommendation data pipeline

`build_assets.py` generates aggregate background clusters and five-level
composition targets from local photos. `--pose-only` retains the verified
pose-validation path. `pose_analysis.py` exposes the reusable measurement and detector APIs.
See [the completion report](POSE_RECOGNITION_COMPLETION.md) for exact formulas,
real-image results, model hashes, and the human review still required.

## Environment and tests

Run from the repository root (or the `feat/tools` worktree root), with Python 3.12
and uv. The pinned packages below were approved for the Tools environment; Flutter
dependencies are unchanged. On Windows:

```powershell
uv venv --python 3.12 tools/.venv
uv pip install --python tools/.venv/Scripts/python.exe -r tools/requirements-recommend.txt
uv run --no-project --python tools/.venv/Scripts/python.exe python -m unittest discover -s tools -p 'test_*.py' -v
```

## Recommendation generation

`app/assets/recommend.json` is a provisional snapshot and may be regenerated
when additional photos arrive. Each invocation recursively scans the complete
`--photos` directory (normally `data/photos/`), reruns pose and segmentation/CLIP,
and recomputes all weighted boundaries, clusters and fallbacks from scratch.
It never appends statistics to or trains from the previous JSON/report. No
per-photo cache is used; unchanged data, models, runtime and configuration retain
deterministic output. Keep generated outputs outside the input photo tree.

The fixed aggregate-only `recommendation_baseline.json` records the verified
797 processed / 548 CLIP-accepted / 8 portrait clusters / 14 landscape clusters /
23,478-byte snapshot and its asset hash. Future reports automatically compare
current totals against this baseline, with configuration-match and hash-match
indicators. `--baseline` can select another reviewed aggregate-only baseline;
the pipeline never overwrites it. Baseline values affect reporting only, not
training, clustering or composition calculations. No filenames, photo IDs,
per-photo measurements, image derivatives or new dependencies are needed.

The recommendation requirements add the separately approved ONNX Runtime and
scikit-learn dependencies to the pose requirements. For pose-only use, install
`requirements-pose.txt` and run only `test_pose_analysis.py`/`test_import_photos.py`.
The full pipeline reuses the existing bundled CLIP ViT-B/32 q8 ONNX vision encoder; it does not
download a second encoder or require PyTorch. Add Google's local
SelfieSegmenter square model
to ignored `tools/.cache/selfie_segmenter.tflite`.

```powershell
uv run --no-project --python tools/.venv/Scripts/python.exe python tools/build_assets.py --photos data/photos --pose-model tools/.cache/pose_landmarker_lite.task --person-model tools/.cache/efficientdet_lite0.tflite --segmentation-model tools/.cache/selfie_segmenter.tflite --clip-model app/assets/clip/vision_q8.onnx --out app/assets/recommend.json --report tools/report.md
```

Use the same command with an absolute `--photos` path if the dataset is in a
different checkout. `--team-weight` defaults to 3, `--supplementary-weight` to 1.
Source folders must remain separate; all non-team sources use supplementary
weight. No labels.csv, categories or text embeddings are used.

Segmentation errors/empty/full masks reject the sample instead of embedding its
person. The existing shot crop is reused before segmentation. CLIP uses RGB,
short-side 224 bicubic resize, centre crop and the exact mean/std from AGENTS.md
§5; outputs must be finite, 512-dimensional and L2-normalized. Pillow/Dart
interpolation parity on natural images still requires device QA.

Weighted inverse-CDF quintiles of person scale s determine the five levels per
orientation. Dominant framing and medians use source weights. Deterministic
weighted K-means targets about 20 actual photos per cluster, up to 64 per
orientation. Groups below three photos merge; unsupported cluster-level medians
are omitted. Missing fallback levels pool nearest levels of the same orientation
until there are three contributors of the dominant framing. Generation aborts if
an orientation lacks sufficient data. The report makes pooling/omissions explicit.

Only `recommend.json` and aggregate `tools/report.md` are written. The strict
schema allowlist excludes per-photo information; no embedding cache or image
derivatives are saved. The report includes model hashes and runtime versions.
See `report.md` for the latest actual counts and remaining quality-review tasks.

## Asset contract for the Dart recommender

Both orientations always contain four descending scale boundaries and valid
`fallback[orientation]['1'..'5']` compositions. Cluster `lv` maps are intentionally
sparse: a missing level is represented by an absent key, never an empty object or
zero-filled composition. This is the AGENTS.md rule for insufficient support.
Every exported level has at least three actual dominant-framing contributors.

The consumer must filter clusters to the requested shot orientation and prefer
entries containing the chosen level. If that level is unavailable, use the
nearest available level as specified in AGENTS.md; for an equal-distance tie,
the lower-numbered level is a deterministic choice. Select up to three nearest
background clusters. Use the top cluster's framing and combine only compatible
framings with cosine/support weights; never average spans across different
anchors. Cluster `n` counts all photos in that cluster, while `lv[level].n` counts
the photos contributing to that framing's composition. Neither is source-weight
mass. Decode `e` as 512 signed int8 values, divide by 127 and L2-normalize before
cosine comparison.

If there are no usable clusters/levels, invalid data or non-positive total usable
weight, return the requested orientation/level fallback. Model, asset or inference
failure must also use that fallback with `neighbors: 0` and `modelVariant: 'none'`.
These are consumer requirements only; Dart implementation is not included here.

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
The Dart Recommender and on-device recommendation validation remain separate
work and are not implemented by these Python tools.
