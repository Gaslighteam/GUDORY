"""Recommender v2: a small linear model over the app's person-masked background
CLIP embedding, replacing per-cluster medians (docs/cadb.md, report_v2.md).

Inputs: background embedding -> PCA (k=32) + one-hot (orientation, level).
Outputs: framing (multinomial logistic), offset |cx - 0.5| and eye line cy
(ridge), person height h = weighted median for (orientation, level, framing).
The side (left/right of centre) is NOT learned: the app puts the person on the
side they already stand on (person mask centroid), or on the side that leaves room in
front of them (photo rules). Splitting offset from side is what removes the
centre bias: medians of a left/right mix collapse to the middle.

Photos are weighted by CADB composition score when --scores is given
(max((score - 1) / 2, 0.2)), else 1. Only aggregate weights are written; no
photo names, per-photo values or embeddings.

    python tools/train_recommender_v2.py --photos data/photos/cadb_719 \
        --scores data/photos/cadb_meta/composition_scores.json \
        --pose-model ... --person-model ... --segmentation-model ... \
        --clip-model app/assets/clip/vision_q8.onnx \
        --baseline-asset app/assets/recommend.json \
        --out app/assets/recommend_v2.json --report tools/report_v2.md
"""
import argparse
import base64
import json
import sys
from pathlib import Path

import numpy as np

FRAMINGS = ("chestUp", "waistUp", "kneeUp", "fullBody")
ORIENTATIONS = ("portrait", "landscape")
K, ALPHA, C, MAX_OFFSET = 32, 10.0, 1.0, 0.35
CENTRE = (0.42, 0.58)


def wmedian(values, weights):
    order = np.argsort(values)
    cum = np.cumsum(weights[order]) / weights.sum()
    return float(values[order][np.searchsorted(cum, .5)])


def level_of(s, edges):
    """Level 1 = largest person scale; edges descending."""
    for i, edge in enumerate(edges):
        if s >= edge:
            return i + 1
    return 5


def quality(score):
    return 1.0 if score is None else max((score - 1) / 2, .2)


class V2Model:
    def fit(self, rows):
        from sklearn.decomposition import PCA
        from sklearn.linear_model import LogisticRegression, Ridge
        q = np.array([quality(r["score"]) for r in rows])
        self.edges, self.height = {}, {}
        for o in ORIENTATIONS:
            idx = [i for i, r in enumerate(rows) if r["orientation"] == o]
            if len(idx) < 20:
                raise ValueError(f"Not enough {o} photos")
            s, w = np.array([rows[i]["s"] for i in idx]), q[idx]
            order = np.argsort(-s)
            cum = np.cumsum(w[order]) / w.sum()
            self.edges[o] = [float(s[order][np.searchsorted(cum, p)]) for p in (.2, .4, .6, .8)]
            lv = np.array([level_of(x, self.edges[o]) for x in s])
            fs = np.array([rows[i]["f"] for i in idx])
            hs = np.array([rows[i]["h"] for i in idx])
            ratio = {}
            for f in FRAMINGS:
                m = fs == f
                ratio[f] = (wmedian(hs[m] / s[m], w[m]) if m.sum() >= 3 else
                            wmedian(np.array([r["h"] / r["s"] for r in rows if r["f"] == f]),
                                    np.array([quality(r["score"]) for r in rows if r["f"] == f])))
            for level in range(1, 6):
                m = lv == level
                s_level = wmedian(s[m], w[m]) if m.any() else wmedian(s, w)
                for f in FRAMINGS:
                    mf = m & (fs == f)
                    h = wmedian(hs[mf], w[mf]) if mf.sum() >= 3 else s_level * ratio[f]
                    self.height[o, level, f] = float(np.clip(h, .02, 1))
        E = np.stack([r["emb"] for r in rows])
        self.pca = PCA(K, random_state=0).fit(E)
        X = self.features(E, [level_of(r["s"], self.edges[r["orientation"]]) for r in rows],
                          [r["orientation"] for r in rows])
        sw = q / q.mean()
        self.offset = Ridge(ALPHA).fit(X, [abs(r["cx"] - .5) for r in rows], sample_weight=sw)
        self.eye = Ridge(ALPHA).fit(X, [r["cy"] for r in rows], sample_weight=sw)
        y = [FRAMINGS.index(r["f"]) for r in rows]
        if len(set(y)) != 4:
            raise ValueError("Every framing needs training photos")
        self.framing = LogisticRegression(C=C, max_iter=2000).fit(X, y, sample_weight=sw)
        self.n = len(rows)
        return self

    def features(self, E, levels, orientations):
        z = self.pca.transform(np.atleast_2d(E))
        onehot = np.zeros((len(z), 10))
        for i, (level, o) in enumerate(zip(levels, orientations)):
            onehot[i, (level - 1) + 5 * ORIENTATIONS.index(o)] = 1
        return np.hstack([z, onehot])

    def predict(self, emb, level, orientation, person_x):
        X = self.features(emb, [level], [orientation])
        f = FRAMINGS[int(np.argmax(X @ self.framing.coef_.T + self.framing.intercept_))]
        d = float(np.clip(self.offset.predict(X)[0], 0, MAX_OFFSET))
        side = 1 if person_x is None or person_x >= .5 else -1
        return dict(f=f, h=self.height[orientation, level, f], cx=.5 + side * d,
                    cy=float(np.clip(self.eye.predict(X)[0], 0, 1)))

    def asset(self):
        r6 = lambda v: [round(float(x), 6) for x in np.ravel(v)]
        return {
            "model": "gudory-recommender-v2", "encoder": "clip-vit-base-patch32-background",
            "dim": 512, "k": K, "photos": self.n,
            "framings": list(FRAMINGS),
            "features": "pca[k] + onehot[(level-1) + 5*orientationIndex], orientation order portrait, landscape",
            "mean": r6(self.pca.mean_),
            "components": [r6(c) for c in self.pca.components_],
            "framing": {"coef": [r6(c) for c in self.framing.coef_], "intercept": r6(self.framing.intercept_)},
            "offset": {"coef": r6(self.offset.coef_), "intercept": round(float(self.offset.intercept_), 6),
                       "max": MAX_OFFSET},
            "eyeY": {"coef": r6(self.eye.coef_), "intercept": round(float(self.eye.intercept_), 6)},
            "height": {o: {str(level): {f: round(self.height[o, level, f], 6) for f in FRAMINGS}
                           for level in range(1, 6)} for o in ORIENTATIONS},
            "levels": {o: [round(e, 6) for e in self.edges[o]] for o in ORIENTATIONS},
        }


