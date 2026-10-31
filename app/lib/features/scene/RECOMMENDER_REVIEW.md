# Dart Recommender implementation checkpoint

Draft implementation on `feat/scene`; landscape and production integration are
not fully verified. Existing Scene work is preserved. Main was fast-forwarded
to `e897ddb` for submission, including PR #29's asset, Coach integration and
the lead's latest specifications. The current asset
is 23,888 bytes, SHA-256
`baa49f324801e6dfd2ace43e4d5243845163222f8a1db7c596c5fbfdb4811e53`.

## Implementation and file ownership

All authored changes are inside `app/lib/features/scene/`:

- `recommender.dart`: `SceneRecommender implements Recommender`, safe warmup,
  lazy asset load/reload, deadlines, cache, backpressure, diagnostics and disposal.
- `recommendation_data.dart`: bounded aggregate parser, int8 decoding and
  renormalization, level selection, matching, medians and emergency fallbacks.
- `scene_embedding.dart`: injectable embedding interface and native mask/CLIP
  adapter; production preprocessing without PNG-preview allocation.
- `model_manager.dart`: offline bundled q8 implementation of `ModelManager`.
- `clip_runner.dart`: extends the existing runner with `runPixels`, injected
  `ModelManager`, worker-isolate session creation and a loaded-variant snapshot.
  The original still-image path, native output checks and worker Run remain.
- `recommendation_data_test.dart`, `recommender_test.dart`,
  `scene_embedding_test.dart`, `recommendation_test_fixtures.dart`: synthetic
  aggregate fixtures and focused tests, including desktop native integration.
- `debug_recommender_main.dart`: standalone Android QA consumer of the existing
  CameraService/FrameBus and held-orientation provider, without changing shared
  entry points or wiring.
- This report and `ANDROID_RECOMMENDER_CHECK.md`.

Original `preprocess.dart`, `person_mask.dart`, `nv21_frame.dart`, their tests,
Step 1/2 diagnostics and completion records are preserved. No category work is
deleted. No Tools drafts, contracts, Flutter dependencies or other owners' source
files were authored or changed. An automated Dart fixer briefly moved the
existing flutter_test declaration; that exact edit was restored and shared-file
diffs checked clean. No package installation was performed.

## Selection and failure rules

1. Require encoder metadata `clip-vit-base-patch32`, 512, int8; validate finite
   normalized compositions and descending orientation-specific boundaries.
   Quantized centres must have 512 signed values in [-127,127], norm within
   (0.85,1.15) before renormalization and actual support >=3. Sparse level keys
   are absent; `{}` placeholders are invalid. Corrupt clusters are discarded;
   valid fallback medians survive. Unknown root schema fails closed.
2. Use only requested-orientation clusters. Prefer the requested level if any
   same-orientation cluster has it. Otherwise choose the globally nearest
   populated level, with lower level winning an equal-distance tie. Do not fill
   an incomplete exact-level pool with different levels.
3. Compute cosine against renormalized centres and keep positive scores only.
   Sort descending, ties by asset order; select up to three clusters first.
   The first cluster determines framing. Discard incompatible framings without
   backfilling a fourth cluster. Never mix spans measured to different anchors.
