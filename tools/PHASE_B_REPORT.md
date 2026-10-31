# Phase B: spatially aware selection (experimental)

## B1: scope and feasibility decisions

Base: `5f89582b7deef5def4052a521c0233922c80fdfc`, the reviewed 414-prototype Phase A implementation published on `feat/scene-layout-prototypes-phase-a` in Draft PR #60. The original remote `feat/scene-layout-prototypes` instead points to `33bb8e87827ed49646a9623d38e9ac3b771c9bb8`, a different implementation with six-second stabilization. Its stabilization behavior is reused in isolation; the two branches are not merged. The reviewed Phase A itself did not include temporal stabilization, and its reported switching limitation must not be rewritten as already solved.

Worktree: `.worktrees/spatial-layout-phase-b`; branch: `feat/scene-spatial-layout-phase-b`. Main inspected at the implementation checkpoint: `528368f9f54176e2be18ab12064dacb487d9756f`. That main had no relevant core/Scene/dependency contract changes against the experiment; newer UI changes were not merged into the frozen experiment. Composition Director V1 is separate and untouched.

User authorization and repository ownership allow Tools and Scene changes. Core, camera, coach, providers, routing, Flutter dependencies and production recommendation assets are excluded. No new packages or models. Implementation originally stopped before publication; the subsequent publication request authorizes only a commit and ordinary push of the reviewed Phase B files, with no PR, merge or rebase. Production registration of the experimental path requires a separate team-lead integration decision.

MVP uses only spatial complexity/negative-space relationships (one feature category), with regional four-neighbor luma differences and 3x3 local luma range. These are not buildings, sky or important-object detectors. Dominant lines/vanishing points are deferred because robust line grouping/confidence would add unsupported assumptions. Horizon/sky/ground/water and semantic structures require reliable semantic evidence or an approved additional model and are excluded.

Feature input is one already-oriented, already-visible-cropped shot and its aligned person mask. Normalize geometry once outside the extractor. Nearest-center integer sampling gives 96x96 normalized shot coordinates; luma is `(77R+150G+29B+128)//256`. Exclude person confidence >=0.5 and a two-pixel halo before any gradients. Do not fill the person with mean color for spatial measurements. All nine regions require at least 25% observed pixels; overall coverage must reach 55%. No missing region is imputed as empty space. Low contrast/energy and confidence below 0.1 disable spatial scoring.

The complexity centroid and left/right/top/bottom asymmetry represent distributions of background edge/texture energy, never a semantic object center. Training records learn normalized relative offsets and placement/asymmetry interactions per supported prototype. A learned relationship can favor complex or open regions. It is not a hard rule to put people in low-complexity cells. Target coordinates are fixed prototype coordinates; a coordinate-shifting counterfactual is evaluated only offline because it would move held targets and create unsupported positions.

Python/Dart parity target for identical RGB/mask inputs is absolute error <=1e-9 for normalized features/confidence. Sensor color conversion, ML Kit versus MediaPipe masks and true physical-device behavior are separate end-to-end limitations; synthetic parity is not proof of natural camera-frame equivalence. Resolution and mask-translation perturbations are evaluated explicitly.

## Decision

The experiment is implemented, but the evidence does **not** justify production integration. The isolated Dart entry point defaults to `beta = 0` and does not extract spatial features by default. An explicit experimental caller can opt in. No production provider references this entry point, and production recommendation behavior remains unchanged.

After correcting a missing-statistics ranking hazard, the held-out source-relationship reconstruction error was 0.041602 for Phase B versus 0.041712 for equivalent Phase A without current-person hints: a tiny descriptive difference, with no significance or aesthetic interpretation. Historical Phase A with person context achieved 0.038628 and remained better. The source-relationship proxy uses the source photograph's observed placement; it is not an independent preference label. Do not retain this complexity in production on the strength of these results.

## B2: training, assets and privacy