class Baseline:
    """Python port of RecommendationData.match (features/scene/recommendation_data.dart)."""

    def __init__(self, path):
        self.asset = json.loads(Path(path).read_text())
        self.clusters = []
        for c in self.asset["clusters"]:
            v = np.frombuffer(base64.b64decode(c["e"]), dtype=np.int8).astype(np.float64) / 127
            self.clusters.append(("portrait" if c["o"] == "p" else "landscape", v / np.linalg.norm(v),
                                  {int(k): x for k, x in c["lv"].items()}))

    def predict(self, emb, level, orientation):
        same = [c for c in self.clusters if c[0] == orientation]
        selected = sorted({l for c in same for l in c[2]}, key=lambda l: (abs(l - level), l))[0]
        scored = sorted([(float(np.clip(emb @ c[1], -1, 1)), i, c) for i, c in enumerate(same) if selected in c[2]],
                        key=lambda t: (-t[0], t[1]))
        scored = [t for t in scored if t[0] > 0]
        if not scored:
            fb = self.asset["fallback"][orientation][str(level)]
            return dict(f=fb["f"], h=fb["h"], cx=fb["cx"], cy=fb["cy"])
        f = scored[0][2][2][selected]["f"]
        W = h = cx = cy = 0.0
        for score, _, c in scored[:3]:
            x = c[2][selected]
            if x["f"] == f:
                w = score * x["n"]
                W, h, cx, cy = W + w, h + w * x["h"], cx + w * x["cx"], cy + w * x["cy"]
        return dict(f=f, h=h / W, cx=cx / W, cy=cy / W)


def collect(photos, args, scores):
    sys.path.insert(0, str(Path(__file__).parent))
    from background_clip import (ClipEncoder, NOT_REAL_PERSON, PersonPrompts, SelfieSegmenter,
                                 mask_person, normalize_embedding)
    from pose_analysis import MediaPipePhotoAnalyzer, center_crop_rect, load_photo
    pose = MediaPipePhotoAnalyzer(args.pose_model, args.person_model)
    segmenter, encoder = SelfieSegmenter(args.segmentation_model), ClipEncoder(args.clip_model)
    prompts = PersonPrompts(args.person_prompts)
    rows, counts = [], {}
    count = lambda k: counts.__setitem__(k, counts.get(k, 0) + 1)
    try:
        for path in sorted(p for p in photos.rglob("*") if p.suffix.lower() in (".jpg", ".jpeg", ".png")):
            count("processed")
            r = pose.analyze(path)
            if not r.accepted:
                count(f"rejected/pose/{r.reason}")
                continue
            with load_photo(path) as image:
                shot = (image.crop(center_crop_rect(image.width, image.height, r.crop == "portrait_3_4"))
                        if r.crop in ("portrait_3_4", "landscape_4_3") else image.copy())
            with shot:
                if prompts.not_real_probability(shot, r.person, encoder) >= NOT_REAL_PERSON:
                    count("rejected/not_real_person")
                    continue
                try:
                    mask = segmenter(shot)
                    with mask_person(shot, mask) as filled:
                        emb = normalize_embedding(encoder(filled))
                except Exception:
                    count("rejected/segmentation_or_embedding")
                    continue
                m = np.asarray(mask, dtype=np.float32) >= .5
                person_x = float(np.nonzero(m)[1].mean() / m.shape[1])
            c = r.composition
            rows.append(dict(orientation=r.orientation, f=c.f, h=c.h, s=c.s, cx=c.cx, cy=c.cy, emb=emb,
                             person_x=person_x, score=scores.get(path.name, {}).get("mean")))
            count("accepted")
    finally:
        pose.close()
        segmenter.close()
    return rows, counts


