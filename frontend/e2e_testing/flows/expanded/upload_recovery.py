import shutil,subprocess
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner=actors['owner'];p=owner['page'];cid=suite.fixtures['channel']['channelId'];video={}
    file=suite.run_dir/'retry-fixture.mp4'
    subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','10','-c:v','libx264','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
    def cancellation(entry):
        before=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'pageSize':100}).json()
        created=[]
        def observe(request):
            if request.method=='POST' and request.url==owner['api_url']+'/videos':created.append(request)
        p.on('request',observe)
        try:
            suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard');p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            p.locator('.btn-cancel-upload').click();expect(p.locator('.file-name')).to_have_count(0)
            after=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'pageSize':100}).json()
            assert not created,'Cancel unexpectedly submitted a video creation request'
            assert after['total']==before['total']
            assert {v['videoId'] for v in after['items']}=={v['videoId'] for v in before['items']}
            entry['steps']=['Read actual owned video inventory before selecting a file','Actual file metadata/preflight ready',
                'Cancel selected file before upload; file UI cleared','Observe no POST /videos; actual inventory IDs and total unchanged']
        finally:p.remove_listener('request',observe)
    case(suite,owner,'UPLOAD-CANCEL-BEFORE-PUBLISH','U-STUDIO.04','Cancel selected file creates no video',cancellation,'studio')
    def retry(entry):
        suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard');p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000);p.locator('.btn-wizard-next').click()
        title='QC offline retry '+suite.run_id;p.locator('#videoTitle').fill(title)
        for _ in range(3):p.locator('.btn-wizard-next').click()
        p.locator('input[name=visibility][value=private]').check()
        requests=[]
        def observe(request):
            if request.method=='POST' and request.url==owner['api_url']+'/videos':requests.append(request.headers.get('idempotency-key'))
        p.on('request',observe)
        owner['context'].set_offline(True)
        try:
            p.locator('.btn-wizard-publish').click();expect(p.locator('.btn-wizard-publish')).to_be_enabled(timeout=10000)
            expect(p.locator('.step-6')).to_have_count(0)
            def error_feedback(child):
                expect(p.locator('app-upload-progress-tray .tray-error')).to_be_visible()
                child['steps']=['Actual browser network offline at publish','No completion step','Actual global upload tray visibly reports the failure']
            case(suite,owner,'UPLOAD-OFFLINE-VISIBLE-ERROR','U-STUDIO.04','Offline publish exposes actionable error',error_feedback,'studio')
        finally:owner['context'].set_offline(False)
        def pointer_access(child):
            p.locator('.btn-wizard-publish').scroll_into_view_if_needed()
            assert p.locator('.btn-wizard-publish').evaluate('(b)=>{const r=b.getBoundingClientRect();const e=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return !!e?.closest(".btn-wizard-publish")}'),'Failed-upload tray covers the Publish/Retry button and intercepts pointer input'
            result=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201);video.update(result.json())
            expect(p.locator('.step-6')).to_be_visible()
            assert len(requests)>=2 and requests[0] and requests[0]==requests[-1]
            child['resource_ids']=[video['videoId']]
            child['steps']=['Actual failed-upload tray remains visible','Publish/Retry center is unobstructed','Real mouse retry POST 201 and completion','Same idempotency key across failed request and mouse retry']
        case(suite,owner,'UPLOAD-RETRY-POINTER-ACCESS','U-STUDIO.04','Failed upload keeps mouse retry accessible',pointer_access,'studio')
        assert video,'Actual pointer retry must create the fixture before persistence checks'
        expect(p.locator('.step-6')).to_be_visible();assert len(requests)>=2 and requests[0] and requests[0]==requests[-1],'Failed publish and retry must retain the same idempotency key'
        data=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'search':title,'pageSize':100}).json()['items'];assert sum(v['title']==title for v in data)==1
        entry['resource_ids']=[video['videoId']];entry['steps']=['Real browser offline publish fails without completion','Restore network; actual mouse retry POST returns one persisted ID','Same idempotency key retained across failed request/retry','Managed inventory contains one matching video; no fake completion']
        entry['upload_contract']='Actual response supplies videoId; normal uploader uses multipart and idempotency key, not the user-excluded CF Seeder chunk API'
        p.remove_listener('request',observe)
    try:case(suite,owner,'UPLOAD-OFFLINE-RETRY-IDEMPOTENCY','U-STUDIO.04','Network recovery reuses key and creates one actual video',retry,'studio')
    finally:
        owner['context'].set_offline(False)
        if video:suite.api(owner,'delete','/videos/'+video['videoId'],expected=(200,204))
