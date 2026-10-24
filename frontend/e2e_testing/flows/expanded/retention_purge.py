"""Real retention worker: hold for appeal, then purge, then deny restoration."""
import json,time,uuid
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.media_deep import upload_fixture,submit_public
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if not config.get('runtime_control_request'):raise PrerequisiteMissing('Actual owned API restart/retention worker required')
    ensure_actor_pages(suite,actors,['owner','member','admin','reviewer1','reviewer2'])
    owner,member,admin,r1,r2=(actors[k] for k in ['owner','member','admin','reviewer1','reviewer2'])
    db=LocalDb(config);p=owner['page'];video=upload_fixture(suite,owner,member,'RETENTION');vid=video['videoId'];cid=video['channelId']
    pending=submit_public(suite,owner,admin,video);mid=pending['moderationCaseId']
    suite.api(r1,'post','/admin/moderation/'+mid+'/claim',data={})
    suite.api(r1,'post','/admin/moderation/'+mid+'/resolve',data={'decision':'approve','reason':'QC retention fixture approval'})
    suite.api(admin,'post','/admin/videos/'+vid+'/remove',data={'reason':'QC exact disposable retention fixture'},expected=204)
    request={'targetType':'video','targetId':vid,'moderationCaseId':mid,'reason':'QC active appeal holds original media'}
    appeal=suite.api(owner,'post','/appeals',data=request,expected=201).json();aid=appeal['appealId']
    def restart():
        req=Path(config['runtime_control_request']);res=Path(config['runtime_control_response']);id=uuid.uuid4().hex
        temp=req.with_suffix('.tmp');temp.write_text(json.dumps({'id':id,'action':'restart-owned-api','mode':'normal'}),encoding='utf-8');temp.replace(req)
        deadline=time.monotonic()+75
        while time.monotonic()<deadline:
            if res.exists():
                try:value=json.loads(res.read_text(encoding='utf-8'))
                except (PermissionError,FileNotFoundError):
                    p.wait_for_timeout(250);continue
                if value.get('id')==id:return
            p.wait_for_timeout(250)
        raise AssertionError('Actual API/retention worker restart timed out')
    def state():
        return json.loads(db.sql("SELECT json_build_object('purged',media_purged_at IS NOT NULL,'started',media_purge_started_at IS NOT NULL,'status',status,'moderation',moderation_status,'size',file_size,'url',video_url) FROM videos WHERE video_id=:'id'::uuid;",{'id':vid}))
    urls=json.loads(db.sql("SELECT coalesce(json_agg(path),'[]') FROM (SELECT video_url AS path FROM videos WHERE video_id=:'id'::uuid UNION SELECT thumbnail_url FROM videos WHERE video_id=:'id'::uuid AND thumbnail_url IS NOT NULL UNION SELECT file_url FROM video_renditions WHERE video_id=:'id'::uuid) paths;",{'id':vid}))
    root=(Path(config['state_dir'])/'api-root').resolve();files=[]
    for url in urls:
        assert not url.startswith('r2://'),'This worker scenario is restricted to owned Local storage'
        file=(root/urlsplit(url).path.lstrip('/')).resolve();assert file.is_relative_to(root/'uploads');files.append(file)
    assert files and all(file.exists() for file in files)
    # Move only the deadline, never seed the purge state or deleted files.
    changed=db.sql("UPDATE videos SET media_retention_until=now()-interval '1 minute' WHERE video_id=:'id'::uuid AND title=:'title' RETURNING video_id;",{'id':vid,'title':video['title']});assert changed==vid
    def hold(entry):
        restart();actual=state()
        assert not actual['purged'] and not actual['started'] and all(file.exists() for file in files)
        assert any(a['appealId']==aid and a['status']=='pending' for a in suite.api(owner,'get','/appeals/my').json())
        suite.go(owner,'/studio/content?channelId='+cid,'app-studio-content-page')
        expect(p.locator('.video-row').filter(has_text=video['title'])).to_be_visible()
        entry['resource_ids']=[vid,mid,aid];entry['steps']=['Actual uploaded/approved video removed through Admin API','Owner actual pending appeal before deadline change','Shorten only retention deadline in owned fixture DB','Restart actual retention worker; active appeal holds media','No purge intent/completion; original source/rendition/thumbnail files still exist']
    case(suite,owner,'RETENTION-PENDING-APPEAL-HOLDS-MEDIA','A-MODERATION.04','Expired retention does not purge active appeal media',hold,'appeals')
    def purge(entry):
        suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'reject','reviewNote':'QC final independent review'})
        before=int(db.sql("SELECT storage_used FROM channel_quotas WHERE channel_id=:'id'::uuid;",{'id':cid}))
        restart();deadline=time.monotonic()+30
        while not state()['purged'] and time.monotonic()<deadline:p.wait_for_timeout(250)
        actual=state();assert actual['purged'] and actual['started']
        assert all(not file.exists() for file in files)
        assert db.sql("SELECT count(*) FROM video_renditions WHERE video_id=:'id'::uuid AND status<>'deleted';",{'id':vid})=='0'
        after=int(db.sql("SELECT storage_used FROM channel_quotas WHERE channel_id=:'id'::uuid;",{'id':cid}))
        assert after==max(0,before-actual['size'])
        suite.api(member,'get','/videos/'+vid+'/playback',expected=(403,404,409))
        suite.go(owner,'/studio/content?channelId='+cid,'app-studio-content-page')
        entry['resource_ids']=[vid,aid,cid];entry['purged_file_count']=len(files)
        entry['steps']=['Independent Reviewer2 actually rejects appeal','Restart actual worker after no active appeal remains','Worker records intent/completion and physically removes exact source/rendition/thumbnail files','All rendition rows marked deleted and quota decreases exactly once','Member playback denied; no purge result seeded']
    case(suite,owner,'RETENTION-WORKER-PURGE-EXACT-QUOTA','U-STUDIO.06','Worker purges retained media after final appeal decision',purge,'studio')
    def cannot_restore(entry):
        assert state()['purged'],'Actual worker purge is required'
        response=suite.api(admin,'post','/admin/videos/'+vid+'/restore',data={'reason':'QC purged restoration must fail'},expected=409)
        assert response.json()['code']=='VIDEO_MEDIA_PURGED'
        response=suite.api(owner,'post','/appeals',data=request,expected=409);assert response.json()['code']=='VIDEO_APPEAL_WINDOW_CLOSED'
        suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'approve','reviewNote':'QC processed replay'},expected=409)
        suite.api(owner,'post','/videos/'+vid+'/retry-processing',data={},expected=(403,409))
        assert state()['purged'] and all(not file.exists() for file in files)
        suite.go(admin,'/videos','app-admin-videos-page','/admin/videos')
        entry['resource_ids']=[vid,aid];entry['steps']=['Actual purged fixture required','Admin restore returns VIDEO_MEDIA_PURGED','Owner new appeal denied after retention window','Processed appeal replay and retry-processing denied','No media recreated or moderation restored']
    case(suite,admin,'PURGED-VIDEO-CANNOT-RESTORE-APPEAL-RETRY','A-VIDEOS.03','Purged content cannot be restored by alternate flows',cannot_restore,'videos')
    # A second worker pass must not subtract quota for this video twice.
    def repeat(entry):
        before=db.sql("SELECT storage_used FROM channel_quotas WHERE channel_id=:'id'::uuid;",{'id':cid})
        restart();assert state()['purged']
        assert db.sql("SELECT storage_used FROM channel_quotas WHERE channel_id=:'id'::uuid;",{'id':cid})==before
        suite.go(owner,'/studio/content?channelId='+cid,'app-studio-content-page')
        entry['resource_ids']=[vid,cid];entry['steps']=['Restart actual retention worker a second time','Purged timestamp retained','Quota unchanged; no double release of storage']
    case(suite,owner,'RETENTION-PURGE-RESTART-IDEMPOTENCY','X-MODERATION.01','Repeated worker restart does not release quota twice',repeat,'studio')
