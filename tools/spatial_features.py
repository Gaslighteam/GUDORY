"""Phase B v1 fixed-shot spatial descriptor; no semantic object claims.

Input RGB and mask must describe the SAME already-oriented, already-cropped
shot. Never apply a camera/preview crop here. Integer sampling permits a direct
Dart implementation. Arrays and individual descriptors are memory-only.
"""
from dataclasses import dataclass
import numpy as np

SIZE = 96
SPEC = 'grid96-luma77-150-29-edge4-range9-dilate2-v1'


@dataclass(frozen=True)
class SpatialFeature:
    grid: tuple = ()
    centroid: tuple = (.5, .5)
    asymmetry: tuple = (0., 0.)
    confidence: float = 0.
    coverage: float = 0.
    reason: str = 'unavailable'

    @property
    def valid(self):
        return (self.reason == 'ok' and .1 <= self.confidence <= 1 and len(self.grid) == 18
                and len(self.centroid)==len(self.asymmetry)==2
                and np.isfinite([*self.grid,*self.centroid,*self.asymmetry,self.coverage]).all()
                and all(0<=v<=1 for v in (*self.grid,*self.centroid,self.coverage))
                and all(-1<=v<=1 for v in self.asymmetry))

    def relation(self, cx, cy):
        if not self.valid or not np.isfinite([cx,cy]).all() or not 0 <= cx <= 1 or not 0 <= cy <= 1:
            raise ValueError('Reliable feature and normalized candidate required')
        return np.array([(cx-self.centroid[0]+1)/2,(cy-self.centroid[1]+1)/2,
                         .5+(cx-.5)*self.asymmetry[0],.5+(cy-.5)*self.asymmetry[1]])


def extract_spatial(rgb, mask):
    """18 bounded grid values + complexity centroid/asymmetry, or unavailable.

    No mean-color fill is used here. Person boundary and two grid-pixel halo
    are excluded BEFORE differences. Every cell needs >=25% observed support;
    missing cells are never imputed as negative space.
    """
    try:
        a=np.asarray(rgb)
        m=np.asarray(mask,dtype=float)
        if (a.ndim!=3 or a.shape[2]!=3 or min(a.shape[:2])<3 or a.dtype!=np.uint8
                or m.ndim!=2 or min(m.shape)<1 or not np.isfinite(m).all()
                or np.any(m<0) or np.any(m>1)):
            return SpatialFeature(reason='invalid-input')
        ys=((2*np.arange(SIZE)+1)*a.shape[0])//(2*SIZE)
        xs=((2*np.arange(SIZE)+1)*a.shape[1])//(2*SIZE)
        p=a[ys[:,None],xs].astype(np.int32)
        my=((2*np.arange(SIZE)+1)*m.shape[0])//(2*SIZE)
        mx=((2*np.arange(SIZE)+1)*m.shape[1])//(2*SIZE)
        person=m[my[:,None],mx]>=.5
        y=(77*p[:,:,0]+150*p[:,:,1]+29*p[:,:,2]+128)//256
        allowed=np.zeros((SIZE,SIZE),dtype=bool)
        good=np.ones((SIZE-4,SIZE-4),dtype=bool)
        for dy in range(5):
            for dx in range(5): good &= ~person[dy:dy+SIZE-4,dx:dx+SIZE-4]
        allowed[2:-2,2:-2]=good
        edge=np.zeros_like(y)
        edge[1:-1,1:-1]=(abs(y[1:-1,1:-1]-y[1:-1,:-2])+abs(y[1:-1,1:-1]-y[1:-1,2:])
            +abs(y[1:-1,1:-1]-y[:-2,1:-1])+abs(y[1:-1,1:-1]-y[2:,1:-1]))
        neighbors=np.stack([y[dy:dy+SIZE-2,dx:dx+SIZE-2] for dy in range(3) for dx in range(3)])
        texture=np.zeros_like(y); texture[1:-1,1:-1]=neighbors.max(axis=0)-neighbors.min(axis=0)
        edges=[];textures=[];coverages=[]
        for row in range(3):
            for col in range(3):
                region=np.s_[row*32:(row+1)*32,col*32:(col+1)*32]
                keep=allowed[region]; n=int(keep.sum())
                potential=(min((row+1)*32,94)-max(row*32,2))*(min((col+1)*32,94)-max(col*32,2))
                coverages.append(n/potential)
                if n==0: return SpatialFeature(reason='coverage')
                edges.append(int(edge[region][keep].sum())/(n*1020))
                textures.append(int(texture[region][keep].sum())/(n*255))
        coverage=float(allowed.sum())/(92*92)
        if min(coverages)<.25 or coverage<.55:
            return SpatialFeature(coverage=coverage,reason='coverage')
        energy=(np.array(edges)+np.array(textures))/2
        contrast=float(energy.max()-energy.min())
        if float(energy.mean())<.005 or contrast<.005:
            return SpatialFeature(coverage=coverage,reason='uninformative')
        confidence=min(1,(min(coverages)-.25)/.4)*min(1,(coverage-.55)/.3)*min(1,contrast/.03)
        if confidence<.1: return SpatialFeature(coverage=coverage,reason='low-confidence')
        total=float(energy.sum())
        centroid=(sum(float(v)*((i%3+.5)/3) for i,v in enumerate(energy))/total,
                  sum(float(v)*((i//3+.5)/3) for i,v in enumerate(energy))/total)
        asym=(sum(float(v)*(-1 if i%3==0 else 1 if i%3==2 else 0) for i,v in enumerate(energy))/total,
              sum(float(v)*(-1 if i//3==0 else 1 if i//3==2 else 0) for i,v in enumerate(energy))/total)
        grid=tuple(min(1,v/(4*max(float(np.mean(values)),.005)))
                   for values in (edges,textures) for v in values)
        return SpatialFeature(grid,centroid,asym,float(confidence),coverage,'ok')
    except (TypeError,ValueError,IndexError):
        return SpatialFeature(reason='invalid-input')
