"""Native Windows input rendezvous; never replace Escape with exitFullscreen()."""
import json
import time
from flows.expanded.common import case,snapshot_module
from flows.expanded.plan_lifecycle import native_actor
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    with native_actor(suite,'member') as actor:
        def escape(entry):
            p=actor['page'];vid=suite.fixtures['video']['videoId']
            suite.go(actor,'/watch/'+vid,'app-watch-page');p.bring_to_front()
            p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=1')
            title='HuTube QC Escape '+suite.run_id
            p.evaluate('(title)=>{document.title=title;window.__qcEscape=[];document.addEventListener("keydown",e=>{if(e.key==="Escape")setTimeout(()=>window.__qcEscape.push({trusted:e.isTrusted,prevented:e.defaultPrevented}),0)})}',title)
            p.locator('video.video-player').hover();p.locator('.player-fullscreen-button').click()
            p.wait_for_function('()=>!!document.fullscreenElement')
            entry['steps']=['Native Chrome without focus emulation','UI click enters actual fullscreen',
                'Windows Computer Use selects unique QC window and sends Escape','Actual fullscreen must exit without exitFullscreen() call']
            (suite.run_dir/'native-escape-ready.json').write_text(json.dumps({'window_title':title}),encoding='utf-8')
            deadline=time.monotonic()+240
            while time.monotonic()<deadline and not (suite.run_dir/'native-escape-input.json').exists():p.wait_for_timeout(500)
            if not (suite.run_dir/'native-escape-input.json').exists():raise PrerequisiteMissing('Windows input rendezvous timed out; native Escape is not certified')
            p.wait_for_function('()=>!document.fullscreenElement',timeout=10000)
            entry['native_escape_observation']=p.evaluate('()=>window.__qcEscape')
            entry['windows_input_evidence']='native-escape-input.json'
            entry['resource_ids']=[vid]
        case(suite,actor,'WATCH-FULLSCREEN-NATIVE-ESCAPE','U-WATCH.01','Physical Windows Escape exits real fullscreen',escape,'watch')
