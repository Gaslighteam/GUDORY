"""Phase A native rebuild + paired offline evaluation; aggregate outputs only.

All Sample objects, original-byte checks, queries and split membership stay in
memory. No per-photo cache, prediction table, embedding or identifier is written.
"""
import argparse
from collections import Counter
from contextlib import ExitStack
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import subprocess
import time
import tracemalloc

import numpy as np
from threadpoolctl import threadpool_limits

from background_clip import ClipEncoder, SelfieSegmenter
from import_photos import IMAGE_EXTENSIONS
from layout_prototypes import (Matcher, PrototypeConfig, SelectionConfig,
    build_prototypes, serialize_prototypes)
from pose_analysis import Composition, MediaPipePhotoAnalyzer
from recommendation_assets import Sample, build_asset, level_for, serialize_asset
from recommendation_pipeline import collect_samples


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def distribution(values, weights=None):
    x = np.array([v['cx'] for v in values])
    if not len(x):
        return {'count': 0}
    w = np.ones(len(x)) if weights is None else np.asarray(weights)
    region = {'left': x < .42, 'near_center': (x >= .42) & (x <= .58), 'right': x > .58}
    return {'count': len(x), 'mean_x': float(np.mean(x)), 'std_x': float(np.std(x)),
            'regions': {k: int(v.sum()) for k, v in region.items()},
            'percent': {k: float(100 * v.mean()) for k, v in region.items()},
            'weighted_percent': {k: float(100 * w[v].sum() / w.sum()) for k, v in region.items()},
            'x_histogram': np.histogram(x, bins=[0,.2,.42,.58,.8,1.00000001])[0].tolist()}


def source_distribution(rows):
    return distribution([{'cx': r.composition.cx} for r in rows], [r.weight for r in rows])


def asset_distribution(asset, experimental=False):
    values = [v for c in asset['clusters'] for value in c['lv'].values()
              for v in (value if experimental else [value])]
    return {'all': distribution(values), 'support_histogram': dict(sorted(Counter(v['n'] for v in values).items())),
            'minimum_support': min((v['n'] for v in values), default=None),
            'clusters': dict(Counter(c['o'] for c in asset['clusters'])),
            'by_orientation': {o: distribution([v for c in asset['clusters'] if c['o']==o[0]
                for value in c['lv'].values() for v in (value if experimental else [value])]) for o in ('portrait','landscape')}}


def split_samples(rows):
    # Deterministic grouping of identical embedding bytes; does not use target
    # coordinates. Near-duplicate scenes/people cannot be grouped without IDs.
    train, holdout = [], []
    for r in rows:
        key = hashlib.sha256(b'gudory-phase-a-v1' + r.orientation.encode() + r.embedding.tobytes()).digest()
        (holdout if int.from_bytes(key[:8], 'big') % 5 == 0 else train).append(r)
    return train, holdout


def pair_metrics(rows, legacy, experiment, contextual, selection=SelectionConfig()):
    old, new = Matcher(legacy), Matcher(experiment, True, selection)
    values = {'legacy': [], 'prototype': []}
    actual = {'legacy': [], 'prototype': []}
    repeat_errors = 0
    for r in rows:
        subject = {'cx':r.composition.cx, 'f':r.composition.f} if contextual else None
        for level in range(1,6):
            for name, matcher in [('legacy',old),('prototype',new)]:
                answer = matcher.recommend(r.embedding, level, r.orientation, subject)
                values[name].append((r.orientation, level, answer))
                if answer != matcher.recommend(r.embedding,level,r.orientation,subject):
                    repeat_errors += 1
                if level == level_for(r.composition.s,legacy['levels'][r.orientation]):
                    c = answer['composition']
                    same = c['f'] == r.composition.f
                    actual[name].append((same, abs(c['cx']-r.composition.cx),
                                         abs(c['cy']-r.composition.cy), abs(c['h']-r.composition.h)))
    results = {'repeat_mismatches':repeat_errors}
    for name, records in values.items():
        def summarize(subset):
            return distribution([a['composition'] for _,_,a in subset])
        agreement = actual[name]
        compatible = [a for a in agreement if a[0]]
        results[name] = {'all':summarize(records),
            'normal_matching':summarize([r for r in records if r[2]['status']!='legacy_fallback']),
            'fallback':summarize([r for r in records if r[2]['status']=='legacy_fallback']),
            'fallback_count':sum(a['status']=='legacy_fallback' for _,_,a in records),
            'nearest_level_count':sum(a['selected_level']!=lv for _,lv,a in records),
            'by_orientation':{o:summarize([r for r in records if r[0]==o]) for o in ('portrait','landscape')},
            'by_level':{str(lv):summarize([r for r in records if r[1]==lv]) for lv in range(1,6)},
            'observed_layout_consistency': {
                'actual_level_queries':len(agreement), 'same_framing_count':len(compatible),
                'same_framing_mean_abs_x_y_h':np.mean(np.array(compatible)[:,1:],axis=0).tolist() if compatible else None}}
    return results


