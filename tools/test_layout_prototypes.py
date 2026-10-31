"""Deterministic public synthetic fixtures; no private training data."""
import copy
from dataclasses import replace
import json
import unittest

import numpy as np

from layout_prototypes import (Matcher, PrototypeConfig, SelectionConfig,
    build_prototypes, discover, serialize_prototypes, validate_prototypes)
from pose_analysis import Composition
from recommendation_assets import Sample, build_asset


def row(x=.5, orientation='portrait', framing='fullBody', weight=1, scale=.1, axis=0):
    e = np.zeros(512, dtype=np.float32)
    e[axis] = 1
    return Sample(orientation, Composition(framing, .6, scale, x, .3), e, weight)


def bimodal():
    # Single center sample makes the legacy median central, but cannot support
    # a private center prototype. Two genuinely supported modes remain.
    return [row(.2)] * 9 + [row(.5)] + [row(.8)] * 9


def assets(rows):
    other = [row(orientation='landscape')] * 20
    legacy, _ = build_asset(rows + other)
    return legacy, build_prototypes(rows + other, legacy)


class GenerationTests(unittest.TestCase):
    def test_two_modes_preserved_and_no_private_center_prototype(self):
        values = discover(bimodal(), 19)
        self.assertEqual(len(values), 2)
        np.testing.assert_allclose([v['cx'] for v in values], [.2, .8])
        self.assertEqual([v['n'] for v in values], [9, 9])
        self.assertEqual(sum(v['n'] for v in values), 18)

    def test_one_mode_and_continuum_not_forced_to_four(self):
        self.assertEqual(len(discover([row()] * 24, 24)), 1)
        values = discover([row(x) for x in np.linspace(.1, .9, 24)], 24)
        self.assertEqual(len(values), 1)

    def test_three_supported_patterns_can_be_discovered(self):
        values = discover([row(x) for x in (.2, .5, .8) for _ in range(9)], 27)
        self.assertEqual(len(values), 3)

    def test_off_center_patterns_are_not_fabricated_from_center_only_sources(self):
        values=discover([row(x) for x in np.linspace(.46,.54,15)],15)
        self.assertTrue(values)
        self.assertTrue(all(.46<=v['cx']<=.54 for v in values))

    def test_complexity_cap_does_not_average_known_separated_modes(self):
        self.assertEqual(discover(bimodal(),19,PrototypeConfig(max_leaves=1)),[])

    def test_sparse_data_and_source_weight_are_not_actual_support(self):
        self.assertEqual(discover([row(weight=3)] * 2, 6), [])
        values = discover([row(.2), row(.4), row(.8, weight=3)], 5,
                          PrototypeConfig(minimum_gap=100))
        self.assertAlmostEqual(values[0]['cx'], .6)
        self.assertEqual(values[0]['n'], 3)
        self.assertEqual(values[0]['w'], 5)
        self.assertGreater(values[0]['confidence'], 0)

    def test_framing_and_orientation_cohorts_never_mix(self):
        for extra in (row(framing='waistUp'), row(orientation='landscape')):
            with self.assertRaises(ValueError):
                discover([row()] * 4 + [extra], 5)
        legacy, experiment = assets([row(framing=f) for f in ('chestUp','waistUp','kneeUp','fullBody') for _ in range(6)])
        values = [v for c in experiment['clusters'] if c['o'] == 'p' for vs in c['lv'].values() for v in vs]
        self.assertEqual({v['f'] for v in values}, {'chestUp','waistUp','kneeUp','fullBody'})
        self.assertEqual(experiment['fallback'], legacy['fallback'])

    def test_joint_size_position_relationship_is_retained(self):
        left = [replace(row(.2), composition=Composition('fullBody', .7, .15, .2, .2))] * 9
        right = [replace(row(.8), composition=Composition('fullBody', .4, .08, .8, .5))] * 9
        values = discover(left + right, 18)
        self.assertEqual(len(values), 2)
        np.testing.assert_allclose([[v[k] for k in ('cx','cy','h','s')] for v in values],
                                   [[.2,.2,.7,.15],[.8,.5,.4,.08]])

    def test_exact_input_reordering_determinism_and_production_unchanged(self):
        rows = bimodal()
        legacy, first = assets(rows)
        before = json.dumps(legacy, sort_keys=True)
        second = build_prototypes(list(reversed(rows + [row(orientation='landscape')] * 20)), legacy)
        self.assertEqual(serialize_prototypes(first), serialize_prototypes(second))
        self.assertEqual(before, json.dumps(legacy, sort_keys=True))

    def test_all_levels_and_orientations_preserved(self):
        _, experiment = assets(bimodal())
        for o in ('portrait','landscape'):
            self.assertEqual(set(experiment['fallback'][o]), set('12345'))
            self.assertEqual(len(experiment['levels'][o]), 4)

    def test_schema_privacy_roundtrip_and_minimum_support(self):
        _, experiment = assets(bimodal())
        self.assertEqual(json.loads(serialize_prototypes(experiment)), experiment)
        for location in ('root','cluster','prototype'):
            bad = copy.deepcopy(experiment)
            target = bad if location == 'root' else bad['clusters'][0] if location == 'cluster' else next(iter(bad['clusters'][0]['lv'].values()))[0]
            target['photo_id'] = 'forbidden'
            with self.assertRaises((ValueError, TypeError)):
                validate_prototypes(bad)
        for field, value in [('n',2),('s',float('nan')),('w',10000),('cx',1.1),('hy',.4)]:
            bad = copy.deepcopy(experiment)
            next(iter(bad['clusters'][0]['lv'].values()))[0][field] = value
            with self.assertRaises(ValueError):
                validate_prototypes(bad)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.legacy, self.experiment = assets(bimodal())
        self.old = Matcher(self.legacy)
        self.new = Matcher(self.experiment, True)

    def test_center_median_versus_whole_prototype_selection(self):
        self.assertAlmostEqual(self.old.recommend(row().embedding, 1, 'portrait')['composition']['cx'], .5)
        answer = self.new.recommend(row().embedding, 1, 'portrait', {'cx': .5})
        self.assertEqual(answer['status'], 'prototype')
        self.assertTrue(any(abs(answer['composition']['cx']-x)<1e-9 for x in (.2,.8)))

    def test_subject_location_selects_supported_side(self):
        for x in (.2,.8):
            answer = self.new.recommend(row().embedding, 1, 'portrait', {'cx':x})
            self.assertAlmostEqual(answer['composition']['cx'], x)

    def test_small_noise_stability_and_determinism(self):
        e = row().embedding.copy()
        first = self.new.recommend(e,1,'portrait',{'cx':.2})
        e[2] = .001
        self.assertEqual(first, self.new.recommend(e,1,'portrait',{'cx':.201}))
        self.assertEqual(first, self.new.recommend(row().embedding,1,'portrait',{'cx':.2}))

    def test_equal_support_center_tie_deadband(self):
        a = self.new.recommend(row().embedding,1,'portrait',{'cx':.499})
        b = self.new.recommend(row().embedding,1,'portrait',{'cx':.501})
        self.assertEqual(a,b)

    def test_discrete_selector_still_has_a_switch_boundary(self):
        # Explicit limitation: deterministic tie handling is not temporal
        # hysteresis. A tiny move across its boundary can switch whole modes.
        a=self.new.recommend(row().embedding,1,'portrait',{'cx':.516})
        b=self.new.recommend(row().embedding,1,'portrait',{'cx':.526})
        self.assertGreater(abs(a['composition']['cx']-b['composition']['cx']),.5)

    def test_sparse_missing_inference_and_nonpositive_matching_fallback(self):
        empty = copy.deepcopy(self.experiment)
        empty['clusters'] = []
        for matcher, e in [(Matcher(empty,True),row().embedding),(self.new,None),(self.new,-row().embedding)]:
            result = matcher.recommend(e,3,'portrait')
            self.assertEqual(result['status'],'legacy_fallback')
            self.assertEqual(result['composition'],self.legacy['fallback']['portrait']['3'])

    def test_nearest_level_tie_and_orientation(self):
        answer = self.new.recommend(row().embedding,3,'portrait')
        self.assertEqual(answer['selected_level'],1)
        self.assertAlmostEqual(self.new.recommend(row().embedding,1,'landscape')['composition']['cx'],.5)

    def test_parameters_configurable_but_validated(self):
        matcher = Matcher(self.experiment,True,SelectionConfig(position=0))
        a=matcher.recommend(row().embedding,1,'portrait',{'cx':.2})
        b=matcher.recommend(row().embedding,1,'portrait',{'cx':.8})
        self.assertEqual(a,b)
        with self.assertRaises(ValueError):
            Matcher(self.experiment,True,SelectionConfig(position=-1))

    def test_legacy_top_three_framing_filter_without_backfill(self):
        a=copy.deepcopy(self.legacy)
        base=copy.deepcopy(a['clusters'][0])
        a['clusters']=[]
        for x,f in [(.2,'fullBody'),(.9,'waistUp'),(.8,'fullBody'),(.9,'fullBody')]:
            c=copy.deepcopy(base); c['o']='p'; c['n']=6
            c['lv']={'1':{'f':f,'h':.6,'cx':x,'cy':.3,'hy':None,'n':6}}
            a['clusters'].append(c)
        answer=Matcher(a).recommend(row().embedding,1,'portrait')
        self.assertAlmostEqual(answer['composition']['cx'],.5)
        self.assertEqual(answer['support'],12)


