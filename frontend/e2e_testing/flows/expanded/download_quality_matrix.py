"""Download every actual 720p-source rendition, verify bytes/dimensions and ownership."""
import hashlib,json,re,shutil,subprocess,time
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.media_deep import submit_public
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','member','reviewer1','admin'])
    owner,member,reviewer,admin=(actors[k] for k in ['owner','member','reviewer1','admin']);p=owner['page'];cid=suite.fixtures['channel']['channelId'];video={};downloads={}
    file=suite.run_dir/'download-source-720p.mp4'
    subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=1280x720:rate=24','-t','5','-c:v','libx264','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
    try:
        def prepare(entry):
            assert suite.api(owner,'get','/plans/my-plan').json()['features'].get('download')
            suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard')
            p.locator('#videoFile').set_input_files(str(file));expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            p.locator('.btn-wizard-next').click();p.locator('#videoTitle').fill('QC actual download qualities '+suite.run_id)
            for _ in range(3):p.locator('.btn-wizard-next').click()
            p.locator('input[name=visibility][value=private]').check()
            video.update(suite.response(owner,'/videos',lambda:p.locator('.btn-wizard-publish').click(),method='POST',status=201).json())
            vid=video['videoId'];deadline=time.monotonic()+90
            while time.monotonic()<deadline:
                response=suite.api(owner,'get','/videos/'+vid+'/playback',expected=(200,409))
                if response.status==200 and {'360p','480p','720p'}<={r['quality'] for r in response.json()['renditions']}:break
                p.wait_for_timeout(500)
            else:raise AssertionError('Actual 720p source did not produce all three ready renditions')
            pending=submit_public(suite,owner,admin,video);mid=pending['moderationCaseId']
            suite.api(reviewer,'post','/admin/moderation/'+mid+'/claim',data={})
            suite.api(reviewer,'post','/admin/moderation/'+mid+'/resolve',data={'decision':'approve','reason':'Approve exact disposable download quality fixture'})
            suite.api(member,'get','/videos/'+vid+'/playback')
            suite.go(owner,'/watch/'+vid,'app-watch-page');p.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            entry['resource_ids']=[vid,mid,cid]
            entry['steps']=['Generate actual five-second 1280x720 MP4','Owner actual wizard upload; no video/rendition status seeded','Wait actual source/480p/360p ready responses','Independent Reviewer approves actual public submission','Member playback succeeds; fixture visibility does not mask entitlement tests']
        if not case(suite,owner,'DOWNLOAD-QUALITY-REAL-720P-PREPARATION','U-STUDIO.03','Prepare actual three-rendition eligible video',prepare,'downloads'):raise PrerequisiteMissing('Real quality fixture unavailable')
        vid=video['videoId']
        for quality in ['720p','480p','360p']:
            def download(entry,quality=quality):
                suite.go(owner,'/watch/'+vid,'app-watch-page');p.locator('button[aria-controls=download-popover]').click()
                option=p.locator('#download-popover button.primary-button').filter(has_text=re.compile('^'+quality+r'\s'))
                expect(option).to_be_visible();suite.evidence(owner,entry,'actual-'+quality+'-download-option')
                suite.response(owner,'/videos/'+vid+'/downloads',lambda:option.click(),method='POST',status=201)
                rows=suite.api(owner,'get','/downloads').json();matching=[d for d in rows if d['videoId']==vid and d['quality']==quality];assert len(matching)==1
                item=matching[0];downloads[quality]=item;assert item['status']=='ready' and item['fileSize']>0
                assert urlsplit(item['fileUrl']).hostname in ('127.0.0.1','localhost'),'This download matrix is restricted to owned Local storage'
                response=owner['context'].request.get(item['fileUrl'],headers=owner['headers']);assert response.status==200
                payload=response.body();assert len(payload)==item['fileSize']
                artifact=suite.run_dir/('download-actual-'+quality+'.mp4');artifact.write_bytes(payload)
                probe=json.loads(subprocess.run([shutil.which('ffprobe'),'-v','error','-show_streams','-show_format','-of','json',str(artifact)],check=True,capture_output=True,text=True,encoding='utf-8',timeout=30).stdout)
                stream=next(s for s in probe['streams'] if s['codec_type']=='video');assert stream['height']==int(quality[:-1]) and float(probe['format']['duration'])>=4.5
                repeated=suite.api(owner,'post','/videos/'+vid+'/downloads',data={'quality':quality},expected=201).json();assert repeated['videoDownloadId']==item['videoDownloadId']
                entry['resource_ids']=[vid,item['videoDownloadId']];entry['media_artifact']=artifact.name;entry['media_sha256']=hashlib.sha256(payload).hexdigest();entry['decoded_height']=stream['height']
                entry['steps']=['Select actual '+quality+' option in Watch popover','Actual UI POST creates exactly one ready download ID','Read actual media bytes; file size and independent ffprobe dimensions/duration match selected quality','Repeated same-quality request retains same ID; no duplicated download record']
            case(suite,owner,'WATCH-DOWNLOAD-ACTUAL-QUALITY-'+quality.upper(),'U-WATCH.03','Actual '+quality+' download contains the requested media quality',download,'downloads')
        def denied(entry):
            assert not suite.api(member,'get','/plans/my-plan').json()['features'].get('download'),'Independent Member must lack download entitlement'
            suite.api(member,'get','/videos/'+vid+'/playback')
            response=suite.api(member,'post','/videos/'+vid+'/downloads',data={'quality':'360p'},expected=403);assert response.json()['code']=='DOWNLOAD_NOT_INCLUDED'
            response=suite.api(owner,'post','/videos/'+vid+'/downloads',data={'quality':'2160p'},expected=403);assert response.json()['code']=='DOWNLOAD_QUALITY_DENIED'
            response=suite.api(owner,'post','/videos/'+vid+'/downloads',data={'quality':''},expected=400);assert response.json()['code']=='INVALID_DOWNLOAD_QUALITY'
            for item in downloads.values():suite.api(member,'delete','/downloads/'+item['videoDownloadId'],expected=404)
            suite.go(member,'/watch/'+vid,'app-watch-page');entry['resource_ids']=[vid,*[v['videoDownloadId'] for v in downloads.values()]]
            entry['steps']=['Public video playback allowed to independent Member','Actual valid-quality download denied specifically by plan, not video visibility','Entitled Owner cannot request absent/empty quality','Foreign identity cannot delete any Owner download ID']
        case(suite,member,'WATCH-DOWNLOAD-QUALITY-ENTITLEMENT-OWNERSHIP','U-WATCH.03','Download permission/quality/ownership boundaries remain independent',denied,'downloads')
        def single_delete(entry):
            assert len(downloads)==3,'All quality downloads prerequisite'
            selected=downloads['360p']['videoDownloadId'];suite.api(owner,'delete','/downloads/'+selected,expected=204)
            ids={d['videoDownloadId'] for d in suite.api(owner,'get','/downloads').json()}
            assert selected not in ids and all(downloads[q]['videoDownloadId'] in ids for q in ['720p','480p'])
            assert {'360p','480p','720p'}<={r['quality'] for r in suite.api(owner,'get','/videos/'+vid+'/playback').json()['renditions']}
            suite.go(owner,'/account','app-account-page');p.locator('.settings-nav-list > button').nth(2).click()
            entry['resource_ids']=[vid,selected,*[downloads[q]['videoDownloadId'] for q in ['720p','480p']]]
            entry['steps']=['Delete exact 360p record through actual backend API','720p and 480p records remain','All source renditions remain playable','This certifies backend single deletion only; missing Account individual-delete UI remains a separate FAIL']
        case(suite,owner,'DOWNLOAD-SINGLE-API-DELETE-RETAINS-OTHERS','U-ACCOUNT.04','Backend single-record deletion preserves other downloads and source',single_delete,'downloads')
    finally:
        if downloads:
            ids={d['videoDownloadId'] for d in suite.api(owner,'get','/downloads').json()}
            for item in downloads.values():
                if item['videoDownloadId'] in ids:suite.api(owner,'delete','/downloads/'+item['videoDownloadId'],expected=204)
        if video:suite.api(owner,'delete','/videos/'+video['videoId'],expected=204)
