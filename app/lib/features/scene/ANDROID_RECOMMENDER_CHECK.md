# Android Recommender verification

These are verification instructions, not a claim of device success. The feature
is submitted as a Draft; do not merge or mark it ready before the remaining
integration-critical checks are assessed. No photos are captured, saved or
uploaded by the diagnostic page.

## Run on one physical USB phone

Unlock the phone, enable USB debugging, select a data-capable USB connection and
accept the computer's RSA prompt. The first command must list exactly one device
with status `device` (not `unauthorized` or `offline`).

```powershell
Set-Location C:\Users\kuson\projects\gudory\app
$adb = 'C:\Users\kuson\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$flutter = 'C:\Users\kuson\projects\gudory\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat'
& $adb devices -l
$phone = & $adb -d get-serialno
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& $flutter run --debug --no-pub -d $phone --target lib/features/scene/debug_recommender_main.dart
```

For the already built normal diagnostic APK, install without clearing app data:

```powershell
& $adb -d install -r build/app/outputs/flutter-apk/app-debug.apk
& $adb -d shell am force-stop com.gaslighteam.gudory
& $adb -d shell am start -n com.gaslighteam.gudory/.MainActivity
```

That file must have been built with the diagnostic target, not the normal main.
Grant camera permission on the phone. The page uses the existing CameraService
and heldOrientationProvider. Its preview is the whole portrait frame, with no
additional visible crop; production crop-provider wiring is a separate lead task.

## Required checks

1. **Three backgrounds:** indoor, street and open sky, with one visible person
   and usable background. Stay still and tap **새 배경 분석**, then **1·3·5 비교**.
   Record phone model/Android version, background label and orientation. Save
   scalar diagnostics only: top cosine, selected level, f/h/cx/cy/hy, neighbors,
   model variant, total_ms, cached and embedding_calls. Console prefix is
   `SCENE RECOMMENDER`. Do not share frames, embeddings or private photos.
2. **Cache:** in each 1/3/5 comparison, embedding_calls must not increase after
   the first uncached analysis while geometry is stable and the three-second
   window has not expired. cached should be true for subsequent calls. Different
   arriving camera frames do not defeat this cache. **새 배경 분석** explicitly
   invalidates it. Wait past three seconds and verify a later run can refresh.
3. **Direction/orientation:** repeat all levels in portrait, top-left landscape
   (`quarterTurns=1`) and top-right landscape (`-1`). Target orientation must
   match held orientation. Lens switching must invalidate the embedding. Use
   **카메라 전환** for front-camera checks; the fill must follow the same person
   in the preserved Step 2 mask diagnostic. No extra mirror/rotation is allowed.
4. **Target interpretation:** verify scale s ranks large-person to small-person
   levels. Compare h only when framing f is the same: shoulders, hips, knees and
   ankles use different anchors, so h is not globally monotonic. Record framing
   changes rather than claiming a cross-framing h ordering failure.
5. **Inference failure:** enable **추론 실패 주입**, then compare 1/3/5. Expect
   source fallback, neighbors 0, model none, finite target values and the correct
   orientation. Disable it and request fresh analysis. This is a synchronous
   injected failure, not evidence of every native crash/failure mode.
6. **Missing asset:** enable **에셋 누락 주입**. All ten orientation/level
   requests must remain usable using the embedded 797-photo emergency medians,
   neighbors 0/model none; no CLIP job should run. Disable the switch to reload
   the current bundled 861-photo medians and clusters.
7. **Actual missing model:** stop the normal run and launch a separate build:

   ```powershell
   & $flutter run --debug --no-pub -d $phone --target lib/features/scene/debug_recommender_main.dart --dart-define=SCENE_MISSING_MODEL=true
   ```

   This selects a deliberately absent model path. With a valid person mask,
   model/session loading must fail safely, returning the loaded asset's median
   with neighbors 0/model none. With no usable person mask it falls back before
   model loading; do not mislabel that as proof of a model-load attempt. The
   corresponding worker missing-model path is covered by desktop automation.
   Restart without this define to restore normal inference. To inspect a real
   missing bundled q8 file, the lead would need a separate asset-test build;
   do not alter shared asset declarations locally.
8. **Mask failure/no person:** test empty background, person extremely close,
   obstructed lens and extreme lighting. Invalid/empty/full masks should produce
   fallbacks without an unmasked CLIP inference. Use Step 2 diagnostics to
   examine actual mask alignment; automatic fallback alone proves no accuracy.
9. **Lifecycle:** background/resume, rotate both sides, flip lens and leave/reopen
   the page. Verify the camera restarts, stale geometry is not reused, no late
   disposed result appears and the UI stays responsive. A native call that never
   returns is not cancellable by the ten-second per-stage deadline; requests
   fall back while it remains occupied, and process restart may be necessary.

## Result template

| Device / Android | Background | Orientation / quarterTurns | Level / selected | f | h / cx / cy | Cosine | Neighbors / variant | Total ms | Cached / embedding_calls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pending | indoor/street/sky | p / l(+1) / l(-1) | 1,3,5 | | | | | | |

Keep injection results separate from actual native inference observations.
Full-frame diagnostics do not certify production preview-crop wiring. Report
mask alignment, cache behavior and median quality separately from measured
latency; debug-mode latency is not a release-build performance guarantee.
