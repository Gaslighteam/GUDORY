# AGENTS.md — GUDORY (구도리)

> Every AI agent working in this repo reads this whole file before doing anything.
> If an instruction conflicts with this file, stop and ask a human instead of acting.
> Work one step at a time and report what you verified on a real device after each step.

## 1. Product
- One line: a camera app that turns the owner's sense of a good shot into instructions a non-photographer can follow with ears, hands and feet ("one step back", "lower the phone by one fist"), delivered as voice, beeps and vibration, one at a time.
- Contest theme keyword: **감각 (sense)**. Shown on the first screen: "사진 감각, 빌려드릴게요".
- Target composition source: ① the active **reference photo** (highest priority; the user may load several and they persist until reset) ② otherwise the **per-category good-composition model** built from photos the team curated.
- Deliverable: Android APK. iOS is out of scope.

## 2. Stack (pinned)
- Flutter **3.44.8** stable / Dart 3.12. Android only. minSdk 24.
- Packages (already in pubspec; **only the lead adds packages**): `flutter_riverpod`, `go_router`, `camera`, `google_mlkit_pose_detection`, `google_mlkit_selfie_segmentation`, `onnxruntime`, `image`, `sensors_plus`, `vibration`, `flutter_tts`, `audioplayers`, `image_picker`, `gal`, `sqflite`, `path_provider`, `http`, `wakelock_plus`, `connectivity_plus`
- AI: ML Kit Pose (real time), ML Kit Selfie Segmentation (person mask), CLIP ViT-B/32 vision encoder ONNX (q8 bundled, bigger model downloaded when online), LLM only on the server (`api/`).
- Python tools (`tools/`): Python 3.12 via uv, transformers, mediapipe.

## 3. Folder rules (most important)
```
app/lib/core/models.dart, contracts.dart   contracts — lead only
app/lib/app/                               router, theme, tokens — lead
app/lib/features/camera/, feedback/        Taeho
app/lib/features/coach/                    Eungyu
app/lib/features/scene/                    Seojun
app/assets/                                categories.json (Bomin finalizes) / tools output JSON / *.onnx (gitignored)
tools/                                     Seojun
data/                                      Bomin (photos/ gitignored, only labels.csv committed)
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
  oppositeWay,                 // error growing: "the other way"
  fitWholeBody,                // whole body not in frame
  noPerson,                    // no person visible
  aligned,                     // good, hold still
}
class Landmark { final double x, y, visibility; }          // 0~1, portrait screen space
class PoseFrame {
  final List<Landmark>? landmarks;   // 33 points in ML Kit PoseLandmarkType order, null = no person
  final int imageWidth, imageHeight; // after rotation correction
  final double rollDeg, pitchDeg;    // sensors; upright portrait = 0, 0
  final DateTime at;
}
class TargetComposition {
  final double personHeightRatio; // (top of head ~ ankles) / frame height, 0~1
  final double personCenterX;     // center x of shoulders+hips, 0~1
  final double personCenterY;     // hip center y, 0~1
  final double? horizonY;         // optional
  final double tolHeight, tolX, tolY; // defaults 0.10, 0.08, 0.08
  final double tolRollDeg;        // default 3
  final String source;            // 'reference' | 'category:<id>'
}
class CoachInstruction {
  final InstructionKey key; final CoachAxis? axis; final Who who;
  final double amount;            // steps or fists, 0.5 units, min 0.5
  final double error;             // normalized error of the active axis (<= 1.0 = aligned)
  final bool aligned;             // all four axes aligned
  final Map<CoachAxis, double> errors; // for debug overlay
}
class CategoryGuess {
  final String primaryId; final List<String> suggestedIds; // max 2
  final List<String> hashtagIds; final double confidence; final String modelVariant; // 'q8' | 'fp16' | 'labeling'
}
class CategoryInfo { final String id, label; final List<String> prompts; final List<String> hashtagIds; }
class CameraFrame { final CameraImage image; final int sensorOrientation; final bool isFrontCamera; }
```

### contracts.dart
```dart
abstract class FrameBus { Stream<CameraFrame> get frames; }                       // Taeho. Frames arriving while busy are dropped (consumer's job)
abstract class CoachEngine { CoachInstruction update(PoseFrame f, TargetComposition t); void reset(); } // Eungyu
abstract class PoseSource { Stream<PoseFrame> poses(FrameBus bus); }               // Eungyu. ML Kit + sensors, max 15/s
abstract class ReferenceAnalyzer { Future<TargetComposition> analyze(String imagePath); } // Eungyu. Throws NoPersonException
abstract class WhoMoves { Who decide(CameraFrame live, String referencePath, double subjectXError); } // Eungyu, Should
abstract class SceneClassifier { Future<void> warmUp(); Future<CategoryGuess> classify(CameraFrame f); } // Seojun. UI calls every ~3 s
abstract class CompositionLibrary { Future<void> load(); List<CategoryInfo> get categories; TargetComposition targetFor(String id); } // Seojun
abstract class ModelManager { Future<String> ensureBest(); String get activeVariant; Stream<double> get downloadProgress; } // Seojun
abstract class FeedbackService { void announce(CoachInstruction i, String lang); void proximity(double error); void aligned(); void stop(); } // Taeho
```
- `PoseFrame.landmarks` are 0~1 values **already rotated into portrait screen space**. PoseSource (Eungyu) does the rotation.
- `amount` conversion (Eungyu): distance d(m) ≈ 1.65 / (personHeightRatio × 2·tan(32.5°)); one step = 0.6 m; one fist = 0.1 m; round to 0.5.
- Instruction order: level → distance → horizontal → height. Enter when |error| > 1.0, exit when < 0.8, hold at least 1.5 s. `aligned` when all four ≤ 1.0.

