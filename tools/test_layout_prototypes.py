"""Phase A synthetic mode and privacy gates. No private photo data."""
import copy
import unittest
from types import SimpleNamespace
from layout_prototypes import PrototypeConfig, composition_modes, serialize_layout_asset


def row(x, y=.3, h=.6, f='fullBody', weight=1):
    return SimpleNamespace(composition=SimpleNamespace(cx=x, cy=y, h=h, f=f), weight=weight)


class ModeTests(unittest.TestCase):
    def test_same_background_left_right_stay_separate_not_averaged(self):
        result = composition_modes([row(.3)] * 5 + [row(.7)] * 5)
        self.assertEqual([m['cx'] for m in result], [.3, .7])
        self.assertEqual([m['n'] for m in result], [5, 5])

    def test_single_central_mode_does_not_invent_sides(self):
        result = composition_modes([row(.48 + i*.004) for i in range(12)])
        self.assertEqual(len(result), 1)
        self.assertTrue(.48 <= result[0]['cx'] <= .524)

    def test_continuous_distribution_not_forced_into_four(self):
        self.assertEqual(len(composition_modes([row(i/30) for i in range(31)])), 1)

    def test_both_sides_need_three_actual_rows_not_weight_mass(self):
        self.assertEqual(len(composition_modes([row(.3)]*6 + [row(.7, weight=100)]*2)), 1)
        self.assertEqual(composition_modes([row(.3, weight=100)]*2), [])

    def test_two_vertical_or_size_modes_without_horizontal_labels(self):
        for rows in ([row(.5,.2)]*3+[row(.5,.6)]*3,
                     [row(.5,h=.3)]*3+[row(.5,h=.8)]*3):
            self.assertEqual(len(composition_modes(rows)), 2)

    def test_order_invariant_and_source_weighted(self):
        rows = [row(.29), row(.30,weight=3), row(.31), row(.69), row(.70), row(.71)]
        self.assertEqual(composition_modes(rows), composition_modes(list(reversed(rows))))
        self.assertEqual(composition_modes(rows)[0]['cx'], .30)

    def test_gap_boundary_and_configurable_cap(self):
        rows = [row(.2)]*3+[row(.32)]*3+[row(.7)]*3
        self.assertEqual(len(composition_modes(rows)), 3)
        self.assertEqual(len(composition_modes(rows,PrototypeConfig(max_modes=2))), 2)

    def test_frame_mixing_and_nonfinite_data_rejected(self):
        for rows in ([row(.3)]*3+[row(.7,f='waistUp')]*3,
                     [row(float('nan'))]*3, [row(.5,weight=0)]*3):
            with self.assertRaises(ValueError): composition_modes(rows)

    def test_config_invalid_and_confidence_not_probability_claim(self):
        for kwargs in ({'min_support':2},{'max_modes':5},{'gaps':(.1,float('nan'),.2)}):
            with self.assertRaises(ValueError): PrototypeConfig(**kwargs)
        m=composition_modes([row(.5)]*3)[0]
        self.assertEqual(m['confidence'], .5)
        self.assertEqual(m['spread'], 0)


class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.base={'clusters':[{'o':'p','e':'aggregate-centre','n':6,'lv':{'3':{}}}]}
        modes=composition_modes([row(.3)]*3+[row(.7)]*3)
        for i,m in enumerate(modes):m['id']=f'p-{"a"*24}-3-{i}'
        self.asset={'version':1,'clusters':[{'o':'p','e':'aggregate-centre','lv':{'3':modes}}]}

    def test_valid_only_aggregate_fields_and_does_not_change_legacy(self):
        before=copy.deepcopy(self.base)
        data=serialize_layout_asset(self.asset,self.base)
        self.assertEqual(self.base,before)
        for token in [b'filename',b'embedding',b'photo_id',b'path']:
            self.assertNotIn(token,data)

    def test_unknown_fields_and_invalid_support_rejected(self):
        for mutate in [lambda a:a.update(photo_id='private'),
                       lambda a:a['clusters'][0]['lv']['3'][0].update(filename='private'),
                       lambda a:a['clusters'][0]['lv']['3'][0].update(n=2),
                       lambda a:a['clusters'][0]['lv']['3'][0].update(cx=float('inf')),
                       lambda a:a['clusters'][0].update(e='unrelated')]:
            a=copy.deepcopy(self.asset);mutate(a)
            with self.assertRaises(ValueError):serialize_layout_asset(a,self.base)

    def test_duplicate_ids_clusters_and_excess_support_rejected(self):
        for mutate in [lambda a:a['clusters'].append(copy.deepcopy(a['clusters'][0])),
                       lambda a:a['clusters'][0]['lv']['3'][1].update(id=a['clusters'][0]['lv']['3'][0]['id']),
                       lambda a:a['clusters'][0]['lv']['3'][0].update(n=20)]:
            a=copy.deepcopy(self.asset);mutate(a)
            with self.assertRaises(ValueError):serialize_layout_asset(a,self.base)

    def test_boolean_confidence_is_not_a_number(self):
        a=copy.deepcopy(self.asset);a['clusters'][0]['lv']['3'][0]['confidence']=True
        with self.assertRaises(ValueError):serialize_layout_asset(a,self.base)


class GenerationTests(unittest.TestCase):
    def test_end_to_end_aggregate_groups_keep_modes_and_legacy_unchanged(self):
        import numpy as np
        from pose_analysis import Composition
        from recommendation_assets import Sample, quantize_center
        from layout_prototypes import build_layout_asset
        vector=np.zeros(512);vector[0]=1
        rows=[]
        for orientation in ('portrait','landscape'):
            for x in [.29,.30,.31,.69,.70,.71]:
                rows.append(Sample(orientation,Composition('fullBody',.6,.2,x,.3),vector,1))
        base={'levels':{o:[.4,.3,.2,.1] for o in ('portrait','landscape')},
              'clusters':[{'o':o,'e':quantize_center(vector),'n':6,'lv':{'3':{}}} for o in ('p','l')]}
        before=copy.deepcopy(base)
        # These are the exact precomputed background assignments, not exported
        # photo IDs; grouping itself remains the existing deterministic KMeans.
        result=build_layout_asset(rows,base,background_groups={o:[list(range(6))] for o in ('portrait','landscape')})
        self.assertEqual(base,before)
        self.assertEqual(len(result['clusters']),2)
        for cluster in result['clusters']:
            self.assertEqual([m['cx'] for m in cluster['lv']['3']],[.30,.70])
        serialize_layout_asset(result,base)


if __name__=='__main__':unittest.main()
