# GUDORY — 4-person work plan

Written Sat 2026-10-31 16:40 · **Development until Sun 11:00** · final push **12:15** · commit freeze **12:30** · form deadline **13:00**
About **18 hours** of development left. Deliverable is an **Android APK**; iOS is presented as "coming soon".
Video, upload, README and the final push all have to fit in the 90 minutes after 11:00, so **10:30 = "stable build for the video"** is a fixed point (10:30–11:00 only changes that cannot break that build).

---

## 0. Decisions from today's meeting and how they land

| Decision | In the plan |
|---|---|
| Optional reference photo per shot (reference wins when present, auto-clear after the shot, clear button, visible "in use" state) | Top-center "reference" pill + badge on the camera screen. Target source = `reference` > `category` |
| Strengthen CLIP with team-curated good photos per category | `data/` photos + `labels.csv` → `tools/build_assets.py` → `keywords.json` (CLIP centroids) + `compositions.json` (good composition numbers per category) |
| Offline = compressed model bundled in the app, online = larger model downloaded and run on the phone | `ModelManager`: bundled q8 (~88 MB) by default; when online, download fp16/fp32, cache it, prefer it. Photos never leave the phone |
| Auto category + suggested categories, user can tap to change | Bottom chips: primary highlighted, 2 suggestions with a dot, tap = manual pin (released after the shot) |
| Multi-label hashtags | One category + several hashtags. Shown on the result screen and stored with the photo |
| UI = attached mock, **person outline removed** | Grid, center crosshair, instruction bubble with arrow, zoom chips, category chips, shutter, thumbnail, flip, X, flash |
| Roles = 3 developers + 1 data | Taeho, Seojun, Eungyu develop; Bomin designs categories/hashtags, collects and labels photos, drafts the slides |

---

## 1. Scope

### Screen flow
```
[Camera] ──(tap reference pill)──▶ pick from gallery ──▶ analyze ──▶ Camera (reference-in-use badge)
   │  pose + sensors → one instruction bubble + voice + beeps + vibration
   │  "aligned" held 1 s → auto capture (shutter always available)
   ▼
[Result] original photo (+ reference side by side) + category/hashtag chips + saved to gallery
   └─ "shoot again" → Camera (reference and manual category cleared)
```

### Priorities
| Tier | Feature | Owner |
|---|---|---|
| **Must** | Camera screen UI (as mocked) + full-resolution capture + gallery save + result screen | Taeho |
| **Must** | Voice (TTS), beeps (faster when closer), vibration, auto capture | Taeho |
| **Must** | Reference pick, badge, clear, auto-clear after shot | Taeho (UI) / Eungyu (analysis) |
| **Must** | Coaching engine: pose + sensors → 4-axis error (level, distance, horizontal, height) → pick one instruction (1.5 s hold, hysteresis) → body-relative amount | Eungyu |
| **Must** | Reference analyzer: one photo → target composition | Eungyu |
| **Must** | Scene classification: remove person → CLIP → 1 category + 2 suggestions + hashtags | Seojun |
| **Must** | Per-category good-composition library (`compositions.json`) → target composition | Seojun |
| **Must** | Data pipeline `tools/` (photos → keywords.json + compositions.json) | Seojun (writes) / Bomin (runs) |
| **Must** | Category/hashtag design, photo collection and labeling (20–40 per category) | Bomin |
| **Should** | Model manager: download, cache and select the larger model when online | Seojun |
| **Should** | Who-moves decision (background comparison) → "model, one step left" | Eungyu |
| **Should** | LLM multilingual instructions (Vercel function + Lablup) | Taeho |
| **Should** | Hand-over lock (long-press to exit, hide chips/menus) | Taeho |
| **Could** | Real .5/3 zoom switching, sign-up taste profile ("my sense profile") | — |
| **Cut** | iOS build, 2+ people, tilt/zoom axes, accounts/cloud, editing | — |

---

## 2. Structure and ownership

