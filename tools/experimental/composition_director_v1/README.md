# Experimental Composition Director V1

Isolated offline prototype. No production camera integration, network calls,
LLM, new model, package installation, commit, push, PR, or merge.

## Android follow-up

Current background diagnostics add independent line/complexity controls and
one-Hz sampling. See [background visualization report](BACKGROUND_VISUALIZATION.md)
for the extraction/scoring investigation, live checks, performance and limits.

The isolated Dart Android diagnostic is now implemented and installed as a
separate app. See [Android device report](ANDROID_DEVICE_TEST.md) for exact build
isolation, launch command, actual observations, measurements and owner test steps.
The rest of this README records the original Python-only V1 stage.

## Repository isolation

- Branch: `exp/composition-director-v1`
- Worktree: `C:/Users/kuson/projects/GUDORY-composition-director-v1`
- Base: `6083287c1953a96a1b9833a43557f1be4cd427eb` (fetched `origin/main`)
- Original checkout remains on `feat/scene` at
  `2d64f99d3164e880703dac95d9e33877e59ed00a`.
- Existing worktrees, branches, and uncommitted files were preserved.
- All deliverable files are new under
  `tools/experimental/composition_director_v1/`. No tracked base file changed.

## Run

Use the existing Python 3.12 tools environment; the decision core and procedural
runner use the standard library. The optional RGB adapter uses existing Pillow.
From the worktree's `tools/` directory:

```powershell
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONIOENCODING='utf-8'
python -m experimental.composition_director_v1.runner
python -m experimental.composition_director_v1.runner --benchmark
python -m unittest experimental.composition_director_v1.test_director -v
python -m unittest discover -s . -p 'test_*.py' -v
```

`--input <local.json>` accepts one `Frame` record or a sequence, with an optional
`person` object matching `types.py`. Pixels and person-mask confidence values
must already describe the same visible saved-shot frame. There is no automatic
file upload or photo persistence. Real-input CLI records get no simulated safety
or motion evidence, so uncertain movement produces hold. Library callers can
supply a `Context` with genuine recent observations. Do not use the simulated
fixture context with a real camera. Private input/output stays local and must
not be added to Git.

## Files

| File | Purpose |
| --- | --- |
| `__init__.py` | Package marker |
| `types.py` | Internal scene, person, candidate, measured-motion, action contracts |
| `adapter.py` | Reuse decoded visible RGB, segmentation confidence, and pose landmarks |
| `features.py` | Mask-aware gradients, supported Hough segments, 3x3 occupancy/complexity |
| `candidates.py` | Deterministic candidates, configurable scoring, one selected alternative |
| `actions.py` | Actor-specific evidence gates and Korean sentence construction |
| `director.py` | Stable target, cooldown, observation feedback, hysteresis, fallback |
| `fixtures.py` | Original procedural scenes and explicitly simulated movement evidence |
| `runner.py` | End-to-end demonstration, local JSON input, small desktop benchmark |
| `test_director.py` | Focused deterministic behavioral checks |
| `synthetic_results.jsonl` | Synthetic scene outputs and aggregate desktop benchmark |
| `.gitignore` | Exclude bytecode and disposable validation copy |
| `README.md` | This report and future integration requests |

## Algorithm

1. **Visible geometry.** `Frame` uses normalized x-right/y-down coordinates in
   the actual visible saved-shot orientation. No module rotates, mirrors, or
   crops a second time. Input analysis dimensions are bounded at 128 per side;
   the optional adapter defaults to a 96-pixel longest side. The adapter pools
   foreground confidence conservatively and shares the original normalized pose.
   Only both shoulders require visibility >= 0.5; finite nose/eye estimates are
   used regardless of their visibility. Head top is nose y minus half the
   shoulder-to-nose span, and eye y is the two-eye mean, per AGENTS.md.
2. **Background evidence.** Exclude person-mask neighborhoods, including a
   one-pixel boundary margin. Compute central gradients on known background
   only. Each grid cell records observed coverage, edge density, mean gradient
   complexity, and mean luminance. Masked pixels remain unknown; they never
   become empty space or artificial silhouette edges. Unknown cells do not
   contribute fabricated contrast. Missing/full masks fail closed.
