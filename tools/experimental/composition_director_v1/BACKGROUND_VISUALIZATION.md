# Background Analysis Visualization

## Outcome and scope

Implemented in `exp/composition-director-v1`, worktree
`C:/Users/kuson/projects/GUDORY-composition-director-v1`, base
`6083287c1953a96a1b9833a43557f1be4cd427eb`.
The separate Android app remains `com.gaslighteam.gudory.directorv1`.
No production module, shared contract, existing recommender, CoachEngine,
unrelated worktree, package manifest, or production Android file was edited.
No commit, push, PR or merge was made.

This is an observability change. Extraction, candidate generation/scoring,
action text/policy and stabilization source files have identical SHA-256 hashes
to the pre-change versions. Calibration rules are preserved. At the owner's
request after seeing flicker, diagnostic sampling was slowed from two Hz to one
Hz and line-opacity variation was reduced. This changes input cadence, not
composition scoring; three-sample calibration settling now takes roughly three
seconds, and the existing temporal/safety expiry rules still apply.

## Investigation: extraction vs visualization

**There was no two-line cap.** Both the Python and Dart extractors retain at most
**six** dominant segments. Both versions sort supported peaks by strength, merge
near duplicates, and stop when six survive. The original Android painter looped
over the entire retained list; it also had no top-two slice.

Actual deterministic fixture counts, reproduced from the Python implementation
and matched by the Dart parity suite:

| Scene | Portrait | Landscape |
| --- | ---: | ---: |
| Diagonal structure and nearby pole | 4 | 3 |
| Asymmetric clutter/open region | 2 | 3 |
| Approximately symmetric structure | 5 | 5 |
| Weak flat background | 0 | 0 |

A new procedural six-bar test returns **six** in both extractors. The actual
Android trace also reached **six** retained detections. These are real retained
segments, not extra strokes added to fill a display quota.

Algorithm limitations explaining fewer lines:

- Twelve normal directions (15-degree bins), two-pixel rho bins and bounded
  low-resolution analysis make detection deliberately coarse.
- Gradients below 28, insufficient support, runs shorter than 30% of the frame
  diagonal and poorly occupied runs are rejected.
- Collinear runs separated by a large gap are not joined. Nearby similar peaks
  are merged; this can also reduce the number of close parallel structures.
- Only the strongest six survivors remain. Earlier peaks rejected or beyond
  that existing cap do not influence scoring.
- Very dense texture (edge density > 0.4) clears the supported line list as noise.
- The existing mask gate requires nonempty/nonfull foreground and at least 35%
  observed background. No-person/mask-failure scenes can therefore have no
  usable structural results. Unknown is not interpreted as an open background.
- Masked neighborhoods are excluded from gradients. Their boundaries do not
  become manufactured person-outline edges.

Visualization limitations in the old screen were the missing heatmap/count,
one all-in-one overlay switch, and using current held orientation to project
an older result. The capture-orientation projection is now fixed. The existing
six-line extraction limit and all extraction thresholds were left unchanged.

## Which features influence scoring?

| Feature | Existing use, unchanged |
| --- | --- |
| Every retained line | Strength-weighted near-head/person intersection penalty and background structure covered by a candidate |
| Candidate cell texture | Clutter relative to the observed neighboring cells |
| Candidate cell edge density | Additional relative-space/clutter penalty |
| All nine cells' texture and coverage | Background mass and combined person/background balance |
| Coverage | Unknown-region penalty and selection of supported neighborhood statistics |
| Mean luminance/grid contrast | Feature confidence and scene-change detection |
| Grid changes over time | Target recomputation through the coverage-aware scene descriptor |
| Optional vanishing point | Diagnostic only in V1; no scoring bonus, as documented before this change |

**All retained lines reach scoring.** Both line-based terms iterate the full
retained list. A line outside a candidate's region can correctly contribute zero.
The new regression tests explicitly prove that the sixth line can change both
intersection and structure terms. Changing grid complexity also changes the
space term. No important background feature was found accidentally discarded
between extraction and scoring, so no scoring redesign or repair was needed.

Dart matches the Python core on the eight parity fixtures: retained line count,
feature confidence, cell coverage/texture, selected x/y/scale/framing/score, and
exact Korean instruction. This is fixture parity, not proof of equality on every
natural image. Native NV21 preprocessing and Pillow's optional adapter still have
the previously documented resize/rounding differences.

## Changes