4. Average h/cx/cy with weights `cosine * lv[selected].n` (actual contributors
   to this framing at this level, not the whole cluster's n). `neighbors` sums
   those actual contributor counts. Average non-null hy with its available
   weights; all-null stays null. Clamp roundoff to [0,1]. The source records the
   requested level, even when the selected level is a neighbor.
5. Missing/malformed assets, empty/no-positive clusters, invalid masks, failed
   inference, plugin errors and stage deadlines return the requested
   orientation/level median with `neighbors:0`, `modelVariant:'none'`, source
   `fallback`. When an asset median is unavailable, use embedded aggregate
   medians from the verified 797-photo baseline. These emergency values remain
   explicitly older than the preferred loaded 861-photo asset.
6. `recommend()` catches ordinary Dart exceptions and Errors, including
   synchronous failures from injected dependencies. No frame or embedding is
   written to disk. `warmUp()` tolerates optional model failures; asset reload is
   explicit (app restart normally reloads a newly bundled asset).

## Geometry, preprocessing and cache

`SceneView` supplies the portrait-preview crop and core-compatible quarterTurns:
0 portrait, +1 top left / rotate photo counterclockwise, -1 top right / rotate
clockwise. Validate it against the requested ShotOrientation. The default is
full-frame portrait; without a supplied landscape direction, return fallback
instead of guessing. The standalone diagnostic uses the full frame explicitly.

One owned NV21 snapshot is used for both ML Kit and RGB. Reuse the existing
stride-4 raw sampling, BT.601/VU decode and source-to-mask mapping. Rotate by
sensor orientation, mirror front RGB/mask together, apply the supplied portrait
crop once, then rotate both by -90*quarterTurns. Compute the rounded RGB mean
over that shot, fill person confidences >=0.5, resize short side to 224, centre
crop, RGB/255, exact CLIP mean/std, float32 [1,3,224,224], L2-normalized finite
[1,512]. Missing, invalid, empty or full masks fail closed to a composition
fallback; the old Step 2 diagnostics retain their independently verified behavior.

JSON parsing, RGB processing, session creation, native Run and cluster scoring
use worker isolates in the production path. ML Kit remains an asynchronous
platform call; a worker is not an extra camera owner.

One normalized embedding is held in memory for less than three seconds from
capture start, independent of level and across arriving frames with matching
geometry. Orientation/landscape side/crop/sensor rotation/lens/size/format/stride
metadata changes miss the cache. Call invalidateEmbedding for zoom changes,
pause/resume or an explicit fresh analysis. Clock rollback expires the cache.
Concurrent same-geometry requests join one job; incompatible busy requests get
their own orientation/level fallback. Invalidated or disposed jobs cannot publish
late matches. Model variant is captured when the session loads, so an external
manager update cannot relabel a still-open q8 session.

The default ten-second deadlines apply per asynchronous stage, not as a single
end-to-end stopwatch. A timeout is not native cancellation: the original job
remains occupied until completion, late results are discarded, and disposal
waits before freeing native resources. A permanently hung native call requires
app/process recovery; releasing its active session would be unsafe.

## Verified versus pending

- Draft submission rerun: **287 tests passed, zero skipped** (65 Scene and 222
  app tests after syncing the lead's new reference-analyzer tests). Two new
  regressions distinguish mask failure, empty clusters, invalid crop and
  orientation mismatch. Stage-specific scalar diagnostics were added to aid
  landscape diagnosis; they do not constitute a landscape fix or device pass.

- **231 automated tests passed, zero skipped:** 63 Scene (31 preserved + 32 new)
  and 168 existing app tests. Includes real local q8 ONNX worker-session/tensor
  inference and synthetic-mask background CLIP -> updated real aggregate asset
  matching with embedding reuse. This is Windows desktop native execution,
  not Android segmentation or device latency evidence.
- `flutter analyze --no-pub`: no issues.
- Android standalone debug APK built with target
  `lib/features/scene/debug_recommender_main.dart`; existing nonblocking
  flutter_tts future-Kotlin compatibility warning remains upstream.
- Ten fallbacks in the merged asset parsed; schema/canonical aggregate counts
  are covered by the current-asset test. No raw/per-photo data or weights added.
- Physical Android smoke checks subsequently ran on SM-S937N / Android 16 after
  USB authorization became visible. The diagnostic APK installed successfully;
  camera/segmentation initialized, portrait q8 matching and cached 1/3/5 changes
  passed. Inference-failure and missing-asset injections returned valid fallbacks,
  and both switches were restored. See `ANDROID_RECOMMENDER_RESULTS.md` for exact
  scalar evidence and checks that remain unverified.

Performance/quality still requires Android measurement: full-resolution ML Kit,
frame snapshot/packing, Dart isolate startup/transfers, first model copy/session
warmup and quantized inference all contribute. Cached level changes skip masking,
RGB preprocessing and CLIP but still transfer/score the bounded aggregate asset.
Live RGB uses the preserved stride-4 point sampling; Python uses full images.
Pillow and Dart bicubic implementations can differ. Natural-image embedding
parity, portrait/landscape mask alignment and recommendation quality are not
proved by synthetic tests. Levels order person scale s; raw h across different
framings must not be forced monotonic.

## 팀장 요청 — production integration

The current asset declaration and clip directory are already present in
pubspec.yaml; no new declaration or dependency is required. Shared
`recommenderProvider` still returns FakeRecommender. The lead should replace it
with a lifecycle-owned SceneRecommender and supply the existing geometry:

```dart
final recommender = SceneRecommender(viewForFrame: (_, orientation) {
  final held = ref.read(heldOrientationProvider);
  if (held.orientation != orientation) throw StateError('Orientation changed');
  final crop = ref.read(visibleCropProvider); // portrait preview coordinates
  return SceneView(quarterTurns: held.quarterTurns, left: crop.left,
      top: crop.top, width: crop.width, height: crop.height);
});
ref.onDispose(() => unawaited(recommender.dispose()));
return recommender;
```

The lead owns provider imports and lifecycle/zoom invalidation wiring. Do not
pass cropInShotSpace output here: the pipeline performs that rotation once.
Use a new embedder/recommender instance if selecting a different model after
warmup. Default q8 is offline only; automatic fp16 download is not implemented.
Human/device review and this shared wiring are the remaining integration tasks.