3. **Dominant lines.** A bounded, gradient-aligned Hough vote uses 12 normal
   angles and two-pixel rho bins. Require enough support, a sufficiently long
   contiguous run, and coverage along the segment; merge near duplicates and
   retain up to six. Reject saturated noisy texture. Angle/strength are exposed.
   An optional vanishing point requires at least three reliable lines agreeing
   inside the observed image. Two crossing lines alone do not establish it.
   No horizon is invented. Vanishing points are diagnostic in V1, not a scoring
   preference.
4. **Candidates.** Vary current/local/grid-region x, local eye y, and scale by
   up to 20 percent. Choose the deepest already-observed anchor that geometrically
   fits at each placement; do not relabel the same full-body placement as waist
   up. Reject insufficient head/side/bottom margins. Do not evaluate background
   beyond the visible rectangle or invent previously hidden body anchors.
   Five configurable emphasis preferences use head-to-shoulder scales
   0.22/0.16/0.10/0.075/0.05. These are experimental priors, not dataset quintiles.
5. **Scoring.** `Weights` controls penalties for observed segment intersections
   and near-head clearance, relative local clutter, background structure covered
   by the person, combined person/background mass imbalance, level/scale error,
   displacement effort, and poorly observed regions. Low edge density alone is
   not an aesthetic-quality reward. Retaining an already acceptable off-center
   placement is allowed. Choose the single highest-scoring candidate; no averaging
   of incompatible compositions. Every score term is returned for inspection.
6. **Action.** Evaluate measured local responses for each actor independently.
   A response describes changes in x, eye y, and scale per positive step/fist:
   right/forward/up. Compare predicted error reduction for a half-unit action.
   A subject move and a camera move have separate responses; camera motion also
   requires evidence that background structure is preserved. No static-image
   assumption equates them. Require confidence >= 0.7, calibration age <= 5 s,
   fresh direction-specific safety evidence <= 2 s, matching geometry epochs,
   valid predicted geometry, and meaningful expected improvement. Select the
   best feasible error reduction, then construct one Korean sentence. Output
   actor, direction, approximate magnitude/unit, confidence, validity, and reason.
   Confidence is a heuristic indicator, not a calibrated probability.
7. **Feedback.** Keep the selected target and its baseline descriptor stable.
   Wait at least 1.5 s after a movement; return a non-actionable hold while
   observing. Confirm improvement in both total error and the instructed axis.
   With no progress or worsening, hold and require reassessment instead of
   repeating or immediately reversing. Reset on significant scene change,
   lens/crop/zoom/shot-direction epoch, orientation or level changes, and person
   loss. After six seconds, an unsettled target may be replaced only with a
   meaningful score advantage. Entry/exit tolerances keep an acceptable
   composition steady. Capture means a manual shutter instruction, never an
   automatic shutter trigger.

A movement instruction requires externally supplied measured response and
safety evidence. V1 does not discover traversable ground from an RGB photograph
and does not bootstrap calibration by asking someone to move without evidence.
Its normal conservative result for an uncalibrated live scene is hold.

## Synthetic examples

All scenes are procedurally generated in `fixtures.py`; no third-party or private
photographs, source filenames, or per-photo embeddings are included. The
coordinates below are shoulder x, eye y, and head-to-shoulder scale.

| Scene | Supported lines | Selected (x, y, scale) | Direct Korean instruction |
| --- | ---: | --- | --- |
| synthetic/portrait/diagonal | 4 | (0.78, 0.20, 0.10) | 모델님, 촬영자 기준 오른쪽으로 반 걸음 이동해 주세요. |
| synthetic/portrait/asymmetric | 2 | (0.46, 0.20, 0.10) | 모델님, 촬영자 기준 오른쪽으로 반 걸음 이동해 주세요. |
| synthetic/portrait/symmetric | 5 | (0.50, 0.20, 0.10) | 촬영자님, 그대로 유지하고 셔터를 눌러 주세요. |
| synthetic/portrait/weak | 0 | (0.50, 0.20, 0.10) | 촬영자님, 잠시 그대로 유지해 주세요. |
| synthetic/landscape/diagonal | 3 | (0.50, 0.20, 0.10) | 촬영자님, 그대로 유지하고 셔터를 눌러 주세요. |
| synthetic/landscape/asymmetric | 3 | (0.46, 0.20, 0.10) | 모델님, 촬영자 기준 오른쪽으로 반 걸음 이동해 주세요. |
| synthetic/landscape/symmetric | 5 | (0.50, 0.20, 0.10) | 촬영자님, 그대로 유지하고 셔터를 눌러 주세요. |
| synthetic/landscape/weak | 0 | (0.50, 0.20, 0.10) | 촬영자님, 잠시 그대로 유지해 주세요. |
| synthetic/after-movement | 3 | (0.46, 0.20, 0.10) | 촬영자님, 그대로 유지하고 셔터를 눌러 주세요. |

