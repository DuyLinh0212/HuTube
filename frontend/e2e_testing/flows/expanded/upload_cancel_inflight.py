"""Cancel the actual client request while real upstream body is incomplete."""
import json,shutil,subprocess,time
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module,open_upload_progress
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing
from support import transport_proxy

def run(suite,config,actors):
    snapshot_module(suite,__file__);snapshot_module(suite,transport_proxy.__file__)
    if not config.get('transport_fault_file'):raise PrerequisiteMissing('Actual loopback transport hold required')
    ensure_actor_pages(suite,actors,['owner']);owner=actors['owner'];p=owner['page'];cid=suite.fixtures['channel']['channelId']
    root=Path(config['transport_fault_file']);arm=root.with_suffix('.hold.json');applied=root.with_suffix('.hold.applied.json');release=root.with_suffix('.hold.release')
    file=suite.run_dir/'cancel-inflight.mp4'
    subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','8','-c:v','libx264','-b:v','1500k','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
    aborted=[]
    def failed(request):
        if request.method=='POST' and request.url==owner['api_url']+'/videos':aborted.append({'failure':request.failure,'at':time.monotonic()})
    p.on('requestfailed',failed)
    def cancel(entry):
        title='QC cancel in flight '+suite.run_id
        before=suite.api(owner,'get','/plans/my-plan').json()['usedStorage']
        suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard')
        p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
        p.locator('.btn-wizard-next').click();p.locator('#videoTitle').fill(title)
        for _ in range(3):p.locator('.btn-wizard-next').click()
        p.locator('input[name=visibility][value=private]').check();arm.write_text('{}',encoding='utf-8')
        p.locator('.btn-wizard-publish').click();deadline=time.monotonic()+10
        while not applied.exists() and time.monotonic()<deadline:p.wait_for_timeout(50)
        assert applied.exists(),'Actual body hold did not activate'
        fault=json.loads(applied.read_text(encoding='utf-8'));assert 0<fault['bytes_forwarded']<fault['declared_bytes']
        open_upload_progress(p)
        expect(p.locator('app-upload-progress-tray .tray-cancel')).to_be_visible()
        suite.evidence(owner,entry,'real-upload-before-cancel')
        p.locator('app-upload-progress-tray .tray-cancel').click()
        deadline=time.monotonic()+5
        while not aborted and time.monotonic()<deadline:p.wait_for_timeout(50)
        assert aborted and 'ABORTED' in aborted[-1]['failure'],'Client did not actually abort its request before proxy release'
        entry['transport_fault']=fault;entry['client_request_failure']=aborted[-1]['failure']
        release.write_text('Release after observed client abort only',encoding='utf-8')
        expect(p.locator('app-upload-progress-tray .upload-tray')).to_have_count(0)
        expect(p.locator('.step-6')).to_have_count(0)
        expect(p.locator('.btn-wizard-publish')).to_be_enabled()
        inventory=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'search':title,'pageSize':100}).json()['items']
        assert not any(v['title']==title for v in inventory)
        assert suite.api(owner,'get','/plans/my-plan').json()['usedStorage']==before
        suite.evidence(owner,entry,'cancelled-without-completion')
        entry['transport_fault']=fault;entry['client_request_failure']=aborted[-1]['failure'];entry['resource_ids']=[cid]
        entry['steps']=['Select real MP4 and publish through actual wizard','Actual upstream receives only a partial body and is held, with byte-count proof','Open circular progress details and press actual Cancel; browser emits ERR_ABORTED before proxy release','Release incomplete real connection without a fabricated API response','No completion, video row or quota increase; Publish can be used again']
    try:case(suite,owner,'UPLOAD-INFLIGHT-UI-CANCEL-NO-RESOURCE','U-STUDIO.04','Actual in-flight Cancel aborts the client and grants no upload result',cancel,'studio')
    finally:
        release.write_text('Bounded teardown release',encoding='utf-8')
        if arm.exists():arm.unlink()
        p.remove_listener('requestfailed',failed)
