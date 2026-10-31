# Step 2 — camera preprocessing review checkpoint

Implemented only inside `app/lib/features/scene/` on `feat/scene`, based on
main `50069d3a499c2e7c773c1073b39d06fc34179e47`. No shared files, entry points,
dependencies or Tools drafts were changed. No classifier/Step 3 is included.

## Interfaces and behavior

- `Nv21FrameData.fromCameraFrame(frame)` takes an owned byte snapshot and validates
  format, plane count, size, row stride and rotation. Single-plane NV21/raw 17 is
  supported. Width/height must be even and at least 2; sensor rotation must be
  0/90/180/270. Unknown multi-plane layouts are rejected, not reinterpreted.
- `preprocessFrame(CameraFrame frame, {PersonMask? mask})` and
  `preprocessData(Nv21FrameData frame, {PersonMask? mask})` produce a
  `PreparedSceneFrame` in a worker isolate, with float32 NCHW `[1,3,224,224]`,
  original/filled PNG previews, final 224x224 crop, mean color and filled count.
- `PersonMasker.maskFor(CameraFrame frame)` / `maskData(Nv21FrameData frame)`
  return an upright, **unmirrored** person mask or null. `close()` waits for
  pending segmentation and releases the detector. Busy calls return no mask;
  masks are never reused across frames.
- `clipImagePixels(img.Image image)` shares Step 1's crop/normalization with the
  camera pipeline. The original 8 tests, including real desktop ONNX inference,
  still pass, with identical normalized first-five embedding values.

The spatial downsampling stride is exactly **4 in both axes**, starting at raw
pixel (0,0). Samples are (0,0), (4,0), ...; (0,4), (4,4), ... . Sample dimensions
are ceil(width/4), ceil(height/4), so a 2x2 image produces one RGB sample. This
is point sampling, not averaging/anti-aliasing. RGB is decoded only for those
samples, using BT.601 limited-range integer YUV conversion and V-before-U order.

The mean is the rounded RGB mean of the entire downsampled image **before**
masking or cropping. Pixels with foreground confidence >= 0.5 receive that mean.
An all-zero valid mask changes no pixels; an all-one mask fills the whole image.
`maskApplied` means a valid mask was evaluated; `maskedPixels` records actual
filled samples. Invalid/null masks result in the exact unmasked tensor.

For each raw RGB sample, map the original source pixel through sensor rotation
to upright ML Kit coordinates, then rescale into the returned mask dimensions.
Nearest mask sampling uses the source pixel center. This preserves the sampling
grid's phase when dimensions are not multiples of 4. Filled and original RGB
are then rotated clockwise and front-camera mirrored together. Both receive the
same center crop/resizing. The mask is not independently mirrored or rotated a
second time. Full-image previews preserve the natural image aspect, with no
person outline.

## Verified installed-package behavior

Inspected the versions referenced by `app/.dart_tool/package_config.json`:

- `camera_android_camerax 0.7.6+1`: `android_camera_camerax.dart` calls
  `ImageProxyUtils.getNv21Buffer`, emits one plane with `bytesPerRow=width`,
  `bytesPerPixel=1`, format group NV21 and raw 17. The native
  `ImageProxyUtils.java` packs Y rows followed by interleaved VU rows, removing
  source plane padding. It may retain unused trailing allocation bytes; these
  are not interpreted as pixels. Its README has an older statement about
  reporting YUV420; the inspected implementation explicitly overrides to NV21.
- The app's existing `CameraService` requests NV21 and constructs the shared
  `CameraFrame` with camera `sensorOrientation` and front-facing status.
- `google_mlkit_selfie_segmentation 0.12.1` forwards mask width/height and
  row-major float confidences from Android ML Kit over its method channel.
- `google_mlkit_commons 0.13.0` Android `InputImageConverter.kt` passes bytes,
  width, height, rotation and format to `InputImage.fromByteArray`; it **does not
  use bytesPerRow**. Consequently padded NV21 is repacked tightly for ML Kit,
  with metadata row stride equal to the repacked width. RGB conversion still
  uses the original stride.

Padded single-plane support explicitly assumes Y and VU share a row stride and
VU starts at rowStride * height; the final chroma row may omit trailing padding.
The single-plane camera contract cannot express a separate chroma stride.
Other formats/ambiguous multi-plane layouts produce a visible diagnostic error.
No shared camera infrastructure has been changed to work around them.

