"""Optional aggregate-only composition modes; never exports photo records.

Phase A: conservative gap separation, not an aesthetic-quality predictor.
The v1 recommendation asset is unchanged; this produces a separate sidecar.
"""
from dataclasses import dataclass
import hashlib
import json
import math
import re

FRAMINGS = ('chestUp', 'waistUp', 'kneeUp', 'fullBody')


@dataclass(frozen=True)
class PrototypeConfig:
    min_support: int = 3
    max_modes: int = 4
    # A continuous distribution is deliberately NOT split just to fill k slots.
    gaps: tuple = (.12, .10, .15)  # cx, cy, h, within the same framing

    def __post_init__(self):
        if (type(self.min_support) is not int or self.min_support < 3
                or type(self.max_modes) is not int or not 1 <= self.max_modes <= 4
                or len(self.gaps) != 3
                or not all(math.isfinite(v) and v > 0 for v in self.gaps)):
            raise ValueError('Invalid prototype configuration')


def _median(rows, name):
    pairs = sorted((float(getattr(r.composition, name)), float(r.weight)) for r in rows)
    half = sum(w for _, w in pairs) / 2
    mass = 0
    for value, weight in pairs:
        mass += weight
        if mass >= half:
            return value
    raise ValueError('Empty group')


def composition_modes(rows, config=PrototypeConfig()):
    """Separate only observable gaps with >=min_support on both sides.

    Support counts actual input rows, not upweighted copies. Repeated ingestion
    of a photo must be prevented upstream; this function does not invent IDs.
    """
    rows = sorted(rows, key=lambda r: (r.composition.cx, r.composition.cy, r.composition.h, r.weight))
    if len(rows) < config.min_support:
        return []
    for r in rows:
        c = r.composition
        if (c.f not in FRAMINGS or not math.isfinite(r.weight) or r.weight <= 0
                or not all(math.isfinite(v) and 0 <= v <= 1 for v in (c.h, c.cx, c.cy))
                or c.h <= 0):
            raise ValueError('Invalid composition sample')
    if len({r.composition.f for r in rows}) != 1:
        raise ValueError('Never mix framing anchors')
    groups = [rows]
    names = ('cx', 'cy', 'h')
    while len(groups) < config.max_modes:
        best = None
        for group_index, group in enumerate(groups):
            for axis, name in enumerate(names):
                ordered = sorted(group, key=lambda r: (getattr(r.composition, name), r.composition.cx, r.composition.cy, r.composition.h, r.weight))
                for i in range(config.min_support, len(ordered) - config.min_support + 1):
                    gap = getattr(ordered[i].composition, name) - getattr(ordered[i-1].composition, name)
                    gain = gap / config.gaps[axis]
                    if gain < 1 - 1e-12:
                        continue
                    # Deterministic tie order, independent of ingestion order.
                    key = (gain, -group_index, -axis, -i)
                    if best is None or key > best[0]:
                        best = (key, group_index, ordered[:i], ordered[i:])
        if best is None:
            break
        _, index, left, right = best
        groups[index:index+1] = [left, right]
    modes = []
    for group in groups:
        values = {name: _median(group, name) for name in names}
        mass = sum(r.weight for r in group)
        spread = math.sqrt(sum(r.weight * sum(
            ((getattr(r.composition, name) - values[name]) / scale) ** 2
            for name, scale in zip(names, config.gaps)) for r in group) / (3 * mass))
        # Support/compactness heuristic, NOT calibrated probability or beauty.
        confidence = len(group) / (len(group) + config.min_support) / (1 + spread)
        modes.append({'f': group[0].composition.f, **{k: values[k] for k in ('h', 'cx', 'cy')},
                      'hy': None, 'n': len(group), 'spread': spread, 'confidence': confidence})
    return sorted(modes, key=lambda m: (m['cx'], m['cy'], m['h']))


