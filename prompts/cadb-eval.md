# Bomin + Eungyu: before/after evaluation and slides (CADB)

Paste everything below into your Claude Code session.

---

`git pull`, then read `docs/cadb.md` in full. Summarize it back before starting.

## Goal
Prove with numbers that GUDORY's guidance improves composition. We have a
composition scorer trained on CADB that beats the published model (SRCC 0.716
vs SAMP-Net 0.656 on the same test set). Use it to score photos taken without and
with GUDORY.

## Bomin: shoot the pairs (start now, done by 08:30)
- 12 scenes, mixed: 4 indoor, 4 street, 4 open/landscape. Half portrait, half landscape.
- Per scene, the same subject and spot, two shots by a teammate who is not the
  photographer type:
  1. **before**: the stock camera app, "just take a photo of me"
  2. **after**: GUDORY recommend mode, level 3, shoot when the shutter ring turns yellow
- Name files `NN_before.jpg` / `NN_after.jpg` and keep them **outside the repo**
  (e.g. `Documents/gudory-eval/`). `data/eval/` is not git-ignored, and anything under
  `data/photos/` gets pulled into `build_assets.py`. Never commit them. Ask the
  subject before any photo goes on a slide.
- Note per scene: scene type, orientation, seconds GUDORY took.

## Scoring (whoever has the tools venv; Seojun's `tools/train_composition_score.py` ships the head)
- Score every photo with the same head as the app (`app/assets/composition_score.json`).
  Print only aggregates: mean raw score before vs after, mean percentile before vs
  after, wins (after > before) out of 12, Wilcoxon signed-rank p.
- If the scorer is not merged by 09:00, ask Taeho to score them on his PC.

## Eungyu: slides (draft by 09:30)
One slide "구도, 숫자로 확인했어요":
- Scorer credibility: CADB test set (950 photos, rated by 5 fine-art raters).
  Ours 0.716 vs SAMP-Net 0.656 (SRCC, higher is better). Cite CADB (BMVC 2021).
- Before/after: mean percentile before → after, wins x/12, one best pair as images
  (with consent).
- One line from `docs/cadb.md` §2: in 719 one-person photos, higher-rated shots put
  the person nearer a third line than dead centre. Person size does not change the
  rating, so GUDORY lets the user choose it (the 5-level bar).
Keep claims to what the numbers show. 12 pairs is a demo, not a study. Say so.
