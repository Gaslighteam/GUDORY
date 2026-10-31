"""Deterministic, weighted aggregation. No paths/IDs or per-photo serialization."""
import base64
from collections import Counter
from dataclasses import dataclass
import json

import numpy as np

from background_clip import normalize_embedding
from pose_analysis import Composition

FRAMINGS = ("chestUp", "waistUp", "kneeUp", "fullBody")
ORIENTATIONS = ("portrait", "landscape")
MIN_SUPPORT = 3


@dataclass(frozen=True)
class Sample:
    orientation: str
    composition: Composition
    embedding: np.ndarray
    weight: float


def weighted_quantile(values, weights, quantile):
    """Inverse empirical weighted CDF; equal values always share a level."""
    values, weights = np.asarray(values, dtype=float), np.asarray(weights, dtype=float)
    if (values.ndim != 1 or len(values) == 0 or values.shape != weights.shape
            or not np.isfinite(values).all() or not np.isfinite(weights).all()
            or np.any(weights <= 0) or not 0 <= quantile <= 1):
        raise ValueError("Invalid weighted quantile inputs")
    order = np.argsort(values, kind="stable")
    cumulative = np.cumsum(weights[order])
    index = min(int(np.searchsorted(cumulative, quantile * cumulative[-1], side="left")), len(values) - 1)
    return float(values[order[index]])


def level_for(scale, edges):
    return next((index + 1 for index, edge in enumerate(edges) if scale >= edge), 5)


def aggregate(samples):
    if not samples:
        raise ValueError("Cannot aggregate no samples")
    weights = Counter()
    for sample in samples:
        weights[sample.composition.f] += sample.weight
    # Equal weighted counts: fixed order, closest framing wins the tie.
    framing = max(FRAMINGS, key=lambda f: weights[f])
    selected = [s for s in samples if s.composition.f == framing]
    if len(selected) < MIN_SUPPORT:
        return None
    result = {"f": framing}
    for name in ("h", "cx", "cy", "hy"):
        valid = [s for s in selected if getattr(s.composition, name) is not None]
        result[name] = (weighted_quantile([getattr(s.composition, name) for s in valid],
                                        [s.weight for s in valid], .5) if len(valid) >= MIN_SUPPORT else None)
    result["n"] = len(selected)  # actual contributors, not source-weight mass
    return result


def quantize_center(vector):
    unit = normalize_embedding(vector)
    return base64.b64encode(np.rint(np.clip(unit, -1, 1) * 127).astype(np.int8).tobytes()).decode("ascii")


