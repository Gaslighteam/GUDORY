# Phase A: offline layout prototypes

Offline experimental implementation, Phase A only, approved for publication as a Draft PR. Do not integrate this asset into the app or proceed to Phase B/C without the user's review. This is the existing multi-composition prototype experiment, separate from Composition Director V1. Recommendation aesthetics have not been validated.

## Repository and scope

- Base commit: `f0c878c227e2a4c996dc36f5e0d82c53b3afe7e2` (latest origin/main when this work began).
- Branch: `feat/scene-layout-prototypes`; isolated worktree: `.worktrees/layout-prototypes`.
- New files only: `tools/layout_prototypes.py`, `tools/evaluate_layout_prototypes.py`, `tools/test_layout_prototypes.py`, `tools/phase_a_baseline.json`, `tools/layout_prototypes.experimental.json`, `tools/phase_a_metrics.json`, and this report.
- Production `app/assets/recommend.json`, the Dart parser/recommender, contracts, CoachEngine, PoseSource, camera/providers, Flutter dependencies and existing worktrees are unchanged. This experiment does not run on the phone.
- The existing Python 3.12.16/uv environment and approved NumPy, scikit-learn, MediaPipe, Pillow and ONNX Runtime dependencies were reused. No packages or models were installed/downloaded.

## Frozen baseline and diagnosis

The legacy pipeline EXIF-corrects photos, validates one person, applies the approved near-square centre crop, segments the person, replaces person pixels with the whole-shot mean RGB, then runs the existing q8 CLIP ViT-B/32 encoder. Short side 224, bicubic resize, integer centre crop, exact mean/std, float32 NCHW, finite 512-vector and L2 normalization are unchanged.

Team source weight is 3, supplementary weight 1. Weighted K-means separates orientations, uses seed 0/n_init 10, targets about 20 photos per cluster and caps at 64. Small background groups merge. Per-orientation weighted quintiles of scale s define levels. Each cluster/level chooses one source-weight-dominant framing and independently takes weighted h/cx/cy/hy medians from that framing, with at least three actual contributors. Other framings and multiple layouts within the winning framing are lost.

The production Dart matcher first finds the globally nearest supported level within the requested orientation (lower number wins a level-distance tie). It scores eligible centres by cosine, keeps three positive matches, chooses the top match's framing, and averages only those three's compatible medians using cosine times actual level/framing n. It does not backfill a fourth cluster. This can average opposite positions into a central target not represented by any selected mode. Source weights already affect clustering and medians; runtime n is actual count, not source-weight mass.

Global orientation/level medians supply fallback when model inference/assets/matching fail. All ten current fallbacks are near center. Empty/invalid model queries and empty/nonpositive matches are tested separately from successful embedding queries.

Native reconstruction exactly reproduced the production 107,801-byte asset, SHA-256 `75f3e9bc6c33c3536e4f04e7152ac9306582bd46a6b2f5cfa6a72f8c5a3c456c`. Baseline source/median/matching statistics were recorded before experimental aggregation. The baseline matcher is an offline Python mirror of the current Dart rules, not a new Android parity certification.

Near center means inclusive cx in [0.42, 0.58]. Counts below are unweighted photographs, aggregate entries, or query cases as labeled; these denominators differ. Paired recommendation tests use exactly the same queries. Entry counts alone are not a causal estimate of median compression.

Both native runs processed 5603 originals: 3256 passed pose validation, 3233 passed CLIP/segmentation (1191 portrait/2042 landscape), and 2370 were rejected. Rejections: 1850 ambiguous person count, 334 pose-count mismatch, 84 invalid measurements, 75 person/pose-box mismatch, one missing required landmark, three square-crop cuts, and 23 segmentation failures. No additional photos were imported for this experiment.

| Stage | Left | Near center | Right | Near-center share |
| --- | ---: | ---: | ---: | ---: |
| Accepted source photos | 877 | 1372 | 984 | 42.44% |
| Exported legacy cluster/level medians | 52 | 210 | 41 | 69.31% |
| Legacy training-set recommendations (5 levels/photo) | 1546 | 13569 | 1050 | 83.94% |