def build_layout_asset(samples, legacy_asset, config=PrototypeConfig(), *, background_groups=None):
    # Imports are lazy: pure mode tests do not need native models or sklearn.
    import numpy as np
    from recommendation_assets import deterministic_clusters, quantize_center, level_for, _key
    samples = sorted(samples, key=_key)
    supported = {(c['o'], c['e']): c for c in legacy_asset['clusters']}
    clusters = []
    for orientation in ('portrait', 'landscape'):
        rows = [s for s in samples if s.orientation == orientation]
        if not rows:
            continue
        edges = legacy_asset['levels'][orientation]
        groups = deterministic_clusters(rows) if background_groups is None else background_groups[orientation]
        if sorted(i for group in groups for i in group) != list(range(len(rows))):
            raise ValueError('Background groups must partition the samples')
        for indices in groups:
            members = [rows[i] for i in indices]
            vector = np.average(np.stack([s.embedding for s in members]), axis=0,
                                weights=[s.weight for s in members])
            encoded = quantize_center(vector)
            legacy = supported.get((orientation[0], encoded))
            if legacy is None:
                continue
            if len(members) != legacy['n']:
                raise ValueError('Background support differs from legacy asset')
            levels = {}
            for level in range(1, 6):
                # Preserve exactly the legacy orientation/level availability.
                if str(level) not in legacy['lv']:
                    continue
                subset = [s for s in members if level_for(s.composition.s, edges) == level]
                modes = []
                for framing in FRAMINGS:
                    modes += composition_modes([s for s in subset if s.composition.f == framing], config)
                for index, mode in enumerate(modes):
                    # ID derives from aggregate geometry, never file names/IDs.
                    prefix = hashlib.sha256(encoded.encode('ascii')).hexdigest()[:24]
                    mode['id'] = f'{orientation[0]}-{prefix}-{level}-{index}'
                if modes:
                    levels[str(level)] = modes
            if levels:
                clusters.append({'o': orientation[0], 'e': encoded, 'lv': levels})
    clusters.sort(key=lambda c: (c['o'], c['e']))
    asset = {'version': 1, 'clusters': clusters}
    serialize_layout_asset(asset, legacy_asset)
    return asset


def serialize_layout_asset(asset, legacy_asset):
    """Strict allowlist and support/centre checks prevent row-data leakage."""
    if set(asset) != {'version', 'clusters'} or type(asset['version']) is not int or asset['version'] != 1:
        raise ValueError('Invalid layout version/fields')
    if not isinstance(asset['clusters'], list) or len(asset['clusters']) > 128:
        raise ValueError('Invalid cluster count')
    base = {(c['o'], c['e']): c for c in legacy_asset['clusters']}
    identities, ids = set(), set()
    for c in asset['clusters']:
        if set(c) != {'o', 'e', 'lv'}:
            raise ValueError('Invalid cluster fields')
        key = (c['o'], c['e'])
        if key not in base or key in identities:
            raise ValueError('Duplicate or unrelated background centre')
        identities.add(key)
        if not c['lv'] or not set(c['lv']).issubset(base[key]['lv']):
            raise ValueError('Unrelated levels')
        if sum(m['n'] for modes in c['lv'].values() for m in modes) > base[key]['n']:
            raise ValueError('Total support exceeds background cluster')
        for level, modes in c['lv'].items():
            if not isinstance(modes, list) or not 1 <= len(modes) <= 16:
                raise ValueError('Invalid modes')
            if sum(m['n'] for m in modes) > base[key]['n']:
                raise ValueError('Support exceeds cluster')
            for m in modes:
                if set(m) != {'id', 'f', 'h', 'cx', 'cy', 'hy', 'n', 'spread', 'confidence'}:
                    raise ValueError('Invalid mode fields')
                if (not isinstance(m['id'], str) or not 1 <= len(m['id']) <= 80
                        or not re.fullmatch(rf'{c["o"]}-[0-9a-f]{{24}}-{level}-[0-9]+', m['id'])
                        or m['id'] in ids):
                    raise ValueError('Invalid/duplicate aggregate ID')
                ids.add(m['id'])
                if (m['f'] not in FRAMINGS or type(m['n']) is not int or m['n'] < 3
                        or m['hy'] is not None):
                    raise ValueError('Invalid mode support/framing')
                for name in ('h', 'cx', 'cy', 'confidence'):
                    v = m[name]
                    if (isinstance(v, bool) or not isinstance(v, (int, float))
                            or not math.isfinite(v) or not 0 <= v <= 1):
                        raise ValueError('Invalid unit value')
                if (m['h'] <= 0 or m['confidence'] <= 0 or isinstance(m['spread'], bool)
                        or not isinstance(m['spread'], (int, float))
                        or not math.isfinite(m['spread']) or m['spread'] < 0):
                    raise ValueError('Invalid mode spread/span')
    payload = (json.dumps(asset, separators=(',', ':'), allow_nan=False) + '\n').encode()
    if len(payload) >= 1_000_000:
        raise ValueError('Layout asset exceeds 1 MB')
    return payload