All 5,603 local originals were read without modification. The frozen Phase A native pipeline was rerun from scratch: 3,256 pose-accepted, 3,233 CLIP-accepted (1,191 portrait / 2,042 landscape). Rejections were 1,850 ambiguous person counts, 334 pose-count mismatches, 84 invalid measurements, 75 person/pose mismatches, one missing required landmark, three square crops cutting the person, and 23 segmentation failures. Team samples retain weight 3 and supplementary samples weight 1. There are 44 accepted team samples and 3,189 accepted supplementary samples.

The original EXIF correction, square-photo crop, one-person validation, framing, segmentation, mean-color CLIP masking, embedding normalization, weighted levels and background clustering are preserved. Full reconstruction reproduces the production asset and all 414 Phase A prototypes exactly. A legacy pose-policy difference is deliberately frozen for this controlled comparison: the reviewed Tools baseline requires a visible nose and uses valid-eye fallback, while current AGENTS permits estimated nose/eye coordinates irrespective of visibility. Updating that policy would change the evaluation cohort and belongs in a separately reviewed rebuild, not this experiment.

Spatial features are computed before mean-color filling; individual RGB arrays, masks, embeddings, features, cohort memberships and held-out predictions stay in process memory. The extractor is available on 1,315 of 3,233 accepted photos (40.67%). It rejects 1,746 for coverage and 172 for low confidence. Large foreground subjects frequently prevent reliable coverage of every region. This is an intentional failure condition, not evidence of empty background.

Phase B replays the exact Phase A cohort partition and verifies each cohort's framing, count and centroid against its existing prototype. Only members with reliable spatial features contribute. At least **three actual photos**, not three units of source weight, are required per spatial record. Weighted means and population variances are stored for the 18 grid values, four relative-position values and four placement values (`cx, cy, h, s`). Record confidence is:

`weightedMean(featureConfidence) * n/(n+6) / (1 + 5*mean(placementVariance))`.

This heuristic discounts sparse and compositionally dispersed cohorts; it is not calibrated as a probability. There are 162 supported spatial records for 414 Phase A prototypes (39.13%). The support histogram is 3:67, 4:33, 5:22, 6:11, 7:5, 8:9, 9:4, 10:4, 11:2, 12:1, 13:2, 14:1, 19:1. Many records are barely above the privacy floor, so reliable discrimination is limited.

Experimental schema:

```json
{
  "schema": "gudory-spatial-layout",
  "version": 2,
  "feature_spec": "grid96-luma77-150-29-edge4-range9-dilate2-v1",
  "phase_a_sha256": "<canonical aggregate Phase A asset digest>",
  "records": {
    "p-<cluster>-<level>-<prototype>": {
      "n": 3, "w": 3, "confidence": 0.1,
      "grid": ["18 aggregate values"], "grid_var": ["18 aggregate variances"],
      "rel": ["4 aggregate values"], "rel_var": ["4 aggregate variances"],
      "placement_var": ["4 aggregate variances"]
    }
  }
}
```

The schema sketch uses descriptive array placeholders; validators require finite numeric arrays of the exact stated dimensions. IDs describe aggregate prototype positions, never photos. Root/record allowlists reject unknown fields, insufficient/excess support, invalid bounds and incorrect content links. Missing records are explicit absence, not zero-filled statistics. An invalid, missing or older sidecar disables spatial scoring. The asset is 178,553 bytes, below 1 MB; with the unchanged 144,588-byte A sidecar the total is 323,141 bytes. No new cluster embedding is published by B.

The outputs contain only cohort statistics, distributions, timings, counts and aggregate asset hashes. They contain no original filenames, photo IDs, photo hashes, URLs, GPS/EXIF records, images, private per-photo embeddings or per-photo results. `phase_b_parity.json` is explicitly public synthetic data generated by procedural patterns and basis-vector embeddings, not exported training examples. Original photo SHA-256 values are held only in memory for the before/after integrity check. No photo manifest or descriptor cache is written.

## B3: feature and scoring definitions

