# Recommender v2 report

Aggregate output only. No photo names, per-photo values or embeddings.

Photos: 719 processed, 694 used. recommend_v2.json: 162,342 bytes.

Filter | Count
--- | ---:
accepted | 694
processed | 719
rejected/not_real_person | 3
rejected/pose/hand_dominant | 9
rejected/pose/head_cut | 1
rejected/pose/person_too_small | 9
rejected/segmentation_or_embedding | 3

## 5-fold cross-validation by photo

Truth: 48.7% of photos have the shoulder centre in 0.42-0.58.

Model | Framing match | cx MAE | offset \|cx-.5\| MAE | cy MAE | h MAE | h MAE (same framing) | centre share
--- | ---: | ---: | ---: | ---: | ---: | ---: | ---:
current (recommend.json) | 56.5% | 0.119 | 0.093 | 0.101 | 0.150 | 0.082 | 90.2%
v2 | 63.1% | 0.079 | 0.070 | 0.087 | 0.130 | 0.082 | 11.1%

v2 cx uses the side of each test photo's person mask, as the app does
live; on a test photo that side is the true side, so cx is optimistic. The
offset column does not depend on the side.

## Out-of-sample check: 500 Open Images photos (2026-11-01, local run)

The current recommend.json was built from these photos; v2 never saw them.

Model | Framing match | cx MAE | offset \|cx-.5\| MAE | cy MAE | h MAE | h MAE (same framing) | centre share
--- | ---: | ---: | ---: | ---: | ---: | ---: | ---:
current (recommend.json) | 63.2% | 0.135 | 0.104 | 0.100 | 0.119 | 0.065 | 83.8%
v2 | 62.4% | 0.091 | 0.080 | 0.097 | 0.125 | 0.075 | 6.6%

Truth there: 41.6% centred. v2 places the person better (offset, cy) and
removes the centre bias. The current model, scored on its own training photos,
keeps a small edge on framing (+0.8 pt) and person height.

Centre-bias weights (inverse offset frequency^p) were tried, p = 0..1: they push
the centre share from 11% to 0% and raise every error, so v2 uses quality weights
only. Splitting offset from side is what removes the bias.
