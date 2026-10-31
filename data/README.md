# data/ — training photos for 추천 모드 (Bomin)

Nothing in this folder is committed except this README (.gitignore).

Target style: everyday / travel photos **as people post on Instagram** — one person, taken by a friend with a phone, any framing from chest-up to full body.

| Path | What |
|---|---|
| `photos/team/` | **Primary.** Photos taken by team members, and by friends who gave permission. Any file name |
| `photos/unsplash/`, `unsplash/raw/` | Unsplash Lite test download (mostly studio portraits — supplementary at most) |
| `openimages/raw/` | Open Images V7 label files for the supplementary test (Flickr, CC BY 2.0) |
| `demo_refs/` | 3–5 reference photos for the demo video, **team members only** |

## Rules for `photos/team/`
- One person, head and shoulders visible. Chest-up, waist-up, knee-up and full body are all welcome; portrait and landscape both.
- Original files from the phone are best. Instagram downloads are fine too; square ones are centre-cropped to 3:4 or 4:3 by `build_assets.py`.
- Friends' photos only with the permission of the person who took them. No other internet photos. **Pexels is not allowed** (its terms forbid collection for machine learning).
- No label file: orientation comes from the image size; `build_assets.py` checks one person and the framing with pose detection.
- Aim for **100–200** photos so every level (5) × orientation has enough.

## Supplementary dataset
Decided after a CLIP style test ("phone snapshot" vs "studio portrait"). Whatever is used, its terms forbid publishing the data: only aggregated numbers go into the app, and README credits it.

Old guide (categories, labels — outdated): `prompts/bomin-data-guide.md`