The spatial descriptor uses a 3x3 grid over 96x96 shot space. Integer nearest-center sampling is `floor((2*i+1)*dimension/192)`. Luma is `(77*R + 150*G + 29*B + 128)//256`. Person mask values >=0.5, their two-pixel Chebyshev halo and the two-pixel image boundary are excluded before regional measurements. The two per-pixel signals are the sum of four axial absolute luma differences divided by 1,020 and the 3x3 local max-minus-min divided by 255.

Each regional mean uses observed pixels only. The 18 grid values concatenate nine edge and nine texture means, each divided by `4*max(meanOfItsNineRegions, .005)` and clipped to [0,1]. Let `E_i` be the average of regional edge and texture means. Its weighted cell-center centroid is `(gx, gy)` and its right-minus-left and bottom-minus-top normalized energy asymmetries are `(ax, ay)`. A constant, uniformly complex or unobserved background supplies no reliable directional evidence.

Reliability requires every cell coverage >=0.25, whole-image interior coverage >=0.55, mean E >=0.005, `max(E)-min(E) >=0.005`, and confidence >=0.1. Confidence is:

`min(1,(minimumCellCoverage-.25)/.4) * min(1,(coverage-.55)/.3) * min(1,(max(E)-min(E))/.03)`.

For each supported, fixed prototype coordinate `(cx, cy)`, the relative feature is:

`[(cx-gx+1)/2, (cy-gy+1)/2, .5+(cx-.5)*ax, .5+(cy-.5)*ay]`.

The observed training relationships can prefer the complex side or the open side. Synthetic regressions verify both cases and verify that changing person color or moving a mask over a flat region does not create background structure. B has no current-person-distance bonus and cannot shift prototype coordinates to manufacture diversity.

Candidate retrieval retains same-orientation CLIP top-three clusters and chosen-level/nearest-level behavior. Spatial compatibility is:

`C = exp(-min(50, .3*mean((grid-meanGrid)^2/(gridVariance+.0025)) + .7*mean((relative-meanRelative)^2/(relativeVariance+.0025))))`.

Support `U = log(1+prototypeWeight)/log(1+candidatePoolWeight)`. For reliable query and record confidence, `b = beta*queryConfidence*recordConfidence`; otherwise `b=0`. With default offline experimental settings alpha=1, beta=0.8, gamma=0.08:

`score = (alpha*cosine + b*C + gamma*U)/(alpha+b+gamma)`.

All selectable scores are finite and normalized to [0,1]. Missing terms are omitted and the remaining weights renormalized. Spatial candidates must also have positive cosine >=max(0.15, bestCosine-0.08), so spatial compatibility cannot promote an unrelated weak-CLIP background. When no spatial term is active, equivalent A behavior is retained. A 0.005 raw-score tie band preserves Phase A support/count/order tie resolution; normalized tied scores are canonicalized for the temporal selector.

An initial implementation exposed a normalization hazard: a prototype without spatial statistics could win because other candidates received spatial penalties. The final coverage guard detects that outcome and reranks the whole pool using equivalent Phase A, instead of removing unsupported prototypes or treating absence as favorable evidence. It triggers on 236 held-out level queries. Targeted Python and Dart regressions cover this defect.

**Beta-zero equivalence has a precise scope.** It reproduces Phase A with equivalent weights and `position=0, framing=0`, including tie resolution, fallbacks and nearest levels. The historical 79.38% Phase A comparison supplied source `cx` and framing; B intentionally does not use those hints. Its valid beta-zero control is the separately reported 80.18% A-no-position ablation, not the historical context-enabled result.

### Runtime stability and failures

The original six-second selector is reused from the separate `33bb8e8` Scene implementation. It keeps both a target snapshot and the original selection time, including on repeated same-ID recommendations. Switching requires six seconds elapsed and a current-input normalized score advantage >=0.08. An incumbent outside the current retrieval top three is separately rescored for the margin comparison and cannot re-enter as a challenger. Non-positive-cosine incumbents have score zero. Context changes in level, orientation or mode reset selection. Transient feature/inference failures retain a valid held target; first-use failure uses A/legacy fallback. Async request epochs/tickets reject stale results.