The previously reported 103 clusters (43 portrait/60 landscape), 303 compositions, 210 near-center and 93 outside were recalculated and confirmed. Successful training-query matching used no fallbacks: 0/16,165. Thus the measured central concentration here is not caused by fallback use. Inference failures are excluded from this successful-embedding query population.

| Orientation | Accepted source near-center | Legacy median near-center | Legacy training recommendation near-center |
| --- | ---: | ---: | ---: |
| Portrait | 602/1191 (50.55%) | 93/117 (79.49%) | 5447/5955 (91.47%) |
| Landscape | 770/2042 (37.71%) | 117/186 (62.90%) | 8122/10210 (79.55%) |

Source-weighted near-center shares are 50.98% portrait and 37.85% landscape. Both median compression/dominant-framing loss and the second cross-cluster average contribute to the observed behavior; controlled fixtures isolate these mechanisms.

## Prototype generation

The experiment deliberately reuses the legacy background partitions, quantized centres, boundaries and fallbacks. No new encoder, background features or background clustering policy is introduced. Composition candidates are discovered separately for each background cluster, orientation, level and framing. Legacy omitted background groups are not added back.

Joint features are `[cx/0.12, cy/0.12, log(h)/0.35, log(s)/0.35]`. The fixed feature units are transparent heuristics, not learned optimal scales. We use weighted PCA to initialize a deterministic two-means split, then at most 40 weighted Lloyd updates. Accept a split only when:

- Weighted SSE reduction is at least 65%.
- Child-centre distance is at least 1.5 feature units.
- The gap along the child-centre direction is at least max(0.5, 3 times the median adjacent projected spacing).
- Only child cohorts with at least three actual photos can be exported. A separated unsupported cohort is omitted rather than folded back into the other mode.

Splitting recurses adaptively, at most eight leaves per framing/cell. If the cap would force a separated cohort to collapse, that unresolved cohort is omitted. No fixed left/center/right categories and no exactly-four layout assumption are used. A single mode/continuous cloud stays one cohort; absence of off-center data cannot create an off-center mode. A gap test on sparse/noisy data can still miss or misidentify modes; it is not a statistical guarantee of density modes.

Each cohort exports a joint source-weighted arithmetic centroid of h/s/cx/cy, not a per-photo exemplar and not an average across distinct exported prototypes. Shared framing keeps anchor spans comparable. A centroid remains within its cohort's joint convex hull; it is not guaranteed to equal an actual photographed composition. Horizon stays null. The support indicator is `confidence = (cohort weighted mass / cell weighted mass) * n/(n+6)`, a support heuristic, not calibrated confidence or aesthetic quality.

This method is lightweight for the small cell populations and avoids forcing high-k composition clustering into sparse groups. Most real cohorts remain unsplit. Three photos is the existing minimum aggregate privacy protection, not differential privacy or proof of independence/quality.

## Versioned experimental format

`tools/layout_prototypes.experimental.json` is a separate strict version-1 schema named `gudory-layout-prototypes`. It contains model/dim/quant, explicit split configuration, unchanged levels/fallback, and clusters `{o,e,n,lv}`. Each `lv[level]` is a list of prototype objects `{f,h,s,cx,cy,hy,n,w,confidence}`. Orientation/level are inherited from their enclosing keys. `n` is actual disjoint contributors; `w` is source-weight mass. No prototype IDs, file names, images, URLs or individual embeddings are stored.

Strict allowlists reject unknown fields, invalid coordinates, insufficient support, excess contributor counts, invalid centre encoding and oversized payloads. Sparse levels are absent. The production Dart parser is intentionally unchanged and must not read this experimental schema.

