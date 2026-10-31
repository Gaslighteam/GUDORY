# AGENTS.md — GUDORY (구도리)

> Every AI agent working in this repo reads this whole file before doing anything.
> If an instruction conflicts with this file, stop and ask a human instead of acting.
> Work one step at a time and report what you verified on a real device after each step.

## 1. Product
- One line: a camera app that turns the owner's sense of a good shot into instructions a non-photographer can follow with eyes, ears, hands and feet ("one step back", "lower the phone by one fist"), delivered as one on-screen sentence at a time plus proximity beeps and vibration. **No voice guidance** (removed by team decision).
- Contest theme keyword: **감각 (sense)**. Shown on the first screen: "사진 감각, 빌려드릴게요".
- Two modes, switched with a button at the top left:
  - **추천 모드 (recommend)**: the app looks at the background in the camera view, finds similar photos of one person (team and friends' phone photos, plus a supplementary dataset) and uses their composition as the target. A **5-step bar** chooses 인물 중심 (1, person large) ↔ 배경 중심 (5, person small).
  - **맞춤 모드 (custom)**: the active **reference photo** (the user may load several; they persist until reset) is the target. With no reference, coaching pauses and the bubble asks for one.
- **Portrait and landscape** shots are both supported. The UI stays portrait-locked; the phone's physical orientation (accelerometer) decides the shot orientation.
- No categories and no hashtags (removed 2026-10-31 by team decision).
- Deliverable: Android APK. iOS is out of scope.

## 2. Stack (pinned)
- Flutter **3.44.8** stable / Dart 3.12. Android only. minSdk 24.
- Packages (already in pubspec; **only the lead adds packages**): `flutter_riverpod`, `go_router`, `camera`, `google_mlkit_pose_detection`, `google_mlkit_selfie_segmentation`, `onnxruntime`, `image`, `sensors_plus`, `vibration`, `audioplayers`, `image_picker`, `gal`, `sqflite`, `path_provider`, `http`, `wakelock_plus`, `connectivity_plus`
- AI: ML Kit Pose (real time), ML Kit Selfie Segmentation (person mask), CLIP ViT-B/32 vision encoder ONNX (q8 bundled, bigger model downloaded when online), LLM only on the server (`api/`).
- Python tools (`tools/`): Python 3.12 via uv, transformers, mediapipe.

## 3. Folder rules (most important)
```
app/lib/core/models.dart, contracts.dart   contracts — lead only
app/lib/app/                               router, theme, tokens — lead
app/lib/features/camera/, feedback/        Taeho
app/lib/features/coach/                    Eungyu
app/lib/features/scene/                    Seojun
app/assets/                                recommend.json, recommend_v2.json (tools output) / *.onnx (gitignored)
tools/                                     Seojun (unsplash_candidates.py: Bomin)
data/                                      Bomin (photos/, unsplash/, openimages/ gitignored, nothing but README committed)
api/                                       Taeho
```
- **Never edit outside your own folder.** If you need something there, write a "request for the lead" and stop.
- Do not change the contracts in `core/`. Request a change instead. If a contract lacks something, add an internal type inside your own folder.
- Do not install packages. Request it (a native dependency can break the build for everyone).
- If another module does not exist yet, write a **Fake** implementing the interface in `contracts.dart` inside your own folder and keep going.

## 4. Contracts (app/lib/core)

### models.dart
```dart
enum CoachAxis { level, distance, horizontal, height }
enum Who { camera, subject }
enum InstructionKey {
  holdPhoneUpright,            // level
  stepBack, stepForward,       // distance (photographer)
  stepLeft, stepRight,         // horizontal (photographer, body-relative)
  subjectLeft, subjectRight,   // horizontal (subject) — Should
  phoneUp, phoneDown,          // height
  fitWholeBody,                // whole body not in frame
  noPerson,                    // no person visible
  aligned,                     // good, hold still
  turnLandscape, turnPortrait, // target orientation differs from how the phone is held
  addReference,                // custom mode with no reference
  raisePhone,                  // phone lies flat (rollReliable false) and the other axes are aligned: axis null, aligned false
}
enum ShootMode { recommend, custom }
enum ShotOrientation { portrait, landscape }
enum Framing { chestUp, waistUp, kneeUp, fullBody } // lowest visible anchor: shoulders / hips / knees / ankles
class Landmark { final double x, y, visibility; }          // 0~1, shot space (see below)
class PoseFrame {
  final List<Landmark>? landmarks;   // 33 points in ML Kit PoseLandmarkType order, null = no person
  final int imageWidth, imageHeight; // in shot space (landscape: width > height)
  final ShotOrientation orientation; // from the accelerometer, hysteresis 45°/60°
  final double rollDeg, pitchDeg;    // sensors, relative to the shot orientation; level = 0, 0
  final bool rollReliable;           // default true; false while the phone lies flat (skip the level axis)
  final DateTime at;
}
class TargetComposition {
  final Framing framing;
  final double personHeightRatio; // (head top ~ framing anchor) / frame height, 0~1 (see the table below)
  final double personCenterX;     // shoulder midpoint x, 0~1
  final double personCenterY;     // eye line y (mean of both eyes), 0~1
  final double? horizonY;         // optional
  final ShotOrientation orientation;
  final double tolHeight, tolX, tolY; // defaults 0.10, 0.08, 0.08
  final double tolRollDeg;        // default 3
  final String source;            // 'reference' | 'recommend:<1-5>' | 'fallback'
}
class Recommendation {
  final TargetComposition target;
  final int neighbors;            // photos behind the target (0 = fallback median only, no CLIP)
  final String modelVariant;      // 'q8' | 'fp16' | 'none'
}
class CoachInstruction {
  final InstructionKey key; final CoachAxis? axis; final Who who;
  final double amount;            // steps or fists, 0.5 units, min 0.5
  final double error;             // normalized error of the active axis (<= 1.0 = aligned)
  final bool aligned;             // all four axes aligned
  final Map<CoachAxis, double> errors; // for debug overlay
}
class CameraFrame { final CameraImage image; final int sensorOrientation; final bool isFrontCamera; }
```

### contracts.dart
```dart
abstract class FrameBus { Stream<CameraFrame> get frames; }                       // Taeho. Frames arriving while busy are dropped (consumer's job)
abstract class CoachEngine { CoachInstruction update(PoseFrame f, TargetComposition t); void reset(); } // Eungyu
abstract class PoseSource { Stream<PoseFrame> poses(FrameBus bus); }               // Eungyu. ML Kit + sensors, max 15/s
abstract class ReferenceAnalyzer { Future<TargetComposition> analyze(String imagePath); } // Eungyu. Throws NoPersonException
abstract class WhoMoves { Who decide(CameraFrame live, String referencePath, double subjectXError); } // Eungyu, Should
abstract class Recommender {                                                      // Seojun. UI calls every ~3 s in recommend mode
  Future<void> warmUp();                                                           // loads recommend.json + CLIP
  Future<Recommendation> recommend(CameraFrame f, int level, ShotOrientation o);   // level 1~5. Never throws: falls back to the level median
}
abstract class ModelManager { Future<String> ensureBest(); String get activeVariant; Stream<double> get downloadProgress; } // Seojun
abstract class FeedbackService { void proximity(double error); void aligned(); void stop(); } // Taeho
```
- `PoseFrame.landmarks` are 0~1 values **already rotated into shot space**: the frame as the saved photo will look (portrait, or landscape when the phone is held sideways). PoseSource (Eungyu) does the rotation using `orientation`.
- Shot space = the part of the camera frame **visible in the preview** (`visibleCropProvider` in `features/camera/framing.dart`); the saved photo is exactly that crop. **Who does what:** PoseSource emits landmarks 0~1 over the **whole analysis frame**, rotated to the shot orientation — it does **not** crop. `coaching.dart` maps them into the visible crop (`toVisible(frame, cropInShotSpace(...))`) right before `CoachEngine.update`, so the engine sees 0~1 inside the saved photo. Do not crop twice.
- Shot orientation: **use `core/orientation.dart`** (shared by PoseSource and the UI): `nextHeldOrientation(current, ax, ay)` (|roll| > 60° → landscape, < 45° → portrait, flat guard), `accelRollDeg(ax, ay)` (+ = top tilted left), `levelRollDeg(roll, held)` (landscape measured from ±90° → `PoseFrame.rollDeg`), `isRollReliable(ax, ay)` (→ `PoseFrame.rollReliable`; false while flat: keep the last reliable `rollDeg` and skip the level axis). `HeldOrientation.quarterTurns`: 1 = top to the left, -1 = top to the right.
- Head reference (Eungyu and Seojun use **the same formulas**, identical constants). Only **both shoulders** (visibility ≥ 0.5) are required. Nose and eyes use the **estimated coordinates the pose model always returns, regardless of their visibility score** — on a back view or profile they land near the back/side of the head, which is close enough, so **back views and profiles are kept**:
  - eye line y (`cy`) = mean of both eyes' y
  - head top y = nose y − 0.5 × (shoulder-mid y − nose y)
  - Person count (Seojun): `PoseLandmarker(num_poses=2)` plus a person detector; more than one person → drop (`tools/pose_analysis.py`). Exactly one pose; the main person is the top detector box (score ≥ 0.3); another person box at least 15% of the main person's height is a second subject → drop; smaller ones are background passers-by and stay.
  - Training-data filters (Python only): head top or nose outside the frame, main person under 20% of the frame height, a hand longer than 2× the head-to-shoulder height (hand in front of the lens, lying or folded bodies), and a person crop that CLIP scores ≥ 0.85 as a painting/statue/poster/mannequin/mirror (`tools/person_prompts.npz`).
- Framing and body span (same formulas on both sides, written once in `features/coach/` and ported to Python):

  | Framing | Anchor (lowest visible, visibility ≥ 0.5) | Span | Real span L |
  |---|---|---|---|
  | `chestUp` | shoulders | head top ~ shoulder mid | 0.28 m |
  | `waistUp` | hips | head top ~ hip mid | 0.80 m |
  | `kneeUp` | knees | head top ~ knee mid | 1.15 m |
  | `fullBody` | ankles | head top ~ ankle mid | 1.55 m |
- Live frames are measured **at the target's framing**: if the target anchor is not visible (e.g. target `fullBody`, ankles cut off), estimate it from the visible landmarks with the real-span ratios above, so the distance axis says "step back". `fitWholeBody` is no longer needed for that case.
- `amount` conversion (Eungyu): distance d(m) ≈ L / (personHeightRatio × 2·tan(fov/2)), fov = 65° vertical in portrait, 50° in landscape; one step = 0.6 m; one fist = 0.1 m; round to 0.5.
- Camera angle (high / low) is **not** coached (cannot be learned from photos); the height axis covers raising or lowering the phone.
- Instruction order: **orientation** (target ≠ frame → `turnLandscape`/`turnPortrait`) → level → distance → horizontal → height. Enter when |error| > 1.0, exit when < 0.8, hold at least 1.5 s. `aligned` when all four ≤ 1.0.
- Directions stay body-relative to the photographer in both orientations ("왼쪽으로 한 걸음", "폰을 아래로").

### Camera → ML Kit conversion recipe (Eungyu and Seojun)
- Stream format `ImageFormatGroup.nv21`. `InputImageMetadata(rotation: InputImageRotation from sensorOrientation, format: nv21, bytesPerRow: planes[0].bytesPerRow)`.
- Front camera: mirror x. UI portrait locked (`DeviceOrientation.portraitUp`); the shot orientation comes from the accelerometer, not the UI.

### Asset format
- `recommend.json` (built by `tools/build_assets.py`):
  ```json
  { "model": "clip-vit-base-patch32", "dim": 512, "quant": "int8",
    "levels":   { "portrait": [0.30, 0.17, 0.10, 0.06], "landscape": [0.32, 0.18, 0.11, 0.07] },
    "fallback": { "portrait": { "1": {"f":"chestUp","h":0.62,"cx":0.5,"cy":0.33,"hy":null}, "...": {} }, "landscape": { } },
    "clusters": [ { "o":"p", "e":"<base64 int8 x512>", "n":41,
                    "lv": { "1": {"f":"waistUp","h":0.70,"cx":0.5,"cy":0.30,"hy":null,"n":8}, "2": {}, "3": {}, "4": {}, "5": {} } } ] }
  ```
  - **Person scale** s = (head top ~ shoulder mid) / frame height — measurable in every framing. `levels` = quintile edges of s per orientation (descending). Level 1 = person largest (인물 중심, mostly `chestUp`/`waistUp`), 5 = smallest (배경 중심, mostly `fullBody`).
  - `f` = the most common framing of those photos; `h` = median span **at that framing**, `cx`/`cy`/`hy` = medians.
  - `fallback`: per orientation × level, over all photos (used when CLIP is unavailable).
  - `clusters`: k-means (k ≈ 64 per orientation) over background embeddings of one-person photos (any framing). `e` = L2-normalized cluster centre, int8 (value × 127). `lv` per level (missing when a level has < 3 photos).
  - **No per-photo data** (no photo ids, no per-photo embeddings or numbers) goes into the app or the repo: dataset terms forbid publishing any portion of the data, and team/friends' photos are private. Only aggregated clusters and medians.

## 5. CLIP and recommendation (Seojun)
- Preprocessing: resize short side to 224 → center crop 224×224 → RGB/255 → mean [0.48145466,0.4578275,0.40821073], std [0.26862954,0.26130258,0.27577711] → `pixel_values [1,3,224,224] float32` → `image_embeds [1,512]` → L2 normalize. Same in `tools/` and the app.
- Fill person-mask pixels with the image mean color before running CLIP (we compare **backgrounds**).
- Recommend: live background embedding → cosine with clusters of the same orientation → top 3 clusters that have the chosen level (else the nearest level) → framing = the top cluster's `f`; average the `lv` medians of clusters with that framing, weighted by cosine × n → `TargetComposition(source: 'recommend:<level>')`. CLIP failure → `fallback`.
- **Recommend v2** (`recommend_v2.json`, `tools/train_recommender_v2.py`, `features/scene/composition_model.dart`; used when present, any failure → the v1 path above): PCA(k=32) of the same background embedding + one-hot(orientation, level) → framing (multinomial logistic), offset `|cx − 0.5|` and `cy` (ridge), `h` from an (orientation, level, framing) table. **Side is not learned:** `cx = 0.5 ± offset` on the side of the person-mask centroid (`SceneEmbeddingTrace.personX`); photo rules may override it with the facing direction. Trained on CADB `human` photos weighted by composition score (`docs/cadb.md`, `tools/report_v2.md`). `source: 'recommend-v2:<level>'`, `neighbors` = training photos.
- Model files: bundled `assets/clip/vision_q8.onnx` (copied once to the app directory), downloaded `<appDir>/models/vision_big.onnx`. Same inputs/outputs.

### Training data
- Goal: everyday / travel photos **as people post on Instagram** (taken by a friend with a phone), any framing from chest-up to full body.
- **Primary: `data/photos/team/`** — photos taken by team members, and by friends who gave permission (Bomin collects). These match the target style best.
- **Supplementary (to be decided by Bomin after a test):** Open Images V7 (Flickr, CC BY 2.0) one-person photos ranked by CLIP for "phone snapshot" style, or Unsplash Lite (too many studio portraits; only ~100 phone shots). Whatever is used: raw files, photos and per-photo numbers stay on the PC; only the aggregated `recommend.json` ships; credit it in README.
- `build_assets.py` should weight team photos above supplementary ones.
- Square photos (w/h between 0.9 and 1.1, e.g. Instagram crops): after pose detection, centre-crop to portrait 3:4; if the nose or a shoulder falls outside, centre-crop to landscape 4:3 instead; if both cut the person, drop the photo. Crop around the **image centre**, not the person, so the photographer's composition is kept.
- **Pexels is not allowed**: its terms forbid automated collection for machine-learning purposes.
- `build_assets.py` keeps one-person photos whose head and shoulders are visible (pose), classifies the framing, and builds `recommend.json`.

## 6. UX rules (from the UI mock)
- **Preview is 3:4 (the still's own aspect), letterboxed** like Samsung's 3:4 mode: the top bar sits in the black area above it, the shutter row in the black area below. What you see is the whole photo, so saving does no crop; landscape shots only get their EXIF orientation rewritten (`exif_orientation.dart`), no re-encode.
- Camera screen (matches the mock): **mode toggle `추천 | 맞춤` at the top left**, X right of the toggle (reset references, custom mode only, shown when references exist) and flash at the top right, 3×3 grid, dashed center lines with a ringed dot, **one instruction bubble + direction arrow** (upper third), zoom pill `.6 / 1x / 2 / 3` (only supported levels) that opens a **continuous slider** when dragged sideways, pinch zoom, bottom row = **reference slot** · shutter · flip.
- **Mid row (bottom of the preview):** composition button (recommend only) · zoom pill · ⠿ menu. Each round button **expands in place** into its panel (`ExpandFromButton`): composition = × · 인물 · 5 silhouettes · 배경 (default 3, closes 3 s after the last touch); ⠿ = 사용법 · language · ⚙ settings · ×. A tap anywhere outside the open panel closes it (`TapRegion`).
- **Recommend mode**: composition button shown; the reference slot is hidden.
- **Custom mode**: the 5-step bar is hidden; the reference slot is shown.
- In landscape, icons and the bubble rotate 90° in place (the layout does not move).
- **Do not draw a person outline.**
- References: tap the bottom-left slot to pick **one or more** photos (portrait or landscape). The active one (yellow border) is the target; with several, a sheet lets the user switch, add, remove or clear. **References persist across shots** and are removed only by X / "모두 지우기".
- **No result screen.** After a shot the photo is saved to the GUDORY album and a short toast confirms it.
- **No auto shutter** (team decision): `aligned` → ding + vibration + yellow shutter ring and the bubble says "좋아요! 지금 셔터를 눌러 주세요"; the photographer always presses the shutter.
- **Front camera = plain camera**: the flip button switches to it; coaching, recommendations, the bubble, mode toggle, level bar and reference slot are off until switching back (flash, zoom, shutter, flip, `?` and language stay).
- **Swipe up/down on the preview flips the camera** (along the held vertical, so it works sideways too); pinch still zooms.
- **Shutter sound = the system camera sound** (`camera_click.ogg` with MediaActionSound's enforced-audible attributes, played at 0.18 volume via the `gudory/shutter` channel in `MainActivity.kt`); in Korea it plays even in silent mode, like the stock camera. No setting for it.
- **⠿ menu:** 사용법 starts the tour; language morphs the same pill into `한국어 · English · 日本語` (no sheet); picking one highlights it, closes the panel, and the bubble text follows it; ⚙ opens `/settings`.
- **How-to = a tour on the real camera screen** (`features/tutorial/camera_tour.dart`), not separate pages: the screen dims except a hole around one control; touches outside the hole are blocked, on "try it" steps the control works and using it moves on. Steps live in `CameraScreen._tourSteps` (target = a `GlobalKey` on the control; missing controls are skipped). Shown automatically on the first launch (`TutorialGate`, flag file), and from ⠿ → 사용법 or settings.
- **Settings** (`/settings`, `features/settings/`): language, distance beeps, done sound, vibration, grid lines, centre mark (persisted to `settings.json` in the app support dir via `settingsProvider`; `languageProvider` reads from it), plus where photos are saved, replay the tour, version, team, open-source licences.
- **Brand:** `docs/brand/logo.svg` is the source. `python tools/brand/make_icons.py` regenerates the launcher icons (adaptive yellow G on black + monochrome, legacy PNGs) and `app/assets/brand/logo_on_dark.png` (RY in white for dark screens).
- **Hand-over mode was removed** (team decision).
- No empty buttons or "coming soon" screens; drop what does not work. UI text in Korean, no photography jargon ("틸트" → "폰 윗부분을 앞으로").
- Tokens: background `#000000`, bubble `#333336` at ~78% radius 24, bottom bar (5-step bar) `#1C1C1E`, selected chip `rgba(255,255,255,0.18)` radius 16, text `#FFFFFF`, accent (1x) `#FFD60A`, font Pretendard (system fallback), body 16 / instruction 17 / chip 15.

## 7. Security and data
- Lablup key and Vercel tokens never go into the app or the repo. LLM calls only from `api/`, env vars `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`.
- Photos never leave the phone (the LLM receives only instruction templates as text).
- `data/photos/`, `data/unsplash/`, `data/openimages/`, `app/assets/clip/*.onnx`, `*.keystore`, `.env*` are never committed (.gitignore).

## 8. Git
- Branches `feat/camera` `feat/coach` `feat/scene` `feat/tools` `data/photos`. main only via PR; the lead merges (19:30 / 22:00 / 01:00 / 03:00 / 05:30 / 08:00 / 10:30 / 11:00). **Development ends Sunday 11:00**; after that only critical bug fixes.
- Commits `feat(coach): ...` / `fix(scene): ...` / `data: ...` / `docs: ...`. Small and often.
- Before a PR: `cd app && flutter analyze && flutter build apk --debug` must pass.
- **No commits or pushes after Sunday 12:30.** Do not paste code written before the contest.

## 9. Definition of done
1. `flutter analyze` with 0 warnings, `flutter build apk --debug` succeeds
2. The feature works end to end on a **real Android device**
3. The screen does not break when a model or the network fails (there is a fallback)
