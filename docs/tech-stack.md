# GUDORY — tech stack (Flutter)

> Baseline: Flutter 3.44.8 stable / Dart 3.12.2 (lead's PC). **Everyone uses the same version.**
> Platform: Android (APK). iOS is out of scope for the contest. Dev machines are Windows.

## 1. Repo layout (monorepo)
```
GUDORY/
├─ app/        Flutter app (Android)
├─ api/        Vercel function: one LLM proxy (TypeScript)
├─ tools/      Python: CLIP text vectors, category centroids, composition stats
├─ data/       labels.csv (photos gitignored)
├─ docs/, prompts/
├─ AGENTS.md, CLAUDE.md (= @AGENTS.md), README.md
```

## 2. App (app/)
| Area | Package | Use |
|---|---|---|
| State | `flutter_riverpod` | cross-screen state (reference, coaching state, settings) |
| Routing | `go_router` | camera → result |
| Camera | `camera` | preview + frame stream (analysis) + `takePicture()` **full resolution** |
| Pose | `google_mlkit_pose_detection` | 33 joints → distance, horizontal, height errors |
| Person mask | `google_mlkit_selfie_segmentation` | remove the person before background comparison / CLIP |
| Scene (CLIP) | `onnxruntime` | CLIP vision encoder q8 (ONNX), once before the shot |
| Image ops | `image` | 224×224 resize/normalize, edge images |
| Sensors | `sensors_plus` | roll and pitch from gravity |
| Haptics | `vibration` + `HapticFeedback` | "aligned" = vibration |
| Voice | `flutter_tts` | read instructions (ko/en/ja) |
| Beeps | `audioplayers` | faster beeps when closer |
| Pick photo | `image_picker` | reference photo |
| Save photo | `gal` | save result to gallery |
| Local DB | `sqflite` | shot history (settings are a JSON file, `features/settings/app_settings.dart`) |
| Files | `path_provider` | CLIP model location |
| HTTP | `http` | big model download, LLM API |
| Keep awake | `wakelock_plus` | screen stays on while coaching |
| Connectivity | `connectivity_plus` | decide when to download the big model |

### Platform setup (lead, once at kickoff)
- Android: minSdk 24, camera/vibrate/internet/media permissions in the manifest, portrait locked.

### Known traps
- **Camera frame → ML Kit:** open the stream as `ImageFormatGroup.nv21` on Android and pass `sensorOrientation` as the rotation.
- **Stream analysis vs `takePicture()`:** stop the image stream right before capture → capture → resume.
- **Analysis rate:** 10–15 pose frames per second is enough; drop frames while the previous one is being processed.

## 3. AI components
| Model | Runs | Size (est.) | License |
|---|---|---|---|
| ML Kit Pose Detection | device (real time) | in package | Google ML Kit terms |
| ML Kit Selfie Segmentation | device (real time) | in package | Google ML Kit terms |
| CLIP ViT-B/32 vision encoder **q8** (ONNX) | device (once before the shot) | ~88 MB, bundled | MIT |
| CLIP vision encoder fp16/fp32 | device, downloaded when online | 175–350 MB | MIT |
| Keyword text vectors + centroids + composition stats | device (asset JSON) | < 1 MB | ours |
| Lablup `DeepSeek-V4.1-Flash-B300` | server (api/) | — | — |

- Offline after the first run. Only the LLM needs a connection (built-in ko/en/ja strings when offline).
- **Plan B (CLIP fails in Flutter):** `google_mlkit_image_labeling` labels mapped to categories. Decided in the first 30 minutes of kickoff.

## 4. Server (api/)
- Vercel Functions, TypeScript, one endpoint: `POST /api/instructions` → instruction set JSON for a language
- Env: `LLM_BASE_URL=https://api.console.lablup.ai/anthropic`, `LLM_API_KEY`, `LLM_MODEL=DeepSeek-V4.1-Flash-B300`
- 20 s timeout, per-language cache, per-IP rate limit. On failure the app uses built-in strings
- **The Lablup key never goes into the app** (APKs can be unpacked and the repo is public)

## 5. tools/ (Python 3.12, Seojun)
- `transformers` CLIP for text + image embeddings → per-category/hashtag centroids; `mediapipe` pose → composition stats
- Outputs `app/assets/clip/keywords.json` and `app/assets/compositions.json`
- **Same CLIP checkpoint as the app's ONNX** so vectors match
- Only team-taken photos; only vectors are committed

## 6. Build and release
| Step | Android |
|---|---|
| Development | USB `flutter run` (hot reload) |
| Release | `flutter build apk --release` → **GitHub Releases** asset, link in README |
| Signing | release keystore kept by the lead, never committed |

## 7. Pre-flight (before kickoff)
- [ ] Everyone passes `flutter doctor` (Android toolchain), Flutter 3.44.8
- [ ] USB debugging on at least two Android phones (dev + demo)
- [ ] Vercel login (for api/)

## 8. Kickoff first 30 minutes (Plan B if any fails)
1. Empty Flutter app with all packages → Android build succeeds
2. Camera preview + pose joints drawn on a real device
3. CLIP ONNX loads and embeds one photo (else Plan B)