- 414 usable prototypes: 155 portrait/259 landscape; 102 clusters: 43 portrait/59 landscape. One eligible legacy cluster has no safely usable prototype and is omitted.
- 298 supported cluster/level cells; 94 have multiple prototypes. Seven cells have multiple modes within one framing, three contain supported same-framing left and right modes, and one of those cells has a near-center legacy median. These counts are heuristic discoveries, not independent mode labels.
- Actual maximum: three prototypes per cell, two per framing/cell. No default cap was reached.
- 2267 actual composition contributors (70.12% of 3233 accepted), versus 1889 (58.43%) contributing to legacy dominant-framing medians. All accepted samples still affect the original global boundaries/fallbacks and background fitting. Prototype n is not the count of all accepted photos.
- Support range 3-37; 150 cohorts have n=3, and 281/414 (67.87%) have n=3-5. Small-support uncertainty is substantial.
- Prototype framing counts: chestUp 61, waistUp 110, kneeUp 50, fullBody 193.
- Asset: 144,588 bytes (<1 MB), versus 107,801 production bytes (+36,787). SHA-256 `d069c3356e9fe3f25416076f885a3f9b41f045bea73c2c54cdeb37df029a9f82`.

The exported prototype entries themselves are 70.05% near-center, slightly more than legacy medians' 69.31%. Representation alone does not solve central concentration. Most extra candidates are minority framings; only a few same-framing side modes have enough clear support at this fine background/level partition.

## Automatic candidate selection

Choose the nearest available level within the requested orientation, then the three highest positive-cosine background clusters with usable candidates. Select one existing prototype; never average their incompatible compositions.

Default score is `cosine + 0.08*log(1+w)/log(1+candidate_mass) + 0.04*same_framing - 0.15*abs(candidate_cx-subject_cx)`. Subject terms are absent if no subject context is provided. Candidates within 0.005 of the best score resolve by weighted mass, actual n and canonical order. This deterministic tie band is not temporal hysteresis. The exact weights are configurable through `SelectionConfig`/`--selection-config`; split parameters through `PrototypeConfig`/`--prototype-config`. They were not optimized on the held-out data.

This is fully automatic: no object clicks, candidate picker, labels, pairwise ratings or manual evaluation of individual recommendations is needed to operate. It is also a heuristic selector: subject proximity can preserve an already-poor placement and cannot determine which background side has suitable negative space. Invalid/missing embeddings or no usable prototypes return the unchanged requested orientation/level legacy fallback.

## Paired automated evaluation

Full-data training consistency uses 3233 accepted embeddings times all five levels = 16,165 queries per algorithm. The holdout groups identical embedding bytes together using a fixed salted hash independent of composition labels. Train: 2557 (941 portrait/1616 landscape); holdout: 676 (250 portrait/426 landscape). Boundaries, legacy medians, backgrounds and prototypes are refit using training data only. The holdout has 3380 matched query cases per method.

This is one within-collection holdout, not scene/person/photographer-disjoint generalization. Near-duplicate scenes, repeated people and bursts can remain across splits because no identity labels exist. Training-set consistency is not generalization. No aesthetic labels are used or inferred.

| Query population / method | Left | Near center | Right | X standard deviation |
| --- | ---: | ---: | ---: | ---: |
| Full training, legacy | 9.56% | 83.94% | 6.50% | 0.06970 |
| Full training, prototype/background only | 9.52% | 78.48% | 12.00% | 0.07614 |
| Full training, prototype/subject context | 9.33% | 78.29% | 12.38% | 0.07423 |
| Holdout, legacy | 8.31% | 84.79% | 6.89% | 0.06294 |
| Holdout, prototype/background only | 7.90% | 80.18% | 11.92% | 0.06749 |
| Holdout, prototype/subject context | 8.52% | 79.38% | 12.10% | 0.07239 |

All these valid-embedding comparisons had zero legacy fallbacks and zero nearest-level substitutions. Separate deterministic fixtures test failed embeddings, nonpositive similarities, missing clusters and sparse prototype fallback. Neither zero observed fallback nor increased diversity certifies real-device inference reliability.

| Holdout orientation | Legacy left/center/right | Contextual prototype left/center/right |
| --- | --- | --- |
| Portrait (1250 queries) | 2.88% / 94.64% / 2.48% | 2.24% / 87.44% / 10.32% |
| Landscape (2130 queries) | 11.50% / 79.01% / 9.48% | 12.21% / 74.65% / 13.15% |

| Holdout level | Legacy near center | Contextual prototype near center |
| --- | ---: | ---: |
| 1 | 92.60% | 84.47% |
| 2 | 77.51% | 78.11% |
| 3 | 78.55% | 77.81% |
| 4 | 91.72% | 80.03% |
| 5 | 83.58% | 76.48% |

