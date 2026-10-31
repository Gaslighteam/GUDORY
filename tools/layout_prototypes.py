"""Phase A offline aggregates and selectors. Never imported by the app.

No image identifiers or individual embeddings are serialized. Existing pose,
CLIP, source weights, background partitions and legacy fallbacks are reused.
"""
import base64
import copy
from dataclasses import asdict, dataclass
import json
import math

import numpy as np

from recommendation_assets import (FRAMINGS, MIN_SUPPORT, ORIENTATIONS, _key,
    deterministic_clusters, level_for, quantize_center, validate_asset)


@dataclass(frozen=True)
class PrototypeConfig:
    x_unit: float = .12
    y_unit: float = .12
    log_span_unit: float = .35
    log_scale_unit: float = .35
    minimum_gain: float = .65
    minimum_separation: float = 1.5
    minimum_gap: float = .5
    gap_multiplier: float = 3.0
    max_leaves: int = 8
    confidence_prior: float = 6.0

    def validate(self):
        for k, v in asdict(self).items():
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v <= 0:
                raise ValueError('Invalid prototype configuration')
        if self.minimum_gain >= 1 or type(self.max_leaves) is not int or self.max_leaves > 32:
            raise ValueError('Invalid split limits')


@dataclass(frozen=True)
class SelectionConfig:
    background: float = 1.0
    support: float = .08
    framing: float = .04
    position: float = .15
    tie_margin: float = .005

    def validate(self):
        if any(isinstance(v, bool) or not math.isfinite(v) or v < 0 for v in asdict(self).values()):
            raise ValueError('Invalid selection configuration')


def features(rows, config):
    return np.array([[r.composition.cx / config.x_unit,
                      r.composition.cy / config.y_unit,
                      math.log(r.composition.h) / config.log_span_unit,
                      math.log(r.composition.s) / config.log_scale_unit] for r in rows])


def _split(x, w, config):
    """Weighted PCA initialization + two-means; accept only separated modes.

    A gap must exceed both a fixed meaningful feature distance and three times
    typical projected neighbor spacing. This rejects ordinary uniform continua;
    it is a heuristic mode test, not a density/quality guarantee.
    """
    if len(x) < MIN_SUPPORT or len(np.unique(x, axis=0)) < 2:
        return None
    mean = np.average(x, axis=0, weights=w)
    centered = x - mean
    covariance = (centered * w[:, None]).T @ centered / w.sum()
    _, axes = np.linalg.eigh(covariance)
    axis = axes[:, -1]
    if axis[np.argmax(np.abs(axis))] < 0:
        axis = -axis
    projection = centered @ axis
    centers = x[[np.argmin(projection), np.argmax(projection)]].copy()
    for _ in range(40):
        labels = np.argmin(((x[:, None] - centers) ** 2).sum(axis=2), axis=1)
        if len(set(labels)) < 2:
            return None
        updated = np.array([np.average(x[labels == i], axis=0, weights=w[labels == i]) for i in (0, 1)])
        if np.allclose(updated, centers, rtol=0, atol=1e-12):
            centers = updated
            break
        centers = updated
    left, right = [np.flatnonzero(labels == i) for i in (0, 1)]
    # Reorient the projection along the actual split, then require a real gap.
    direction = centers[1] - centers[0]
    distance = float(np.linalg.norm(direction))
    if distance < config.minimum_separation:
        return None
    projected = x @ (direction / distance)
    gap = float(projected[right].min() - projected[left].max())
    spacing = float(np.median(np.diff(np.sort(projected))))
    before = float(np.sum(w[:, None] * centered ** 2))
    after = float(np.sum(w[:, None] * (x - centers[labels]) ** 2))
    if (before <= 0 or 1 - after / before < config.minimum_gain
            or gap < max(config.minimum_gap, config.gap_multiplier * spacing)):
        return None
    return left.tolist(), right.tolist()