def sensitivity(rows, legacy, experiment, selection=SelectionConfig()):
    # Equal spaced deterministic sample, capped per orientation to prevent the
    # portrait/landscape proportions from deciding which side gets exercised.
    chosen = []
    for o in ('portrait','landscape'):
        group = [r for r in rows if r.orientation==o]
        chosen.extend(group[::max(1,len(group)//100)][:100])
    results = {}
    for name, matcher in [('legacy',Matcher(legacy)),('prototype',Matcher(experiment,True,selection))]:
        rng = np.random.default_rng(17)  # identical perturbations for both methods
        diffs = {'embedding':[], 'subject':[]}
        changed = Counter()
        for r in chosen:
            subject = {'cx':r.composition.cx,'f':r.composition.f}
            noise = rng.normal(size=512); noise = noise/np.linalg.norm(noise)*.01
            for lv in (1,3,5):
                answer = matcher.recommend(r.embedding,lv,r.orientation,subject)
                for kind,e,s in [('embedding',r.embedding+noise,subject),
                                  ('subject',r.embedding,{**subject,'cx':min(1,r.composition.cx+.01)})]:
                    perturbed = matcher.recommend(e,lv,r.orientation,s)
                    dx = abs(answer['composition']['cx']-perturbed['composition']['cx'])
                    diffs[kind].append(dx)
                    changed[kind] += (answer['status']!=perturbed['status'] or
                                      answer['composition']['f']!=perturbed['composition']['f'])
        results[name] = {kind:{'queries':len(xs),'mean_abs_dx':float(np.mean(xs)),
            'max_abs_dx':float(max(xs,default=0)), 'dx_over_002':sum(x>.02 for x in xs),
            'dx_over_016':sum(x>.16 for x in xs),'status_or_framing_changes':changed[kind]}
            for kind,xs in diffs.items()}
    return results


def mode_counts(legacy, experiment):
    old = {(c['o'],c['e'],lv):v for c in legacy['clusters'] for lv,v in c['lv'].items()}
    result = Counter()
    for c in experiment['clusters']:
        for lv, values in c['lv'].items():
            result['supported_cells'] += 1
            result['multiple_prototype_cells'] += len(values)>1
            for f in ('chestUp','waistUp','kneeUp','fullBody'):
                cohort = [v for v in values if v['f']==f]
                if len(cohort)>1:
                    result['multiple_same_framing_cells'] += 1
                    xs = [v['cx'] for v in cohort]
                    if min(xs)<.42 and max(xs)>.58:
                        result['same_framing_left_and_right_cells'] += 1
                        previous = old.get((c['o'],c['e'],lv))
                        result['legacy_center_despite_left_right'] += bool(previous and .42<=previous['cx']<=.58)
    return dict(result)


def synthetic_cases(selection=SelectionConfig()):
    def row(x, axis=0, framing='fullBody', orientation='portrait'):
        e = np.zeros(512,dtype=np.float32); e[axis]=1
        return Sample(orientation,Composition(framing,.6,.1,x,.3),e,1)
    fixtures = {
        'two_modes_with_central_legacy_median':[row(.2)]*9+[row(.5)]+[row(.8)]*9,
        'single_meaningful_mode':[row(.28)]*19,
        'sparse_two_unsupported_modes':[row(.2)]*2+[row(.8)]*2,
        'similar_support':[row(.2)]*8+[row(.5)]+[row(.8)]*9,
        'similar_backgrounds_top_three_cancellation':[row(.2,0)]*20+[row(.8,1)]*20,
        'separate_framings':[row(.2,framing='fullBody')]*9+[row(.8,framing='waistUp')]*9}
    output = {}
    for name, rows in fixtures.items():
        rows += [row(.5,orientation='landscape')]*20
        legacy,_ = build_asset(rows); experiment = build_prototypes(rows,legacy)
        e = row(.5).embedding.copy()
        if name=='similar_backgrounds_top_three_cancellation':
            e[1]=1; e/=np.linalg.norm(e)
        item = {'prototypes':asset_distribution(experiment,True)['all']['count']}
        for label,x in [('no_subject',None),('center_subject',.5),('left_subject',.2),('right_subject',.8),
                        ('below_switch_boundary',.516),('above_switch_boundary',.526)]:
            subject = None if x is None else {'cx':x}
            item[label] = {method:matcher.recommend(e,1,'portrait',subject)
                          for method,matcher in [('legacy',Matcher(legacy)),('prototype',Matcher(experiment,True,selection))]}
        output[name] = item
    return output


def benchmark(rows, legacy, experiment, selection=SelectionConfig()):
    # CPython desktop selector benchmark, not Dart/Android latency or memory.
    output = {}
    for name, asset, experimental in [('legacy',legacy,False),('prototype',experiment,True)]:
        tracemalloc.start()
        matcher = Matcher(asset,experimental,selection)
        _, peak = tracemalloc.get_traced_memory(); tracemalloc.stop()
        elapsed = []
        for i in range(300):
            r = rows[i%len(rows)]
            start = time.perf_counter()
            matcher.recommend(r.embedding,i%5+1,r.orientation,{'cx':r.composition.cx,'f':r.composition.f})
            elapsed.append((time.perf_counter()-start)*1000)
        output[name] = {'median_ms':float(np.median(elapsed)), 'p95_ms':float(np.quantile(elapsed,.95)),
                        'index_construction_tracemalloc_peak_bytes':peak,
                        'decoded_center_array_bytes':sum(v.nbytes for _,v in matcher.groups.values())}
    return output


def run(args):
    prototype_config=PrototypeConfig(**json.loads(args.prototype_config))
    selection=SelectionConfig(**json.loads(args.selection_config))
    prototype_config.validate(); selection.validate()
    production = Path('app/assets/recommend.json')
    original_asset = production.read_bytes()
    original = json.loads(original_asset)
    before = {p:digest(p) for p in args.photos.rglob('*') if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS}
    # Protect existing worktree tracked files and nonignored local drafts.
    preserved = {}
    inventory = subprocess.check_output(['git','worktree','list','--porcelain'],text=True)
    for line in inventory.splitlines():
        if not line.startswith('worktree '): continue
        root = Path(line[9:])
        if root.resolve()==Path.cwd().resolve(): continue
        names = subprocess.check_output(['git','-C',str(root),'ls-files','--cached','--others','--exclude-standard'],text=True).splitlines()
        for name in names:
            path = root/name
            if path.is_file(): preserved[path]=digest(path)
    start = time.perf_counter()
    with ExitStack() as stack:
        pose=MediaPipePhotoAnalyzer(args.pose_model,args.person_model); stack.callback(pose.close)
        segmenter=SelfieSegmenter(args.segmentation_model); stack.callback(segmenter.close)
        samples,counts=collect_samples(args.photos,pose,segmenter,ClipEncoder(args.clip_model),3,1)
    native_seconds = time.perf_counter()-start
    print('Native extraction complete; computing frozen baseline.',flush=True)
    with threadpool_limits(limits=1):
        start = time.perf_counter(); full_legacy,_=build_asset(samples); legacy_seconds=time.perf_counter()-start
        reproduced = serialize_asset(full_legacy)==original_asset
        baseline=json.loads(Path('tools/phase_a_baseline.json').read_bytes())
        baseline['production_reproduced_by_native_rebuild']=reproduced
        baseline['input_counts']=dict(counts)
        baseline['accepted_source_compositions']={o:source_distribution([r for r in samples if r.orientation==o]) for o in ('portrait','landscape')}
        # Frozen BEFORE experimental aggregation; source/median/legacy-matching stages.
        baseline['exported_cluster_medians']=asset_distribution(full_legacy)
        # Reuse baseline as an experimental-schema stand-in only for paired legacy
        # evaluation would be invalid; compute legacy queries directly here.
        old=Matcher(full_legacy)
        answers=[old.recommend(r.embedding,lv,r.orientation) for r in samples for lv in range(1,6)]
        baseline['training_query_legacy_recommendations']={
            'all':distribution([a['composition'] for a in answers]),
            'matched':distribution([a['composition'] for a in answers if a['status']=='matched']),
            'fallback_count':sum(a['status']=='legacy_fallback' for a in answers)}
        del answers
        write_json(Path('tools/phase_a_baseline.json'),baseline)
        print('Baseline recorded. Building experimental aggregate, then repeating from reversed input.',flush=True)
        start=time.perf_counter(); full=build_prototypes(samples,full_legacy,prototype_config); prototype_seconds=time.perf_counter()-start
        payload=serialize_prototypes(full)
        assert payload==serialize_prototypes(build_prototypes(list(reversed(samples)),full_legacy,prototype_config))
        metrics={'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
            'prototype_config':asdict(prototype_config),'selection_config':asdict(selection),
            'full_prototype_asset':asset_distribution(full,True),'full_mode_preservation':mode_counts(full_legacy,full),
            'full_training_consistency':{label:pair_metrics(samples,full_legacy,full,context,selection)
                for label,context in [('background_only',False),('with_subject',True)]}}
        train,heldout=split_samples(samples)
        print(f'Held-out evaluation: train {len(train)}; holdout {len(heldout)}.',flush=True)
        train_legacy,_=build_asset(train)
        train_prototypes=build_prototypes(train,train_legacy,prototype_config)
        metrics['split']={'train_count':len(train),'holdout_count':len(heldout),
            'by_orientation':{o:{'train':sum(r.orientation==o for r in train),'holdout':sum(r.orientation==o for r in heldout)} for o in ('portrait','landscape')},
            'train_prototypes':asset_distribution(train_prototypes,True),'mode_preservation':mode_counts(train_legacy,train_prototypes)}
        metrics['holdout']={label:pair_metrics(heldout,train_legacy,train_prototypes,context,selection)
                           for label,context in [('background_only',False),('with_subject',True)]}
        metrics['sensitivity']=sensitivity(heldout,train_legacy,train_prototypes,selection)
        metrics['synthetic']=synthetic_cases(selection)
        metrics['prototype_asset_bytes']=len(payload)
        metrics['prototype_asset_sha256']=hashlib.sha256(payload).hexdigest()
        metrics['deterministic_aggregate_rebuild']=True
        metrics['performance']={'native_extraction_seconds':native_seconds,'legacy_aggregate_build_seconds':legacy_seconds,
            'prototype_aggregate_build_seconds_including_reclustering':prototype_seconds,
            'desktop_selector':benchmark(heldout,train_legacy,train_prototypes,selection)}
    assert production.read_bytes()==original_asset,'Production asset changed'
    assert all(digest(p)==value for p,value in before.items()),'Original image bytes changed'
    assert all(digest(p)==value for p,value in preserved.items()),'Existing worktree/draft changed'
    assert len(before)==counts['processed']
    metrics['safety']={'originals_unchanged':len(before),'existing_worktree_files_unchanged':len(preserved),
                       'production_asset_unchanged':True,'per_photo_records_written':0}
    Path('tools/layout_prototypes.experimental.json').write_bytes(payload)
    write_json(Path('tools/phase_a_metrics.json'),metrics)
    print('PASS: experimental deterministic aggregates, production/original/worktree integrity. Aggregate metrics written.',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('photos','pose-model','person-model','segmentation-model','clip-model'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--prototype-config',default='{}',help='JSON object overriding PrototypeConfig defaults')
    parser.add_argument('--selection-config',default='{}',help='JSON object overriding SelectionConfig defaults')
    args=parser.parse_args()
    run(args)


if __name__=='__main__':
    main()
