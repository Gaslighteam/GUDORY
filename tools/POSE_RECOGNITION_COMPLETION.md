# Pose Recognition Completion Report

Status: Python implementation, deterministic tests, dataset import, and native
real-photo execution complete; submitted for team review. Human-labelled accuracy and
Android verification remain pending.
Original baseline: origin/main `e75ae53` plus the team lead's explicit landmark,
eye fallback, and measurement decisions in this chat. The outdated `axes.dart`
was not ported. The independent `feat/tools` branch was safely fast-forwarded to
origin/main `9144c46` before preparing the pose-only review commit.

## Real-photo verification checkpoint — 2026-10-31 (Asia/Seoul)

Latest specification inspected: origin/main `9144c46`, including the square-photo
crop rule in AGENTS.md §5. No shared contracts or other owners' code changed.
The user explicitly approved preserving team and Open Images as separate sources.

### Import and original preservation

- Archive inspected BEFORE extraction: 799 files, 797 JPEG candidates, one README
  and one attribution CSV; 97,709,875 bytes uncompressed (~97.7 MB).
- Source folders: team 21, Open Images 776. Both remain separate under the MAIN
  checkout's `data/photos/`, in source-specific collision-free import directories.
- The source ZIP remains unchanged. README and attribution CSV are preserved
  under ignored `data/photos/.imports/`; import identifiers stay local.
- Import rejects unsafe paths, symlinks, Windows reserved names/ADS, case
  collisions, encrypted entries and excessive expansion. Files are exclusively
  created without overwrite; CRC and SHA-256 verified on extraction.
- After all native inference: **797/797 original images still match the archive
  byte-for-byte by SHA-256**. All images decoded successfully as JPEG.
- EXIF: 4 images had orientation 6 (corrected before analysis); 793 had no
  orientation tag. Corrected source counts: portrait 224, landscape 521,
  near-square 52. Near-square is inclusive 0.9 <= width/height <= 1.1.
- Images and local attribution metadata are gitignored. No raw images or
  per-photo rows/hashes/measurements are in this report or public output.

### Square-photo handling

Detect people/poses on the original EXIF-corrected image, then validate its
person count before cropping, so a crop cannot hide a second detected person.
For near-square inputs, try the largest exact-ratio image-centred 3:4 rectangle;
if the valid nose or either shoulder is outside it, try 4:3. Reject if both cut
any required landmark. Ratios use integer multiples of 3/4; any odd leftover
pixel is placed on the right/bottom (centre error <= 0.5 pixel).

Crops remain in memory. Landmarks are reprojected using
`xCrop = (xOriginal * width - cropLeft) / cropWidth`, and similarly for y.
Landmarks outside the crop become unavailable; framing and all composition
measurements are recomputed in crop-normalized coordinates. Original image bytes
are never rewritten. Future CLIP must use the identical rectangle helper.

32 candidates used a portrait crop and 6 used a landscape crop; 759 had no crop.
These are crop attempts, not a separate claim that every cropped candidate was
accepted. Near-square images rejected by the original person/pose validation
remain in the no-crop count. Zero candidates reached the both-crops-cut rejection.

### Native pose-only results

Ran the existing `tools/build_assets.py --pose-only` entry point independently on
the 21-photo team import and the 776-photo supplementary import. Both runs exited
0 using real model inference on the CPU (TensorFlow Lite XNNPACK).

| Outcome | Team | Open Images | Total |
|---|---:|---:|---:|
| Processed | 21 | 776 | 797 |
| Accepted | 8 | 544 | 552 |
| Rejected | 13 | 232 | 245 |

Accepted counts, in final shot/crop orientation:

| Orientation / framing | Team | Open Images | Total |
|---|---:|---:|---:|
| Portrait / chestUp | 3 | 19 | 22 |
| Portrait / waistUp | 5 | 39 | 44 |
| Portrait / kneeUp | 0 | 25 | 25 |
| Portrait / fullBody | 0 | 115 | 115 |
| Landscape / chestUp | 0 | 39 | 39 |
| Landscape / waistUp | 0 | 90 | 90 |
| Landscape / kneeUp | 0 | 52 | 52 |
| Landscape / fullBody | 0 | 165 | 165 |
| Total | 8 | 544 | 552 |