- New `background_overlay.dart`: read-only display snapshot, mask-aware clipping,
  coordinate projection, line/heatmap painter and two independent controls.
- New `background_overlay_test.dart`: extraction/display/scoring, raster clipping,
  rotation, opacity, controls and recommendation-invariance checks.
- `live_analysis.dart`: attach the frame's captured quarter-turn direction to its
  result, with no model or pixel-processing changes.
- `diagnostic_page.dart`: independent **배경 선** and **복잡도** chips, detected and
  shown line counts, actual heat values/coverage, renderer timing and capture
  orientation. The existing layers icon now controls only person/target markup.
  The line counter reads the same snapshot as the painter, including after a
  target reset. No toggle resets or feeds the director/calibration.
- After the owner's flicker feedback: one-Hz diagnostic cadence, visible cadence
  and supported-cell count, and a narrower but still confidence/strength-driven
  opacity range. Unsupported lines are never padded, extrapolated or held as
  stale cached geometry.
- Python: two additional behavioral tests; no Python algorithm changes.
- Tools: extended aggregate device probe, source-hash audit and measurement /
  toggle-verification artifacts. All stay in the authorized experimental scope.

### Lines

The renderer processes the same **0..6** retained segments as scoring, with no
additional limit and no fabricated fillers. Strength controls stroke width and
opacity; scene confidence also modulates opacity. A narrower opacity range
reduces distracting brightness swings while preserving that relationship.

Foreground pixels and the same one-pixel margin used by feature extraction are
clipped out. A detected line may consequently appear as partial background
strokes; the count means retained detected segments, not a promise of six
unbroken strokes across the person.

### Heatmap

Each cell uses the actual `RegionCell.texture`: mean known-background gradient
magnitude divided by 64, capped to 0..1. The displayed number is that measurement
multiplied by 100. `bg` is the measured observed-background percentage. No new
complexity value, aesthetic score or inferred scene content is generated.

The translucent palette runs from blue (lower measured complexity) to orange
(higher). **Lower complexity does not mean a better composition.** Cells with
coverage below 0.5, or without a valid frame mask, show `—` / unknown styling.
Person-mask neighborhoods are clipped out of fills, line strokes and text.
Actual integer pixel-grid boundaries match the extractor's thirds. A compact
nine-value summary remains available when labels are partly occluded by the mask.

### Geometry

The preview shows the entire diagnostic 720x480 stream with letterboxing, not a
cover crop. The painter occupies the exact CameraPreview aspect rectangle.
Frame coordinates already include sensor rotation, mirroring and shot rotation;
projection only applies the inverse shot-to-portrait transform for that captured
frame. It never applies a second crop or mirror. Tests cover portrait and both
landscape directions, already mirrored/visible coordinates, and mask clipping.
The diagnostic uses the rear camera; front-camera behavior and production
still-photo crop parity were not physically tested by this task.

## Real Android verification

Device **SM-S937N**, Android **16/API 36**, ID **R5KYA00HPRW**. The device was
identified again with ADB/Flutter rather than assuming a stored target. USB
disconnected during testing twice; affected measurements were not treated as
successful live observations. The owner reconnected it. The existing Android
16 native-library alignment notice was acknowledged with OK after reinstall;
its checks/settings were not disabled and dependencies were not upgraded.

Build/launch succeeded using the existing isolated tools harness and pinned
Flutter 3.44.8 / Dart 3.12.2 SDK:

```powershell
# From the experiment worktree root
./tools/experimental/composition_director_v1/prepare_android_harness.ps1 -SyncOnly
# Then from tools/experimental/composition_director_v1/.android_harness
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME='C:\Users\kuson\AppData\Local\Android\Sdk'
& 'C:\Users\kuson\projects\gudory\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat' run --no-pub --debug -d R5KYA00HPRW -t lib/features/scene/experimental/composition_director_v1/diagnostic_main.dart --no-resident
```

No web target was launched and the production app identity was not used.

Actual observations, distinguished from synthetic tests:

- First overlay build: **561 live samples**, including
  **197 usable-mask samples**, up to **6 real lines**, and
  **197 distinct supported measured heat grids**.
- There were **0 count mismatches** between actual
  retained detections and the reported drawn count for enabled/disabled states.
- The owner reported that lines align and heatmap values change, **but not
  always**, with overlays dimming in/out. This is partial real visual validation,
  not a claim of perfect alignment. It prompted the cadence/opacity refinement.
