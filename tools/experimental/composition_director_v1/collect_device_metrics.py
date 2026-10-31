"""Small read-only Android probe. Saves aggregate diagnostics, never images."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import statistics
import subprocess


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device',required=True)
    parser.add_argument('--adb',default=r'C:\Users\kuson\AppData\Local\Android\Sdk\platform-tools\adb.exe')
    parser.add_argument('--package',default='com.gaslighteam.gudory.directorv1')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--last-samples',type=int,default=0,help='Optional recent window for before/after comparison')
    args=parser.parse_args()
    def adb(*cmd):
        run=subprocess.run([args.adb,'-s',args.device,*cmd],capture_output=True,check=True,timeout=30)
        return run.stdout.decode('utf-8',errors='replace').strip()
    pid=adb('shell','pidof',args.package).split()[0]
    records=[]
    logs=adb('logcat','-d',f'--pid={pid}','-v','raw','-s','flutter:I')
    errors=[]
    for line in logs.splitlines():
        if 'DIRECTOR_LIVE ' in line:
            try: records.append(json.loads(line.split('DIRECTOR_LIVE ',1)[1]))
            except json.JSONDecodeError: pass
        if 'DIRECTOR_ERROR' in line: errors.append(line)
    unique={record['sample']:record for record in records}
    records=sorted(unique.values(),key=lambda r:r['sample'])
    if args.last_samples>0: records=records[-args.last_samples:]
    warm=[r for r in records if r['sample']>3]
    def dist(name, subset=None):
        values=sorted(r[name] for r in (warm if subset is None else subset))
        return {'median':statistics.median(values),'p95':values[int(.95*(len(values)-1))],'max':max(values)} if values else None
    top=adb('shell','top','-b','-n','1','-p',pid,'-o','PID,%CPU,RES,ARGS')
    cpu=None
    lines=top.splitlines()
    for i,line in enumerate(lines):
        if 'CPU' in line and 'PID' in line:
            header=[v.strip('[]') for v in line.split()]
            if '%CPU' in header:
                for row in lines[i+1:]:
                    values=row.split()
                    if values and values[0]==pid: cpu=float(values[header.index('%CPU')].strip('%'))
    memory=adb('shell','dumpsys','meminfo',args.package)
    def kb(label):
        match=re.search(label+r':\s+(\d+)',memory)
        return int(match.group(1)) if match else None
    battery=adb('shell','dumpsys','battery')
    bat={key:int(value) for key,value in re.findall(r'^\s+(level|temperature|status):\s+(\d+)\s*$',battery,re.M)}
    thermal=adb('shell','dumpsys','thermalservice')
    match=re.search(r'Thermal Status:\s+(\d+)',thermal)
    report={'recorded_utc':datetime.now(timezone.utc).isoformat(),'device':args.device,
        'model':adb('shell','getprop','ro.product.model'),'android':adb('shell','getprop','ro.build.version.release'),
        'api':adb('shell','getprop','ro.build.version.sdk'),'package':args.package,'pid':pid,
        'live_samples_available':len(records),'sample_range':[records[0]['sample'],records[-1]['sample']] if records else None,
        'warm_samples':len(warm),'actual_person_samples':sum(r['person'] for r in records),
        'valid_mask_samples':sum(r['maskValid'] for r in records),
        'directions':dict(Counter(r['direction'] for r in records)),
        'reasons':dict(Counter(r['reason'] for r in records)),
        'observed_instructions':sorted({r['instruction'] for r in records}),
        'orientation_quarter_turns':sorted({r['q'] for r in records}),
        'timing_ms':{name:dist(name) for name in ('coreMs','poseMs','maskMs','prepareMs','pipelineMs')},
        'last_reported_hz':records[-1]['hz'] if records else None,
        'overlay_prepare_ms':dist('overlayPrepareMs',[r for r in warm if 'overlayPrepareMs' in r]),
        'overlay_paint_ms':dist('overlayPaintMs',[r for r in warm if 'overlayPaintMs' in r]),
        'overlay_modes_seen':sorted({(r['showLines'],r['showHeatmap']) for r in records if 'showLines' in r}),
        'line_display_mismatch_count':sum(r['drawnLines'] != (r['lines'] if r['showLines'] else 0) for r in records if 'drawnLines' in r),
        'heatmap_supported_samples':sum(any(v is not None for v in r.get('heatValues',[])) for r in records),
        'heatmap_distinct_observed_grids':len({tuple(round(v,3) if v is not None else None for v in r['heatValues']) for r in records if any(v is not None for v in r.get('heatValues',[]))}),
        'overlay_options_events':sum('DIRECTOR_OVERLAY_OPTIONS ' in line for line in logs.splitlines()),
        'pose_and_mask_positive_core_ms':dist('coreMs',[r for r in warm if r['person'] and r['maskValid']]),
        'pose_and_mask_positive_pipeline_ms':dist('pipelineMs',[r for r in warm if r['person'] and r['maskValid']]),
        'target_generations_seen':sorted({r['targetGeneration'] for r in records}),
        'max_detected_line_count':max((r['lines'] for r in records),default=0),
        'cpu_percent_one_core_scale':cpu,'cpu_capacity_percent':int(re.search(r'(\d+)%cpu',top).group(1)) if re.search(r'(\d+)%cpu',top) else None,'total_pss_kib':kb('TOTAL PSS'),'total_rss_kib':kb('TOTAL RSS'),
        'battery':bat,'thermal_status':int(match.group(1)) if match else None,'runtime_error_count':len(errors),
        'limitations':'Debug build, uncontrolled live scene; no claims of aesthetic quality or validated physical movement. CPU is one top snapshot. Core may be only a fallback path when person/mask are absent.'}
    args.output.write_bytes((json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
    print(json.dumps(report,ensure_ascii=True,indent=2))


if __name__=='__main__':
    main()
