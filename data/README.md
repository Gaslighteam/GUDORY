# data/ — training photos for 추천 모드 (Bomin)

Nothing in this folder is committed except this README (.gitignore).

| Path | What |
|---|---|
| `unsplash/raw/` | Unsplash Lite Dataset 1.4.0 (TSV files). Download: https://unsplash.com/data/lite/latest |
| `unsplash/candidates.csv` | one-person candidates picked by `tools/unsplash_candidates.py` |
| `photos/unsplash/<id>.jpg` | downloaded candidates (short side 640 px) |
| `photos/team/` | optional photos taken by team members (same rules: one person, full body) |
| `demo_refs/` | 3–5 reference photos for the demo video, **team members only** |

## Steps
```bash
python tools/unsplash_candidates.py --download 3000   # from the repo root
```
1. Look through `photos/unsplash/` and **delete** photos with a bad composition, two or more people, or no full body. No label file: orientation comes from the image size, and `build_assets.py` checks one person / full body with pose detection.
2. Tell Seojun → `build_assets.py` → `app/assets/recommend.json`. Check the per-orientation, per-level counts in `tools/report.md`.

## Rules
- Unsplash Lite terms (`unsplash/raw/TERMS.md`): storing and training are allowed; **publishing any part of the data is not**. Only aggregated numbers (clusters, medians) go into the app.
- **Pexels is not allowed** (its terms forbid automated collection for machine learning).
- No other internet photos.

Old guide (categories, labels — outdated): `prompts/bomin-data-guide.md`