The experimental class caches CLIP and spatial features together for three seconds; level changes can reuse them. Orientation, view geometry, lens metadata and frame-layout keys prevent inappropriate cache reuse. It exposes explicit mode and embedding invalidation hooks for future provider integration. Timed-out native operations stay single-flight until completion; late invalidated results cannot refill the cache. Parsing, inference and ranking failures do not escape `recommend()`.

Geometry is supplied by the caller through the existing SceneView snapshot. Spatial extraction reuses the same crop, rotation and front-mirror transform as CLIP, exactly once, before mask filling. Existing CLIP tensors remain unchanged when the optional extractor is used. No camera, preview, PoseSource or CoachEngine implementation was edited.

## B4: evaluation

The frozen embedding-hash split is the same as Phase A: 2,557 training photos (941 portrait / 1,616 landscape), 676 held-out photos (250 portrait / 426 landscape). All assets, level boundaries, clusters and spatial moments used in held-out selection are fit on training photos only. The train-only A asset has 332 prototypes and 120 spatial records. Five requested levels per held-out image produce 3,380 identical inputs per method. There are 273 reliable held-out feature inputs (80 portrait / 193 landscape), hence 1,365 feature-available level queries; 2,015 have no spatial evidence. B actually selects a spatially scored prototype on 527 queries. Among feature-available pools, 224 have complete spatial statistics, 542 partial statistics and 599 none. No valid-embedding query required legacy fallback in this comparison; separate failure tests cover it.

Near-center means `abs(cx-.5) <= .08`, or cx in [0.42,0.58], exactly as in Phase A. The full-training legacy final rate of 83.94% is distinct from the held-out identical-query legacy rate of 84.79% below. The source-relative proxy compares the four relative features at the recommended target with those at the held-out photo's observed person placement, at that photo's training-defined level. It averages absolute error on the same 273 cases for every method. Lower error means closer reconstruction of the observed relationship, not a better final photograph.

| Method | Left % | Near-center % | Right % | cx std | Relative proxy MAE | Distinct prototype tuples used |
|---|---:|---:|---:|---:|---:|---:|
| Legacy top-three | 8.31 | 84.79 | 6.89 | 0.06294 | 0.041665 | n/a |
| Legacy top-one | 14.38 | 71.89 | 13.73 | 0.09023 | 0.042729 | n/a |
| Phase A with historical person context | 8.52 | 79.38 | 12.10 | 0.07239 | 0.038628 | 324/332 (97.59%) |
| Phase A without position/framing hints | 7.90 | 80.18 | 11.92 | 0.06749 | 0.041712 | 244/332 (73.49%) |
| Phase B, beta=0.8, guarded | 7.84 | 80.33 | 11.83 | 0.06726 | 0.041602 | 249/332 (75.00%) |

Utilization counts distinct composition tuples, not necessarily distinct IDs when coordinates coincide. Lower center rate or higher utilization is not a success criterion by itself.

| Method | Portrait left / center / right % | Landscape left / center / right % | Level 2 left / center / right % |
|---|---|---|---|
| Legacy top-three | 2.88 / 94.64 / 2.48 | 11.50 / 79.01 / 9.48 | 9.62 / 77.51 / 12.87 |
| Legacy top-one | 7.36 / 84.32 / 8.32 | 18.50 / 64.60 / 16.90 | 15.83 / 66.27 / 17.90 |
| Phase A with context | 2.24 / 87.44 / 10.32 | 12.21 / 74.65 / 13.15 | 8.14 / 78.11 / 13.76 |
| Phase A without hints | 2.64 / 86.56 / 10.80 | 10.99 / 76.43 / 12.58 | 5.18 / 77.81 / 17.01 |
| Phase B | 2.64 / 86.64 / 10.72 | 10.89 / 76.62 / 12.49 | 5.18 / 77.81 / 17.01 |