### Repo (`GUDORY`, created by the lead, public)
```
app/                          Flutter app
  lib/main.dart, app/         router, theme, tokens                [Taeho]
  lib/core/models.dart        data types (contract)                [lead only]
  lib/core/contracts.dart     module interfaces (contract)         [lead only]
  lib/features/camera/        camera screen, capture, result, reference UI [Taeho]
  lib/features/feedback/      TTS, beeps, haptics, instruction strings     [Taeho]
  lib/features/coach/         engine, axes, reference analyzer, who-moves  [Eungyu]
  lib/features/scene/         CLIP inference, preprocessing, model manager, classifier, composition library [Seojun]
  assets/categories.json      category/hashtag definitions         [Bomin → committed by Seojun]
  assets/clip/keywords.json   CLIP centroids (tools output)
  assets/compositions.json    per-category target compositions (tools output)
  assets/clip/*.onnx          (gitignored) fetched with tools/fetch_models.py
tools/                        Python data pipeline                 [Seojun]
data/photos/ (gitignored), data/labels.csv                         [Bomin]
api/                          Vercel function (LLM proxy, Should)  [Taeho]
AGENTS.md, README.md
```

### Contracts (details in `AGENTS.md` §4)
| Interface | Provider | Consumer |
|---|---|---|
| `FrameBus` (camera frame stream + rotation) | Taeho | Eungyu, Seojun |
| `CoachEngine.update(PoseFrame, TargetComposition) → CoachInstruction` | Eungyu | Taeho |
| `ReferenceAnalyzer.analyze(path) → TargetComposition` | Eungyu | Taeho |
| `SceneClassifier.classify(frame) → CategoryGuess` | Seojun | Taeho |
| `CompositionLibrary.targetFor(categoryId) → TargetComposition` | Seojun | Taeho |
| `ModelManager.ensureBest()` | Seojun | Seojun (internal) |
| `FeedbackService`, `InstructionText.of(key, amount, lang)` | Taeho | Taeho |

If you want a contract changed, **do not change it — message the lead**. The lead edits it and tells everyone.

---

## 3. Work by person

### Taeho (lead · integration · camera screen) — developed directly by the lead's Claude session
1. 16:40–17:30 kickoff: repo, Flutter project, all packages, folders, contracts, stubs, `categories.json` draft, AGENTS.md, Android licenses, **one debug APK build**, push
2. 17:30 everyone clones → `flutter run` on a real device
3. Camera screen UI (as mocked, no outline) + preview + `FrameBus`
4. Capture (`takePicture`, full resolution) → gallery save → result screen
5. `FeedbackService` (TTS, beeps, haptics) + Korean instruction string table
6. Reference pill/badge/clear + category chip state (auto / suggested / manual)
7. 22:00 integration 1 (pose → bubble), 01:00 integration 2 (category/reference → target → auto capture)
8. Merges (19:30 / 22:00 / 01:00 / 03:00 / 05:30 / 08:00 / 10:30 / 11:00), release APK, GitHub Releases, demo video

### Seojun (scene classification · models · data pipeline)
1. 17:30–18:30 **CLIP go/no-go**: load the q8 vision encoder with the `onnxruntime` package and embed one photo on a real device. If it does not work by 18:30 → **Plan B = `google_mlkit_image_labeling` labels → category mapping**
2. Preprocessing: `CameraImage` (NV21) → 224×224 RGB, person pixels neutralized with selfie segmentation
3. `SceneClassifier`: text vectors + category centroids combined → primary, 2 suggestions, hashtags (threshold), every 3 s
4. `CompositionLibrary`: load `compositions.json`
5. `tools/build_assets.py` (first working version by 20:00): `data/photos` + `labels.csv` → `keywords.json` + `compositions.json` + report (per-category counts, leave-one-out accuracy)
6. Should: `ModelManager` download/cache/select (start after 01:00; drop if not working by the 08:00 cut)

### Eungyu (coaching engine · reference analysis · presenter)
- After the 08:00 cut: review the slides Bomin drafted, finalize the script, rehearse. Eungyu presents.
1. 17:30–19:30 pose stream: `FrameBus` → ML Kit `InputImage` conversion → `PoseFrame` (33 joints + roll/pitch)
2. 4-axis errors (distance = person height ratio, horizontal = person center x, height = hip y, level = roll) + body-relative amounts (steps, fists)
3. Instruction selection: level → distance → horizontal → height, enter 1.0 / exit 0.8 hysteresis, min 1.5 s hold, `oppositeWay` when growing, `fitWholeBody` when not fully visible
4. `ReferenceAnalyzer`: still photo → `TargetComposition` with the same definitions (throws when no person)
5. Working on device with a dummy target by 22:00 → integrate with Taeho
6. Should: who-moves (segmentation mask → 96 px background edges → ±20 px shift match) — **start only if the engine is stable at the 01:00 integration; drop if not working by 08:00**