Portrait total 206; landscape total 346. Framing totals: chestUp 61,
waistUp 134, kneeUp 77, fullBody 280.

| Rejection reason | Team | Open Images | Total |
|---|---:|---:|---:|
| ambiguous_person_count | 13 | 159 | 172 |
| pose_count_mismatch | 0 | 47 | 47 |
| invalid_measurements | 0 | 20 | 20 |
| person_pose_mismatch | 0 | 6 | 6 |
| Total | 13 | 232 | 245 |

No invalid-image, detector-error, missing-model, invalid-person-evidence,
missing-required-landmark or square-crop-cut rejection occurred. Person-count
ambiguity includes zero candidates, multiple candidates, or a sole score below
0.5; these subcases were not separately logged. Thresholds were not relaxed to
increase acceptance. Counts describe the algorithm's decisions, not human labels.

### Models and verification

Downloaded from Google's official MediaPipe model links into ignored
`tools/.cache/` (no photo data is sent during model downloads):

- [Pose Landmarker Lite float16](https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task)
  SHA-256 `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.
- [EfficientDet Lite0 int8](https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/int8/latest/efficientdet_lite0.tflite)
  SHA-256 `0720bf247bd76e6594ea28fa9c6f7c5242be774818997dbbeffc4da460c723bb`.

Native initialization/inference succeeded. MediaPipe emitted nonfatal feedback
signature and NORM_RECT projection warnings. No inference exception was reported;
geometric accuracy still requires human review rather than inference success alone.

New files: `tools/import_photos.py` and `tools/test_import_photos.py`.
Updated: `tools/pose_analysis.py` (crop support and aggregate counters),
`tools/test_pose_analysis.py` (crop tests), and this report.
For submission, `build_assets.py` is a dedicated pose-only entry point. The
obsolete category/CLIP draft is preserved locally in ignored Tools cache and
excluded from the commit, alongside the unrelated model-downloader changes
and broader pyproject draft. Approved pose dependencies are pinned separately
in `requirements-pose.txt`; `tools/README.md` documents setup and invocation.

Remaining review items: visually label representative accepted/rejected examples,
calibrate person thresholds against those labels, check the 20 invalid spans and
6 pose/box disagreements, and verify Dart/Python parity when Eungyu's math file
is available. No precision/recall claim or Android-device verification is made.
Keep the archive's consent and dataset attribution conditions with the local data.
No required model/data blocker remains for this Python run.

Stopped at pose review: no CLIP clustering, recommend.json generation, weighted
levels, Dart recommender, or photo uploads. The user subsequently authorized
commit/push and a review PR for this milestone; Taeho handles merging.

## Completed and verified

- Reusable `pose_analysis.py`: pure landmark measurement, image loading,
  candidate acceptance, injectable detectors, and MediaPipe Tasks adapter.
- Four framings: chestUp, waistUp, kneeUp, fullBody. The lowest valid anchor
  pair wins even if an intermediate pair is missing. Both sides are required.
- Nose and both shoulders must be valid. Coordinates and visibility must be
  finite, with visibility >= 0.5; clamp each landmark x/y to [0, 1] before math.
- Fully decode images, apply EXIF rotation/reflection before either detector,
  and convert to RGB. Non-square orientation follows corrected dimensions;
  near-square handling is described in the real-photo checkpoint above.
- Reject missing/invalid images, unavailable/ambiguous person evidence, detector
  exceptions, pose/person disagreement, and invalid final measurements.
- `build_assets.py --pose-only` invokes this component without CLIP imports and
  prints only aggregate acceptance/rejection and orientation/framing counts.
  It writes no assets, per-photo rows, images, or embeddings.

Files changed for this milestone (all relative to the Tools worktree):

- `tools/pose_analysis.py` — new implementation and aggregate CLI.
- `tools/test_pose_analysis.py` — new deterministic synthetic tests.
- `tools/build_assets.py` — dedicated pose-only entry point.
- `tools/import_photos.py` — safe local import and integrity/EXIF audit.
- `tools/test_import_photos.py` — import safety and tamper detection.
- `tools/test_build_assets.py` — CLI routing and unsupported-operation checks.
- `tools/requirements-pose.txt` — approved pose-only dependency versions.
- `tools/.gitignore` — local SDK, tooling and cache exclusions.
- `tools/README.md` — pose setup and usage instructions.
- `tools/POSE_RECOGNITION_COMPLETION.md` — this report.

Existing Scene sources/tests, Tools model downloader changes, pyproject draft,
and existing category pipeline draft remain preserved outside the commit. The
submitted entry point requires `--pose-only`; asset generation is not exposed.

## Exact coordinate formulas

MediaPipe image-normalized landmarks: nose 0, left eye 2, right eye 5,
shoulders 11/12, hips 23/24, knees 25/26, ankles 27/28.
x increases right; y increases down in the EXIF-corrected image. Left/right
are anatomical labels, with no sorting by image x. Do not use world landmarks.

For each valid landmark use x'=clamp(x,0,1), y'=clamp(y,0,1):

```text
shoulderMidX = (leftShoulderX' + rightShoulderX') / 2
shoulderMidY = (leftShoulderY' + rightShoulderY') / 2
headTop = noseY' - (shoulderMidY - noseY') / 2
anchorMidY = (leftAnchorY' + rightAnchorY') / 2
h = anchorMidY - headTop
s = shoulderMidY - headTop
cx = shoulderMidX
cy = (leftEyeY' + rightEyeY') / 2  if both valid
     valid eye Y'                if exactly one valid
     noseY'                      otherwise