Asymmetry persists: portrait left diversity remains low and Level 2 distribution is unchanged by B. These results oppose a claim that spatial features solve central bias or background-layout selection.

### Helpful and harmful cases, and failure investigation

Using an absolute proxy-error change tolerance of 0.005, Phase B is closer on 20 cases, farther on 16 and tied on 237 versus equivalent A without hints. Against historical A with context it is closer on 23, farther on 51 and tied on 199. These are **proxy outcomes**, not human preference votes. No actual photograph or individual prediction is exported to illustrate them.

Public synthetic examples demonstrate the intended mechanism: when observed training puts subjects at cx=0.2 with complexity on the right, the matching right-complexity query selects cx=0.2; swapping the background selects cx=0.8. A separate training fixture reverses the learned relationship and correctly selects the complex side, disproving a hard-coded low-complexity rule. Failure examples include insufficient visible background, flat/uninformative scenes, missing prototype statistics, and weak CLIP matches despite artificially favorable spatial compatibility.

Before the coverage guard, B proxy MAE was 0.042834, worse than 0.041712 for equivalent A; paired counts were 29 closer / 38 farther / 206 tied. That failed aggregate run is retained as `phase_b_initial_metrics.json`. The guard corrected the identified algorithmic hazard; it did not establish a useful photographic improvement.

An exploratory, predeclared beta sweep on the same holdout gives MAE 0.041520 (beta=.2), 0.041602 (.8), 0.041071 (2). These are diagnostic sensitivity results, not selection of a tuned optimum or independent confirmation. Training-set consistency is reported separately: A-with-context 0.034322, A-without-hints 0.036889, B 0.037068. Training consistency is not held-out evidence and B was slightly worse than its equivalent A control there.

A rejected coordinate-shifting counterfactual proposes a mean absolute cx change of 0.03368 on 212 conditional cases; every proposal leaves its original prototype, with conditional proxy MAE 0.040304. That subset differs from the full 273 cases, so its error cannot be compared as an overall win. It would introduce moving unsupported target coordinates and is not used by either runtime. Fixed candidate selection is preserved.

### Photographic preference and important elements

**Aesthetic quality, preservation of important background objects and practical achievable-shot quality remain unverified.** Edge/texture energy is not object importance. No human preference votes were collected or invented, and no marker-overlay quality claim is made.

For a future authorized local evaluation, use the same private held-out shots and achieved photographs, randomize A/B identity and left/right presentation, and collect only aggregate counts of A preferred / B preferred / tie / both unsuitable plus important-element preservation and achievable movement. Keep raw comparison materials local and do not publish photo identifiers or per-photo labels. This is a review protocol, not a labeling dependency for runtime recommendation. No public photo comparison pack is generated because the source photographs are private.

## Verification and reproducibility

- Python 3.12.16 through the existing uv environment: 96 tests passed (78 existing Phase A/baseline tests plus 18 Phase B tests). All Tools Python files parsed successfully; the three new runtime modules imported successfully. `uv pip check` checked 28 installed packages and found all compatible. No packages were installed.
- Pinned Dart 3.12.2: `dart analyze` passed with no issues.
- Pinned Flutter 3.44.8: `flutter analyze --no-pub` passed with no issues.
- `flutter test --no-pub test lib/features/scene`: 343 passed, three optional native-inference tests skipped because their explicit CLIP model environment flag was not set. They are not claimed as native Android/Python parity evidence.
- `flutter build apk --debug --no-pub --target lib/main.dart`: succeeded in 166.9 seconds. The normal-app APK is at `app/build/app/outputs/flutter-apk/app-debug.apk`; it was not installed or launched for this experiment. This build does not exercise the unregistered experimental class on a device.
- Identical synthetic RGB/mask feature and candidate fixtures match Python/Dart at absolute tolerance 1e-9. Coverage, mask boundaries, person color, mask translation, replicated resolution, portrait/landscape, camera crop/rotation/front-mirror transforms, beta-zero selection, learned complex/open preferences, weak-CLIP guard, malformed assets, fallback completeness, caching, stale async responses and incumbent rescoring are covered.
- The native frozen-dataset evaluator reconstructs production and Phase A assets byte-for-byte, rebuilds B twice including reversed input order, verifies zero repeated-query mismatches, and checks all 5,603 original photo hashes in memory before/after. Three complete independent native passes reproduced the same B asset SHA-256; the initial selection failure and corrected selection results are explicitly separated. Metrics timing fields are measurements and are not expected to be byte-identical.
- Strict spatial schema, canonical serialization, aggregate privacy-field checks, synthetic-fixture provenance and all ten orientation/level fallbacks passed. `git diff --check` passed; the index is empty. The local model, test log and APK are ignored by Git.

