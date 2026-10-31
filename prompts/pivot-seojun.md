# Seojun — pivot prompt (Recommender + data pipeline)

Paste everything below into your Claude Code session.

---

The team changed the product structure. `git pull` (or check out `docs/recommend-mode`), then read `AGENTS.md` §1, §4, §5 and the "Pivot" table at the top of `docs/work-plan.md` in full. Summarize the `Recommender` contract and the `recommend.json` format before writing code. Work one step at a time and stop after each.

## What changed for you
- `SceneClassifier`, `CompositionLibrary`, categories, hashtags, `keywords.json`, `compositions.json`, `labels.csv` are **gone**.
- New: `Recommender.recommend(CameraFrame, int level, ShotOrientation) → Recommendation`. CLIP now compares **backgrounds** (person masked) against background clusters built from one-person photos.
- **Four framings** (`chestUp`, `waistUp`, `kneeUp`, `fullBody`), not only full body. Position = shoulder midpoint x and eye line y. Levels are cut by person scale (head top ~ shoulder). See AGENTS.md §4.
- Your existing CLIP runner, preprocessing and person mask are reused unchanged.
- Training data: **`data/photos/team/`** (team and friends' phone photos, Instagram style; primary, weight it higher) + a supplementary dataset Bomin picks after a test (Open Images or Unsplash, in another `data/photos/<name>/` folder). Nothing per-photo may be published: the app gets only aggregated clusters and medians (no photo ids, no per-photo embeddings). Pexels is not allowed.
- Photos are not in git. Get them from Bomin, or have Bomin run your script on her PC.

## Scope
- May edit: `app/lib/features/scene/**`, `tools/**`, `app/assets/recommend.json`
- `tools/unsplash_candidates.py` was written by Bomin (keyword filter + download); you may change it.
- Must not edit `core/` (Taeho applies the contract change first — wait for his merge or use a local copy of the types until then).

## Step 1 — `tools/build_assets.py` (rewrite)
Input: every image under `data/photos/` (recursively). `team/` photos get weight 3, others 1 (CLI flags).
1. Orientation from EXIF-corrected size (h > w → portrait). Square photos (w/h between 0.9 and 1.1, e.g. Instagram crops): after pose detection, centre-crop to portrait 3:4; if the nose or a shoulder falls outside, centre-crop to landscape 4:3 instead; if both cut the person, drop the photo. Crop around the **image centre**, not the person, so the photographer's composition is kept.
2. Pose (mediapipe): keep photos with **exactly one person** whose nose and both shoulders are visible (≥ 0.5). Framing = lowest visible anchor (shoulders / hips / knees / ankles). Compute `f`, `h` (span at that framing), `s` (person scale), `cx` (shoulder mid x), `cy` (eye line y), `hy` (horizon, null unless cheap) with **the same formulas as Eungyu's `composition_math.dart`** (AGENTS.md §4 table) — copy them exactly.
3. Selfie segmentation → fill person pixels with the mean colour → CLIP (`openai/clip-vit-base-patch32`, preprocessing per §5) → L2-normalized background embedding.
4. Per orientation: `levels` = weighted quintile edges of `s` (descending). `fallback` per level = most common framing `f` + medians of `h`/`cx`/`cy`/`hy` over the photos with that framing.
5. Per orientation: k-means on embeddings (k ≈ 64, fewer if < 20 photos per cluster; `uv pip install scikit-learn` in `tools/.venv` is fine). For each cluster store the int8 base64 centre, `n`, and per level `f` + medians as in `fallback` (skip a level with < 3 photos).
6. Write `app/assets/recommend.json` (target < 1 MB) and `tools/report.md`: photo counts per orientation × level × framing, how many were dropped by each filter, cluster size histogram. **No per-photo rows in the report** (it is committed).

## Step 2 — `features/scene/recommender.dart`
- `warmUp()`: load `recommend.json` + the CLIP session (reuse `ModelManager`).
- `recommend()`: live frame → person mask → CLIP → cosine against clusters of the same orientation → top 3 that have the chosen level (else the nearest level) → average of their medians weighted by cosine × n → `TargetComposition(source: 'recommend:<level>', orientation: ...)`.
- **Never throws**: no model / no clusters / any error → `fallback` for that level and orientation, `neighbors: 0`, `modelVariant: 'none'`.
- Off the UI thread; cache the embedding so a level change re-scores without re-running CLIP.

## Step 3 — on device
Log for 3 different backgrounds (indoor, street, open sky): top cluster cosine, chosen h/cx/cy at levels 1, 3, 5, time per call. Levels must be monotonic (level 1 h > level 5 h).

## Should (after 01:00, drop at the 08:00 cut)
`ModelManager` fp16 download as before.
