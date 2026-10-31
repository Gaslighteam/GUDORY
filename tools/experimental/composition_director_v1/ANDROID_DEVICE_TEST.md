# Composition Director V1 Android Diagnostic

## Outcome

The isolated Dart Composition Director was built, installed and launched on the
connected Android device. Actual rear-camera images, native ML Kit pose and
selfie masks, structural features, candidates and Korean instructions ran.
The installed diagnostic app is left available for the owner's physical tests.
Production source, its recommender/coach/contracts and unrelated worktrees were
not changed. No commit, push, PR or merge was made.

The owner requested **build and launch first; physical scene testing afterward**.
Accordingly, this report does not claim the six controlled scene/movement
scenarios or photographic quality have been validated. Actual observed output
was hold and acceptable-composition advice. **No live calibrated movement
instruction was verified in this session.**

## Environment and isolation

- Branch: `exp/composition-director-v1`
- Worktree: `C:/Users/kuson/projects/GUDORY-composition-director-v1`
- Base SHA: `6083287c1953a96a1b9833a43557f1be4cd427eb`
- Device identified by both ADB and Flutter: **SM-S937N**
- Android: **16**, API **36**, arm64
- Actual device ID: `R5KYA00HPRW`
- Flutter: 3.44.8; Dart: 3.12.2; Android Studio JBR: 21.0.10
- Separate installed package: `com.gaslighteam.gudory.directorv1`
- Launcher label: `구도리 실험 V1`
- Diagnostic camera: rear camera, NV21, medium preset, native **720x480** stream
- Analysis: **64x96** in portrait and **96x64** in landscape
- UI stays portrait locked; shared accelerometer/orientation helpers choose shot
  orientation. The screen stays awake during diagnostic testing.

Experimental Flutter source is exclusively under
`app/lib/features/scene/experimental/composition_director_v1/`:

| File | Purpose |
| --- | --- |
| `director_models.dart` | Internal person/frame/features/candidate/action contracts |
| `background_features.dart` | Mask-aware grid statistics, supported Hough segments, optional vanishing point |
| `compositions.dart` | Candidate generation, explainable scores, single selection |
| `actions.dart` | Actor-specific measured-response action policy and Korean construction |
| `director.dart` | Stable target, cooldown, feedback, hysteresis and fallback |
| `live_analysis.dart` | Same-frame NV21/pose/mask preprocessing and native ML Kit bridge |
| `diagnostic_camera.dart` | Lower-resolution, diagnostic-only FrameBus/camera owner |
| `diagnostic_page.dart` | Live preview, overlays, level and actor controls, observed calibration, timings |
| `diagnostic_main.dart` | Standalone entrypoint; no production router/provider changes |
| `director_test.dart` | Python parity and action/feedback regression checks |
| `parity_fixtures.json` | Eight original procedural fixtures, no private photo data |

New tools alongside the Python prototype:
`prepare_android_harness.ps1`, `export_dart_fixtures.py`,
`collect_device_metrics.py`, `android_device_metrics.json`, this report, and an
updated local `.gitignore`. The original Python core remains unchanged.

## Reproduce build and launch

From the experiment worktree root, prepare an isolated disposable build copy:

```powershell
./tools/experimental/composition_director_v1/prepare_android_harness.ps1
```

If it already exists, use `-SyncOnly`. The copy is at
`tools/experimental/composition_director_v1/.android_harness/` and is ignored by
Git. It reuses the existing locked package cache and generated plugin registry;
no packages are added or installed.