def evaluate(rows, baseline, folds=5):
    from sklearn.model_selection import KFold
    preds = {"current (recommend.json)": [None] * len(rows), "v2": [None] * len(rows)}
    for train, test in KFold(folds, shuffle=True, random_state=0).split(rows):
        model = V2Model().fit([rows[i] for i in train])
        for i in test:
            r = rows[i]
            preds["v2"][i] = model.predict(r["emb"], level_of(r["s"], model.edges[r["orientation"]]),
                                           r["orientation"], r["person_x"])
            if baseline:
                preds["current (recommend.json)"][i] = baseline.predict(
                    r["emb"], level_of(r["s"], baseline.asset["levels"][r["orientation"]]), r["orientation"])
    if not baseline:
        del preds["current (recommend.json)"]
    out = {}
    for name, p in preds.items():
        same = np.array([q["f"] == r["f"] for r, q in zip(rows, p)])
        err = lambda k: np.array([abs(q[k] - r[k]) for r, q in zip(rows, p)])
        cx = np.array([q["cx"] for q in p])
        out[name] = dict(
            framing=same.mean(), cx=err("cx").mean(),
            offset=np.mean([abs(abs(q["cx"] - .5) - abs(r["cx"] - .5)) for r, q in zip(rows, p)]),
            cy=err("cy").mean(), h=err("h").mean(), h_same=err("h")[same].mean(),
            centre=((cx >= CENTRE[0]) & (cx <= CENTRE[1])).mean())
    return out


def report(counts, rows, metrics, size):
    truth = np.mean([CENTRE[0] <= r["cx"] <= CENTRE[1] for r in rows])
    lines = ["# Recommender v2 report", "",
             "Aggregate output only. No photo names, per-photo values or embeddings.", "",
             f"Photos: {counts.get('processed', 0)} processed, {len(rows)} used. "
             f"recommend_v2.json: {size:,} bytes.", "", "Filter | Count", "--- | ---:"]
    lines += [f"{k} | {v}" for k, v in sorted(counts.items())]
    lines += ["", "## 5-fold cross-validation by photo", "",
              f"Truth: {truth:.1%} of photos have the shoulder centre in {CENTRE[0]}-{CENTRE[1]}.", "",
              "Model | Framing match | cx MAE | offset \\|cx-.5\\| MAE | cy MAE | h MAE | h MAE (same framing) | centre share",
              "--- | ---: | ---: | ---: | ---: | ---: | ---: | ---:"]
    for name, m in metrics.items():
        lines.append(f"{name} | {m['framing']:.1%} | {m['cx']:.3f} | {m['offset']:.3f} | {m['cy']:.3f} | "
                     f"{m['h']:.3f} | {m['h_same']:.3f} | {m['centre']:.1%}")
    lines += ["", "v2 cx uses the side of each test photo's person mask, as the app does",
              "live; on a test photo that side is the true side, so cx is optimistic. The",
              "offset column does not depend on the side.", ""]
    return "\n".join(lines)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ("--photos", "--pose-model", "--person-model", "--segmentation-model", "--clip-model"):
        p.add_argument(name, type=Path, required=True)
    p.add_argument("--scores", type=Path, help="CADB composition_scores.json (optional weights)")
    p.add_argument("--person-prompts", type=Path, default=Path(__file__).with_name("person_prompts.npz"))
    p.add_argument("--baseline-asset", type=Path, help="current recommend.json, for the comparison")
    p.add_argument("--out", type=Path, default=Path("app/assets/recommend_v2.json"))
    p.add_argument("--report", type=Path, default=Path("tools/report_v2.md"))
    args = p.parse_args(argv)
    scores = json.loads(args.scores.read_text()) if args.scores else {}
    rows, counts = collect(args.photos, args, scores)
    metrics = evaluate(rows, Baseline(args.baseline_asset) if args.baseline_asset else None)
    payload = json.dumps(V2Model().fit(rows).asset(), separators=(",", ":")).encode()
    if len(payload) >= 1_000_000:
        raise SystemExit("Asset too large")
    args.out.write_bytes(payload)
    text = report(counts, rows, metrics, len(payload))
    args.report.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
