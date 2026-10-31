"""Phase B aggregate relationships and offline ranking. No camera integration."""
import copy
from dataclasses import dataclass
import hashlib
import json
import math
import numpy as np

from layout_prototypes import (Matcher,PrototypeConfig,SelectionConfig,_split,_unit,features,
                               serialize_prototypes,validate_prototypes)
from recommendation_assets import _key,deterministic_clusters,level_for,quantize_center
from spatial_features import SPEC,SpatialFeature


def prototype_ids(asset):
    return {f"{c['o']}-{ci}-{level}-{pi}":v for ci,c in enumerate(asset['clusters'])
            for level,values in c['lv'].items() for pi,v in enumerate(values)}


def cohorts(rows,config):
    """Replay the frozen Phase A partition, returning memory-only membership."""
    rows=sorted(rows,key=_key)
    if not rows: return []
    x=features(rows,config); w=np.array([r.weight for r in rows]); leaves=[list(range(len(rows)))]; cursor=0
    while cursor<len(leaves):
        g=leaves[cursor]; split=_split(x[g],w[g],config)
        if split is None: cursor+=1; continue
        children=[[g[i] for i in child] for child in split]
        children=[child for child in children if len(child)>=3]
        if len(leaves)-1+len(children)>config.max_leaves: children=[]
        leaves[cursor:cursor+1]=children
    return [[rows[i] for i in g] for g in leaves if len(g)>=3]


def _centroid_key(group):
    w=[r.weight for r in group]
    return tuple(float(np.average([getattr(r.composition,k) for r in group],weights=w)) for k in ('cx','cy','s','h'))


def build_spatial(samples,phase_a,spatial):
    validate_prototypes(phase_a)
    config=PrototypeConfig(**phase_a['config'])
    output={'schema':'gudory-spatial-layout','version':2,'feature_spec':SPEC,
            'phase_a_sha256':hashlib.sha256(serialize_prototypes(phase_a)).hexdigest(),'records':{}}
    parents={(c['o'],c['e']):(ci,c) for ci,c in enumerate(phase_a['clusters'])}
    visited=set()
    for o in ('portrait','landscape'):
        rows=sorted([r for r in samples if r.orientation==o],key=_key)
        for indices in deterministic_clusters(rows):
            members=[rows[i] for i in indices]
            center=quantize_center(np.average(np.stack([r.embedding for r in members]),axis=0,weights=[r.weight for r in members]))
            parent=parents.get((o[0],center))
            if parent is None: continue
            ci,c=parent
            for level,prototypes in c['lv'].items():
                subset=[r for r in members if level_for(r.composition.s,phase_a['levels'][o])==int(level)]
                groups=[]
                for f in ('chestUp','waistUp','kneeUp','fullBody'):
                    groups.extend(sorted(cohorts([r for r in subset if r.composition.f==f],config),key=_centroid_key))
                assert len(groups)==len(prototypes),'Phase A cohort replay mismatch'
                for pi,(group,proto) in enumerate(zip(groups,prototypes)):
                    assert group[0].composition.f==proto['f'] and len(group)==proto['n']
                    assert np.allclose(_centroid_key(group),[proto[k] for k in ('cx','cy','s','h')],atol=1e-12,rtol=0)
                    identity=f"{c['o']}-{ci}-{level}-{pi}"; visited.add(identity)
                    good=[r for r in group if spatial[id(r)].valid]
                    if len(good)<3: continue
                    weights=[r.weight for r in good]
                    def moments(values):
                        x=np.asarray(values); mean=np.average(x,axis=0,weights=weights)
                        return mean.tolist(),np.average((x-mean)**2,axis=0,weights=weights).tolist()
                    grid,gvar=moments([spatial[id(r)].grid for r in good])
                    rel,rvar=moments([spatial[id(r)].relation(r.composition.cx,r.composition.cy) for r in good])
                    _,pvar=moments([[getattr(r.composition,k) for k in ('cx','cy','h','s')] for r in good])
                    confidence=float(np.average([spatial[id(r)].confidence for r in good],weights=weights))
                    confidence*=len(good)/(len(good)+6)/(1+5*float(np.mean(pvar)))
                    output['records'][identity]={'n':len(good),'w':sum(weights),'confidence':confidence,
                        'grid':grid,'grid_var':gvar,'rel':rel,'rel_var':rvar,'placement_var':pvar}
    assert visited==set(prototype_ids(phase_a)),'Missing Phase A cohorts'
    validate_spatial(output,phase_a)
    return output