def discover(rows, cell_mass, config=PrototypeConfig()):
    """Variable-count, disjoint same-framing cohorts; unsupported modes dropped.

    Joint weighted centroids preserve first-order h/s/position relationships.
    We do not independently select four named layouts or force off-center modes.
    """
    config.validate()
    if not rows:
        return []
    if (not math.isfinite(cell_mass) or cell_mass < sum(r.weight for r in rows)
            or any(not np.isfinite([r.weight, r.composition.cx, r.composition.cy,
                                   r.composition.h, r.composition.s]).all()
                   or r.weight not in (1, 3) or r.composition.f not in FRAMINGS
                   or not 0 < r.composition.s <= r.composition.h <= 1
                   or not 0 <= r.composition.cx <= 1 or not 0 <= r.composition.cy <= 1
                   for r in rows)):
        raise ValueError('Invalid composition cohort/mass')
    if len({(r.orientation, r.composition.f) for r in rows}) != 1:
        raise ValueError('Framing/orientation cohorts must be separate')
    rows = sorted(rows, key=_key)
    x = features(rows, config)
    w = np.array([r.weight for r in rows])
    leaves = [list(range(len(rows)))]
    cursor = 0
    while cursor < len(leaves):
        group = leaves[cursor]
        split = _split(x[group], w[group], config)
        if split is None:
            cursor += 1
            continue
        children = [[group[i] for i in child] for child in split]
        # Do not merge an unsupported separated mode into a central average.
        children = [child for child in children if len(child) >= MIN_SUPPORT]
        if len(leaves) - 1 + len(children) > config.max_leaves:
            # A complexity cap must not collapse a known separated cohort into
            # a fabricated central representative. Omit unresolved support.
            children = []
        leaves[cursor:cursor + 1] = children
    output = []
    for group in leaves:
        if len(group) < MIN_SUPPORT:
            continue
        members = [rows[i] for i in group]
        mass = float(w[group].sum())
        value = {'f': members[0].composition.f, 'n': len(group), 'w': mass,
                 'confidence': mass / cell_mass * len(group) / (len(group) + config.confidence_prior)}
        for field in ('h', 's', 'cx', 'cy'):
            value[field] = float(np.average([getattr(r.composition, field) for r in members], weights=w[group]))
        # No reliable horizon evidence is produced by the existing pose pipeline.
        value['hy'] = None
        output.append(value)
    return sorted(output, key=lambda v: (FRAMINGS.index(v['f']), v['cx'], v['cy'], v['s'], v['h']))


def build_prototypes(samples, legacy, config=PrototypeConfig()):
    validate_asset(legacy)
    config.validate()
    output = {'schema': 'gudory-layout-prototypes', 'version': 1,
              'model': legacy['model'], 'dim': 512, 'quant': 'int8',
              'config': asdict(config), 'levels': copy.deepcopy(legacy['levels']),
              'fallback': copy.deepcopy(legacy['fallback']), 'clusters': []}
    # Isolate the composition change: exactly the legacy background partitions,
    # centres, boundaries and fallback targets, not a new background model.
    allowed = {(c['o'], c['e']) for c in legacy['clusters']}
    for orientation in ORIENTATIONS:
        rows = sorted((s for s in samples if s.orientation == orientation), key=_key)
        if not rows:
            continue
        for group in deterministic_clusters(rows):
            members = [rows[i] for i in group]
            center = quantize_center(np.average(np.stack([s.embedding for s in members]), axis=0,
                                                weights=[s.weight for s in members]))
            if (orientation[0], center) not in allowed:
                continue
            levels = {}
            for level in range(1, 6):
                cohort = [r for r in members if level_for(r.composition.s, legacy['levels'][orientation]) == level]
                mass = sum(r.weight for r in cohort)
                values = [v for f in FRAMINGS for v in discover(
                    [r for r in cohort if r.composition.f == f], mass, config)]
                if values:
                    levels[str(level)] = values
            if levels:
                output['clusters'].append({'o': orientation[0], 'e': center, 'n': len(members), 'lv': levels})
    output['clusters'].sort(key=lambda c: (c['o'] != 'p', c['e'], c['n']))
    validate_prototypes(output)
    return output


def validate_prototypes(asset):
    """Versioned strict allowlist; no per-photo fields or singleton cohorts."""
    if set(asset) != {'schema', 'version', 'model', 'dim', 'quant', 'config', 'levels', 'fallback', 'clusters'}:
        raise ValueError('Unexpected experimental root fields')
    if asset['schema'] != 'gudory-layout-prototypes' or type(asset['version']) is not int or asset['version'] != 1:
        raise ValueError('Unsupported prototype schema')
    if set(asset['config']) != set(asdict(PrototypeConfig())) or not isinstance(asset['clusters'], list):
        raise ValueError('Invalid configuration/cluster schema')
    config = PrototypeConfig(**asset['config'])
    config.validate()
    reduced = {k: copy.deepcopy(asset[k]) for k in ('model', 'dim', 'quant', 'levels', 'fallback')}
    reduced['clusters'] = []
    counts = {'p': 0, 'l': 0}
    for c in asset['clusters']:
        if set(c) != {'o', 'e', 'n', 'lv'} or c['o'] not in counts:
            raise ValueError('Unexpected cluster fields')
        counts[c['o']] += 1
        if counts[c['o']] > 64 or not c['lv']:
            raise ValueError('Invalid cluster count/levels')
        used = 0
        for level, values in c['lv'].items():
            if level not in set('12345') or not isinstance(values, list) or not values:
                raise ValueError('Invalid prototype levels')
            for v in values:
                if set(v) != {'f', 'h', 's', 'cx', 'cy', 'hy', 'n', 'w', 'confidence'} or v['f'] not in FRAMINGS:
                    raise ValueError('Unexpected prototype fields')
                if type(v['n']) is not int or v['n'] < MIN_SUPPORT:
                    raise ValueError('Insufficient actual support')
                for key in ('h', 's', 'cx', 'cy', 'w', 'confidence'):
                    if isinstance(v[key], bool) or not isinstance(v[key], (int, float)) or not math.isfinite(v[key]):
                        raise ValueError('Non-finite prototype measurement')
                if (not 0 < v['s'] <= v['h'] <= 1 or not 0 <= v['cx'] <= 1 or not 0 <= v['cy'] <= 1
                        or not v['n'] <= v['w'] <= 3 * v['n'] or not 0 < v['confidence'] <= 1 or v['hy'] is not None):
                    raise ValueError('Invalid prototype measurements/support')
                used += v['n']
            # Exercise legacy centre/normalized-coordinate/support validators.
            first = values[0]
            reduced['clusters'].append({**{k: c[k] for k in ('o', 'e', 'n')}, 'lv': {
                level: {k: first[k] for k in ('f', 'h', 'cx', 'cy', 'hy', 'n')}}})
        if used > c['n']:
            raise ValueError('Overlapping/excess support')
    # Check centres individually to avoid counting repeated levels as clusters.
    clusters = reduced.pop('clusters')
    validate_asset({**reduced, 'clusters': []})
    for c in clusters:
        validate_asset({**reduced, 'clusters': [c]})
    if len(json.dumps(asset, allow_nan=False, separators=(',', ':')).encode()) >= 1_000_000:
        raise ValueError('Prototype asset exceeds 1 MB')