### Bomin (categories · data · slide draft · QA)
1. **Finalize categories and hashtags by 18:00** (ids are baked into code, no changes afterwards). Proposal: the mock's 5 (mountain, sea, city, sunset, forest) + **indoor** → 6. ≤ 15 hashtags
2. By 18:30 have everyone drop "photos they took themselves (travel, people)" into a shared folder (no internet photos; photos are never committed, only vectors)
3. Labeling: `data/labels.csv` (file, one category, several hashtags, person count, orientation). 20–40 per category, portrait, one person, full body preferred
4. 20:00 first batch (≥10 per category) → Seojun runs the script → 23:30 second batch → **01:00 final** JSON frozen
5. Shoot 3–5 demo reference photos (around the venue, bright)
6. After 01:00: slide deck (sense translation table, competitor table, 4-layer AI diagram), demo script, 500-char intro — **complete by 10:00 with only the video link missing**
7. 10:30+: QA on the stable build (with Eungyu), act as the "photographer" in the 11:00 demo video, README credits (CLIP MIT, ML Kit, fonts)

---

## 4. Timeline

| Time | Taeho | Seojun | Eungyu | Bomin |
|---|---|---|---|---|
| **16:40** | Kickoff: repo, packages, contracts, APK | Python 3.12 env (uv), ONNX model download | ML Kit pose sample, conversion recipe | Category/hashtag draft |
| 17:30 | Everyone clones · `flutter run` works | | | |
| 17:30–19:30 | Camera screen UI + FrameBus | **CLIP go/no-go (18:30)** → preprocessing | Pose stream → PoseFrame → 4-axis errors | 18:00 categories final, photo collection |
| **19:30** | Check-in ① · merge 1 | | | |
| 19:30–22:00 | Capture, save, result, feedback service | Classifier + tools v1 | Instruction selection + reference analyzer | 20:00 batch 1 → keep labeling |
| **22:00** | Merge 2 · **integration 1: pose → bubble on device** | | | |
| 22:30 | Check-in ② | | | |
| 22:30–01:00 | Reference UI, category chip state, auto capture | Composition library, tools final, (model manager start) | Who-moves (conditional) | 23:30 batch 2, **01:00 final JSON** |
| **01:00** | Merge 3 · **integration 2: category/reference → target → auto capture** | | | Slides start |
| 01:00–03:00 | Polish auto capture and result, (Should) LLM api | (Should) model manager | (Should) who-moves | Slides |
| **03:00** | Check-in ③ · merge 4 · **cut 1** (drop any Should not yet started) | | | |
| 03:15–05:15 | Bug fixes | Sleep A | Bug fixes | Sleep A |
| **05:30** | Merge 5 | | | |
| 05:30–07:30 | Sleep B | Finish Should, bugs | Sleep B | Slides, script |
| **08:00** | Check-in ④ · merge 6 · **cut 2** (remove anything not working from the UI) | | | |
| 08:00–10:30 | Hand-over lock (Should), UI polish, release signing | Classification tuning, download stability | Engine tuning (tolerances, hold time), README draft in gaps | Script, captions, slides done by 10:00 (no video link) |
| **10:30** | **Merge 7 = stable build for the video** · release APK v1 → Releases | | QA on the stable build (full flow on device) | QA |
| 10:30–11:00 | Only changes that cannot break the stable build | | | Prepare location and photographer |
| **11:00** | **Development ends** · shoot the demo video (≥2 takes, 11:00–11:30) | Assist external filming | README body | Photographer role, script |
| 11:30–11:50 | YouTube upload (unlisted) · link in chat | Final APK rebuild (critical bugs only) | README (APK and video links) | Insert video link into slides, export PDF |
| 11:50–12:15 | Replace final APK in Releases · confirm repo public, no keys | | Finalize 500-char intro | One rehearsal |
| **12:15** | Final push | | | |
| **12:30** | Commit freeze · submit the form · screenshot confirmation | | | |

Rules: stuck 30 min → team chat; 1 hour → shrink scope. Native package additions need the lead's approval (build breakage). Taeho and Seojun never sleep at the same time.
**After 11:00, code changes are limited to "critical bugs that break what was filmed."** No APK rebuilds after 11:30 (no time for build + upload + verification).

---

## 5. Data pipeline (Bomin ↔ Seojun)