def deterministic_clusters(samples, max_clusters=64, photos_per_cluster=20):
    from sklearn.cluster import KMeans
    from threadpoolctl import threadpool_limits
    vectors = np.stack([normalize_embedding(s.embedding) for s in samples])
    weights = np.array([s.weight for s in samples], dtype=np.float64)
    count = min(max_clusters, max(1, len(samples) // photos_per_cluster),
                len(np.unique(vectors, axis=0)))
    with threadpool_limits(limits=1):
        labels = KMeans(n_clusters=count, random_state=0, n_init=10,
                        algorithm="lloyd", max_iter=300).fit_predict(vectors, sample_weight=weights)
    groups = [np.flatnonzero(labels == index).tolist() for index in sorted(set(labels))]
    # Never export a singleton/doubleton centre, which could expose one photo.
    while len(groups) > 1 and min(map(len, groups)) < MIN_SUPPORT:
        small = min(range(len(groups)), key=lambda i: (len(groups[i]), i))
        centers = [np.average(vectors[g], axis=0, weights=weights[g]) for g in groups]
        nearest = min((i for i in range(len(groups)) if i != small),
                      key=lambda i: (float(np.linalg.norm(centers[i] - centers[small])), i))
        groups[nearest] = sorted(groups[nearest] + groups[small])
        del groups[small]
    return groups


def _key(sample):
    c = sample.composition
    return (sample.orientation, c.f, c.h, c.s, c.cx, c.cy,
            -1 if c.hy is None else c.hy, sample.weight, sample.embedding.tobytes())


def build_asset(samples):
    samples = sorted(samples, key=_key)
    for sample in samples:
        c = sample.composition
        if (sample.orientation not in ORIENTATIONS or c.f not in FRAMINGS
                or not np.isfinite([c.h, c.s, c.cx, c.cy, sample.weight]).all()
                or not 0 < c.s <= c.h <= 1 or not 0 <= c.cx <= 1 or not 0 <= c.cy <= 1
                or sample.weight <= 0 or (c.hy is not None and (not np.isfinite(c.hy) or not 0 <= c.hy <= 1))):
            raise ValueError("Invalid training measurement")
        normalize_embedding(sample.embedding)
    asset = {"model": "clip-vit-base-patch32", "dim": 512, "quant": "int8",
             "levels": {}, "fallback": {}, "clusters": []}
    diagnostics = {}
    for orientation in ORIENTATIONS:
        rows = [s for s in samples if s.orientation == orientation]
        if len(rows) < MIN_SUPPORT:
            raise ValueError("Need at least three accepted photos in each orientation")
        edges = [weighted_quantile([s.composition.s for s in rows], [s.weight for s in rows], q)
                 for q in (.8, .6, .4, .2)]
        asset["levels"][orientation] = edges
        bins = {lv: [s for s in rows if level_for(s.composition.s, edges) == lv] for lv in range(1, 6)}
        fallback, pooling = {}, {}
        for level in range(1, 6):
            selected, used = [], []
            for neighbor in sorted(bins, key=lambda lv: (abs(lv - level), lv)):
                selected += bins[neighbor]
                used.append(neighbor)
                composition = aggregate(selected) if selected else None
                if composition is not None:
                    fallback[str(level)] = {k: v for k, v in composition.items() if k != "n"}
                    pooling[str(level)] = used
                    break
            else:
                raise ValueError("No dominant framing with at least three contributors")
        asset["fallback"][orientation] = fallback
        clusters = []
        groups = deterministic_clusters(rows)
        for group in groups:
            members = [rows[i] for i in group]
            center = np.average(np.stack([s.embedding for s in members]), axis=0,
                                weights=[s.weight for s in members])
            levels = {}
            for level in range(1, 6):
                subset = [s for s in members if level_for(s.composition.s, edges) == level]
                composition = aggregate(subset) if subset else None
                if composition is not None:
                    levels[str(level)] = composition
            # A cluster without any supported level cannot serve recommendations.
            if levels:
                clusters.append({"o": orientation[0], "e": quantize_center(center), "n": len(members), "lv": levels})
        clusters.sort(key=lambda c: (c["e"], c["n"]))
        asset["clusters"] += clusters
        diagnostics[orientation] = {"photos": len(rows), "weight": sum(s.weight for s in rows),
            "levels": {lv: {"count": len(bins[lv]), "weight": sum(s.weight for s in bins[lv]),
                             "framings": dict(Counter(s.composition.f for s in bins[lv]))} for lv in bins},
            "fallback_pooled_levels": pooling, "cluster_sizes": dict(sorted(Counter(c["n"] for c in clusters).items())),
            "clusters": len(clusters), "omitted_clusters": len(groups) - len(clusters)}
    validate_asset(asset)
    return asset, diagnostics


def validate_asset(asset):
    """Strict allowlist: schema validation also prevents per-photo field leakage."""
    if set(asset) != {"model", "dim", "quant", "levels", "fallback", "clusters"}:
        raise ValueError("Unexpected asset fields")
    if asset["model"] != "clip-vit-base-patch32" or type(asset["dim"]) is not int or asset["dim"] != 512 or asset["quant"] != "int8":
        raise ValueError("Unexpected encoder metadata")
    if set(asset["levels"]) != set(ORIENTATIONS) or set(asset["fallback"]) != set(ORIENTATIONS):
        raise ValueError("Both orientations required")

    def composition(value, clustered):
        expected = {"f", "h", "cx", "cy", "hy"} | ({"n"} if clustered else set())
        if set(value) != expected or value["f"] not in FRAMINGS:
            raise ValueError("Unexpected composition fields")
        for key in ("h", "cx", "cy", "hy"):
            v = value[key]
            if key == "hy" and v is None:
                continue
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not np.isfinite(v) or not 0 <= v <= 1:
                raise ValueError("Invalid normalized composition")
        if value["h"] <= 0 or (clustered and (type(value["n"]) is not int or value["n"] < MIN_SUPPORT)):
            raise ValueError("Insufficient composition support")

    for orientation in ORIENTATIONS:
        edges = asset["levels"][orientation]
        if (not isinstance(edges, list) or len(edges) != 4 or not all(
                isinstance(x, (int, float)) and not isinstance(x, bool) and np.isfinite(x) and 0 < x <= 1 for x in edges)
                or edges != sorted(edges, reverse=True)):
            raise ValueError("Invalid quintile edges")
        if set(asset["fallback"][orientation]) != {str(i) for i in range(1, 6)}:
            raise ValueError("Missing fallback level")
        for c in asset["fallback"][orientation].values():
            composition(c, False)
    if not isinstance(asset["clusters"], list):
        raise ValueError("Clusters must be a list")
    counts = Counter()
    for cluster in asset["clusters"]:
        if set(cluster) != {"o", "e", "n", "lv"} or cluster["o"] not in ("p", "l"):
            raise ValueError("Unexpected cluster fields")
        counts[cluster["o"]] += 1
        if type(cluster["n"]) is not int or cluster["n"] < MIN_SUPPORT:
            raise ValueError("Insufficient cluster support")
        vector = np.frombuffer(base64.b64decode(cluster["e"], validate=True), dtype=np.int8)
        if vector.shape != (512,) or not vector.any() or np.any(vector == -128):
            raise ValueError("Invalid quantized centre")
        if not .85 < float(np.linalg.norm(vector.astype(float) / 127)) < 1.15:
            raise ValueError("Centre was not normalized before quantization")
        if not cluster["lv"] or not set(cluster["lv"]).issubset({str(i) for i in range(1, 6)}):
            raise ValueError("Invalid cluster levels")
        for value in cluster["lv"].values():
            composition(value, True)
            if value["n"] > cluster["n"]:
                raise ValueError("Invalid contributor count")
        if sum(value["n"] for value in cluster["lv"].values()) > cluster["n"]:
            raise ValueError("Level contributor counts exceed cluster size")
    if any(n > 64 for n in counts.values()):
        raise ValueError("Too many clusters")
    if len(json.dumps(asset, allow_nan=False, separators=(",", ":")).encode()) >= 1_000_000:
        raise ValueError("Asset exceeds 1 MB")


def serialize_asset(asset):
    validate_asset(asset)
    data = (json.dumps(asset, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(data) >= 1_000_000:
        raise ValueError("Asset exceeds 1 MB")
    return data
