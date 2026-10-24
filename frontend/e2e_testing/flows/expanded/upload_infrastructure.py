"""Actual owned API restarts, failed probe/encode and reversible local storage fault."""
import json,shutil,subprocess,time,uuid
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if not config.get('runtime_control_request'):raise PrerequisiteMissing('Owned API restart controller required')
    ensure_actor_pages(suite,actors,['owner','member'])
    owner=actors['owner'];member=actors['member'];p=owner['page'];cid=suite.fixtures['channel']['channelId'];db=LocalDb(config)
    file=suite.run_dir/'infrastructure-fixture.mp4'
    subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=1280x720:rate=24','-t','5','-c:v','libx264','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
    request=Path(config['runtime_control_request']);response=Path(config['runtime_control_response']);created=[]
    def restart(mode):
        id=uuid.uuid4().hex;temp=request.with_suffix('.tmp');temp.write_text(json.dumps({'id':id,'action':'restart-owned-api','mode':mode}),encoding='utf-8');temp.replace(request)
        deadline=time.monotonic()+75
        while time.monotonic()<deadline:
            if response.exists():
                try:value=json.loads(response.read_text(encoding='utf-8'))
                except (PermissionError,FileNotFoundError):
                    p.wait_for_timeout(250);continue
                if value['id']==id:
                    assert value['status']=='ready';return value
            p.wait_for_timeout(250)
        raise AssertionError('Owned API restart did not return healthy')
    def prepare(label):
        suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard')
        p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
        p.locator('.btn-wizard-next').click();title='QC infra '+label+' '+suite.run_id;p.locator('#videoTitle').fill(title)
        for _ in range(3):p.locator('.btn-wizard-next').click()
        p.locator('input[name=visibility][value=private]').check();return title
    def inventory(title):return [v for v in suite.api(owner,'get','/videos/manage',params={'channelId':cid,'search':title,'pageSize':100}).json()['items'] if v['title']==title]
    def probe_failure(entry):
        title=prepare('probe');before=suite.api(owner,'get','/plans/my-plan').json()['usedStorage'];restart('ffprobe-failure')
        try:
            response=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=(422,500,503))
            expect(p.locator('app-upload-progress-tray .tray-error')).to_be_visible();expect(p.locator('.step-6')).to_have_count(0)
            assert not inventory(title) and suite.api(owner,'get','/plans/my-plan').json()['usedStorage']==before
            suite.evidence(owner,entry,'real-probe-failure')
        finally:restart('normal')
        video=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201).json();created.append(video['videoId'])
        expect(p.locator('.step-6')).to_be_visible();assert len(inventory(title))==1
        suite.evidence(owner,entry,'normal-probe-retry')
        entry['resource_ids']=[video['videoId']];entry['steps']=['Actual wizard selects valid MP4','Restart only runner-owned API with nonexistent ffprobe binary','Real publish fails visibly; no completion, video or quota increase','Restore normal API in finally','Actual UI retry creates exactly one video']
    def storage_failure(entry):
        title=prepare('storage');root=(Path(config['state_dir'])/'api-root/uploads').resolve();folder=root/'videos';backup=root/('videos.qc-backup-'+suite.run_id)
        assert folder.resolve().is_relative_to(root) and folder.is_dir() and not backup.exists()
        before=suite.api(owner,'get','/plans/my-plan').json()['usedStorage']
        # Preserve the full owned directory verbatim; a file at its exact path
        # makes Directory.CreateDirectory fail. Never delete the directory/tree.
        folder.rename(backup);folder.write_bytes(b'QC temporary storage fault')
        try:
            suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=(500,502,503))
            expect(p.locator('app-upload-progress-tray .tray-error')).to_be_visible();expect(p.locator('.step-6')).to_have_count(0)
            assert not inventory(title) and suite.api(owner,'get','/plans/my-plan').json()['usedStorage']==before
            suite.evidence(owner,entry,'actual-local-storage-failure')
        finally:
            assert folder.is_file() and folder.read_bytes()==b'QC temporary storage fault'
            folder.unlink();backup.rename(folder)
        video=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201).json();created.append(video['videoId'])
        expect(p.locator('.step-6')).to_be_visible();assert len(inventory(title))==1
        suite.evidence(owner,entry,'restored-storage-retry')
        entry['resource_ids']=[video['videoId']];entry['steps']=['Actual owned Local storage directory preserved under verified same-root backup','Temporary file blocks creation of new video object directory','Actual upload fails; no video/quota mutation','Restore original directory byte-for-byte in finally','Actual UI retry creates one video']
    def encode_failure(entry):
        title=prepare('encode');restart('ffmpeg-failure')
        try:
            video=suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201).json();vid=video['videoId'];created.append(vid)
            entry['resource_ids']=[vid]
            deadline=time.monotonic()+35
            while time.monotonic()<deadline:
                state=suite.api(owner,'get','/videos/'+vid).json()
                if state['status']=='failed':break
                p.wait_for_timeout(500)
            rows=json.loads(db.sql("SELECT coalesce(json_agg(json_build_object('quality',quality_label,'codec',codec,'status',status)),'[]') FROM video_renditions WHERE video_id=:'id'::uuid;",{'id':vid}))
            entry['observed_video_status']=state['status'];entry['observed_renditions']=rows
            assert state['status']=='failed','FFmpeg error did not persist failed video state'
            assert any(r['status']=='failed' and r['codec']!='source' for r in rows)
            assert any(r['codec']=='source' and r['status']=='ready' for r in rows)
            suite.go(owner,'/studio/content?channelId='+cid,'app-studio-content-page');expect(p.locator('.video-row').filter(has_text=title)).to_be_visible()
            suite.evidence(owner,entry,'real-encode-failure')
        finally:restart('normal')
        suite.api(member,'post','/videos/'+vid+'/retry-processing',data={},expected=403)
        suite.api(owner,'post','/videos/'+vid+'/retry-processing',data={})
        deadline=time.monotonic()+75
        while time.monotonic()<deadline:
            state=suite.api(owner,'get','/videos/'+vid).json()
            unfinished=db.sql("SELECT count(*) FROM video_renditions WHERE video_id=:'id'::uuid AND status IN ('failed','processing');",{'id':vid})
            if unfinished=='0':break
            p.wait_for_timeout(500)
        assert state['status']!='failed'
        assert db.sql("SELECT count(*) FROM video_renditions WHERE video_id=:'id'::uuid AND status='failed';",{'id':vid})=='0'
        assert len(inventory(title))==1
        playback=suite.api(owner,'get','/videos/'+vid+'/playback').json();assert playback['renditions']
        suite.go(owner,'/studio/content?channelId='+cid,'app-studio-content-page');suite.evidence(owner,entry,'recovered-same-video')
        entry['resource_ids']=[vid];entry['steps']=['Actual FFmpeg binary failure marks derived renditions and video failed','Source rendition remains ready; no fake completed encode','Restore normal API process','Foreign retry denied; Owner actual retry-processing retains same ID','All failed rows recover; one video with actual playback renditions']
    try:
        if not config.get('infrastructure_encode_only'):
            case(suite,owner,'UPLOAD-FFPROBE-FAILURE-RESTART-RETRY','U-STUDIO.04','Probe failure and process restart recover without duplicate',probe_failure,'studio')
            case(suite,owner,'UPLOAD-STORAGE-FAILURE-RETRY','U-STUDIO.04','Storage failure preserves quota and retries once',storage_failure,'studio')
        case(suite,owner,'UPLOAD-FFMPEG-FAILURE-SAME-ID-RETRY','U-STUDIO.04','Failed encoding retries same video after restart',encode_failure,'studio')
    finally:
        restart('normal')
        for vid in created:suite.api(owner,'delete','/videos/'+vid,expected=(200,204))