hy = null
```

Choose anchors in priority order ankles -> knees -> hips -> shoulders.
The derived headTop is not independently clamped: retain the exact specified
formula. Reject final measurements unless all are finite, 0 < s <= h <= 1,
and cx/cy are in [0, 1]. The h >= s check rejects an anchor above the shoulders;
invalid spans are rejected rather than silently repaired or reclassified.
No real-span ratios, head approximations, or horizon estimates are introduced.

## Person-count validation

1. Run PoseLandmarker in IMAGE mode with num_poses=2, allowing a second pose to
   be returned. Count all poses before filtering landmark confidence.
2. Independently run an ObjectDetector in IMAGE mode on the same corrected RGB,
   with category_allowlist=['person'], score_threshold=0.2 and max_results=-1.
   Supply a Tasks-compatible object model with the English metadata label
   `person`, such as EfficientDet Lite0. These are post-NMS object detections.
3. Require exactly one person candidate >= 0.2 and require its score >= 0.5.
   A sole weak candidate or any extra candidate in [0.2, 0.5) rejects the image.
   Duplicate boxes are conservatively treated as ambiguous, not merged.
4. Require exactly one pose and require its clamped nose and both shoulders
   inside that person's normalized box. Reject malformed boxes/scores,
   unavailable detector output, errors, or disagreement.

One returned pose alone never authorizes acceptance. Detector scores and the
0.2/0.5 person thresholds are an explicit initial filtering policy, separate from
the lead's fixed 0.5 landmark-visibility rule. They need real-photo calibration.

## Automated verification

Environment provisioned through bundled uv 0.13.6 with user approval:
Python 3.12.16, Pillow 13.0.0, NumPy 2.5.4, MediaPipe 1.2.0.
Only the existing Tools dependency subset was installed into `tools/.venv`;
Python and uv caches are local under ignored `tools/.cache`.

Run from `.worktrees/tools` in PowerShell:

```powershell
$env:UV_CACHE_DIR = "$PWD\tools\.cache\uv"
& .\tools\.uv\bin\uv.exe run --no-project --python .\tools\.venv\Scripts\python.exe python -m unittest discover -s tools -p test_pose_analysis.py -v
```

Initial milestone: **17 tests passed, zero skipped**. Tests verify all four framings and
numeric outputs; exact 0.5 visibility boundary; nonfinite/missing/low-confidence
landmarks; bilateral anchors; clamping before averaging; both/one/no-eye cases;
invalid spans; ambiguous/absent/multiple person evidence; pose/box disagreement;
all eight EXIF orientations; rotation pixel direction; invalid/missing/truncated
images; detector failures; and installed MediaPipe adapter configuration,
result conversion, and resource cleanup with mocked inference.

Also passed: `build_assets.py --pose-only --help`, Python compilation of all
three Python files, and `git diff --check`.

Latest expanded suite: **29 tests passed, zero skipped** (23 pose/crop tests,
4 ZIP-import/audit tests and 2 CLI tests), including post-import tamper detection. Use
`-p 'test_*.py'` in the unittest command above to run the entire suite.

Submission verification after syncing main and isolating the pose-only CLI:

- All 29 Python tests passed; zero skipped.
- Python syntax compilation and imports of all submitted implementation modules
  and installed pose dependencies passed. The upstream candidate helper also
  passed syntax compilation. `uv pip check` found no dependency conflicts.
- A fresh combined native run through the submitted pose-only CLI processed
  all 797 photos and reproduced every aggregate above: 552 accepted, 245
  rejected, 206 portrait and 346 landscape accepted. Exit 0.
- The read-only post-run audit again verified 797 unchanged original images,
  797 decoded JPEGs and the same EXIF/orientation counts.
- Flutter 3.44.8 / Dart 3.12.2: locked dependency resolution passed;
  `flutter analyze --no-pub` passed with no issues; `flutter build apk --debug
  --no-pub` succeeded. The existing flutter_tts future-Kotlin warning is
  nonblocking. APK compilation is not physical-device verification.
- The staged file list is restricted to the ten Tools files listed above.
  All staged changes are text; no photos, datasets, model weights, per-photo
  records, personal paths, generated caches, or unrelated CLIP drafts are staged.
  `git diff --cached --check` passed.

## Remaining limitations and 팀장 요청

- Native inference is now verified by the real-photo checkpoint above. Accuracy
  against human-labelled framing/person-count ground truth remains unverified.
- This filter cannot prove a photo contains exactly one person. Both detectors
  can miss small, obscured, edge-cropped, or low-confidence people, especially
  below the 0.2 person threshold. Model-internal proposal limits/NMS can also
  suppress people. False positives and duplicate boxes can reject good photos.
  Manual review remains necessary; no dataset-level precision/recall claimed.
- Model setup errors fail explicitly before batch processing. Per-image decode,
  inference, or result failures reject the image. Native hangs/timeouts are not
  solved by this synchronous offline component.
- Landmarks can be finite and confident while inaccurate. Per the lead's rule,
  out-of-image normalized landmarks are clamped and may still select an anchor.
- Request Eungyu to apply these same formulas and clamping rules in
  `composition_math.dart`; executable Dart/Python parity is pending that file.
- No physical Android test was performed: this milestone is Python only.
- CLIP clustering, recommendation JSON generation, weighted levels, and the Dart
  Recommender remain outside this completed milestone and await review.

Example (run in the Tools worktree, substitute an absolute imported source path):

```powershell
& .\tools\.uv\bin\uv.exe run --no-project --python .\tools\.venv\Scripts\python.exe python tools/build_assets.py --pose-only --photos ABSOLUTE_IMPORTED_SOURCE_DIRECTORY --pose-model tools/.cache/pose_landmarker_lite.task --person-model tools/.cache/efficientdet_lite0.tflite
```

Submitted for the mandatory team review checkpoint; do not merge automatically
or begin the recommendation pipeline without review.
