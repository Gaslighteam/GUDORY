# Step 1 — CLIP device checkpoint

This report covers Step 1. Step 2 preprocessing and segmentation are documented
separately in STEP2.md; classifier, composition library and model manager are
not implemented. The shared entry point and router are not imported or changed.
The paused tools drafts are separate.

## Approved completion record — physical Android device

The user supplied the following physical-device measurements and explicitly
approved Step 1 as complete. These are user-reported device results, not an
additional device test performed by the agent.

| Run | Native inference time |
| --- | ---: |
| First | 15.841 ms |
| Repeat 1 | 31.198 ms |
| Repeat 2 | 38.375 ms |
| Repeat 3 | 32.243 ms |

First-run dimensions: **512**. Reported first five normalized values:
`[0.02, -0.04, 0.00, -0.06, 0.01]`. Reported L2 norm: **1.00**.
Values and norm are recorded at the precision provided by the user.

Conclusion approved by the user: Android ONNX inference works on a real device;
output dimensions and normalization are correct; Step 1 passes. Phone model and
Android version can be appended later and do not block Step 2.

After integrating upstream main `50069d3a499c2e7c773c1073b39d06fc34179e47`,
all 8 Scene tests passed (0 skipped), full Flutter analysis passed with no
issues, and the standalone debug APK built successfully. The initial SDK
37 target-discovery failure cleared on retry after platform installation.
The earlier manifest and analyzer blockers below are historical and resolved
by the lead's upstream changes. No shared files were edited locally.

The user subsequently approved the Step 2 files/signatures and implementation.
Step 3, commits, pushes and PRs remain unauthorized. The remaining sections retain
the original Step 1 implementation notes and historical check results.

## Model inspected before runner implementation

Downloaded from:
https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main/onnx/vision_model_quantized.onnx

- Size: 89,117,001 bytes.
- SHA-256: `583fd1110a514667812fee7d684952aaf82a99b959760c8d7dca7e0ab9839299`.
- Graph input: `pixel_values`, ONNX FLOAT (enum 1 / float32), symbolic shape
  `[batch_size, num_channels, height, width]`.
- Graph output: `image_embeds`, ONNX FLOAT (enum 1 / float32), shape
  `[batch_size, 512]`.
- The input axes are **not** fixed at 1/3/224/224 in the graph. The native
  integration test verifies that this concrete shape is accepted.
- Graph metadata was read directly from the local ONNX protobuf with
  standard-library Python, using ModelProto.graph=7, GraphProto.input=11 /
  output=12 and ValueInfoProto.type. Field definitions:
  https://github.com/onnx/onnx/blob/main/onnx/onnx.proto
- The upstream folder also contains `vision_model_fp16.onnx`; its URL is
  recorded as `clipFp16Url`. fp16 download/execution is outside this step.

The runner copies the bundled q8 to application support storage once, checks
session names, decodes an image, resizes its short side to 224 using cubic
interpolation, center-crops, and creates an RGB-normalized float32 NCHW tensor.
The run and preprocessing execute in a worker isolate. Native errors propagate
to the debug page, which displays an error and allows retry. The runner releases
native tensors/options and waits for an active run before releasing the session.
Missing/corrupt models fail visibly; this debug harness does not claim a
production scene-classification fallback.

## Deterministic fixture and asset option

`debug_test_image.dart` creates the same 448x224 RGB stripe PNG each time.
It exercises actual image decoding without changing shared asset declarations.
Its center crop is green on the left and blue on the right. Unit tests check all
150,528 normalized values, channel ordering, shape, portrait resizing, invalid
images, L2 errors, debug metrics and missing-model retry.

`runAsset(path)` also works; the native integration test uses an AssetBundle
test double to verify this path. A real bundled photo is optional and requires
the lead's authorization to add it to `assets/demo/`. Set
`--dart-define=CLIP_TEST_ASSET=assets/demo/<authorized-photo>.jpg` when available.
The default stripe fixture is an inference smoke test, not evidence of scene
classification quality or realistic photo accuracy.

## Launch on a physical Android phone (PowerShell)

Use Flutter 3.44.8 / Dart 3.12.2. In this checkout:

**Currently blocked:** the shared manifest merge failure below must be resolved
by the lead before this command can install or launch the Android build.

