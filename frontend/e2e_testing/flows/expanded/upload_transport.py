"""Interrupt a real in-flight multipart upload, then retry the actual UI."""
import shutil,subprocess,time,json
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner'])
    owner=actors['owner'];p=owner['page'];cid=suite.fixtures['channel']['channelId'];video={}
    file=suite.run_dir/'inflight-network-fixture.mp4'
    subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','8','-c:v','libx264','-b:v','1500k','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
    assert file.stat().st_size>65536
    if not config.get('transport_fault_file'):raise PrerequisiteMissing('Requires real loopback transport fault proxy')
    control=Path(config['transport_fault_file']);applied=control.with_suffix('.applied.json')
    requests=[]
    def observe(request):
        if request.method=='POST' and request.url==owner['api_url']+'/videos':requests.append(request.headers.get('idempotency-key'))
    p.on('request',observe)
    title='QC in-flight network '+suite.run_id
    def interrupt(entry):
        suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard')
        p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
        p.locator('.btn-wizard-next').click();p.locator('#videoTitle').fill(title)
        for _ in range(3):p.locator('.btn-wizard-next').click()
        p.locator('input[name=visibility][value=private]').check()
        control.write_text('Drop only next owned POST /videos after 32768 forwarded bytes',encoding='utf-8')
        with p.expect_request(lambda r:r.method=='POST' and r.url==owner['api_url']+'/videos'):
            p.locator('.btn-wizard-publish').click()
        expect(p.locator('app-upload-progress-tray .tray-error')).to_be_visible(timeout=20000)
        expect(p.locator('.step-6')).to_have_count(0)
        expect(p.locator('.btn-wizard-publish')).to_be_enabled()
        assert applied.exists(),'No actual transport interruption was recorded'
        fault=json.loads(applied.read_text(encoding='utf-8'))
        assert 0<fault['bytes_forwarded']<fault['declared_bytes']
        suite.evidence(owner,entry,'inflight-interrupted-error')
        actual=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201).json();video.update(actual)
        expect(p.locator('.step-6')).to_be_visible()
        assert len(requests)==2 and requests[0] and requests[0]==requests[1]
        inventory=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'search':title,'pageSize':100}).json()['items']
        exact=[v for v in inventory if v['title']==title]
        assert len(exact)==1 and exact[0]['videoId']==video['videoId']
        deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            actual=suite.api(owner,'get','/videos/'+video['videoId']).json()
            if actual['status'] in ('draft','published') and actual.get('processingStatus')!='processing':break
            p.wait_for_timeout(1000)
        playback=suite.api(owner,'get','/videos/'+video['videoId']+'/playback').json()
        assert playback['renditions'],'Recovered upload did not produce playable renditions'
        suite.evidence(owner,entry,'recovered-upload-complete')
        entry['resource_ids']=[cid,video['videoId']]
        entry['transport_fault']=fault
        entry['steps']=['Real FFmpeg MP4 selected in actual upload wizard','Loopback proxy forwards actual multipart bytes to real API','Drop TCP after 32768 bytes, strictly before declared body end','Actual tray shows error; no completion; Publish becomes available','Actual UI retry uses same idempotency key through restored pass-through proxy','One persisted video ID and real processed playback renditions','No application response mocked; no seeded upload outcome']
    try:case(suite,owner,'UPLOAD-INFLIGHT-CONNECTION-DROP-RETRY','U-STUDIO.04','Mid-upload disconnect recovers once under same key',interrupt,'studio')
    finally:
        if control.exists():control.unlink()
        p.remove_listener('request',observe)
        if video:suite.api(owner,'delete','/videos/'+video['videoId'],expected=(200,204))