- Final build: all four toggle combinations were exercised with on-device taps
  at observed UI-control bounds. Actual live-state logs verified each independent
  Boolean and the displayed count. Both overlays were left enabled. The
  on-device target generation did not reset during these checks; full replay
  tests provide stronger evidence that overlay options cannot alter scoring.
- Final measurement window: **100 updates**, all four
  modes observed, **0 count mismatches**, and
  **0 recorded director runtime errors**. This window
  had no usable person mask while the phone was flat; meaningful background
  variation was observed in the earlier overlay build, not fabricated for this
  final window.
- Live update counters and all control interactions continued. Paint CPU time
  remained small; visual camera FPS/GPU jank was not instrumented, so perfect
  preview smoothness is not claimed.

No camera image was copied off the phone. UI hierarchy and scalar/aggregate
logs were used. Stored artifacts contain no raw images, masks or person
coordinates.

## Performance

These are uncontrolled debug runs, not a locked-scene benchmark:

| Run | Samples | Pipeline median | Pipeline p95 | Update frequency |
| --- | ---: | ---: | ---: | ---: |
| Unmodified screen, 2 Hz | 150 | 158.65 ms | 195.45 ms | 1.93 Hz |
| First overlays, 2 Hz | 561 | 179.40 ms | 221.47 ms | capped at 2 Hz |
| Final one-Hz diagnostics | 100 | 183.45 ms | 233.69 ms | 0.98 Hz |

The observed final pipeline median is **24.80 ms higher (15.6%)** than
the baseline; p95 is also higher. A no-regression claim is not justified. Most
of the measured time is still native pose/mask and pixel preprocessing, which
varied across runs and device conditions. Display-only work was separately
measured:

- Overlay snapshot preparation: **0.65 ms median**,
  **5.83 ms p95**.
- Overlay paint CPU time: **0.80 ms median**,
  **1.66 ms p95**. This is not a GPU/raster presentation metric.
- Composition core: **1.79 ms median**,
  **5.26 ms p95** in the final fallback-heavy window.
- CPU snapshot: 150% to
  114% on the one-core=100% / device=800% scale.
  These are individual snapshots, not sustained averages.
- PSS: 537.4 to 586.3 MiB,
  including debug Flutter, models and camera.
- Battery sensor: 37.3 to
  39.1 C while USB connected. Thermal status
  remained 0. Thermal conditions, JIT/GC and live scene
  differences prevent attributing the overall change solely to visualization.

The one-Hz timing window was recorded before the final counter-binding correction; that correction only makes the text read the painter's snapshot. The pipeline timing stops before display preparation/painting, as before.
The separate renderer timings expose that additional work explicitly. One-Hz
sampling approximately halves analysis calls per second, not per-update latency
or all camera/native work. Calibration still uses real frames and original
expiry/settling rules; fewer samples per second affect when those rules can be
observed.

## Automated checks

- **324 Flutter tests passed**, including 24 focused experimental tests;
  **3 existing native CLIP tests skipped** because their opt-in model path is unset.
- **29 Python prototype tests passed** and **51 existing Python tests passed**.
- **Flutter analysis: zero findings**.
- The updated Android app successfully assembled/installed/launched using the
  separate diagnostic package. No new package/model was installed.
- Source SHA-256 audit proves extraction, scores, instruction policy,
  stabilization and diagnostic camera settings unchanged.

Raster tests verify six actual strokes, no filler lines, foreground/margin
exclusion, true low/high colors, missing-data handling, both rotation mappings,
independent controls, readable confidence-driven opacity and invariant scores /
Korean instructions across all overlay combinations. Synthetic test images are
procedural and are not real-device observations.

## Remaining limits

- A dropped/uncertain ML Kit mask still legitimately removes unsupported lines
  or heat values. The display does not keep stale geometry solely to hide that
  uncertainty. Further temporal mask/feature tracking would be separate
  algorithm work; it was not introduced here.
- The owner confirmed partial alignment/variation on the first build. The
  final slower style has not received a second human grading. Up to one update
  interval of visual lag can appear during fast camera movement; hold the phone
  still when inspecting correspondence.
- All four toggles were verified on-device, but final stable-scene alignment,
  calibrated movement quality, continuous preview FPS and production saved-photo
  geometry remain unverified. Do not interpret an attractive heatmap or passing
  tests as photographic quality.
- Coarse six-line extraction can miss or merge meaningful architectural lines.
  It is preserved deliberately; there is no two-line visualization bug to fix.