```powershell
Set-Location C:\Users\kuson\projects\gudory\app
$flutter = 'C:\Users\kuson\projects\gudory\.worktrees\tools\tools\.flutter-sdk\bin\flutter.bat'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& $flutter devices
# Replace DEVICE_SERIAL with the physical phone's ID from the previous command.
& $flutter run --debug --no-pub -d DEVICE_SERIAL --target lib/features/scene/debug_scene_main.dart
```

1. Enable USB debugging, connect the phone, accept the authorization prompt, and
   confirm `flutter devices` lists the physical phone.
2. Run the standalone entry point above. It opens directly on the debug page.
3. Tap **CLIP 실행**. Record `inference_ms`, `dimensions`, `first_five`, and
   `l2_norm` from the selectable screen text or the `flutter run` console.
4. Tap again at least three times. Record the first run separately from repeated
   runs, phone model, Android version, and any errors. Dimensions must be 512;
   all values must be finite; L2 norm should be within 0.000001 of 1.
5. Restart the app and repeat to check the cached-model path. Report results for
   review before Step 2. Do not interpret a synthetic-image pass as quality
   validation of the later scene classifier.

`inference_ms` measures only native `session.run`. It excludes asset/model
loading, image decoding, resize/crop, tensor allocation, isolate startup and L2
normalization. It is not end-to-end screen latency.

## Automated checks

Run from `app/`, using the pinned SDK's commands:

```powershell
& $flutter pub get --enforce-lockfile
& $flutter analyze --no-pub
& ..\.worktrees\tools\tools\.flutter-sdk\bin\cache\dart-sdk\bin\dart.exe analyze lib/features/scene
$env:PATH = 'C:\Users\kuson\AppData\Local\Pub\Cache\hosted\pub.dev\onnxruntime-1.4.1\windows;' + $env:PATH
& $flutter test --no-pub --reporter expanded --dart-define=CLIP_MODEL_PATH=C:/Users/kuson/projects/gudory/app/assets/clip/vision_q8.onnx lib/features/scene/clip_runner_test.dart
& $flutter build apk --debug --no-pub --target lib/features/scene/debug_scene_main.dart
```

Without `CLIP_MODEL_PATH`, the native integration test is explicitly skipped;
the pure tests still run. Native Windows testing uses the DLL already included
in the locked `onnxruntime` package, without adding a dependency. Desktop
execution does not verify Android native packaging, runtime, or performance.

Latest successful Windows test run: **8 passed, 0 skipped**. Native run times:
26.008 ms and 22.515 ms. Both returned dimensions 512, L2 norm
0.9999999999999994, and first five values:

```text
[0.02182695228389046, -0.03949270042289472, 0.006498497288688345,
 -0.061596198633692596, 0.0013842834261082332]
```

Scene-only analysis: no issues. Full `flutter analyze --no-pub` exits 1 with two
existing informational findings outside Seojun's scope:

- `app/lib/app/app.dart:9:37`: `unnecessary_underscores`.
- `app/lib/core/models.dart:82:39`: `unintended_html_in_doc_comment`.

Standalone `flutter build apk --debug --no-pub --target
lib/features/scene/debug_scene_main.dart` failed, exit 1, after 364.9 seconds.
Gradle task `:app:processDebugMainManifest` failed because the app declares
`WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="29"` at
`app/android/app/src/main/AndroidManifest.xml:8`, while the existing
`camera_android_camerax` dependency declares 28. The merger suggests an explicit
`tools:replace="android:maxSdkVersion"` override. The lead must decide whether
to align the permission limit or override it; no manifest has been edited.
The build also warned about `flutter_tts` using the Kotlin Gradle Plugin, which
future Flutter versions will reject. That warning was not the build failure.

## 팀장 요청 / review gate

- Resolve the shared Android manifest permission conflict above. This blocks
  APK generation and physical-device launch even with the standalone entry.
- Resolve the two shared-file analyzer findings if the project requires a clean
  full-app analysis. No shared files were edited for these findings.
- Optional real-photo asset authorization as described above. No shared image
  asset has been created or changed.
- Physical Android inference and timings are pending. If Android CLIP has not
  passed the device checkpoint by the original 18:30 go/no-go, request a lead
  decision on Plan B (`google_mlkit_image_labeling`, lead-added dependency).
  A label mapping could group beach/ocean → sea, mountain → mountain,
  forest/tree → forest, building/street → city, sunset → sunset, and
  room/furniture → indoor, with explicit confidence/unknown handling. This is a
  sketch only; no dependency or fallback classifier has been added.
- Stop here for implementation review and physical-device results. No commits,
  pushes, PRs, or Step 2 work are authorized at this checkpoint.