def serialize_prototypes(asset):
    validate_prototypes(asset)
    return (json.dumps(asset, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode()


def _unit(values):
    x = np.asarray(values, dtype=np.float64)
    if x.shape != (512,) or not np.isfinite(x).all() or np.linalg.norm(x) == 0:
        raise ValueError('Expected a finite nonzero 512-vector')
    return x / np.linalg.norm(x)


class Matcher:
    """Faithful Dart legacy mirror or experimental one-prototype selection.

    Decode once; timings exclude model inference, isolates and camera work.
    """
    def __init__(self, asset, experimental=False, config=SelectionConfig()):
        (validate_prototypes if experimental else validate_asset)(asset)
        config.validate()
        self.asset, self.experimental, self.config = asset, experimental, config
        self.groups = {}
        for orientation in ORIENTATIONS:
            cs = [c for c in asset['clusters'] if c['o'] == orientation[0]]
            vectors = [_unit(np.frombuffer(base64.b64decode(c['e']), dtype=np.int8).astype(float) / 127) for c in cs]
            self.groups[orientation] = cs, np.array(vectors).reshape(-1, 512)

    def fallback(self, orientation, level):
        return {'composition': copy.deepcopy(self.asset['fallback'][orientation][str(level)]),
                'status': 'legacy_fallback', 'selected_level': level, 'support': 0}

    def recommend(self, embedding, level, orientation, subject=None):
        level = max(1, min(5, level))
        fallback = self.fallback(orientation, level)
        try:
            vector = _unit(embedding)
            cs, vectors = self.groups[orientation]
            available = {int(lv) for c in cs for lv in c['lv']}
            if not available:
                return fallback
            selected = min(available, key=lambda lv: (abs(lv - level), lv))
            scores = np.clip(vectors @ vector, -1, 1)
            indices = [i for i, c in enumerate(cs) if str(selected) in c['lv'] and scores[i] > 0]
            indices.sort(key=lambda i: (-scores[i], i))
            indices = indices[:3]
            if not indices:
                return fallback
            if not self.experimental:
                values = [(cs[i]['lv'][str(selected)], float(scores[i])) for i in indices]
                framing = values[0][0]['f']
                values = [(v, score * v['n']) for v, score in values if v['f'] == framing]
                weight = sum(w for _, w in values)
                composition = {'f': framing}
                for field in ('h', 'cx', 'cy', 'hy'):
                    valid = [(v[field], w) for v, w in values if v[field] is not None]
                    composition[field] = sum(x * w for x, w in valid) / sum(w for _, w in valid) if valid else None
                return {'composition': composition, 'status': 'matched', 'selected_level': selected,
                        'support': sum(v['n'] for v, _ in values)}
            candidates = [(v, float(scores[i]), i, j) for i in indices
                          for j, v in enumerate(cs[i]['lv'][str(selected)])]
            mass = sum(v['w'] for v, *_ in candidates)
            ranked = []
            for v, cosine, i, j in candidates:
                score = self.config.background * cosine + self.config.support * math.log1p(v['w']) / math.log1p(mass)
                if subject:
                    if subject.get('f') in FRAMINGS:
                        score += self.config.framing * (subject['f'] == v['f'])
                    if 'cx' in subject:
                        cx = float(subject['cx'])
                        if not math.isfinite(cx) or not 0 <= cx <= 1:
                            raise ValueError('Invalid subject position')
                        score -= self.config.position * abs(v['cx'] - cx)
                ranked.append((score, v, i, j))
            best = max(t[0] for t in ranked)
            tied = [t for t in ranked if best - t[0] <= self.config.tie_margin]
            _, chosen, _, _ = min(tied, key=lambda t: (-t[1]['w'], -t[1]['n'], t[2], t[3]))
            return {'composition': {k: chosen[k] for k in ('f', 'h', 'cx', 'cy', 'hy')},
                    'status': 'prototype', 'selected_level': selected, 'support': chosen['n']}
        except (ValueError, TypeError, KeyError, FloatingPointError):
            return fallback