class EvaluationTests(unittest.TestCase):
    def test_identical_embedding_groups_do_not_cross_holdout_boundary(self):
        from evaluate_layout_prototypes import split_samples
        rows=[row(x,axis=i,orientation=o) for i in range(32)
              for o in ('portrait','landscape') for x in (.2,.8)]
        train,heldout=split_samples(rows)
        keys=lambda rs:{(r.orientation,r.embedding.tobytes()) for r in rs}
        self.assertTrue(train and heldout)
        self.assertFalse(keys(train)&keys(heldout))
        a,b=split_samples(list(reversed(rows)))
        self.assertEqual(keys(train),keys(a)); self.assertEqual(keys(heldout),keys(b))

    def test_paired_comparison_queries_all_five_levels_and_separates_fallback(self):
        from evaluate_layout_prototypes import pair_metrics
        legacy,experiment=assets(bimodal())
        metrics=pair_metrics([row(.2),row(.8)],legacy,experiment,True)
        self.assertEqual(metrics['repeat_mismatches'],0)
        for name in ('legacy','prototype'):
            self.assertEqual(metrics[name]['all']['count'],10)
            self.assertEqual(set(metrics[name]['by_level']),set('12345'))
            self.assertEqual(metrics[name]['fallback_count'],0)
            self.assertEqual(metrics[name]['nearest_level_count'],8)

    def test_explicit_failure_comparison_reports_fallback_frequency(self):
        from evaluate_layout_prototypes import pair_metrics
        legacy,experiment=assets(bimodal())
        experiment['clusters']=[]
        metrics=pair_metrics([row()],legacy,experiment,False)
        self.assertEqual(metrics['prototype']['fallback_count'],5)
        self.assertEqual(metrics['prototype']['fallback']['count'],5)
        self.assertEqual(metrics['prototype']['normal_matching']['count'],0)

    def test_fixed_synthetic_comparisons_include_mode_cancellation_and_sparsity(self):
        from evaluate_layout_prototypes import synthetic_cases
        cases=synthetic_cases()
        for key in ('two_modes_with_central_legacy_median','similar_backgrounds_top_three_cancellation'):
            case=cases[key]['center_subject']
            self.assertAlmostEqual(case['legacy']['composition']['cx'],.5)
            self.assertGreater(abs(case['prototype']['composition']['cx']-.5),.2)
        self.assertEqual(cases['sparse_two_unsupported_modes']['center_subject']['prototype']['status'],'legacy_fallback')
        self.assertAlmostEqual(cases['single_meaningful_mode']['center_subject']['prototype']['composition']['cx'],.28)

    def test_aggregate_metrics_and_mode_support_do_not_export_records(self):
        from evaluate_layout_prototypes import asset_distribution, mode_counts
        legacy,experiment=assets(bimodal())
        metrics=asset_distribution(experiment,True)
        self.assertGreaterEqual(metrics['minimum_support'],3)
        self.assertEqual(mode_counts(legacy,experiment)['legacy_center_despite_left_right'],1)
        text=json.dumps(metrics)
        self.assertFalse(any(k in text for k in ('photo_id','filename','http://','.jpg','embedding')))

    def test_sensitivity_uses_identical_perturbations_and_repeats_exactly(self):
        from evaluate_layout_prototypes import sensitivity
        legacy,experiment=assets(bimodal())
        a=sensitivity([row(.2),row(.8)],legacy,experiment)
        self.assertEqual(a,sensitivity([row(.2),row(.8)],legacy,experiment))
        for name in ('legacy','prototype'):
            self.assertEqual(a[name]['embedding']['queries'],6)
            self.assertEqual(a[name]['subject']['queries'],6)

    def test_invalid_source_measurements_and_config_fail_explicitly(self):
        for bad in (row(float('nan')),row(weight=0),row(scale=0)):
            with self.assertRaises(ValueError): discover([bad]*3,3)
        with self.assertRaises(ValueError): discover([row()]*3,2)
        with self.assertRaises(ValueError): discover([row()]*3,3,PrototypeConfig(minimum_gain=1))


if __name__ == '__main__':
    unittest.main()
