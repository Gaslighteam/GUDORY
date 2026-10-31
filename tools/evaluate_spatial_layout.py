"""Full Phase B native evaluation. Real-photo records/embeddings stay in RAM."""
import argparse
from collections import Counter
from contextlib import ExitStack
from dataclasses import asdict
import hashlib,json,math,time
from pathlib import Path
import numpy as np
from threadpoolctl import threadpool_limits

from background_clip import ClipEncoder,SelfieSegmenter,SegmentationFailure,mask_person,normalize_embedding
from import_photos import IMAGE_EXTENSIONS
from pose_analysis import MediaPipePhotoAnalyzer,center_crop_rect,load_photo
from recommendation_assets import Sample,build_asset,serialize_asset,level_for
from layout_prototypes import Matcher,SelectionConfig,build_prototypes,serialize_prototypes,_unit
from evaluate_layout_prototypes import distribution,split_samples
from spatial_features import extract_spatial,SPEC
from spatial_layout import (SpatialMatcher,SpatialScoring,SixSecondSelector,build_spatial,serialize_spatial,prototype_ids)


def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def collect(args):
    counts=Counter();rows=[];features={};reasons=Counter();times=[];drift=[];availability_flips=0
    with ExitStack() as stack:
        pose=MediaPipePhotoAnalyzer(args.pose_model,args.person_model);stack.callback(pose.close)
        segmenter=SelfieSegmenter(args.segmentation_model);stack.callback(segmenter.close)
        encoder=ClipEncoder(args.clip_model)
        for path in sorted(args.photos.rglob('*')):
            if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:continue
            counts['processed']+=1
            result=pose.analyze(path)
            if not result.accepted:
                counts['rejected/pose/'+result.reason]+=1;continue
            counts['pose_accepted']+=1
            try:
                with load_photo(path) as image:
                    shot=image.crop(center_crop_rect(image.width,image.height,result.crop=='portrait_3_4')) if result.crop in ('portrait_3_4','landscape_4_3') else image.copy()
                    with shot:
                        mask=segmenter(shot)
                        with mask_person(shot,mask) as filled:vector=normalize_embedding(encoder(filled))
                        rgb=np.asarray(shot.convert('RGB'));start=time.perf_counter()
                        f=extract_spatial(rgb,mask);times.append((time.perf_counter()-start)*1000)
                        small=rgb[:rgb.shape[0]//4*4:4,:rgb.shape[1]//4*4:4]
                        coarse=extract_spatial(small,mask)
                        availability_flips+=f.valid!=coarse.valid
                        if f.valid and coarse.valid:drift.append(float(np.mean(abs(np.array(f.grid)-coarse.grid))))
            except SegmentationFailure:
                counts['rejected/segmentation']+=1;continue
            except Exception:
                counts['rejected/embedding_or_image']+=1;continue
            weight=3 if path.relative_to(args.photos).parts[0]=='team' else 1
            r=Sample(result.orientation,result.composition,vector,weight)
            rows.append(r);features[id(r)]=f;counts['accepted']+=1
            counts['accepted/'+result.orientation]+=1
            reasons[f.reason]+=1
            if counts['processed']%100==0:print(f"Processed {counts['processed']}; CLIP accepted {len(rows)}",flush=True)
    return rows,features,dict(counts),{'reasons':dict(reasons),'extraction_median_ms':float(np.median(times)),
        'extraction_p95_ms':float(np.quantile(times,.95)),
        'rgb_stride4_stress':{'both_available':len(drift),'availability_flips':availability_flips,
            'mean_grid_mae':float(np.mean(drift)) if drift else None,'p95_grid_mae':float(np.quantile(drift,.95)) if drift else None}}


def top_one(matcher,e,level,o):
    cs,matrix=matcher.groups[o];available={int(k) for c in cs for k in c['lv']}
    if not available:return matcher.fallback(o,level)
    selected=min(available,key=lambda lv:(abs(lv-level),lv));scores=matrix@_unit(e)
    indices=[i for i,c in enumerate(cs) if str(selected) in c['lv'] and scores[i]>0]
    if not indices:return matcher.fallback(o,level)
    i=min(indices,key=lambda i:(-scores[i],i));p=cs[i]['lv'][str(selected)]
    return {'composition':{k:p[k] for k in ('f','h','cx','cy','hy')},'status':'matched','support':p['n'],'selected_level':selected}


def compare(rows,features,legacy,phase_a,spatial,config):
    old=Matcher(legacy); a=Matcher(phase_a,True); b=SpatialMatcher(phase_a,spatial,config)
    zero=SpatialMatcher(phase_a,spatial,SpatialScoring(alpha=config.alpha,beta=0,gamma=config.gamma))
    methods=('legacy_top3','legacy_top1','phase_a_context','phase_a_no_position','phase_b')
    outputs={k:[] for k in methods};utilization={k:set() for k in methods};errors={k:[] for k in methods}
    availability=Counter();paired=Counter();adjustment=[];repeat_mismatches=0
    for r in rows:
        f=features[id(r)];availability['queries_with_spatial' if f.valid else 'queries_without_spatial']+=5
        for lv in range(1,6):
            answers={'legacy_top3':old.recommend(r.embedding,lv,r.orientation),
                'legacy_top1':top_one(old,r.embedding,lv,r.orientation),
                'phase_a_context':a.recommend(r.embedding,lv,r.orientation,{'cx':r.composition.cx,'f':r.composition.f}),
                'phase_a_no_position':zero.recommend(r.embedding,lv,r.orientation,f),
                'phase_b':b.recommend(r.embedding,lv,r.orientation,f)}
            if f.valid:
                pool=b.rank(r.embedding,lv,r.orientation,f)
                availability['coverage_guard']+=bool(pool and pool[0].get('coverage_guard',False))
                supported=sum(c['id'] in b.records for c in pool)
                availability['pool_complete' if supported==len(pool) and pool else 'pool_partial' if supported else 'pool_without_stats']+=1
                old_id=answers['phase_a_no_position'].get('candidate_id')
                new_id=answers['phase_b'].get('candidate_id')
                if old_id in b.records and new_id not in b.records:
                    availability['base_supported_b_selected_unsupported']+=1
            repeat_mismatches+=answers['phase_b']!=b.recommend(r.embedding,lv,r.orientation,f)
            for name,answer in answers.items():
                c=answer['composition'];outputs[name].append((r.orientation,lv,answer))
                if name.startswith('phase_') and answer['status']=='prototype':
                    utilization[name].add(tuple(c[k] for k in ('f','h','cx','cy','hy')))
            availability['b_spatial_selected']+=answers['phase_b'].get('spatial_used',False)
            if not f.valid or lv!=level_for(r.composition.s,legacy['levels'][r.orientation]):continue
            observed=f.relation(r.composition.cx,r.composition.cy);current={}
            for name,answer in answers.items():
                c=answer['composition']
                error=float(np.mean(abs(f.relation(c['cx'],c['cy'])-observed)))
                errors[name].append(error);current[name]=error
            for base in ('phase_a_context','phase_a_no_position'):
                delta=current['phase_b']-current[base]
                paired[base+'/better' if delta<-.005 else base+'/worse' if delta>.005 else base+'/tie']+=1
            answer=answers['phase_b'];identity=answer.get('candidate_id');record=spatial['records'].get(identity)
            if record:
                x=float(np.clip(f.centroid[0]+2*record['rel'][0]-1,0,1))
                c=answer['composition'];distance=abs(x-c['cx'])
                # Coordinate modification is an offline rejected counterfactual,
                # never a generated B candidate or operational target.
                adjusted_error=float(np.mean(abs(f.relation(x,c['cy'])-observed)))
                adjustment.append((distance,adjusted_error))
    result={'feature_availability':dict(availability),'repeat_mismatches':repeat_mismatches,
            'paired_source_relationship_proxy':dict(paired),'methods':{}}
    for name,records in outputs.items():
        result['methods'][name]={'all':distribution([a['composition'] for _,_,a in records]),
            'by_orientation':{o:distribution([a['composition'] for q,_,a in records if q==o]) for o in ('portrait','landscape')},
            'level2':distribution([a['composition'] for _,lv,a in records if lv==2]),
            'legacy_fallback_count':sum(a['status']=='legacy_fallback' for _,_,a in records),
            'prototype_tuples_used':len(utilization[name]) if name.startswith('phase_') else None,
            'source_relationship_proxy_count':len(errors[name]),
            'source_relationship_proxy_mae':float(np.mean(errors[name])) if errors[name] else None}
    result['coordinate_shift_counterfactual']={'conditional_cases':len(adjustment),
        'mean_abs_x_shift':float(np.mean([x for x,_ in adjustment])) if adjustment else None,
        'off_original_prototype_count':sum(x>1e-9 for x,_ in adjustment),
        'conditional_source_relationship_mae':float(np.mean([e for _,e in adjustment])) if adjustment else None,
        'status':'rejected for operational use; unsupported moving coordinates'}
    return result


def stability_replay(rows,features,matcher):
    result={}
    for margin in (.04,.08,.12):
        selector=SixSecondSelector(margin);switches=violations=0
        for i,r in enumerate(rows[:200]):
            old=selector.selected;at=selector.at;context=selector.context
            ctx=(3,r.orientation,'recommend')
            candidates=matcher.rank(r.embedding,3,r.orientation,features[id(r)])
            incumbent=matcher.rescore_incumbent(r.embedding,r.orientation,features[id(r)],candidates,
                selector.selected['id'] if selector.selected else None)
            if incumbent:candidates.append(incumbent)
            # Transient missing-feature analysis retains the frozen snapshot.
            if not features[id(r)].valid and matcher.records:candidates=[]
            selected=selector.update(ctx,candidates,float(i))
            if old and selected and context==ctx and old['id']!=selected['id']:
                switches+=1;violations+=i-at<6
        result[str(margin)]={'synthetic_clock_heldout_photo_replay':min(200,len(rows)),
                            'switches':switches,'switches_before_six_seconds':violations}
    return result


def run(args):
    production=Path('app/assets/recommend.json');phase_a_path=Path('tools/layout_prototypes.experimental.json')
    original=production.read_bytes(); a_bytes=phase_a_path.read_bytes();a=json.loads(a_bytes)
    before={p:sha(p) for p in args.photos.rglob('*') if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS}
    rows,features,counts,diagnostics=collect(args)
    assert len(rows)==3233 and counts['processed']==5603,'Full frozen dataset not reproduced'
    print('Native spatial extraction complete. Reconstructing frozen Phase A and holdout.',flush=True)
    with threadpool_limits(limits=1):
        legacy,_=build_asset(rows)
        assert serialize_asset(legacy)==original,'Legacy reconstruction changed'
        rebuilt=build_prototypes(rows,legacy)
        assert serialize_prototypes(rebuilt)==a_bytes,'414-prototype Phase A changed'
        spatial=build_spatial(rows,a,features);payload=serialize_spatial(spatial,a)
        assert payload==serialize_spatial(build_spatial(list(reversed(rows)),a,features),a)
        train,holdout=split_samples(rows)
        old_train,_=build_asset(train);a_train=build_prototypes(train,old_train);b_train=build_spatial(train,a_train,features)
        config=SpatialScoring(beta=args.beta)
        comparison=compare(holdout,features,old_train,a_train,b_train,config)
        result={'schema':'gudory-phase-b-aggregate-evaluation','version':1,'base_commit':'5f89582b7deef5def4052a521c0233922c80fdfc',
            'counts':counts,'spatial_diagnostics':diagnostics,'feature_spec':SPEC,'scoring':asdict(config),
            'full':{'phase_a_prototypes':len(prototype_ids(a)),'spatial_prototypes':len(spatial['records']),
                'spatial_support_histogram':dict(Counter(r['n'] for r in spatial['records'].values())),
                'asset_bytes':len(payload),'asset_sha256':hashlib.sha256(payload).hexdigest()},
            'split':{'train':len(train),'holdout':len(holdout),'train_spatial_prototypes':len(b_train['records']),
                'availability_by_orientation':{o:sum(features[id(r)].valid for r in holdout if r.orientation==o) for o in ('portrait','landscape')}},
            'holdout':comparison,'stability':stability_replay(holdout,features,SpatialMatcher(a_train,b_train,config)),
            'evidence_limits':['source-relative layout proxy is not aesthetics or semantic object preservation',
                'static photograph replay is not real camera video','native Camera/ML Kit parity and device latency unverified']}
        # Exploratory diagnostics, not held-out weight tuning or a selected optimum.
        result['exploratory_beta_sweep']={str(beta):compare(holdout,features,old_train,a_train,b_train,
            SpatialScoring(beta=beta))['methods']['phase_b'] for beta in (.2,.8,2.)}
        result['training_consistency']=compare(train,features,old_train,a_train,b_train,config)
    assert production.read_bytes()==original and phase_a_path.read_bytes()==a_bytes
    assert all(sha(p)==h for p,h in before.items()),'Original photos changed'
    result['safety']={'original_photos_unchanged':len(before),'production_unchanged':True,'phase_a_unchanged':True,'per_photo_records_written':0}
    Path('tools/layout_spatial.experimental.json').write_bytes(payload)
    Path('tools/phase_b_metrics.json').write_text(json.dumps(result,sort_keys=True,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print('PASS: frozen dataset/Phase A reproduced, spatial sidecar deterministic, originals unchanged. Aggregate results saved.',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('photos','pose-model','person-model','segmentation-model','clip-model'):parser.add_argument('--'+key,type=Path,required=True)
    parser.add_argument('--beta',type=float,default=.8)
    run(parser.parse_args())


if __name__=='__main__':main()