Google's [segmentation guide](https://developers.google.com/ml-kit/vision/selfie-segmentation/android)
documents input rotation, raw mask dimensions and reading row-major foreground
probabilities. Its [segmentation graphic sample](https://github.com/googlesamples/mlkit/blob/master/android/vision-quickstart/app/src/main/java/com/google/mlkit/vision/demo/java/segmenter/SegmentationGraphic.java)
scales returned masks to the upright image space. Actual device alignment remains
part of the checkpoint below. Single-image mode is deliberately used for sparse
diagnostic frames and lens switching, to avoid temporal mask carry-over. Native
segmentation receives the full source resolution; RGB processing downsamples
first. No performance claim for live native segmentation has been made.

## Live diagnostics / ownership

The unchanged standalone entry point opens `DebugScenePage`. Its new button
opens `DebugPreprocessPage` inside a ProviderScope. That page obtains the
**existing** `cameraServiceProvider`, subscribes via `FrameBus.frames`, and uses
the service's start/stop/flip operations. It creates no CameraController and
does not implement another camera owner. The scope owns service teardown.

At most one accepted frame is processed per second; arriving frames while busy
are dropped. RGB and segmentation use one snapshot of that accepted frame.
Processing remains on the device, and previews are kept only in memory. The
page locks portrait via the existing Flutter system API; no entry point changed.
Sensor orientation is used under the repository's portrait-up contract. Dynamic
landscape rotation is not supported by this CameraFrame contract.

Exceptions, null/invalid masks, missing plugin and malformed results return no
mask. The debug **분할 실패 테스트** switch injects an exception through the same
fallback path; it does not claim to reproduce every possible native failure.
There is no native cancellation/timeout watchdog in this step; a native call
that never completes would keep that diagnostic run busy. That is distinct from
the tested exception/null/invalid-result fallback.

## Automated verification

Pinned Flutter **3.44.8 / Dart 3.12.2**:

```powershell
Set-Location C:\Users\kuson\projects\gudory\app
$flutter = 'C:\Users\kuson\projects\gudory\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat'
$env:PATH = 'C:\Users\kuson\AppData\Local\Pub\Cache\hosted\pub.dev\onnxruntime-1.4.1\windows;' + $env:PATH
& $flutter test --no-pub --reporter expanded --dart-define=CLIP_MODEL_PATH=C:/Users/kuson/projects/gudory/app/assets/clip/vision_q8.onnx lib/features/scene
& $flutter analyze --no-pub
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& $flutter build apk --debug --no-pub --target lib/features/scene/debug_scene_main.dart
```

- **31 Scene tests passed, 0 skipped**, exit 0. This includes all 8 Step 1 tests.
- Step 2 tests cover known color bars and grayscale, stride-4 raw positions,
  padded Y/VU rows, short final padding, small images, rejection of invalid
  layouts/rotation, owned snapshots, all quarter-turn rotations and mirroring,
  lower/higher-resolution masks, non-square source coordinates, mean fill,
  tensor dimensions, finite values, invalid masks and native failure fallback.
- A mock of the actual ML Kit platform channel verifies packed bytes and
  rotation/format/dimension metadata. This tests the bridge contract, not actual
  Android ML Kit inference.
- Standalone debug APK built successfully, exit 0, in **33.3 seconds**.
  Existing `flutter_tts` future-Kotlin-compatibility warning is nonblocking.
- Full `flutter analyze --no-pub`: **no issues**, exit 0 (21.6 seconds).

## On-device checkpoint (not yet verified)

Connect exactly one USB Android phone, enable USB debugging and accept the
computer authorization prompt. Run:

```powershell
Set-Location C:\Users\kuson\projects\gudory\app
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$phone = & 'C:\Users\kuson\AppData\Local\Android\Sdk\platform-tools\adb.exe' -d get-serialno
& ..\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat run --debug --no-pub -d $phone --target lib/features/scene/debug_scene_main.dart
```

1. Confirm the original **CLIP 실행** still succeeds. Open **Step 2 카메라 전처리
   테스트** and grant camera permission. Hold the phone upright.
2. Check diagnostics: raw 17 / NV21 / one plane, source dimensions and byte count,
   Y/VU row stride, VU offset, sensor rotation and front-mirror flag. The observed
   values are needed to verify real-device layout; source-code inspection is
   not a substitute for this measurement.
3. Point at distinct red/green/blue objects and readable upright text. Disable
   **사람 영역 채우기**. The corrected preview should be upright, retain expected
   colors, and have no skewed rows. The 224x224 preview must match the center crop.
4. Enable **사람 영역 채우기**. Move a person to the left, right and center, away
   from the midpoint. Check that only the person's sampled pixels are filled
   with the reported mean color, with the background in place. Record mask
   dimensions, `mask_applied`, `filled`, and `mean`. No-person frames may have
   zero filled samples; this is not itself a segmentation failure.
5. Use **카메라 전환** and repeat. Compare the corrected original and filled
   previews with the camera preview. Front-camera mirroring should be consistent
   and the fill should follow the person after mirroring, without an extra turn.
6. Enable **분할 실패 테스트** with masking enabled. Expect
   `mask=segmentation-failed`, `mask_applied=false`, `filled=0`; original and
   processed previews must match while frames continue. Disable it and confirm
   real masking recovers. This is a simulated failure, not native failure evidence.
7. Confirm `tensor=float32 [1,3,224,224] count=150528 finite=true`. Use **화면 고정**
   to read/copy the diagnostics. Terminal output is prefixed **SCENE STEP2**.
   `preprocess_ms` includes segmentation, worker preprocessing and PNG previews;
   it is not a CLIP inference measurement.
8. Background/resume the app, exit/re-enter the page, and verify the camera can
   restart. Report phone/Android version, actual layout/rotation metadata, mask
   dimensions, alignment observations, timings and any error text.

Step 1's approved user-reported physical-device measurements remain in STEP1.md:
first 15.841 ms, repeats 31.198 / 38.375 / 32.243 ms, 512 dimensions, first five
`[0.02, -0.04, 0.00, -0.06, 0.01]`, L2 1.00. Phone/Android version can be added
later. Those results do not verify Step 2 camera frames or ML Kit masks.

Stop for user review/device results here. No commits, pushes, PRs or Step 3.
