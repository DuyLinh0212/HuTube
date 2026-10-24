from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);member,owner=actors['member'],actors['owner'];vid=suite.fixtures['video']['videoId']
    def controls(entry):
        suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page'];p.bring_to_front();v=p.locator('video').first
        p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
        renditions=suite.api(member,'get','/videos/'+vid+'/playback').json()['renditions']
        for rendition in renditions:
            p.locator('.player-quality-option select').select_option(rendition['quality']);p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
            expect(p.locator('.player-quality-option select')).to_have_value(rendition['quality']);assert v.evaluate('(v)=>v.videoWidth>0')
        v.hover();p.locator('.player-fullscreen-button').click();p.wait_for_function('()=>!!document.fullscreenElement')
        p.bring_to_front();p.locator('.player-fullscreen-button').click();p.wait_for_function('()=>!document.fullscreenElement',timeout=10000)
        entry['steps']=['Actual headed foreground browser','Select each real rendition and decode dimensions','Actual fullscreen element after UI enter click','Actual UI exit click clears native fullscreen; Escape has a separate assessment']
        entry['resource_ids']=[vid];entry['native_browser_mode']='headed foreground'
    case(suite,member,'WATCH-QUALITIES-FULLSCREEN','U-WATCH.01','Native foreground fullscreen and rendition controls',controls,'watch')
    def escape(entry):
        p=member['page'];p.bring_to_front();p.locator('video.video-player').hover();p.locator('.player-fullscreen-button').click();p.wait_for_function('()=>!!document.fullscreenElement')
        p.evaluate('()=>{window.__qcEscape=[];window.addEventListener("keydown",e=>{if(e.key==="Escape")setTimeout(()=>window.__qcEscape.push({trusted:e.isTrusted,prevented:e.defaultPrevented,target:e.target.tagName}),0)},{once:true})}')
        p.keyboard.press('Escape');p.wait_for_timeout(500)
        entry['native_escape_observation']=p.evaluate('()=>window.__qcEscape')
        if p.evaluate('()=>!!document.fullscreenElement'):
            suite.evidence(member,entry,'native-escape-pending',full_page=False)
            if any(e['prevented'] for e in entry['native_escape_observation']):raise AssertionError('Application prevented Escape while fullscreen remains active')
            raise PrerequisiteMissing('Native Escape remains unconfirmed through automated input despite a foreground headed browser; application did not prevent the key event. UI enter/exit is verified; physical-key manual check required')
        entry['steps']=['Actual native fullscreen','Record trusted/defaultPrevented Escape event','Native fullscreen exits without programmatic exit']
    try:case(suite,member,'WATCH-FULLSCREEN-NATIVE-ESCAPE','U-WATCH.01','Native Escape handling requires accurate browser evidence',escape,'watch')
    finally:
        p=member['page']
        if p.evaluate('()=>!!document.fullscreenElement'):p.locator('.player-fullscreen-button').click()
    def pip_entitlement(entry):
        plan=suite.api(member,'get','/plans/my-plan').json();assert not plan['features'].get('pip'),'Negative fixture requires a plan without PiP entitlement'
        suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page'];p.bring_to_front()
        if not p.evaluate('()=>document.pictureInPictureEnabled'):raise PrerequisiteMissing('Native PiP is unsupported by this browser/device')
        p.wait_for_function('()=>document.querySelector(".global-picture-in-picture-video")?.readyState>=1')
        p.locator('video.video-player').hover();button=p.locator('.player-pip-button')
        if not button.is_disabled():button.click();p.wait_for_timeout(1500)
        assert p.evaluate('()=>!document.pictureInPictureElement'),'Member plan has pip=false but actual native pictureInPictureElement was created'
        entry['steps']=['Read real Member plan pip=false','Actual browser supports PiP','Attempt native UI action','No PiP session allowed without entitlement']
        entry['resource_ids']=[vid,member['identity']['userId']]
    try:case(suite,member,'WATCH-PIP-ENTITLEMENT-DENIAL','U-WATCH.01','PiP enforces actual plan entitlement',pip_entitlement,'watch')
    finally:
        p=member['page']
        if p.evaluate('()=>!!document.pictureInPictureElement'):p.locator('.player-pip-button').click()
