"""Public synthetic Phase B fixtures; no private photo identifiers."""
from dataclasses import replace
import copy,json
from pathlib import Path
import unittest
import numpy as np

from spatial_features import extract_spatial,SpatialFeature,SPEC
from spatial_layout import (SpatialMatcher,SpatialScoring,SixSecondSelector,build_spatial,
                            prototype_ids,serialize_spatial,validate_spatial)
from layout_prototypes import Matcher,SelectionConfig,build_prototypes
from pose_analysis import Composition
from recommendation_assets import Sample,build_asset
from recommendation_assets import quantize_center
from layout_prototypes import serialize_prototypes
import hashlib


def pattern(width=96,height=96,side='right',mask_x=48,person_value=255):
    gx=np.arange(width)*96//width; gy=np.arange(height)*96//height
    xx,yy=np.meshgrid(gx,gy)
    structured=(xx>=64) if side=='right' else (xx<32) if side=='left' else np.zeros_like(xx,dtype=bool)
    luma=np.where(structured,np.where((xx//4+yy//4)%2,220,30),100).astype(np.uint8)
    rgb=np.repeat(luma[:,:,None],3,axis=2)
    mask=((abs(xx-mask_x)<5)&(yy>=38)&(yy<68)).astype(float)
    rgb[mask>.5]=[person_value,0,0]
    return rgb,mask


def toy(complex_side=False):
    rows=[]; fs={}
    for o in ('portrait','landscape'):
        for x,side in [(.2,'left' if complex_side else 'right'),(.8,'right' if complex_side else 'left')]:
            for _ in range(9):
                e=np.zeros(512,dtype=np.float32);e[0]=1
                r=Sample(o,Composition('fullBody',.6,.1,x,.3),e,1)
                rows.append(r); fs[id(r)]=extract_spatial(*pattern(side=side))
    legacy,_=build_asset(rows); a=build_prototypes(rows,legacy); b=build_spatial(rows,a,fs)
    return rows,fs,a,b


def weak_clip_fixture():
    _,_,a,_=toy()
    weak=copy.deepcopy(a['clusters'][0]);vector=np.zeros(512);vector[:2]=(.1,np.sqrt(.99))
    weak['e']=quantize_center(vector);a['clusters'].insert(1,weak)
    b={'schema':'gudory-spatial-layout','version':2,'feature_spec':SPEC,
       'phase_a_sha256':hashlib.sha256(serialize_prototypes(a)).hexdigest(),'records':{}}
    query=extract_spatial(*pattern(side='right'))
    for identity,p in prototype_ids(a).items():
        f=query if identity.startswith('p-1-') else extract_spatial(*pattern(side='left'))
        b['records'][identity]={'n':p['n'],'w':p['w'],'confidence':1.,'grid':list(f.grid),'grid_var':[0.]*18,
            'rel':f.relation(p['cx'],p['cy']).tolist(),'rel_var':[0.]*4,'placement_var':[0.]*4}
    return a,b,query


class FeatureTests(unittest.TestCase):
    def test_mask_boundary_and_person_color_not_background_edges(self):
        a=extract_spatial(*pattern(side='none',person_value=255))
        self.assertFalse(a.valid);self.assertEqual(a.reason,'uninformative')
        self.assertEqual(extract_spatial(*pattern(person_value=20)),extract_spatial(*pattern(person_value=250)))

    def test_resolution_invariance_on_replicated_pixels(self):
        a=extract_spatial(*pattern())
        self.assertTrue(a.valid)
        for n in (192,288,384):
            b=extract_spatial(*pattern(n,n))
            np.testing.assert_allclose(a.grid,b.grid,atol=1e-12)
            self.assertAlmostEqual(a.confidence,b.confidence)

    def test_mask_translation_on_flat_region_does_not_create_structure(self):
        a=extract_spatial(*pattern(mask_x=45));b=extract_spatial(*pattern(mask_x=51))
        np.testing.assert_allclose(a.grid,b.grid,atol=1e-12)
        np.testing.assert_allclose(a.centroid,b.centroid,atol=1e-12)

    def test_coverage_and_invalid_masks_fail_closed(self):
        rgb,mask=pattern()
        for m in (None,[[float('nan')]],np.ones((96,96)),np.full((2,2),2.)):
            self.assertFalse(extract_spatial(rgb,m).valid)

    def test_complexity_centroid_direction_and_relation(self):
        right=extract_spatial(*pattern(side='right'));left=extract_spatial(*pattern(side='left'))
        self.assertGreater(right.centroid[0],.7);self.assertLess(left.centroid[0],.3)
        self.assertGreater(right.asymmetry[0],0)
        self.assertLess(right.relation(.2,.3)[0],right.relation(.8,.3)[0])
        self.assertFalse(replace(right,grid=(float('nan'),)*18).valid)


class AggregateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.rows,cls.features,cls.a,cls.b=toy()

    def test_replay_and_minimum_private_support(self):
        self.assertEqual(len(prototype_ids(self.a)),4)
        self.assertEqual(len(self.b['records']),4)
        sparse={k:SpatialFeature() for k in self.features}
        for r in self.rows[:2]: sparse[id(r)]=self.features[id(r)]
        self.assertEqual(build_spatial(self.rows,self.a,sparse)['records'],{})

    def test_deterministic_rebuild_and_serialization(self):
        reverse=build_spatial(list(reversed(self.rows)),self.a,self.features)
        self.assertEqual(serialize_spatial(self.b,self.a),serialize_spatial(reverse,self.a))
        self.assertEqual(json.loads(serialize_spatial(self.b,self.a)),self.b)

    def test_privacy_schema_and_actual_support(self):
        for target in ('root','record'):
            b=copy.deepcopy(self.b)
            (b if target=='root' else next(iter(b['records'].values())))['photo_id']='forbidden'
            with self.assertRaises(ValueError):validate_spatial(b,self.a)
        for field,value in [('n',2),('grid',[float('nan')]*18),('confidence',2),('w',1000)]:
            b=copy.deepcopy(self.b);next(iter(b['records'].values()))[field]=value
            with self.assertRaises(ValueError):validate_spatial(b,self.a)

    def test_beta_zero_exact_phase_a_under_equivalent_settings(self):
        old=Matcher(self.a,True,SelectionConfig(position=0,framing=0))
        new=SpatialMatcher(self.a,self.b,SpatialScoring(beta=0))
        for o in ('portrait','landscape'):
            for lv in range(1,6):
                for f in (None,extract_spatial(*pattern())):
                    a=old.recommend(self.rows[0].embedding,lv,o)
                    b=new.recommend(self.rows[0].embedding,lv,o,f)
                    self.assertEqual(a,{k:b[k] for k in a})

    def test_missing_invalid_and_older_assets_fall_back_to_phase_a(self):
        old=Matcher(self.a,True,SelectionConfig(position=0,framing=0))
        expected=old.recommend(self.rows[0].embedding,1,'portrait')
        for asset in (None,{},self.a,{**self.b,'version':99}):
            b=SpatialMatcher(self.a,asset).recommend(self.rows[0].embedding,1,'portrait',extract_spatial(*pattern()))
            self.assertEqual(expected,{k:b[k] for k in expected})

    def test_relations_choose_opposite_sides_for_swapped_structure(self):
        matcher=SpatialMatcher(self.a,self.b,SpatialScoring(beta=5))
        for side,x in [('right',.2),('left',.8)]:
            answer=matcher.recommend(self.rows[0].embedding,1,'portrait',extract_spatial(*pattern(side=side)))
            self.assertAlmostEqual(answer['composition']['cx'],x)
            self.assertTrue(answer['spatial_used'])

    def test_no_hard_low_complexity_rule(self):
        rows,fs,a,b=toy(complex_side=True)
        matcher=SpatialMatcher(a,b,SpatialScoring(beta=5))
        for side,x in [('right',.8),('left',.2)]:
            answer=matcher.recommend(rows[0].embedding,1,'portrait',extract_spatial(*pattern(side=side)))
            self.assertAlmostEqual(answer['composition']['cx'],x)

    def test_normalized_scores_and_immutable_supported_coordinates(self):
        matcher=SpatialMatcher(self.a,self.b)
        known=prototype_ids(self.a)
        for c in matcher.rank(self.rows[0].embedding,1,'portrait',extract_spatial(*pattern())):
            self.assertTrue(0<=c['score']<=1)
            self.assertEqual(c['prototype'],known[c['id']])
        self.assertEqual(matcher.recommend(None,1,'portrait')['status'],'legacy_fallback')

    def test_spatial_score_cannot_promote_a_weak_clip_cluster(self):
        a,b,f=weak_clip_fixture();matcher=SpatialMatcher(a,b,SpatialScoring(beta=100))
        ranked=matcher.rank(self.rows[0].embedding,1,'portrait',f)
        self.assertTrue(ranked[0]['id'].startswith('p-0-'))
        self.assertTrue(all(not c['can_challenge'] for c in ranked if c['id'].startswith('p-1-')))

    def test_missing_stats_cannot_win_from_normalization_advantage(self):
        partial=copy.deepcopy(self.b);partial['records'].pop('p-0-1-1')
        matcher=SpatialMatcher(self.a,partial,SpatialScoring(beta=5))
        f=extract_spatial(*pattern(side='left'))
        actual=matcher.rank(self.rows[0].embedding,1,'portrait',f)
        expected=matcher.rank(self.rows[0].embedding,1,'portrait',None)
        self.assertEqual(actual[0]['id'],expected[0]['id'])
        self.assertTrue(actual[0]['coverage_guard'])
        self.assertFalse(any(c['spatial_weight'] for c in actual))


    def test_incumbent_outside_retrieval_pool_gets_current_score(self):
        matcher=SpatialMatcher(self.a,self.b)
        identity='p-0-1-0'
        rescore=matcher.rescore_incumbent(self.rows[0].embedding,'portrait',None,[],identity)
        self.assertIsNotNone(rescore);self.assertFalse(rescore['can_challenge'])
        self.assertGreater(rescore['score'],.8)
        self.assertEqual(rescore['id'],identity)


class StabilityTests(unittest.TestCase):
    def test_six_seconds_margin_same_id_failure_and_context(self):
        selector=SixSecondSelector();ctx=(3,'portrait','recommend')
        a={'id':'a','score':.5,'prototype':{'cx':.2}}
        b={'id':'b','score':.9,'prototype':{'cx':.8}}
        self.assertEqual(selector.update(ctx,[a],0)['id'],'a')
        self.assertEqual(selector.update(ctx,[a,b],5.9)['id'],'a')
        self.assertEqual(selector.update(ctx,[a,b],6)['id'],'b')
        selector.update(ctx,[{**b,'prototype':{'cx':.7}}],7)
        self.assertEqual(selector.at,6);self.assertEqual(selector.selected['prototype']['cx'],.8)
        self.assertEqual(selector.update(ctx,[],20)['id'],'b')
        self.assertEqual(selector.update((2,'portrait','recommend'),[a],21)['id'],'a')
        self.assertIsNone(selector.update((2,'portrait','custom'),[b],22))

    def test_switch_threshold_rescores_incumbent(self):
        s=SixSecondSelector();ctx=(1,'landscape','recommend')
        s.update(ctx,[{'id':'a','score':.9}],0)
        self.assertEqual(s.update(ctx,[{'id':'a','score':.5},{'id':'b','score':.579}],6)['id'],'a')
        self.assertEqual(s.update(ctx,[{'id':'a','score':.5},{'id':'b','score':.58}],7)['id'],'b')


if __name__=='__main__':unittest.main()
