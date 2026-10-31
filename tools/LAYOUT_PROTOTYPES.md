# Phase A: composition modes and stable candidate selection

Status: implemented behind an explicit `loadLayoutAsset` opt-in. Not enabled in
production providers. No real-photo prototype asset has been generated yet.
Phase B spatial descriptors and Phase C production integration are gated on
real-data review. No aesthetic-quality improvement is claimed by these tests.

## Baseline diagnosis

Baseline main: `6e420da1a28d23d6a2211c8df20fe0bdfe5c61e6`.
Legacy asset: 107,801 bytes, SHA-256
`75f3e9bc6c33c3536e4f04e7152ac9306582bd46a6b2f5cfa6a72f8c5a3c456c`.
There are 103 background clusters and 303 supported cluster-level compositions.
With central defined as abs(cx-.5)<=.08, 210/303 (69.31%) are central; all 10
fallback targets are central. All 303 horizon values are null.

A read-only diagnostic replay of each normalized quantized cluster centre at
all five levels (515 queries) gives 420/515 central outputs (81.55%) under the
legacy top-three cosine*n average. A top-one-only averaging ablation gives
353/515 (68.54%). There are 85 cases with an off-centre top-one target but a
central averaged result. These are aggregate-centre probes, NOT camera queries,
photo beauty labels, or a measured live fallback rate. The source-photo position
distribution and live fallback frequency cannot be recovered from the asset.

## Python generation

`layout_prototypes.py` keeps the existing CLIP background clustering, level
boundaries and framing anchors. It separates composition modes only across
observable cx/cy/h gaps with at least three actual contributors on both sides.
It does not force L/C/R labels or a fixed number of modes. Continuous central
samples remain one mode. Each mode exports robust weighted aggregate h/cx/cy,
actual support, dispersion and a support/compactness confidence heuristic.
Confidence is not a probability of aesthetic quality. Candidates are never
averaged back into one target. No source row, filename, source-photo identifier,
per-photo embedding, crop or image is serialized.

`PrototypeConfig` exposes support, gap thresholds and the maximum mode count.
Minimum support cannot be less than three. These conservative thresholds still
need validation on real photos; correlated/diagonal patterns without a clear
axis-wise gap may deliberately remain unsplit.

The existing pipeline accepts optional `--layout-out`. Legacy JSON remains
unchanged in schema. Both outputs are computed from the SAME accepted samples,
models and deterministic background clusters. Layout serialization validates
centre/level correspondence, total support, IDs, normalized values, an explicit
field allowlist and the <1,000,000-byte size limit before any output replacement.
Never point experiment output paths at the committed asset/report.

Example after the existing approved environment/models are available:

```sh
# Run from this experiment worktree. Substitute the actual local source/models.
mkdir -p tools/.cache/layout-experiment
./tools/.venv/bin/python tools/build_assets.py \
  --photos "$PHOTO_ROOT" \
  --pose-model "$POSE_MODEL" --person-model "$PERSON_MODEL" \
  --segmentation-model "$SEGMENTATION_MODEL" --clip-model "$CLIP_MODEL" \
  --out tools/.cache/layout-experiment/recommend-baseline.json \
  --report tools/.cache/layout-experiment/report.md \
  --layout-out tools/.cache/layout-experiment/recommend-layout.json
```

The locally available 861-photo subset has immediate `team/` (85) and
`openimages/` (776) source folders. Pass THAT root, not an extra wrapper directory,
so the existing source weighting recognizes team images. Production report.md
records 5,603 processed / 3,233 accepted photos. The complete 5,603-photo input
has not been found locally. A paired 861-photo experiment must be labelled as a
subset experiment, not compared to the production asset as an algorithm-only
change. Do not replace missing photos with arbitrary images.

## Dart selection and stability

`LayoutPrototypeData` loads the optional sidecar and checks every background
centre against the loaded legacy asset. Missing/corrupt/unsupported sidecars use
the unchanged legacy matcher. Sparse prototype support does not promote a more
distant background: challengers are restricted to the legacy top-three
background retrieval set. Incumbents outside that set are still rescored on the
current input for hysteresis.

Phase A candidate score combines positive background cosine and the support /
compactness heuristic. `LayoutScoringConfig` exposes weights (initial .85/.15).
No spatial-structure or beauty prediction is implemented yet. Rank returns a
single candidate's actual aggregate target; no target coordinates are averaged.

