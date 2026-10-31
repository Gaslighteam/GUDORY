# Eungyu — Claude Code session prompt (run with `claude-lab`, from the repo root after cloning)

Paste everything below as the first message.

---

You are helping the developer who owns the **coaching engine (coach) module** of the "GUDORY" Flutter app. First read `AGENTS.md` at the repo root in full, confirm you read it, and summarize the signatures of `PoseSource`, `CoachEngine`, `ReferenceAnalyzer`, `WhoMoves` and the fields of `PoseFrame`, `TargetComposition`, `CoachInstruction` from §4. Then work through the steps below **one at a time**; after each step stop and wait for my on-device test result.

## My scope
- May edit: `app/lib/features/coach/**`, `app/test/coach/**`
- Must not edit: `app/lib/core/**`, other feature folders, `pubspec.yaml`. If you need something there, write a "request for the lead" and stop.
- Branch `feat/coach`, commit prefix `feat(coach):`.
- For modules that do not exist yet (FrameBus etc.), write Fakes matching `contracts.dart` in `features/coach/fakes/` and keep going.

## Step 1 — PoseSource (working on device by 19:30)
- `features/coach/pose_source.dart`: consume `FrameBus.frames`, run ML Kit `PoseDetector(mode: stream)` for 33 joints, compute roll/pitch from the `sensors_plus` accelerometer, and emit `PoseFrame`s.
  - Use the conversion recipe in AGENTS.md §4 exactly (NV21, sensorOrientation → InputImageRotation, bytesPerRow).
  - Coordinates must be **rotated into portrait screen space, 0~1**. Mirror x for the front camera.
  - Roll: upright portrait = 0°. Base it on `atan2(ax, ay)` from the accelerometer and verify the sign on a device by tilting left/right. Pitch: grows as the phone lies down.
  - Drop frames while busy (max 15 per second).
- Debug page `features/coach/debug_pose_page.dart`: draw joint dots over the camera preview with CustomPaint to confirm the coordinate correction (the lead wires the route).
- Verify: holding the phone upright and pointing at a person, the dots sit exactly on the body, and roll moves ± when tilting left/right.

## Step 2 — four-axis errors and amount conversion
- `features/coach/axes.dart`:
  - Person height ratio = (top of head y ~ mean ankle y) / 1.0. Top of head y ≈ nose y − (mean shoulder y − nose y) × 0.6. Ankle visibility < 0.5 → "not full body".
  - Center x = mean x of shoulders and hips (4 points), hip y = mean y of the two hips.
  - Normalized errors: level = roll / tolRollDeg; distance = (current ratio − target ratio) / tolHeight (+ = too close → stepBack); horizontal = (current x − target x) / tolX (+ = person is right → stepRight); height = (current y − target y) / tolY (+ = person is low → phoneDown).
  - Amounts: distance d ≈ 1.65 / (ratio × 2·tan(32.5°)), steps = |Δd| / 0.6; horizontal m = Δx × d × 2·tan(25°), steps = /0.6; height m = Δy × d × 2·tan(32.5°), fists = /0.1. Round to 0.5, minimum 0.5.
  - If not full body and the target is not full body either (half-body reference), use the shoulder-to-hip length ratio instead.
- Pure functions, with at least 5 unit tests in `test/coach/axes_test.dart` (signs and rounding).

## Step 3 — CoachEngine (instruction selection)
- `features/coach/coach_engine.dart`:
  - No person → `noPerson`; not full body while the target is full body → `fitWholeBody`.
  - In order level → distance → horizontal → height, activate the first axis with |error| > 1.0. Keep it active until |error| < 0.8 (hysteresis). Hold an instruction **at least 1.5 s**, except switching to `aligned`, which is immediate.
  - If the active axis error grows by ≥ 0.3 within 1 s, emit `oppositeWay` once.
  - All four axes ≤ 1.0 → `aligned`.
  - Always fill the `errors` map (debug overlay).
- `test/coach/coach_engine_test.dart`: inject time so the 1.5 s hold, hysteresis and aligned transition are testable.

## Step 4 — ReferenceAnalyzer (by 22:00)
- `features/coach/reference_analyzer.dart`: `InputImage.fromFilePath` → ML Kit pose (single-image mode) → `TargetComposition(source: 'reference')` with **the same definitions as Step 2**. Default tolerances 0.10/0.08/0.08/3°. Throw `NoPersonException` when no person. Apply EXIF orientation first (`image` package `bakeOrientation`).

## Step 5 — 22:00 integration
- When the lead wires the camera screen, verify real instructions appear in the bubble with the dummy target (0.6/0.5/0.6). Tune tolerances and hold time by feel on the device and keep the constants in `features/coach/tuning.dart`.

## Step 6 (Should, only when the engine is stable, after 01:00) — WhoMoves
- Erase the person with the selfie segmentation mask, turn both live and reference into 96 px wide grayscale edge images (Sobel), find the horizontal shift in ±20 px with the best overlap and its match score. Background dx small (≤ 4 px) with a large person-x error → `Who.subject`; otherwise `Who.camera`. Low match score → always `camera`.

## How to work
- Before each step, show the files and function signatures and get my approval.
- Verify every sign with unit tests. If the device says "step back" while I am getting closer, suspect the sign on that axis.
- `flutter analyze` with 0 warnings, `flutter test` passes, `flutter build apk --debug` before a PR.
- If stuck for more than 30 minutes, write a "where I'm stuck" summary for the team chat.
