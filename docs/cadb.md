# CADB: what we found and how we use it

CADB (Composition Assessment DataBase, BMVC 2021) holds 9,497 photos, each rated
1–5 for **composition quality** by five fine-art raters. The label is the mean
score. CADB also carries scene categories, 13 composition classes with element
coordinates, and AADB aesthetic attributes. Code/annotations: MIT,
https://github.com/bcmi/Image-Composition-Assessment-Dataset-CADB. Images come
from AADB (Flickr): use them locally for training and evaluation only. Never commit
or upload them; only aggregate outputs (weights, statistics) may ship.

The score says *how good* a composition is, not *where to move*. So CADB cannot
train GUDORY's direction coaching directly. It can train a **scorer** and back up
claims with numbers.

## Results (measured 2026-11-01, lead's PC)

### 1. The app's own CLIP predicts the composition score well
Image embedding from the bundled `app/assets/clip/vision_q8.onnx` (unmasked,
app preprocessing: short side 224 bicubic, centre crop) + a ridge regression
(512 weights + bias). Official CADB split: train 8,547 / test 950.

| Model | SRCC ↑ | LCC ↑ | MSE ↓ |
|---|---:|---:|---:|
| **CLIP q8 + ridge (ours)** | **0.716** | **0.725** | **0.369** |
| CLIP q8 + MLP (256) | 0.706 | 0.717 | 0.365 |
| SAMP-Net (CADB paper, BMVC 2021) | 0.656 | 0.671 | 0.387 |
| A-Lamp (paper's best baseline) | 0.627 | 0.646 | 0.423 |
| Predict the train mean | – | – | 0.703 |

On the 342 human-scene test photos SRCC is 0.729. Above/below 3.0 is right
75.7% of the time. Letterboxing the full frame instead of the centre crop gives
the same numbers (0.716), so the existing preprocessing is kept.

### 2. Human photos through GUDORY's pose filter
4,319 of 9,497 photos are scene `human`. 719 (16.6%) pass the
`tools/pose_analysis.py` filter (one clear person). Most rejections are several
people (3,407). Of the 719: 423 landscape / 296 portrait; fullBody 225, waistUp 221,
chestUp 168, kneeUp 105; 300 score ≥ 3.0, 87 score ≥ 3.5.

Spearman correlation with the CADB score over the 719:

| Measure | ρ | p |
|---|---:|---:|
| Shoulder centre `cx` distance to the nearest third line | **−0.13** | < 0.001 |
| `cx` distance from the centre | +0.09 | 0.016 |
| Person scale `s` | −0.04 | 0.31 (none) |
| Eye height `cy` | +0.07 | 0.07 (none) |

Higher-rated photos put the person nearer a third line than dead centre. Person
size does not affect the score, so the 5-level person↔background bar is a taste
choice, not a quality one. Eye height sits at ~0.32 of the frame for good and bad
photos alike.

Adding the 719 to `recommend.json` would add ~22% photos (all) or ~9% (≥ 3.0).
Not worth a re-verified rebuild before the release build.

## Local data on the lead's PC (git-ignored)
- `data/photos/cadb/`: all 4,319 human photos
- `data/photos/cadb_719/`: the 719 pose-accepted photos
- `data/photos/cadb_meta/`: the original zip, annotation JSONs,
  `cadb_719_pose.csv` (score + framing + h/s/cx/cy per photo)

`build_assets.py --photos data/photos` would pick up both CADB folders
(and count the 719 twice). Pass the team folder explicitly unless you mean it.
