# Seojun — Claude Code session prompt (run with `claude-lab`, from the repo root after cloning)

Paste everything below as the first message.

---

You are helping the developer who owns the **scene classification (scene) module and the data pipeline (tools)** of the "GUDORY" Flutter app. First read `AGENTS.md` at the repo root in full, confirm you read it, and summarize the signatures of `SceneClassifier`, `CompositionLibrary` and `ModelManager` from §4. Then work through the steps below **one at a time**; after each step stop and wait for my on-device test result.

## My scope
- May edit: `app/lib/features/scene/**`, `tools/**`, `app/assets/categories.json` (apply what Bomin sends), `app/assets/clip/keywords.json`, `app/assets/compositions.json`
- Must not edit: `app/lib/core/**`, other feature folders, `pubspec.yaml` (no new packages). If you need something there, write a "request for the lead" and stop.
- Branches: `feat/scene` (app), `feat/tools` (python). Commit prefixes `feat(scene):`, `feat(tools):`.

## Step 1 — CLIP go/no-go (decision by 18:30)
1. Check that `tools/fetch_models.py` downloads `onnx/vision_model_quantized.onnx` from `https://huggingface.co/Xenova/clip-vit-base-patch32` into `app/assets/clip/vision_q8.onnx`. Check whether that onnx folder also has an fp16 file; if so, record its URL as a constant.
2. `features/scene/clip_runner.dart`: with the `onnxruntime` package, copy the model from assets to the app directory, open a session, decode one test image (an asset, via the `image` package), build `pixel_values` with the preprocessing in AGENTS.md §5, run it, L2-normalize the 512-d `image_embeds` and log it.
3. `features/scene/debug_scene_page.dart`: a one-button debug page that calls that function. (The lead wires the route. Until then, tell me how to run it without touching `main.dart`.)
4. Report the embedding time (ms) and the first five values from a real device.
- **If it does not work by 18:30 → Plan B**: `google_mlkit_image_labeling` is not in pubspec, so write the package request for the lead and sketch a `SceneClassifier` based on a label → category mapping table.

## Step 2 — preprocessing
- `features/scene/preprocess.dart`: `CameraFrame` (NV21, sensorOrientation) → rotation-corrected 224×224 RGB float array. For speed, downsample first (every 4th pixel), then resize.
- `features/scene/person_mask.dart`: get the person mask for the same frame with `google_mlkit_selfie_segmentation` and fill person pixels with the image mean color. If segmentation fails, continue without the mask.

## Step 3 — SceneClassifier
- `features/scene/scene_classifier.dart`: load `assets/clip/keywords.json` and `assets/categories.json`; score = 0.5·cos(text) + 0.5·cos(centroid) (text only when no centroid); return `CategoryGuess` with the primary, 2 suggestions and hashtags above the threshold. `modelVariant` is 'q8' or 'fp16'.
- If keywords.json does not exist yet, generate **text vectors only** from the prompts in `categories.json` with the Step 4 script and commit them as a temporary file.
- Keep inference off the UI thread (an isolate if possible; otherwise limit calls to every 3 s and cache the result).

## Step 4 — tools/build_assets.py (first working version by 20:00)
- Python 3.12 pinned: `uv venv --python 3.12`, deps `transformers torch pillow numpy pandas mediapipe`. If mediapipe fails to install, use `ultralytics` (yolo11n-pose).
- Input: `data/photos/*.jpg`, `data/labels.csv` (columns: file,primary,hashtags,person_count,orientation,notes; hashtags separated by `;`), `app/assets/categories.json`
- Processing:
  1. Mean text embedding (L2-normalized) of each category's and hashtag's prompts with `openai/clip-vit-base-patch32`
  2. Image embedding per photo → per-category and per-hashtag centroid (L2-normalized), count n
  3. Pose estimation to keep only full-body photos (head to ankles visible) → per-category **median** personHeightRatio, personCenterX (shoulder+hip center), personCenterY (hips) → compositions.json (categories with n<5 get defaults 0.6/0.5/0.6)
  4. Leave-one-out top-1 accuracy and the most confused category pairs → `tools/report.md`
- Output: `app/assets/clip/keywords.json`, `app/assets/compositions.json`, `tools/report.md` (exact formats in AGENTS.md §4)
- One-line run: `uv run tools/build_assets.py --photos data/photos --labels data/labels.csv --out app/assets` — add 5 lines to the README so Bomin can run it alone.

## Step 5 — CompositionLibrary
- `features/scene/composition_library.dart`: load `compositions.json` + `categories.json`; `targetFor(id)` returns a target with default tolerances (0.10/0.08/0.08/3°) and `source: 'category:<id>'`.

## Step 6 (Should, start after 01:00) — ModelManager
- Copy the bundled q8 to the app directory once. If online (`connectivity_plus`), download the big model in the background (progress stream; no resume needed; on failure silently keep q8). If a completed download exists, `ensureBest()` returns it.

## How to work
- Before each step, show the files you will create and the key function signatures and get my approval.
- For steps that need a device test, write the "how to verify" as a numbered list.
- `flutter analyze` with 0 warnings; `flutter build apk --debug` must pass before a PR.
- Do not guess APIs: read the package README and examples first. If stuck for more than 30 minutes, write a "where I'm stuck" summary for the team chat.