The diagonal fixture includes an observed pole near the head. The asymmetric
fixture starts the person in a more cluttered left region. Symmetric scenes can
retain both centered and already off-center people. Weak scenes hold. The
movement sequence retains the selected target after a simulated half step and
stops adjusting once it is acceptable. Portrait and landscape line extraction
can differ because their pixel geometry differs; the method does not assume
identical detected structures after changing aspect ratio.

Additional action-sign checks cover separate subject/camera left/right
responses, camera forward/backward and phone up/down, unsafe or stale evidence,
and predicted overshoot. With simulated calibrated distance response, level 1
selects a larger local scale and can say "촬영자님, 앞으로 반 걸음 이동해 주세요.";
level 5 selects a smaller local scale and can say
"촬영자님, 뒤로 반 걸음 이동해 주세요."

## Validation

| Check | Result |
| --- | --- |
| Prototype behavioral suite | 27 passed, Python 3.12.16 |
| Existing production Python suite | 51 passed |
| Existing Flutter camera/core/coach/feedback/scene suite | 300 passed, 3 native CLIP tests skipped |
| `flutter analyze --no-pub` | Zero issues |
| Android device inventory | `adb devices -l` returned no connected devices |
| Real Android feature validation | Not performed; no device available and no app integration |
| Debug APK build | Not performed; prototype is an isolated Python runner |
| Scope verification | No tracked base file changed; production modules/assets unchanged |

Flutter checks used the existing pinned Flutter 3.44.8 / Dart 3.12.2 SDK and
cached dependencies. A disposable, byte-for-byte source copy was created under
this tools directory, with the existing package configuration and expected asset
directories, so production app source and build configuration were untouched.
Commands in that copy were `flutter analyze --no-pub` and
`flutter test --no-pub --no-test-assets test lib/features/scene --reporter expanded`.
The three skips require `--dart-define=CLIP_MODEL_PATH=...`; no native CLIP
inference is claimed. The disposable copy was removed after checking.
No packages were added or installed.

The 27 prototype checks cover deterministic selections in both orientations and
all five levels, line overlap reduction, asymmetric available space, symmetric
and off-center stability, weak/noisy fallback, mask-boundary and fully occluded
cell handling, vanishing-point reliability, framing consistency, actor-specific
movement signs, safety/calibration expiry, camera structural preservation,
overshoot, cooldown, observed progress, blocked repetition, no rapid reversal,
scene/geometry invalidation, malformed observations, and adapter/pose formulas.

## Performance

Measured on this Windows AMD64 host, Python 3.12.16, over
80 updates on eight synthetic 72x96/96x72 scenes after 24 warmups:

- Median: **10.84 ms** per update.
- p95: **12.09 ms**; maximum: **13.45 ms**.
- Separately traced peak Python allocations: **411,116 bytes**
  (401.5 KiB). This is not total process RSS.

Includes feature extraction, candidate selection, and action decision. Excludes
image decoding/resampling, pose, person segmentation, CLIP, camera I/O and
Android runtime. Tracing was measured separately from timing. These are desktop
prototype costs, not evidence of real-device latency, power use, or aesthetics.
The Python implementation is intended for sparse evaluation, not a 15 Hz camera
pipeline. `synthetic_results.jsonl` contains the raw benchmark summary.

## Limitations and unverified assumptions

- This is a Python reference prototype, not an Android implementation or an APK.
  Repository Definition of Done on a real device has not been met.
- No aesthetic preference model is learned or validated. More off-center
  placements are not evidence of better photographs. Weights and five scale
  priors need human review on consented scenes.