Asset integrity:

| Asset | Bytes | SHA-256 |
|---|---:|---|
| Unchanged production recommend.json | 107,801 | `75f3e9bc6c33c3536e4f04e7152ac9306582bd46a6b2f5cfa6a72f8c5a3c456c` |
| Unchanged Phase A experimental sidecar | 144,588 | `d069c3356e9fe3f25416076f885a3f9b41f045bea73c2c54cdeb37df029a9f82` |
| Phase B experimental sidecar | 178,553 | `d75e185450ffcb0a5663433e8447810b54b07d4cf832c2254fd5a18eee28a907` |

Reproduction uses the already approved Tools environment and existing model files. No package or model download is required:

```powershell
uv run --no-project --python <existing-python-3.12> -m unittest discover -s tools -p 'test_*.py'
uv run --no-project --python <existing-python-3.12> tools/evaluate_spatial_layout.py `
  --photos <complete-local-photos-root> --pose-model <existing-pose-model> `
  --person-model <existing-person-model> --segmentation-model <existing-selfie-model> `
  --clip-model <existing-q8-model> --beta .8
# In app/, using the pinned SDK:
dart analyze
flutter analyze --no-pub
flutter test --no-pub test lib/features/scene
flutter build apk --debug --no-pub --target lib/main.dart
```

The evaluator intentionally asserts the frozen 5,603/3,233 cohort and exact A/production reconstruction; a new dataset requires a separate baseline review rather than silently mixing experiments.

### Stability and cost

Deterministic static-photo replay uses the first 200 held-out photos with a synthetic one-second clock, not a video sequence. With current-incumbent rescoring, margins 0.04/0.08/0.12 produced 1/1/0 same-context switches respectively; there were zero switches before six seconds at every margin. The replay changes photographs and sometimes orientation, so it is not natural-video jitter or a human usability result. Unit and runtime tests separately verify exact six-second boundaries, the 0.08 margin, repeated-ID timer preservation, reset contexts and failure retention.

On this Windows host, the final Flutter feature microbenchmark measured p50 280 microseconds / p95 348 microseconds. Typed work-array payload is 46,080 bytes; that excludes caller RGB/masks, image conversions, object/list/isolate overhead, parsed assets and total runtime allocations. The final full-photo Python extractor measured 1.4815 ms median / 2.4115 ms p95; timing varies between complete runs. No physical Android latency, peak process memory or thermal result is claimed.

Stride-four RGB stress on the real accepted set produced zero availability flips across 1,315 jointly available inputs, mean grid absolute difference 0.008551 and p95 0.014729. This is useful sampling sensitivity evidence, **not** true NV21/MediaPipe-versus-ML-Kit camera parity. Identical-input numerical parity does not prove equivalent natural-camera masks or colors. A connected Android device was available, but Phase B was not installed or exercised there; the production app was not replaced.

Android feasibility remains plausible, based on small fixed work arrays, worker-isolate execution and no new models, but unverified on a physical device. A future isolated harness should compare the same consented oriented/cropped RGB and masks, then real camera/ML Kit outputs, on both landscape directions and portrait. Measure feature availability/error, selected IDs, normalized score deltas, total recommendation p50/p95, six-second holds, cache counters and memory under repeated level/zoom/lens changes. Decide parity tolerances from those measurements before enabling spatial scoring; do not call the RGB stress or host microbenchmark a pass for that gate.

## Files and ownership

All changes are confined to this new worktree, based at `5f89582b7deef5def4052a521c0233922c80fdfc`:
`C:\Users\kuson\projects\gudory\.worktrees\spatial-layout-phase-b`, branch `feat/scene-spatial-layout-phase-b`.

New Tools files: `spatial_features.py`, `spatial_layout.py`, `evaluate_spatial_layout.py`, `test_spatial_layout.py`, `layout_spatial.experimental.json`, `phase_b_metrics.json`, `phase_b_initial_metrics.json`, `phase_b_parity.json`, `PHASE_B_REPORT.md`.

New Scene files: `spatial_features.dart`, `spatial_features_test.dart`, `spatial_asset_digest.dart`, `spatial_layout.dart`, `spatial_layout_test.dart`, `spatial_test_fixtures.dart`, `experimental_spatial_recommender.dart`, `experimental_spatial_recommender_test.dart`, `candidate_stability.dart`, `candidate_stability_test.dart`.

Modified existing Scene file: `scene_embedding.dart` (optional extraction/transport; existing CLIP preparation preserved). No other tracked source file is changed. New test fixtures and experimental sidecars stay under these authorized directories; nothing is declared in the production asset bundle.

Existing Scene, Tools, Phase A, UI-preview and Composition Director V1 worktrees and drafts remain separate. Core, camera, coach, providers/routing, dependency declarations and production assets are unchanged. The authorized source publication does not register or enable the experimental path; no PR or merge is part of publication.

## Publication verification (2026-11-01, Asia/Seoul)

The existing Phase B branch and frozen base were preserved. Remote references were fetched to `origin/main` at `4c481ddfcf0c5d9c7ba67b698ce871b61ee56994`; the newer AGENTS changes concern UI behavior and do not alter this experiment's ownership, contracts or publication rules. No upstream changes were merged or rebased.

Before staging, all 20 intended files were reviewed. The full Python suite again passed 96 tests; all 28 existing Python packages remained compatible. Dart and Flutter analysis again reported no issues. The applicable Flutter suite again passed 343 tests, with the same three optional native-inference skips. The normal `lib/main.dart` debug APK rebuilt successfully in 24.6 seconds without installation. The host-only feature microbenchmark in this rerun measured p50 283 / p95 430 microseconds; the earlier implementation measurements above are retained as their own observations.

Python syntax/import checks, strict aggregate schema validation, canonical serialization and all three recorded asset hashes were rechecked. The original-name exclusion scan covered all 5,603 local photos and found none of their filenames in the publication files. The file list contains only intended Scene/Tools source, tests, aggregate JSON and this English report. No private images, per-photo records, model binaries, caches, secrets or temporary files are included. Production assets and unrelated modules have no diff. Spatial scoring remains disabled by default in the experimental runtime, which still has no production provider reference.

The three complete native builds and their aggregate comparison results were completed during implementation, as documented above. Publication verification did **not** rerun natural-image inference or invent another deterministic native rebuild result; the unchanged experimental bytes still match the verified digest. Physical Android performance and human aesthetic quality remain unverified.

## Remaining limitations and requests for the lead

The selected features do not detect semantic importance, horizon, vanishing points or structures. Availability and cohort support are low; confidence thresholds and variance floors are heuristic. One frozen embedding-hash holdout is not a scene/photographer-grouped generalization study; related backgrounds may cross the split. The proxy is tied to source placement and historical A's context creates an informational advantage. No significance, human quality or device-performance improvement is established.

Future integration requires the lead's approval for experimental asset declarations and an isolated device harness, plus explicit mode/orientation/preview-crop/lens/zoom/cache-invalidation snapshots from providers. None are modified here. A separate dataset-policy decision is needed before changing the inherited head/eye acceptance policy. The recommended current decision is to keep production unchanged, leave spatial scoring off, and retain these results as an offline experiment until stronger independent evidence exists.
