# Taeho — pivot prompt (recommend / custom modes)

Paste everything below into the lead's Claude session.

---

The team changed the product structure. `git pull` (or check out `docs/recommend-mode`), then read `AGENTS.md` §1, §4, §5, §6 and the "Pivot" table at the top of `docs/work-plan.md` in full. Summarize the new `models.dart` / `contracts.dart` signatures before writing code. Work one step at a time and stop after each for an on-device check.

## What changed
- **Categories and hashtags are gone.** Two modes, toggled at the **top left**: `추천` (recommend) and `맞춤` (custom).
- 추천: `Recommender.recommend(frame, level, orientation)` gives the target. A **5-step bar** (`인물 중심` 1 … 5 `배경 중심`, default 3) replaces the category bar.
- 맞춤: the active reference is the target (existing reference slot/sheet). No reference → bubble shows `addReference` ("레퍼런스를 추가해 주세요"), no beeps, no auto capture.
- **Landscape shots**: UI stays portrait-locked; `PoseFrame.orientation` (from Eungyu's PoseSource) tells you how the phone is held.

## Step 1 — contracts (you own `core/`)
- `models.dart`: add `ShootMode`, `ShotOrientation`, `Framing`, `Recommendation`; add `orientation` to `PoseFrame` and `TargetComposition` (default `portrait`), `framing` to `TargetComposition` (default `fullBody`) so existing call sites compile; update the doc comments of `personHeightRatio` (span at the framing), `personCenterX` (shoulder midpoint x), `personCenterY` (eye line y); add `InstructionKey.turnLandscape`, `turnPortrait`, `addReference`; `source` doc → `'reference' | 'recommend:<1-5>' | 'fallback'`. Delete `CategoryGuess`, `CategoryInfo`.
- `contracts.dart`: delete `SceneClassifier`, `CompositionLibrary`; add `Recommender` exactly as in AGENTS.md §4.
- `pubspec.yaml` assets: drop `assets/categories.json`, add `assets/recommend.json`. Delete `app/assets/categories.json`. Until Seojun's file lands, commit a stub `recommend.json` with only `fallback` filled and empty `clusters` — levels 1–5 (both orientations): `chestUp` h 0.62 cy 0.33 / `waistUp` h 0.68 cy 0.30 / `kneeUp` h 0.72 cy 0.28 / `fullBody` h 0.70 cy 0.25 / `fullBody` h 0.40 cy 0.45, all cx 0.5.
- `flutter analyze` must be clean. Merge to `main` fast and announce it — Eungyu and Seojun are blocked on this.

## Step 2 — state
- `shot_state.dart`: remove `CategoryState`/`categoryProvider`. Add a mode state `{ShootMode mode = recommend, int level = 3}`.
- `providers.dart`: `compositionLibraryProvider` → `recommenderProvider` (Fake until Seojun's lands: returns `fallback` for the level/orientation).
- `coaching.dart` `_target()`:
  - custom → active reference target, or `null` (emit `addReference`, skip engine/feedback)
  - recommend → latest `Recommendation.target`, refreshed every ~3 s and **immediately when the level or orientation changes**; before the first result use the fallback.

## Step 3 — UI (AGENTS.md §6)
- Top left: segmented toggle `추천 | 맞춤` (bubble tokens). Switching modes calls `CoachEngine.reset()`.
- Recommend: 5-step bar in the old category bar slot (`#1C1C1E`), 5 tappable stops + labels `인물 중심` / `배경 중심` at the ends; reference slot hidden.
- Custom: 5-step bar hidden, reference slot shown; X only in custom mode when references exist.
- Delete `CategoryChips`. Post-shot toast: "앨범에 저장했어요".
- Landscape: rotate icons, bubble and arrows 90° in place (`AnimatedRotation`); layout does not move.

## Step 4 — landscape capture and feedback
- When `orientation == landscape`, lock the capture orientation (`CameraController.lockCaptureOrientation(landscapeLeft/Right by roll sign)`) so the saved photo is landscape; unlock in portrait. Verify in the gallery.
- `instruction_text.dart`: `turnLandscape` "폰을 가로로 돌려 주세요", `turnPortrait` "폰을 세로로 세워 주세요", `addReference` "레퍼런스 사진을 추가해 주세요".

## Done when
Recommend ↔ custom toggle, the 5-step bar changes the instruction (e.g. level 1 chest-up → "한 걸음 앞으로"), custom with no reference shows the prompt, a landscape shot is saved as landscape. `flutter analyze` 0 warnings, `flutter build apk --debug` passes.