def validate_spatial(asset,phase_a):
    if (set(asset)!={'schema','version','feature_spec','phase_a_sha256','records'}
            or asset['schema']!='gudory-spatial-layout' or type(asset['version']) is not int or asset['version']!=2
            or asset['feature_spec']!=SPEC
            or asset['phase_a_sha256']!=hashlib.sha256(serialize_prototypes(phase_a)).hexdigest()
            or not isinstance(asset['records'],dict)):
        raise ValueError('Invalid spatial schema or Phase A link')
    known=prototype_ids(phase_a)
    for identity,r in asset['records'].items():
        if identity not in known or set(r)!={'n','w','confidence','grid','grid_var','rel','rel_var','placement_var'}:
            raise ValueError('Unexpected/private spatial record')
        if type(r['n']) is not int or not 3<=r['n']<=known[identity]['n']:
            raise ValueError('Insufficient/excess support')
        if (not isinstance(r['w'],(int,float)) or isinstance(r['w'],bool) or not math.isfinite(r['w'])
                or not r['n']<=r['w']<=3*r['n'] or isinstance(r['confidence'],bool)
                or not isinstance(r['confidence'],(int,float)) or not 0<r['confidence']<=1):
            raise ValueError('Invalid spatial support')
        for k,n in [('grid',18),('grid_var',18),('rel',4),('rel_var',4),('placement_var',4)]:
            a=r[k]
            if not isinstance(a,list) or len(a)!=n or any(isinstance(v,bool) or not isinstance(v,(int,float))
                    or not math.isfinite(v) or not 0<=v<=1 for v in a):
                raise ValueError('Invalid aggregate spatial measurements')
    if len(json.dumps(asset,separators=(',',':'),allow_nan=False).encode())>=1_000_000:
        raise ValueError('Spatial sidecar exceeds 1 MB')


def serialize_spatial(asset,phase_a):
    validate_spatial(asset,phase_a)
    return (json.dumps(asset,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()


@dataclass(frozen=True)
class SpatialScoring:
    alpha: float=1.
    beta: float=.8
    gamma: float=.08
    clip_floor: float=.15
    clip_margin: float=.08

    def validate(self):
        if (not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) and v>=0
                    for v in vars(self).values()) or self.alpha<=0 or self.clip_floor>1 or self.clip_margin>2):
            raise ValueError('Invalid spatial scoring configuration')


def compatibility(feature,prototype,stats):
    relation=feature.relation(prototype['cx'],prototype['cy'])
    gd=float(np.mean((np.asarray(feature.grid)-stats['grid'])**2/(np.asarray(stats['grid_var'])+.0025)))
    rd=float(np.mean((relation-stats['rel'])**2/(np.asarray(stats['rel_var'])+.0025)))
    return math.exp(-min(50,.3*gd+.7*rd))