Exact successful launch command, run with that directory as the working directory:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME='C:\Users\kuson\AppData\Local\Android\Sdk'
& 'C:\Users\kuson\projects\gudory\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat' run --no-pub --debug -d R5KYA00HPRW -t lib/features/scene/experimental/composition_director_v1/diagnostic_main.dart --no-resident
```

No Edge, Chrome, web or Windows app target was launched. `--no-resident` leaves
the app on the phone after the launch command exits. Installation succeeded and
the native camera/sensor/model channels initialized after restoring the matching
generated plugin registry in the build copy. Camera permission was granted only
to this diagnostic package. Screen locking during a rebuild was resolved by the
owner unlocking the phone normally; no secure lock was bypassed.

## Disposable native build differences

Automatic approval review rejected build metadata writes directly under `app/`;
we used its suggested disposable tools copy instead. It also rejected installing
with the production package ID; the copy now has a unique diagnostic ID.
These changes are confined to the tools copy, with the preparation script
recording them explicitly:

1. Copied Android `app/build.gradle.kts`: application ID changed from
   `com.gaslighteam.gudory` to `com.gaslighteam.gudory.directorv1`.
2. Copied Android manifest: launcher label changed to `구도리 실험 V1`.
3. Copied Android `app/build.gradle.kts`: applied the already-declared
   `org.jetbrains.kotlin.android` plugin. The base project disables built-in
   Kotlin but does not apply that plugin; without this harness-only fix Gradle
   fails at `kotlin { compilerOptions { jvmTarget ... } }` before Dart is built.
4. Restored the existing generated Android `GeneratedPluginRegistrant.java`
   matching the copied locked dependencies. A no-pub build without it installed
   successfully but initially failed camera/sensor method channels.

**Request for the lead:** a normal base-project Android build needs the Kotlin
Android plugin applied in `app/android/app/build.gradle.kts` (or an approved
consistent migration to AGP built-in Kotlin). We did not edit that production
file. A fresh no-pub build also needs its generated plugin registrant. These are
build prerequisites, not experimental camera integration changes.

Android 16 displayed a debug compatibility notice concerning 16 KB ELF alignment,
including inherited `libonnxruntime.so` and other native libraries. It was
acknowledged with OK; we did not disable future notices or suppress alignment
checks. The current diagnostic runs, but production compatibility requires a
lead-owned dependency/build review. No package upgrades were attempted.

## Actual device observations

Aggregate probe recorded at **2026-11-01 03:00 KST**, process 31230:

- 257 actual live updates available, sample IDs 1..257.
- 94 samples passed the internal pose-person measurement;
  172 had usable mask/background evidence.
- Background extraction reported up to 4 supported lines.
- Portrait and one landscape side (`q=0`, `q=-1`) appeared in actual sensor logs.
  The other landscape side has automated geometry coverage only.
- Target generation occurred in live input. Scene/pose loss, phone flatness and
  geometry changes reset it as designed; this uncontrolled trace is not a
  controlled stability experiment.
- Actual direction counts: `{"hold": 252, "capture": 5}`.
- No `DIRECTOR_ERROR` events in the measured process.
- The app displayed a live preview and its update counter advanced. Continuous
  visual preview FPS and jank were not measured, and camera responsiveness was
  not independently graded by a human in this session.

Actual Korean instructions recorded from device logs:

- "촬영자님, 잠시 그대로 유지해 주세요."
- "촬영자님, 그대로 유지하고 셔터를 눌러 주세요."

The second is the inherited composition-acceptable/capture advisory; this
minimal diagnostic has no photo-saving or shutter flow. It does not take a photo
or auto-trigger anything. This wording should be adapted before production use.

There was no fresh measured movement response plus fresh safety confirmation in
the recorded trace. The system therefore held on uncalibrated compositions.
This is a genuine uncertain-state result, not evidence that left/right, actor
choice or forward/backward have been physically validated.

## On-device performance

Debug build, uncontrolled live scenes, 254 updates after excluding
the first three available samples:

| Measurement | Median | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Composition core, all paths | 1.57 ms | 5.58 ms | 13.60 ms |
| ML Kit pose | 28.35 ms | 61.65 ms | 77.50 ms |
| ML Kit selfie mask | 50.38 ms | 68.70 ms | 77.49 ms |
| Preprocessing/isolate | 64.02 ms | 77.75 ms | 108.42 ms |
| Full serial pipeline | 146.52 ms | 180.92 ms | 220.25 ms |

For pose-and-mask-positive input specifically, composition-core median was
**1.82 ms**, p95 **5.67 ms**. This remains an uncontrolled scene
measurement, not a cross-device benchmark or aesthetic result.

- Last reported update frequency: **1.90 Hz** (target ceiling 2 Hz).
- CPU snapshot: **100.0% of one core**, on an
  8-core/800% capacity scale
  (about 12.5% of total CPU capacity). Snapshot, not a sustained average.
- Total PSS: **639,991 KiB** (625.0 MiB);
  RSS **760,112 KiB**. Includes debug Flutter, native models and camera.
- Battery remained **100%**, connected by USB; energy drain cannot
  be inferred. Battery sensor **34.9 C** at the probe,
  versus 27.8 C before setup. This is not a controlled thermal attribution test.
- Thermal service status **0** at probe time. No claim about
  long-run throttling or subjective device warmth.

The original max-resolution-camera run reached roughly 209 ms median pipeline
and a much larger CPU snapshot. The diagnostic now uses medium resolution;
production camera resolution was not changed. Native preview frames are not
all processed: busy frames and frames before the 500 ms analysis deadline are
dropped. RGB/mask preprocessing runs in an isolate. The pure core currently runs
on the UI isolate; debug worst-case cost still needs profiling on harder scenes.
The desktop Python 10.84/12.09 ms reference excludes native pose/mask and therefore
is not comparable to the full Android pipeline time.

`android_device_metrics.json` contains aggregate data only. No camera images,
reference photos, personal filenames, raw masks or per-person coordinates were
copied from the phone or saved by the probe.

## Automated verification

- **314 Flutter tests passed, 3 native CLIP tests skipped**: 300 existing tests
  plus 14 experimental tests. The skips require a separate native CLIP model
  test path and do not prevent this non-CLIP structural MVP.
- **Flutter analysis: zero issues**, including the final diagnostic camera.
- **Debug APK built and installed** from the disposable harness; current APK is
  `tools/experimental/composition_director_v1/.android_harness/build/app/outputs/flutter-apk/app-debug.apk`.
- Eight Python/Dart procedural fixtures match line count, feature confidence,
  cell coverage/complexity, selected target x/y/scale/framing/score, and exact
  Korean output. The other six focused tests cover safety expiry, separate
  subject/camera directions, cooldown/no-progress block, observed improvement,
  person/mask/geometry invalidation, head formulas and Korean construction.

Commands in the disposable harness:

```powershell
flutter analyze --no-pub
flutter test --no-pub --no-test-assets test lib/features/scene --reporter compact
```

The existing 27 Python prototype tests and 51 production Python tests passed in
the previous stage; this session adds no Python-core modifications. Synthetic
results are explicitly synthetic. Passing these tests is not proof of good
photographs, correct physical movement, preview/saved-photo parity or safety.

## Owner's next live checks

1. Open **구도리 실험 V1**, stand the phone upright and show one person's head and
   both shoulders. Cyan is the pose-derived person extent; yellow is the selected
   target; orange is supported background structure. The top layers button
   toggles diagnostic overlays; the refresh button starts a new target/epoch.
2. Test centered and near-edge people, architectural lines, open space and weak
   backgrounds. Use levels 1..5 to change person/background emphasis. The preview
   is the entire diagnostic stream with no cover crop. No photographs are saved.
3. Movement is conservative by design. Select **모델 이동** or **촬영자 이동**, and
   an axis (subject supports horizontal; photographer also supports distance and
   phone height). Only when the area is safe, tap **공간 확인 후 측정 시작**.
4. Make the selected positive half-unit intervention: photographer-relative
   right half step, photographer forward half step, or phone up half fist. Keep
   other motions controlled, settle for three analysis samples, then tap
   **반 단위 이동 후 완료**. This measures actual x/y/scale response; no synthetic
   calibration is used. Excessive, unstable or background-changing measurements
   are rejected. Camera motion additionally needs structural-preservation evidence.
5. Within five seconds of accepted calibration, verify space on both directions
   of the chosen axis and tap **이동 공간 확인 · 2초**. If the target needs that
   change and predicted progress is adequate, the director can issue one
   actor-specific half-unit Korean movement. Otherwise it holds. Safety evidence
   expires after two seconds; calibration after five. These short expirations
   intentionally make unconfirmed actions non-actionable.
6. Follow an issued instruction and observe progress after the 1.5 s cooldown.
   Repetition/reversal after no progress is blocked pending reassessment. No
   further action should be inferred from a stale calibration. A new calibration
   resets the director; the refresh button also clears calibration.
7. Test both held landscape directions, pause/resume and subject loss. Report
   the displayed reason, instruction and timing rather than assuming success
   from an overlay or a passing automated test.

## Remaining differences and limits

- Core constants and deterministic selections match the exported Python cases,
  including ties-to-even Hough rounding. This is eight-case parity, not formal
  equivalence on all images.
- Dart native preprocessing reuses existing NV21 RGB conversion, source-to-mask
  mapping and conservative mask pooling. It uses double luminance arithmetic;
  Python's optional Pillow adapter has its own resize/rounding. Pixel-exact
  natural-image parity is unverified.
- The Android diagnostic shows the **720x480 stream's full geometry**, not the
  production 3:4 still workflow; it has no save path. Production integration must
  reconcile stream/still crop and timestamp mapping explicitly.
- An Android-only phone-flat guard is added outside the pure director, using
  shared orientation helpers. It can override otherwise acceptable results.
- Calibration is user-attributed, one actor/axis at a time, with an exploratory
  confidence of 0.8. The prototype cannot prove who moved, identify hazards, or
  rule out panning/parallax or person changes. Safety is an explicit owner
  confirmation. Missing evidence yields hold.
- The person boundary is a pose-derived extent using agreed body-span ratios,
  not a full contour detector. There are no new AI models or semantic detectors.
- No live left/right/forward/backward/up/down instruction was confirmed here.
  The six requested physical scenarios and perceived photographic quality remain
  the owner's follow-up tests, as requested.
- Camera resolution, lifecycle, overlay UI and calibration are Scene-local.
  Production camera, existing recommender, CoachEngine, PoseSource and core
  contracts were not edited. The production source/native build has not been
  integrated or repaired by this task.
