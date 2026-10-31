# Seojun: composition score head (CADB) + Dart scorer

Paste everything below into your Claude Code session.

---

`git pull`, then read `docs/cadb.md` in full and `AGENTS.md` §5 (CLIP
preprocessing). Summarize the plan back before writing code. Stop after each step.

## Goal
After a shot, GUDORY shows a composition score for the photo. The score comes from
the app's bundled CLIP encoder plus a 512-weight linear head trained on CADB. On
the lead's PC this already gave SRCC 0.716 on the CADB test split, beating the
paper's SAMP-Net (0.656). Your job: make it reproducible in `tools/`, ship the
head as an asset, and expose a Dart scorer. Taeho does the UI.

## Scope
- May add/edit: `tools/train_composition_score.py`, `tools/test_*.py`,
  `app/assets/composition_score.json`, `app/lib/features/scene/composition_scorer.dart`
  (+ test), the provider for it, the `pubspec.yaml` asset line.
- Must not edit: `core/`, camera UI, `recommend.json`, the recommender.
- Never commit CADB images or per-photo outputs. The asset holds aggregate
  weights only.

## Step 1: training script (target 07:00)
- Data: download `CADB_Dataset.zip` (~2 GB, Dropbox link in the CADB README) to an
  ignored folder, or copy `data/photos/cadb_meta/` from Taeho's PC.
  Use `split.json` (`train`/`test`) and `composition_scores.json` (`mean`).
- Embedding: `background_clip.ClipEncoder` on `app/assets/clip/vision_q8.onnx`,
  **unmasked** image, existing `clip_pixels` (short side 224 bicubic, centre
  crop). No segmentation. Read images straight from the zip; cache embeddings in
  an ignored `.npz` under `tools/.cache/`.
- Head: `sklearn.linear_model.RidgeCV(alphas=np.logspace(-2, 3, 12))` on the
  L2-normalized 512-d embeddings, train split only.
- Report on test: SRCC, LCC, MSE, accuracy at 3.0, and SRCC on the `human` scene
  subset. Expected ≈ 0.716 / 0.725 / 0.369 / 0.757 / 0.729. Large deviations mean
  the preprocessing differs.
- Percentile table: 101 quantiles (0..100%) of the head's predictions on the
  **train** images, so the app can say "top 15%".
- Write `app/assets/composition_score.json` (aggregate only):
  `{"version":1, "model":"vision_q8", "w":[512 floats, 6 dp], "b":float,
  "pct":[101 floats ascending], "metrics":{...}, "source":"CADB (BMVC 2021), MIT"}`.
- Unit test: asset schema, finite values, `pct` ascending, a synthetic embedding
  round-trip.

## Step 2: Dart scorer (target 08:30)
`features/scene/composition_scorer.dart`:
```dart
class CompositionScore { final double raw; final int percentile; } // percentile 0..100
abstract class CompositionScorer { Future<CompositionScore?> score(Uint8List jpeg); }
```
- Reuse the **same CLIP session** the recommender uses (`SceneEmbedding`'s
  `ClipRunner`). Do not open a second 88 MB session. `ClipRunner.runBytes`
  already decodes and centre-crops a JPEG.
- `raw = w·e + b` on the L2-normalized embedding. `percentile` = position of `raw`
  in `pct` (binary search).
- **Never throws**: missing asset, model failure, timeout over 3 s → `null`. Off the UI
  thread. Downscale the 4080×3060 still before decoding if decode time > 300 ms.
- Riverpod provider `compositionScorerProvider`. Tell Taeho (lead session) when
  it is merged. He wires the post-shot UI.

## Step 3: on device (target 09:30)
Score the same 3 JPEGs in Python and on the phone (debug log). The difference must be
< 0.05 raw. Log time per score on the Galaxy. If parity fails, ship nothing
and report. 10:30 is the release build. Nothing lands after 10:15.