Overall held-out near-center share falls by 5.41 percentage points, mainly through more right-side targets. Left diversity does not uniformly improve: it decreases for portrait and without subject context overall. Level 2 becomes slightly more centered. Do not optimize away these findings or treat off-center percentage as beauty.

For actual-source-level queries, framing agreement is 430/676 legacy versus 551/676 contextual prototype. Within each method's same-framing subset, mean absolute cx error to the observed photograph is 0.13570 versus 0.12611; cy 0.08757 versus 0.08692; h 0.07722 versus 0.07892. Subsets differ, so these are descriptive consistency metrics, not a fair aesthetic loss or proof of better spatial reasoning. Background-only prototype errors are worse in cx (0.14009) and h (0.08224). Framing/position bonuses naturally favor the observed pose; this is not independent quality validation.

## Stability, controlled cases and performance

All duplicate identical-query checks return exactly identical results. For 200 held-out photos across both orientations, levels 1/3/5 give 600 perturbation queries per method. Identical L2-norm-0.01 embedding noise is used for both methods; subject perturbation is +0.01 in cx (clamped).

- Embedding noise: dx>0.02 occurs 1/600 legacy and 2/600 prototype; maximum dx 0.05187/0.04536. Prototype changes framing/status once, legacy zero times.
- Subject perturbation: legacy is unaffected by design. Prototype has dx>0.02 in 2/600, maximum 0.14721, and one framing/status change. Neither method shows a dx>0.16 transition in this sampled real-data check.
- Controlled counterexample: with equally supported modes at 0.2 and 0.8, subject cx 0.516 versus 0.526 crosses the tie boundary and switches target by 0.6. Legacy remains near 0.5. Discrete choice can therefore be less temporally smooth than averaging; no temporal hysteresis is claimed.
- Synthetic public fixtures explicitly cover similar-background left/right cancellation, a near-center median over separated source modes, one meaningful mode, sparse modes, similar supports, mixed framings and center/off-center subject positions. Supported left/right modes remain distinct; one-mode targets remain unchanged; insufficient 2+2 support uses the legacy fallback. These fixtures establish behavior, not real aesthetic outcomes.

Desktop CPython selection benchmark (300 calls, held-out trained asset) is approximately 0.06-0.07 ms median for either method in the initial run. Decoded centre arrays are 397,312 bytes legacy and 393,216 prototype (one fewer usable background cluster). Initial index-construction tracemalloc peaks are approximately 0.637/0.644 MB. Native extraction took about 548 seconds; one legacy aggregation about 7.2 seconds; prototype aggregation including repeated background fitting about 5.4 seconds. See `phase_a_metrics.json` for the latest run's measured timings; they vary with system load.

The final independent run measured median 0.03950 ms legacy / 0.04035 ms prototype, p95 0.06061 / 0.06479 ms, with the same 636,768 / 644,472-byte index-construction peaks. Its native extraction took 435.77 seconds and aggregation 5.55 / 4.66 seconds. The difference between runs illustrates timing noise; result distributions and asset bytes were unchanged.

These are desktop measurements, not Android timings, camera latency, total process/native-model RAM or retained Dart object memory. Already allocated asset objects and native model memory are not included in the index-construction trace. Model inference cost is unchanged. Extra serialized asset size and candidate metadata are the primary portable overhead estimates. No performance superiority is established.

## Verification and reproduction

Publication review reran all 78 Python tests, 16 source syntax checks, nine relevant imports, package compatibility, strict experimental schema/canonical serialization, all ten fallbacks, saved-result assertions and the aggregate privacy audit. The experimental asset, baseline and stable comparison fingerprints still match the completed checkpoint. The two complete native rebuilds described below were performed at that checkpoint; they were not repeated solely for publication. The held-out rates are validated saved results, not a newly rerun real-photo inference evaluation. Production files remain unchanged. All submitted Markdown is in English.

The repository-required pre-PR `flutter analyze --no-pub` check found no issues, and `flutter build apk --debug --no-pub --target lib/main.dart` succeeded using pinned Flutter 3.44.8 and existing cached dependencies in this isolated worktree. The local CLIP model and generated build files are excluded from the commit. The APK was not installed for this offline experiment, and these checks do not validate prototype behavior on Android.