### Camera → ML Kit conversion recipe (Eungyu and Seojun)
- Stream format `ImageFormatGroup.nv21`. `InputImageMetadata(rotation: InputImageRotation from sensorOrientation, format: nv21, bytesPerRow: planes[0].bytesPerRow)`.
- Front camera: mirror x. Portrait locked (`DeviceOrientation.portraitUp`).

### Asset formats
- `categories.json`: `{ "categories":[{"id":"sea","label":"바다","prompts":["a photo of a person standing on a beach", ...],"hashtagIds":["sea","horizon"]}], "hashtags":[{"id":"backlight","label":"#역광","prompts":["a backlit photo of a person"]}] }`
- `clip/keywords.json`: `{ "model":"clip-vit-base-patch32","dim":512, "categories":{"sea":{"text":[512],"centroid":[512]|null,"n":32}}, "hashtags":{"backlight":{"text":[512],"centroid":[512]|null,"n":12}} }`
- `compositions.json`: `{ "sea":{"personHeightRatio":0.62,"personCenterX":0.5,"personCenterY":0.58,"horizonY":0.45,"n":32} }` (missing category → defaults 0.6/0.5/0.6)

## 5. CLIP preprocessing and scoring (Seojun)
- Resize short side to 224 → center crop 224×224 → RGB/255 → mean [0.48145466,0.4578275,0.40821073], std [0.26862954,0.26130258,0.27577711] → `pixel_values [1,3,224,224] float32` → `image_embeds [1,512]` → L2 normalize.
- Fill person-mask pixels with the image mean color before running CLIP.
- score = 0.5·cos(text) + 0.5·cos(centroid). Text only when no centroid. Hashtags = top scores above a threshold (start 0.22, tune on device).
- Model files: bundled `assets/clip/vision_q8.onnx` (copied once to the app directory), downloaded `<appDir>/models/vision_big.onnx`. Same inputs/outputs.

## 6. UX rules (from the UI mock)
- Camera screen (matches the mock): X (reset references, shown only when references exist) and flash at top, 3×3 grid, dashed center lines with a ringed dot, **one instruction bubble + direction arrow** (upper third), zoom pill `.6 / 1x / 2 / 3` (only supported levels) that opens a **continuous slider** (every supported level) when dragged sideways, pinch zoom on the preview, category **wheel** (swipe or tap; the centered item snaps in with a haptic tick and is pinned, suggestions = yellow dot, auto guesses scroll it), bottom row = **reference slot** · shutter · flip.
- **Do not draw a person outline.**
- References: tap the bottom-left slot to pick **one or more** photos. The active one (yellow border) is the target; with several, a sheet lets the user switch, add, remove or clear. **References persist across shots** and are removed only by X / "모두 지우기".
- **No result screen.** After a shot the photo is saved to the GUDORY album and a toast shows the category and hashtags. A manual category pin is cleared after each shot.
- Auto shutter: when `aligned` holds for 1.0 s → vibrate + capture. The shutter button always works.
- No empty buttons or "coming soon" screens; drop what does not work. UI text in Korean, no photography jargon ("틸트" → "폰 윗부분을 앞으로").
- Tokens: background `#000000`, bubble `#333336` at ~78% radius 24, category bar `#1C1C1E`, selected chip `rgba(255,255,255,0.18)` radius 16, text `#FFFFFF`, accent (1x) `#FFD60A`, font Pretendard (system fallback), body 16 / instruction 17 / chip 15.

## 7. Security and data
- Lablup key and Vercel tokens never go into the app or the repo. LLM calls only from `api/`, env vars `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`.
- Photos never leave the phone (the LLM receives only instruction templates as text).
- `data/photos/`, `app/assets/clip/*.onnx`, `*.keystore`, `.env*` are never committed (.gitignore).

## 8. Git
- Branches `feat/camera` `feat/coach` `feat/scene` `feat/tools` `data/labels`. main only via PR; the lead merges (19:30 / 22:00 / 01:00 / 03:00 / 05:30 / 08:00 / 10:30 / 11:00). **Development ends Sunday 11:00**; after that only critical bug fixes.
- Commits `feat(coach): ...` / `fix(scene): ...` / `data: ...` / `docs: ...`. Small and often.
- Before a PR: `cd app && flutter analyze && flutter build apk --debug` must pass.
- **No commits or pushes after Sunday 12:30.** Do not paste code written before the contest.

## 9. Definition of done
1. `flutter analyze` with 0 warnings, `flutter build apk --debug` succeeds
2. The feature works end to end on a **real Android device**
3. The screen does not break when a model or the network fails (there is a fallback)