```
data/photos/*.jpg  +  data/labels.csv
        │  uv run tools/build_assets.py --photos data/photos --labels data/labels.csv --out app/assets
        ▼
app/assets/clip/keywords.json      text vectors + photo centroids per category/hashtag + counts
app/assets/compositions.json       median person height ratio, center x, hip y per category + tolerances
tools/report.md                    per-category counts, leave-one-out top-1 accuracy, confused pairs
```

- `labels.csv` columns: `file,primary,hashtags,person_count,orientation,notes` (hashtags separated by `;`)
- Photo criteria: one person, portrait, full body (head to ankles) preferred. Non-full-body photos are excluded from composition stats but still used for CLIP centroids
- Python **3.12 pinned** (uv). CLIP via `transformers` `openai/clip-vit-base-patch32` (same checkpoint as the app's ONNX), pose via `mediapipe`, fallback `ultralytics` pose
- Originals never committed (`.gitignore`), only JSON

---

## 6. Model strategy

| Situation | Model | Location | Size (est.) |
|---|---|---|---|
| Offline / default | CLIP ViT-B/32 vision encoder **q8** (`Xenova/clip-vit-base-patch32` `onnx/vision_model_quantized.onnx`) | bundled asset → copied to app dir on first run | ~88 MB |
| Online | fp16 (if present) or fp32 `vision_model.onnx` from the same repo | background download on first online run, preferred once complete | 175–350 MB |
| Pose, segmentation | ML Kit (inside the packages) | app | ~10 MB |
| LLM (Should) | Lablup `DeepSeek-V4.1-Flash-B300` | via Vercel function | — |

- Fixed preprocessing: short side 224 → center crop 224 → mean `[0.4815,0.4578,0.4082]` std `[0.2686,0.2613,0.2758]` → `pixel_values[1,3,224,224]` → `image_embeds[512]` → L2 normalize → cosine similarity
- score = 0.5·cos(text) + 0.5·cos(centroid) (text only when no centroid). Hashtags = top scores above threshold
- Plan B (decided 18:30): ML Kit Image Labeling labels → category mapping table; hashtags from label names

---

## 7. Risks and cut criteria

| Risk | Signal | Response |
|---|---|---|
| onnxruntime Flutter package does not run | no embedding by 18:30 | Plan B (ML Kit labeling). Present CLIP as "used in the server version" |
| Camera frame → ML Kit conversion errors (rotation, format) | joints in wrong places | NV21 + sensorOrientation recipe pinned in AGENTS.md; Eungyu's first task |
| Instructions flip too often | distracting demo | 1.5 s hold, hysteresis, generous tolerances (±10% / ±8% / ±3°) |
| A category lacks data | < 20 photos | text vectors only (skip centroid), do not mention in the talk |
| APK size | > 150 MB | consider q4 for the bundled model, or no bundled model (first-run download required) |
| Build breaks | after a package add | only the lead adds packages; `flutter build apk --debug` at every merge |
| Overnight integration slips | integration 2 fails at 01:00 | 03:00 cut 1: drop who-moves, LLM, model manager in that order. 08:00 cut 2: remove anything not working from the UI |
| Not enough time after 11:00 | re-shoot or upload delay | stable build frozen at 10:30, two back-to-back takes, slides finished at 10:00 with only the link missing |

---

## 8. Deliverables (Android)

- Public GitHub repo (`README`: intro, **APK download link (Releases)**, demo video link, install steps (allow unknown sources), architecture, AI usage, team, credits: CLIP MIT / ML Kit / fonts / self-made beeps)
- Demo video 2–3 min (YouTube unlisted): 10-second hook → pick reference → align by sound only → (Should) "model, one step left" → vibration + auto capture → side-by-side result → auto category/hashtags
- 8-minute slide PDF, 500-char intro (first sentence contains "감각")
- Check: no keys or photos in the repo, last commit before 12:30, APK installs and runs on another phone

---

## 9. Still to decide as a team (before the 18:00 check-in)

1. Six categories (mountain, sea, city, sunset, forest, **indoor**) — Bomin
2. Reference button position: top-center pill (proposed) vs next to the thumbnail — Bomin, Taeho
3. Keep the hand-over lock as Should? — everyone
4. Auto capture on by default (proposed) vs shutter only — everyone
5. Demo location and photographer (someone who does not care about photos) — Bomin
6. Team name and repo name (`GUDORY` provisional) — Taeho
