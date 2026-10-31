# Eungyu — pivot prompt (landscape + recommend/custom modes)

Paste everything below into your Claude Code session.

---

The team changed the product structure. `git pull` (or check out `docs/recommend-mode`), then read `AGENTS.md` §1 and §4 and the "Pivot" table at the top of `docs/work-plan.md` in full. Summarize what changed in `PoseFrame`, `TargetComposition` and `InstructionKey` before writing code. Work one step at a time and stop after each for an on-device check.

## What changed for you
- Categories are gone; the target now comes from a **reference** (custom mode) or Seojun's **Recommender** (recommend mode, 5 levels). Your `CoachEngine.update(PoseFrame, TargetComposition)` interface is unchanged.
- **Landscape shots are supported.** The UI stays portrait-locked; you decide the shot orientation from the accelerometer.
- New fields/keys (Taeho applies them in `core/`; use them once he merges): `PoseFrame.orientation`, `TargetComposition.orientation`, `InstructionKey.turnLandscape` / `turnPortrait` / `addReference` (`addReference` is emitted by the UI, not by you).

## Scope
- May edit: `app/lib/features/coach/**`. Must not edit `core/` or other features.

## Step 1 — PoseSource
- Orientation with hysteresis: |accelerometer roll| > 60° → landscape, < 45° → portrait.
- Rotate landmarks into **shot space** (the frame as the saved photo will look): landscape → width > height, x along the long side. Mind the sign of roll (landscapeLeft vs Right) and front-camera mirroring.
- In landscape, `rollDeg` is measured from ±90° so "level" still means the horizon is flat.
- Verify: hold the phone sideways, stand a person in the frame → `imageWidth > imageHeight` and the hips' y is still "down" in the photo.

## Step 2 — engine
- New first step in the order: if `target.orientation != frame.orientation` → `turnLandscape` / `turnPortrait` (no other axis until it matches).
- Distance amount: vertical fov 65° in portrait, **50° in landscape** (AGENTS.md §4).
- Directions stay body-relative to the photographer in both orientations ("왼쪽으로 한 걸음", "폰을 아래로").
- `reset()` is called on mode switch — clear holds and hysteresis.

## Step 3 — ReferenceAnalyzer
- Set `orientation` from the **EXIF-corrected** image size, so landscape references work.
- Seojun computes `personHeightRatio`, `personCenterX`, `personCenterY` for the Unsplash photos in Python. **Agree on one exact formula with him** (especially head top: nose/eye/ear landmarks + an offset) and put it in `features/coach/composition_math.dart` with a comment he can copy. A mismatch here makes every recommendation off by a constant.

## Done when
A landscape reference + phone held upright → "폰을 가로로 돌려 주세요"; after turning, the four axes coach normally and the saved photo is landscape. Recommend level 1 vs 5 produces "앞으로" vs "뒤로" on the same scene.