- Calibrated responses, actor identity and safety are caller evidence, not
  inferred or guaranteed by this prototype. Apparent 2D movement can be caused
  by panning, parallax, lens changes, or a different person. Real usage needs
  conservative attribution; without it the director holds.
- Background scores describe the currently observed scene only. A proposed
  person rectangle is a local hypothesis, not a rendered future view. Unseen
  background and wider FOV after stepping backward are never scored. Camera
  translation is allowed only with explicit structure-preservation evidence;
  parallax/depth and collision hazards remain unmodeled.
- Body extents use the agreed real-span ratios as conservative proxies. V1 has
  no dense projected body model, identity tracking, occlusion reasoning, or
  independent person-count check. The caller must ensure one intended person.
- Supported segments are coarse and can miss short, curved, or occluded
  structure. A line is not automatically a horizon or an architectural object.
- Brightness/composition changes can invalidate the descriptor; the simple
  thresholds are deterministic heuristics rather than a scene-understanding
  model. A blocked/no-progress action needs explicit reset or significant new
  scene evidence; it does not keep retrying.
- Phone roll/flatness and target-orientation coaching remain responsibilities of
  the existing engine/sensors. The prototype cannot claim all four production
  axes are aligned just because its local composition is acceptable.
- The RGB adapter reuses existing pose/mask outputs but does not start models or
  synchronize their timestamps. No native Android preprocessing/latency parity
  has been tested. CLIP is intentionally not needed for this structural MVP.

## Request for the lead: future production integration (not implemented)

1. Approve a separate disabled-by-default experimental path. Port these pure
   modules to `app/lib/features/scene/experimental/composition_director_v1/`
   or choose an approved on-device runtime. Do not embed Python or add packages
   without a lead decision. Keep the current `SceneRecommender` unchanged.
2. In that scene adapter, reuse `Nv21FrameData`, `downsampleNv21`, and
   `PersonMasker`. Snapshot `SceneView` and held quarter-turn direction; rotate,
   mirror and crop RGB/mask together exactly once. Pair these with the SAME
   timestamp's pose, already mapped through `toVisible`/`cropInShotSpace`.
   Invalidate the geometry epoch on lens/zoom/crop/orientation-direction changes.
   Existing CLIP mean-filled/224-center-cropped pixels cannot substitute for the
   full visible structural analysis image; CLIP may remain optional.
3. Lead-owned `app/lib/app/providers.dart`: add a separate opt-in experimental
   director provider and lifecycle/busy-drop management. Preserve
   `recommenderProvider`, `coachEngineProvider`, custom references and the front
   camera's plain-camera behavior. Do not alter existing core contracts merely
   to route this prototype.
4. Camera-owner `app/lib/features/camera/coaching.dart`: synchronize scene,
   mask, pose and geometry snapshots; route experimental decisions only when
   explicitly enabled in recommend mode. Supply trustworthy calibrated response
   and fresh safe-direction evidence, otherwise hold. Retain existing sensor
   orientation/roll gates and reset at pause/resume, scene or lens changes.
   Start with a slow feature cadence, bounded queue and dropped busy frames.
5. Camera-owner `app/lib/features/camera/widgets/instruction_bubble.dart` and
   feedback-owner `app/lib/features/feedback/instruction_text.dart`: agree an
   adapter for explicit actor/text/confidence/validity without silently changing
   `CoachInstruction` or `InstructionText`. Korean direct strings are only V1;
   English/Japanese, accessibility and proximity feedback need an explicit
   design. Only one instruction policy should run at a time. Hold must never
   be rendered as aligned/capture. Keep the manual shutter behavior.
6. Coach-owner review: validate projected anchor geometry and use the existing
   level/orientation safety gates without editing `CoachEngine`/`PoseSource`
   contracts. Current Python/Dart code still requires visible nose in some
   measurement helpers while latest AGENTS allows low-visibility estimates;
   the experiment follows AGENTS internally and changes none of those helpers.
7. With a real Android device, verify both landscape directions and portrait,
   saved/preview crop parity, person/mask synchronization, actor-relative
   movement, unsafe-area/unknown-evidence hold, subject loss, scene changes,
   model failure and thermal latency. Run the standard full analysis/debug APK
   checks before any integration PR. No production activation is authorized by
   this prototype task.
