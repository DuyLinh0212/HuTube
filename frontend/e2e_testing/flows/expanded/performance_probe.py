"""Local measurement evidence, explicitly without a production performance gate."""
import json
import math
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

OBSERVER='''(()=>{
  window.__qcPerf={lcp:[],shifts:[],longTasks:[],events:[],video:[]};
  for(const [type,key] of [['largest-contentful-paint','lcp'],['layout-shift','shifts'],['longtask','longTasks'],['event','events']]){
    try{new PerformanceObserver(list=>{for(const e of list.getEntries())window.__qcPerf[key].push({start:e.startTime,duration:e.duration,value:e.value||0,recentInput:!!e.hadRecentInput,interactionId:e.interactionId||0,name:e.name});}).observe({type,buffered:true,durationThreshold:16});}catch{}
  }
  for(const type of ['loadedmetadata','loadeddata','waiting','playing','seeking','seeked'])document.addEventListener(type,event=>{
    if(event.target?.tagName!=='VIDEO')return;
    window.__qcPerf.video.push({type,at:performance.now(),currentTime:event.target.currentTime});
    if(type==='loadedmetadata'&&event.target.requestVideoFrameCallback)event.target.requestVideoFrameCallback(()=>window.__qcPerf.video.push({type:'firstObservedFrame',at:performance.now(),currentTime:event.target.currentTime}));
  },true);
})();'''


def run(suite,config,actors):
    snapshot_module(suite,__file__)
    actor=suite.actor('performance-probe','user','member');p=actor['page']
    actor['context'].add_init_script(OBSERVER)
    output={'environment':'Owned QC localhost, real PostgreSQL/API/video, concurrent functional runs; no CPU/network throttling',
            'device':suite.input_device,'acceptance':'MEASURED_ONLY; no agreed production SLO or load/soak certification',
            'routes':[],'heap_samples':[]}
    path=suite.run_dir/'frontend-performance-baseline.json'
    def save():path.write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
    def sample():
        value=p.evaluate('()=>({url:location.pathname,...window.__qcPerf,navigation:performance.getEntriesByType("navigation").map(e=>({domContentLoaded:e.domContentLoadedEventEnd,load:e.loadEventEnd}))})')
        value['cls']=sum(s['value'] for s in value['shifts'] if not s['recentInput'])
        value['largest_paint_ms']=max([s['start'] for s in value['lcp']],default=None)
        interaction={}
        for event in value['events']:
            if event['interactionId']:interaction[event['interactionId']]=max(interaction.get(event['interactionId'],0),event['duration'])
        times=sorted(interaction.values())
        value['observed_interaction_count']=len(times)
        value['observed_interaction_p95_ms']=times[max(0,math.ceil(len(times)*.95)-1)] if times else None
        value['interaction_limit']='Only instrumented interactions in this probe; not a site-wide INP certification'
        output['routes'].append(value)
    session=actor['context'].new_cdp_session(p)
    session.send('Performance.enable')
    try:
        def routes(entry):
            suite.go(actor,'/home','app-home-page');p.wait_for_timeout(800)
            for cycle in range(4):
                for _ in range(5):
                    p.locator('.top-avatar').click();expect(p.locator('.account-drawer')).to_have_count(1)
                    p.locator('.account-drawer__close').click();expect(p.locator('.account-drawer')).to_have_count(0)
                    p.wait_for_timeout(100)
                sample()
                suite.go(actor,'/account','app-account-page');p.wait_for_timeout(300);sample()
                suite.go(actor,'/home','app-home-page');p.wait_for_timeout(300)
                session.send('HeapProfiler.collectGarbage')
                metrics={m['name']:m['value'] for m in session.send('Performance.getMetrics')['metrics']}
                output['heap_samples'].append({'cycle':cycle+1,'js_heap_used_bytes':metrics.get('JSHeapUsedSize'),
                    'nodes':metrics.get('Nodes'),'documents':metrics.get('Documents')})
            output['heap_limit']='Four route/drawer cycles with GC measurements; trend evidence, not proof of absence of a long-term heap leak'
            save();entry['measurement_artifact']=path.name
            entry['performance_gate']='MEASURED_ONLY'
            entry['steps']=['Twenty real drawer open/close interactions; no residual drawer DOM',
                'Four actual Home/Account round trips','Observe LCP/CLS/long tasks/event durations where the browser emits them',
                'Collect actual heap/DOM metrics after each cycle; save raw values without inventing a production SLO']
        case(suite,actor,'PERF-ROUTE-DRAWER-MEASUREMENTS','X-PERF','Repeated drawer/route behavior with local performance measurements',routes,'performance')
        def video(entry):
            vid=suite.fixtures['video']['videoId']
            suite.go(actor,'/watch/'+vid,'app-watch-page');p.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            v=p.locator('video').first
            if v.evaluate('(e)=>e.paused'):p.locator('.player-big-play').click()
            p.wait_for_function('()=>!document.querySelector("video").paused')
            v.hover();p.locator('.player-control-group').first.locator('button').first.click()
            p.wait_for_function('()=>document.querySelector("video").paused')
            p.locator('.player-progress').fill('3')
            p.wait_for_function('()=>Math.abs(document.querySelector("video").currentTime-3)<.5')
            assert v.evaluate('(e)=>e.videoWidth>0&&e.videoHeight>0')
            sample();save();entry['resource_ids']=[vid];entry['measurement_artifact']=path.name
            entry['performance_gate']='MEASURED_ONLY'
            entry['steps']=['Load actual eligible transcoded fixture','Decoded dimensions and actual UI play/pause/seek state',
                'Capture document-relative metadata/frame/seeking/seeked/waiting/playing events',
                'Save observed video startup/seek/buffering timeline; no network shaping or production performance claim']
        case(suite,actor,'PERF-VIDEO-START-SEEK-MEASUREMENTS','X-PERF','Real decoded video timing baseline',video,'performance')
    finally:
        save();session.detach();suite.release_actor(actor)