`CandidateSelector` uses an injected monotonic clock, candidate ID and selection
time. Default minimum hold is SIX seconds; default switching margin is .08.
After the hold, compare both candidates' CURRENT-input scores before switching.
Recommending the same ID again neither resets time nor mutates its target
snapshot. Noise below margin, temporary inference failure and unsupported
candidate results preserve the last valid target. No new target is fabricated.
Level/orientation/mode changes clear the selection; late asynchronous results
cannot restore an old context. Configurable hold/margin are separate from the
CoachEngine's existing 1.5-second instruction hold.

## Lead integration request (outside approved edit scope)

No core, camera, provider or pubspec changes have been made.
After real-data review, the lead must:

1. Register the reviewed sidecar asset and pass its loader via
   `SceneRecommender(loadLayoutAsset: ...)`. No sidecar is bundled by this change.
2. Call `recommender.setMode(next.mode)` on each explicit mode change, including
   entering custom mode when there are no recommend() calls. Initialize it with
   the current mode. The scene class cannot observe camera mode without this
   hook; production mode invalidation is NOT claimed until it is wired.
3. Continue passing the existing crop/shot orientation. PoseSource and
   CoachEngine remain unchanged; cropping stays in coaching.dart exactly once.

New targets continue through existing Recommendation.target and CoachEngine.
The regression test verifies a candidate change resets a freshly held movement
instruction immediately and preserves raisePhone. Current main has manual
shutter by team decision; this experiment does not add automatic capture.

## Verification and gates

- New synthetic Python tests exercise mode separation, no forced side modes,
  weighted support, framing isolation, deterministic ordering, schema/privacy,
  and paired-aggregate generation without native models.
- Fake-clock Dart tests cover 5.9s/6s, score hysteresis, repeat-ID timing, context
  changes, failure retention, in-flight invalidation and CoachEngine reset.
- Legacy app and Scene tests are run together; Scene tests also live under
  lib/features/scene and are not covered by default test/ discovery alone.
- Host matching benchmark uses already-published aggregate medians solely as a
  load fixture; it is NOT a generated real-photo multi-mode dataset. Timing
  is printed as LAYOUT_HOST_ONLY and is not an Android latency guarantee.
- Real-photo rebuild, held-out human comparison, fallback-rate measurements,
  candidate stability on Android and spatial-descriptor efficacy remain pending.
- Existing full Python tests require the approved sklearn/MediaPipe environment.
  This machine currently lacks them. Optional native Dart inference additionally
  needs the matching macOS ONNX dylib; its absence must not be reported as an
  algorithm-quality failure or bypassed by renaming a different library.

Do not proceed to Phase B merely because off-centre recommendation frequency
increases. Review real-photo candidate support, relation to background and human
preference first. Do not commit/push/PR until the user reviews the experiment.

### Local results before isolated environment recovery

Flutter 3.44.8 / Dart 3.12.2:
- dart analyze: no issues.
- flutter analyze: no issues.
- flutter test --no-pub test lib/features/scene: 321 passed, 3 optional native
  inference tests skipped without CLIP_MODEL_PATH. This includes 27 new tests.
- flutter build apk --debug --no-pub: success. Compilation is not real-device
  verification; this fresh worktree does not bundle the ignored local CLIP
  weights or a real prototype sidecar.
- Explicit optional native tests with the verified local q8 path: 16 passed,
  3 failed because macOS libonnxruntime.1.15.1.dylib is not installed. No plugin,
  native library or dependency changes were made to bypass this environment gap.

Python:
- 14 new synthetic tests passed, including aggregate generation with precomputed
  synthetic background assignments. They do not claim real KMeans/native setup.
- Full suite: 65 attempted, 56 passed, 9 environment errors (7 sklearn missing,
  2 mediapipe missing). Existing requirements were not installed without review.

Isolated host-only matching measurement (100 aggregate-centre probes after warmup):
legacy p50/p95 51/95 microseconds; prototype ranking 66/109 microseconds.
These timings exclude CLIP/segmentation and are not Android performance claims.

Original coach work and Step 4 file hashes remain unchanged. No commits, pushes,
PRs or merges have been made. Phase B and production rollout remain pending.


### Isolated environment recovery checkpoint

The approved requirements were subsequently installed into tools/.venv on macOS
Apple Silicon; uv pip check passes. The three official Google model files were
retrieved into ignored cache and their SHA-256 values match tools/report.md.
Full Python tests and the paired real-photo experiment are being rerun. No
real-photo quality improvement or Phase B/C readiness is claimed at this point.
Local models, environments, data and experiment outputs remain excluded from Git.