- 78 Python tests passed (51 existing committed tests plus 27 Phase A tests); 16 Tools source syntax checks, nine relevant pipeline imports and all 28 installed package compatibility checks passed. No existing source/test was edited.
- Experimental schema, canonical serialization, minimum support, missing-level fallback, framing/orientation separation, source weights, joint relationships, strict privacy fields and deterministic selections are covered.
- Original photos and existing worktree files are checked using in-memory SHA-256 evidence; no per-photo manifest is saved. Both complete runs verified 5603 originals and 437 existing worktree files unchanged. Production asset is unchanged.
- Both complete native rebuilds produced byte-identical experimental and baseline assets. Each run also repeated prototype aggregation with reversed input order and matched exactly. Existing comparison metrics were identical after excluding timing noise and the added public synthetic switch-boundary probes; all real-query metrics matched. The final test run passed all 78 tests again. No per-photo cache was used between native runs.
- Aggregate comparison fingerprint (excluding timing and those additional synthetic probes): `71fe153d9e05d98ac14295204b20dd76d179713245e8b062c040c6208df1afa9`. Native Windows baseline SHA-256 (CRLF): `28ae44a93c6501f38f9d0617026d94070ec250a903bef13da0df34b559c737cb`. Repository baseline SHA-256 after required LF normalization: `81e5117298f4be5b9f392c2b31f6601d8ac82f66a032c50e22a825680a053fa3`. Git normalizes only line endings in the baseline/metrics JSON; parsed results and the stable comparison fingerprint are identical. The canonical experimental asset remains byte-identical with the SHA-256 reported above.

From this worktree, reuse the existing sibling Tools environment/models (PowerShell):

```powershell
$env:UV_CACHE_DIR='../tools/tools/.cache/uv'
& ../tools/tools/.uv/bin/uv.exe run --no-project --python ../tools/tools/.venv/Scripts/python.exe python -m unittest discover -s tools -p 'test_*.py'
& ../tools/tools/.uv/bin/uv.exe run --no-project --python ../tools/tools/.venv/Scripts/python.exe python tools/evaluate_layout_prototypes.py --photos ../../data/photos --pose-model ../tools/tools/.cache/pose_landmarker_lite.task --person-model ../tools/tools/.cache/efficientdet_lite0.tflite --segmentation-model ../tools/tools/.cache/selfie_segmenter.tflite --clip-model ../tools/app/assets/clip/vision_q8.onnx
```

Optional configuration example: `--selection-config '{"support":0.08,"position":0.15,"framing":0.04,"background":1.0,"tie_margin":0.005}'`. The evaluator always rebuilds from originals, never trains from the prior JSON, and only writes the aggregate experimental asset/baseline/metrics under tools. It does not regenerate production `recommend.json`.

## Limitations and Phase B decision

The reused reviewed pose pipeline still requires a visible nose and uses eye-visibility fallbacks, whereas current AGENTS.md permits estimated head landmarks for back/profile views. This pre-existing policy mismatch was deliberately not changed while comparing algorithms on identical accepted photos; a future policy-alignment change would require a separate dataset rebuild and baseline. Pose/count/segmentation errors and photographic source bias remain. Team photos contribute only 44 accepted samples versus 3189 supplementary, despite the 3:1 weight.

1. **Composition diversity:** modest measured improvement in final paired query distributions and retention of supported alternatives. Not uniform across directions, levels or representation-stage entries.
2. **Spatial consistency:** joint cohort relationships are retained by construction, and contextual pose-proximity metrics change. No background-structure consistency improvement is established: horizon, buildings, vanishing points and spatial grids are intentionally absent in Phase A.
3. **Aesthetic quality:** unmeasured. This experiment has not learned or validated beautiful compositions. No human preference labeling is requested or required for operation.

The evidence supports a limited offline Phase B hypothesis test after user review, not production replacement. A future proposal should assess automatically measured background compatibility and temporal switching, use additional grouped/split evaluations, and retain these baseline controls. Most cells are sparse, the representation remains centered, and discrete switching is a real risk. Phase B/C, production schema/parser changes and UI integration have not begun.