class SpatialMatcher:
    def __init__(self,phase_a,spatial=None,config=SpatialScoring()):
        config.validate(); self.a=phase_a; self.config=config
        self.base=Matcher(phase_a,True,SelectionConfig(background=config.alpha,support=config.gamma,framing=0,position=0))
        self.indices={(c['o'],c['e']):i for i,c in enumerate(phase_a['clusters'])}
        self.prototypes=prototype_ids(phase_a)
        self.centers={self.indices[(c['o'],c['e'])]:vector for cs,matrix in self.base.groups.values() for c,vector in zip(cs,matrix)}
        self.records={}
        try:
            validate_spatial(spatial,phase_a); self.records=spatial['records']
        except (TypeError,ValueError,KeyError): pass

    def rank(self,embedding,level,orientation,feature=None):
        level=max(1,min(5,level))
        try:
            vector=_unit(embedding); cs,matrix=self.base.groups[orientation]
            levels={int(k) for c in cs for k in c['lv']}
            if not levels: return []
            selected=min(levels,key=lambda lv:(abs(lv-level),lv))
            cos=np.clip(matrix@vector,-1,1)
            indices=sorted([i for i,c in enumerate(cs) if str(selected) in c['lv'] and cos[i]>0],key=lambda i:(-cos[i],i))[:3]
            candidates=[(i,j,p) for i in indices for j,p in enumerate(cs[i]['lv'][str(selected)])]
            total=sum(p['w'] for _,_,p in candidates); answer=[]
            best_clip=max((float(cos[i]) for i in indices),default=0)
            for i,j,p in candidates:
                identity=f"{cs[i]['o']}-{self.indices[(cs[i]['o'],cs[i]['e'])]}-{selected}-{j}"
                support=math.log1p(p['w'])/math.log1p(total)
                b=0.; spatial_score=None; stats=self.records.get(identity)
                clip_ok=cos[i]>=max(self.config.clip_floor,best_clip-self.config.clip_margin)
                if self.config.beta>0 and feature is not None and feature.valid and stats and clip_ok:
                    spatial_score=compatibility(feature,p,stats)
                    b=self.config.beta*feature.confidence*stats['confidence']
                score=(self.config.alpha*float(cos[i])+self.config.gamma*support+(b*spatial_score if b else 0))/(self.config.alpha+self.config.gamma+b)
                answer.append({'id':identity,'prototype':p,'score':score,'cosine':float(cos[i]),
                    'spatial':spatial_score,'spatial_weight':b,'selected_level':selected,'can_challenge':bool(clip_ok)})
            # beta=0/unavailable feature reproduces Phase A with equivalent
            # no-current-position settings, including the raw .005 tie band.
            width=.005/(self.config.alpha+self.config.gamma+self.config.beta
                if any(c['spatial_weight'] for c in answer) else self.config.alpha+self.config.gamma)
            eligible=[c for c in answer if c['can_challenge']] if any(c['spatial_weight'] for c in answer) else answer
            if not eligible: return []
            if not any(c['spatial_weight'] for c in answer):
                for c in answer: c['can_challenge']=True
            high=max(c['score'] for c in eligible)
            tied=[c for c in eligible if high-c['score']<=width]
            chosen=min(tied,key=lambda c:(-c['prototype']['w'],-c['prototype']['n'],int(c['id'].split('-')[1]),int(c['id'].split('-')[-1])))
            if any(c['spatial_weight'] for c in answer) and chosen['spatial_weight']==0:
                # Missing statistics must not win just because reliable
                # candidates incurred a spatial penalty. Retain Phase A.
                fallback=self.rank(embedding,level,orientation,None)
                for c in fallback:c['coverage_guard']=True
                return fallback
            # Canonicalize tie-band ranking for the temporal selector while
            # keeping normalized score differences outside the band intact.
            for c in tied:
                c['score']=high if c is chosen else max(0,high-1e-10)
            return sorted(answer,key=lambda c:(c is not chosen,-c['score'],c['id']))
        except (TypeError,ValueError,KeyError): return []

    def recommend(self,embedding,level,orientation,feature=None):
        level=max(1,min(5,level))
        candidates=self.rank(embedding,level,orientation,feature)
        if not candidates:
            return {**self.base.fallback(orientation,level),'candidate_id':None,'spatial_used':False}
        c=candidates[0]; p=c['prototype']
        return {'composition':{k:p[k] for k in ('f','h','cx','cy','hy')},'status':'prototype',
                'selected_level':c['selected_level'],'support':p['n'],'candidate_id':c['id'],
                'spatial_used':c['spatial_weight']>0,'score':c['score']}


    def rescore_incumbent(self,embedding,orientation,feature,candidates,identity):
        """Current-input score for an incumbent outside top three; never promote it."""
        if not identity or any(c['id']==identity for c in candidates):return None
        p=self.prototypes.get(identity)
        if p is None or not identity.startswith(orientation[0]+'-'):return None
        cosine=float(np.clip(self.centers[int(identity.split('-')[1])]@_unit(embedding),-1,1))
        if cosine<=0:return None
        mass=max(p['w'],sum(c['prototype']['w'] for c in candidates))
        support=math.log1p(p['w'])/math.log1p(mass)
        b=0.;spatial=None;r=self.records.get(identity)
        best=max((c['cosine'] for c in candidates),default=cosine)
        if (any(c['spatial_weight'] for c in candidates) and feature is not None and feature.valid and r
                and cosine>=max(self.config.clip_floor,best-self.config.clip_margin)):
            spatial=compatibility(feature,p,r);b=self.config.beta*feature.confidence*r['confidence']
        score=(self.config.alpha*cosine+self.config.gamma*support+(b*spatial if b else 0))/(self.config.alpha+self.config.gamma+b)
        return {'id':identity,'prototype':p,'score':score,'cosine':cosine,'spatial':spatial,
                'spatial_weight':b,'selected_level':int(identity.split('-')[2]),'can_challenge':False}


class SixSecondSelector:
    def __init__(self,margin=.08):
        self.margin=margin; self.context=None; self.selected=None; self.at=None

    def update(self,context,candidates,now):
        if context!=self.context:
            self.context=context; self.selected=None; self.at=None
        if context[2]!='recommend': return None
        valid=[c for c in candidates if math.isfinite(c['score']) and 0<=c['score']<=1]
        challengers=[c for c in valid if c.get('can_challenge',True)]
        if not challengers: return self.selected
        best=sorted(challengers,key=lambda c:(-c['score'],c['id']))[0]
        if self.selected is not None:
            if best['id']==self.selected['id'] or now-self.at<6: return self.selected
            current=next((c['score'] for c in valid if c['id']==self.selected['id']),0.)
            if best['score']-current<self.margin-1e-12: return self.selected
        self.selected=copy.deepcopy(best); self.at=now
        return self.selected
