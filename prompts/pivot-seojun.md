# Seojun — pivot prompt (Recommender + Unsplash pipeline)

Paste everything below into your Claude Code session.

---

The team changed the product structure. `git pull` (or check out `docs/recommend-mode`), then read `AGENTS.md` §1, §4, §5 and the "Pivot" table at the top of `docs/work-plan.md` in full. Summarize the `Recommender` contract and the `recommend.json` format before writing code. Work one step at a time and stop after each.

## What changed for you
- `SceneClassifier`, `CompositionLibrary`, categories, hashtags, `keywords.json`, `compositions.json`, `labels.csv` are **gone**.
- New: `Recommender.recommend(CameraFrame, int level, ShotOrientation) → Recommendation`. CLIP now compares **backgrounds** (person masked) against background clusters built from Unsplash photos.
- Your existing CLIP runner, preprocessing and person mask are reused unchanged.
- Training data: **Unsplash Lite Dataset 1.4.0**, already downloaded by Bomin to `data/unsplash/raw/`. **Read `data/unsplash/raw/TERMS.md`**: nothing per-photo may be published, so the app gets only aggregated clusters and medians (no photo ids, no per-photo embeddings). Pexels is not allowed.

## Scope
- May edit: `app/lib/features/scene/**`, `tools/**`, `app/assets/recommend.json`
- `tools/unsplash_candidates.py` was written by Bomin (keyword filter + download); you may change it.
- Must not edit `core/` (Taeho applies the contract change first — wait for his merge or use a local copy of the types until then).

## Step 1 — `tools/build_assets.py` (rewrite)
Input: every image under `data/photos/` (recursively: `unsplash/`, optional `team/`). Bomin runs `python tools/unsplash_candidates.py --download 3000` first and deletes bad photos by hand.
1. Orientation from EXIF-corrected size (h > w → portrait).
2. Pose (mediapipe): keep only photos with **exactly one person** and **full body** (nose and both ankles visible ≥ 0.5). Compute `h` (personHeightRatio), `cx`, `cy`, `hy` (horizon, null unless you have a cheap detector) with **the same formulas as Eungyu's `ReferenceAnalyzer`** — agree on one definition of head top with him and copy it exactly.
3. Selfie segmentation → fill person pixels with the mean colour → CLIP (`openai/clip-vit-base-patch32`, preprocessing per §5) → L2-normalized background embedding.
4. Per orientation: `levels` = quintile edges of `h` (descending). `fallback` = median composition per level.
5. Per orientation: k-means on embeddings (k ≈ 64, fewer if < 20 photos per cluster; `uv pip install scikit-learn` in `tools/.venv` is fine). For each cluster store the int8 base64 centre, `n`, and per-level medians (skip a level with < 3 photos).
6. Write `app/assets/recommend.json` (target < 1 MB) and `tools/report.md`: photo counts per orientation × level, how many were dropped by each filter, cluster size histogram. **No per-photo rows in the report** (it is committed).

## Step 2 — `features/scene/recommender.dart`
- `warmUp()`: load `recommend.json` + the CLIP session (reuse `ModelManager`).
- `recommend()`: live frame → person mask → CLIP → cosine against clusters of the same orientation → top 3 that have the chosen level (else the nearest level) → average of their medians weighted by cosine × n → `TargetComposition(source: 'recommend:<level>', orientation: ...)`.
- **Never throws**: no model / no clusters / any error → `fallback` for that level and orientation, `neighbors: 0`, `modelVariant: 'none'`.
- Off the UI thread; cache the embedding so a level change re-scores without re-running CLIP.

## Step 3 — on device
Log for 3 different backgrounds (indoor, street, open sky): top cluster cosine, chosen h/cx/cy at levels 1, 3, 5, time per call. Levels must be monotonic (level 1 h > level 5 h).

## Should (after 01:00, drop at the 08:00 cut)
`ModelManager` fp16 download as before.
