"""Real admin downgrade and natural expiry worker; no payment result is seeded."""
import json
import re
import subprocess
import time
import queue
import threading
import tempfile
import hashlib
from contextlib import contextmanager
from pathlib import Path
from playwright.sync_api import expect
from support.local_db import LocalDb, DB_USER, DATABASE
from support.live_suite import PrerequisiteMissing
from flows.expanded.common import snapshot_module
from flows.expanded.channels import create_channel
from flows.expanded.security_plan_common import identity, stepcase
from flows.expanded.media_deep import upload_fixture

@contextmanager
def native_actor(suite,credential_key='g2_plan'):
    """A disposable native Chrome profile, without Playwright focus emulation.

    Normal Playwright pages are permanently visible even after tab switching.
    CDP no_defaults on the default context preserves genuine browser visibility.
    """
    with tempfile.TemporaryDirectory(prefix='hutube-qc-native-') as folder:
        process=subprocess.Popen([r'C:\Program Files\Google\Chrome\Application\chrome.exe',
            '--remote-debugging-port=0','--user-data-dir='+folder,'--no-first-run',
            '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding','--disable-background-timer-throttling',
            '--no-default-browser-check','about:blank'],stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
        browser=None;native=None
        try:
            active=Path(folder)/'DevToolsActivePort';deadline=time.monotonic()+15
            while not active.exists() and time.monotonic()<deadline:time.sleep(.1)
            assert active.exists(),'Owned native Chrome failed to start'
            browser=suite.playwright.chromium.connect_over_cdp('http://127.0.0.1:'+active.read_text().splitlines()[0],no_defaults=True)
            context=browser.contexts[0]
            page=context.pages[0]
            window_session=context.new_cdp_session(page)
            window_id=window_session.send('Browser.getWindowForTarget')['windowId']
            window_session.send('Browser.setWindowBounds',{'windowId':window_id,'bounds':{'windowState':'normal'}})
            window_session.detach()
            page.bring_to_front();page.emulate_media(reduced_motion='reduce')
            try:native=suite.actor('g2-native-'+str(len(suite.actors)),'user',credential_key,page=page)
            except Exception:
                diagnostic=page.evaluate('()=>({hidden:document.hidden,focus:document.hasFocus(),ready:document.readyState,inputs:[...document.querySelectorAll("input")].map(e=>({id:e.id,valid:e.validity.valid})),buttons:[...document.querySelectorAll("button[type=submit]")].map(e=>({disabled:e.disabled,rect:JSON.stringify(e.getBoundingClientRect()),animations:e.getAnimations().length}))})')
                (suite.run_dir/('native-login-'+str(len(suite.actors))+'.json')).write_text(json.dumps(diagnostic),encoding='utf-8')
                page.screenshot(path=str(suite.run_dir/('native-login-'+str(len(suite.actors))+'.png')),mask=[page.locator('input[type=password]')],timeout=15000)
                raise
            yield native
        finally:
            if native:suite.release_actor(native)
            if browser:
                try:browser.new_browser_cdp_session().send('Browser.close')
                except Exception:pass
                browser.close()
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=10)

@contextmanager
def pause_worker(config):
    """Hold only the owned worker's advisory lock while requests straddle expiry."""
    process=subprocess.Popen([str(Path(config['postgres_bin'])/'psql.exe'),'-X','-qAt','-v','ON_ERROR_STOP=1',
        '-h','127.0.0.1','-p',str(config['pg_port']),'-U',DB_USER,'-d',DATABASE],
        stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',
        creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        process.stdin.write("SELECT pg_advisory_lock(hashtextextended('hutube:plan-expiration-worker',0));\nSELECT 'QC_WORKER_LOCK_READY';\n");process.stdin.flush()
        ready=queue.Queue()
        def read_ready():
            for line in process.stdout:
                if line.strip()=='QC_WORKER_LOCK_READY':ready.put(True);return
        threading.Thread(target=read_ready,daemon=True).start()
        try:ready.get(timeout=15)
        except queue.Empty:raise RuntimeError('Owned worker lock was not acquired within 15 seconds')
        yield
    finally:
        if process.poll() is None:
            process.stdin.write("SELECT pg_advisory_unlock(hashtextextended('hutube:plan-expiration-worker',0));\n\\q\n");process.stdin.flush()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=5)

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    admin=actors['admin'];db=LocalDb(config);uid=identity(suite,config,'g2_plan');actor=suite.actor('g2-plan-user','user','g2_plan')
    channel=create_channel(suite,actor,'g2plan');cid=channel['channelId'];plans={};created_download={}
    public_video=suite.fixtures['video']['videoId'];p=actor['page'];ap=admin['page']
    original_channel=suite.fixtures['channel']
    def my():return suite.api(actor,'get','/plans/my-plan').json()
    default=my();default_id=default['planId']
    def create(label,features,max_upload,price):
        plan=suite.api(admin,'post','/admin/plans',data={'code':'qc_g2_'+label+'_'+suite.run_id[9:15],
            'name':'QC lifecycle '+label+' '+suite.run_id,'description':'Owned lifecycle test only',
            'price':price,'durationDays':30,'storageLimit':20*1024**3 if label=='high' else 2*1024**3,
            'maxUploadSize':max_upload,'maxVideoDuration':60,'maxVideoQuality':'1080p' if label=='high' else '360p',
            'maxDownloadQuality':'1080p' if label=='high' else '360p','maxMembers':2,'features':json.dumps(features),
            'isDefaultForNewUsers':False},expected=201).json();plans[label]=plan;return plan
    def switch_api(plan):
        hid=my()['subscription']['planHistoryId']
        return suite.api(admin,'post','/admin/subscriptions/'+hid+'/change-plan',data={'planId':plan['planId']}).json()
    def preflight(size=1024,quality='360p'):
        return {'channelId':cid,'fileSize':size,'duration':10,'contentType':'video/mp4','sourceQuality':quality}
    def watch():
        suite.go(actor,'/watch/'+public_video,'app-watch-page');p.bring_to_front()
        p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=1')
    def background(allowed,entry):
        entry['resource_ids']=[uid,public_video]
        entry['steps']=['Read real plan background_play='+str(allowed),'Play actual decoded video',
            'Switch real native Chrome tab; document.hidden must be true',
            'Inspect real paused/currentTime without synthetic visibility events']
        with native_actor(suite) as native:
            page=native['page'];suite.go(native,'/watch/'+public_video,'app-watch-page');page.bring_to_front()
            page.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=1')
            v=page.locator('video.video-player');v.evaluate('(v)=>{v.currentTime=0;v.muted=false;v.volume=0.05}')
            if v.evaluate('(v)=>v.paused'):page.locator('.player-big-play').click()
            page.wait_for_function('()=>document.querySelector("video.video-player").currentTime>0.25')
            before=v.evaluate('(v)=>v.currentTime');other=native['context'].new_page()
            try:
                other.bring_to_front()
                try:page.wait_for_function('()=>document.hidden',timeout=10000)
                except Exception:raise PrerequisiteMissing('Native Chrome tab did not become hidden; no visibility API was mocked')
                page.wait_for_timeout(1800)
                observed=v.evaluate('(v)=>({time:v.currentTime,paused:v.paused})')
                entry['native_visibility']='hidden';entry['playback_observed']=observed
            finally:
                other.close();page.bring_to_front();v.evaluate('(v)=>v.pause()')
                suite.evidence(native,entry,'native-browser-after-background')
            assert (not observed['paused'] and observed['time']>before+0.4) if allowed else observed['paused'], \
                'background_play='+str(allowed)+' but hidden playback observed '+str(observed)
        entry['resource_ids']=[uid,public_video];entry['steps']=['Read real plan background_play='+str(allowed),
            'Play actual decoded video','Switch real native Chrome tab; document.hidden is true','Inspect real paused/currentTime without synthetic visibility events']
    try:
        def provision(entry):
            create('high',{'download':True,'background_play':True,'pip':True},5*1024**2,1234)
            create('low',{'download':False,'background_play':False,'pip':False},512*1024,0)
            switch_api(plans['high']);actual=my();assert actual['planId']==plans['high']['planId']
            assert all(actual['features'][k] for k in ['download','background_play','pip'])
            suite.api(actor,'post','/videos/upload-preflight',data=preflight(1024**2,'720p'))
            created_download.update(suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=201).json())
            media=actor['context'].request.get(created_download['fileUrl'],headers=actor['headers']);assert media.status==200 and len(media.body())>0
            local_download=suite.run_dir/'download-before-downgrade.mp4';local_download.write_bytes(media.body())
            created_download['_local_sha256']=hashlib.sha256(media.body()).hexdigest()
            suite.go(actor,'/plans','app-plans-page','/plans/my-plan')
            entry['resource_ids']=[uid,cid,plans['high']['planId'],plans['low']['planId'],created_download['videoDownloadId']]
            entry['fixture_preparation']='Admin real change-plan grants the synthetic account; payment/webhook is not claimed tested'
            entry['steps']=['Create dedicated high/low plans through Admin API','Admin grants high plan to new owned identity',
                'my-plan exposes real features and quota','Upload preflight allows 720p/1MiB','Actual download creates record and returns nonempty media bytes']
        stepcase(suite,actor,'PLAN-HIGH-PROVISION-ALLOW','U-PLAN.04','High-plan baseline permits real media operations',provision,'plan-lifecycle')
        suite.fixtures['channel']=channel
        try:uploaded=upload_fixture(suite,actor,actors['member'],'G2-LIFECYCLE')
        finally:suite.fixtures['channel']=original_channel
        used=my()['usedStorage'];assert used>0
        def high_pip(entry):
            watch();expect(p.locator('.player-pip-button')).to_be_enabled()
            p.wait_for_function('()=>document.querySelector(".global-picture-in-picture-video")?.readyState>=1')
            p.locator('video.video-player').hover();p.locator('.player-pip-button').click();p.wait_for_function('()=>!!document.pictureInPictureElement')
            p.locator('.player-pip-button').click();p.wait_for_function('()=>!document.pictureInPictureElement')
            entry['resource_ids']=[uid,public_video];entry['steps']=['High plan pip=true','Real native PiP enters and exits through UI']
        stepcase(suite,actor,'PLAN-HIGH-NATIVE-PIP','U-PLAN.04','High plan permits native PiP',high_pip,'plan-lifecycle')
        stepcase(suite,actor,'PLAN-HIGH-BACKGROUND','U-PLAN.04','High plan continues playback in actual hidden tab',lambda e:background(True,e),'plan-lifecycle')
        def open_switch():
            current=my();hid=current['subscription']['planHistoryId']
            suite.go(admin,'/subscriptions','app-admin-subscriptions-page','/admin/subscriptions')
            ap.locator('.search-field input').fill(suite.credentials['g2_plan']['email'])
            row=ap.locator('tbody tr').filter(has_text=hid[:8].upper());expect(row).to_have_count(1);row.click()
            ap.locator('.detail-column button').filter(has_text=re.compile('Chuyển gói|Switch plan',re.I)).click()
            dialog=ap.locator('.switch-dialog');expect(dialog).to_be_visible();dialog.locator('select').select_option(plans['low']['planId'])
            return hid,dialog
        def cancel(entry):
            hid,dialog=open_switch();dialog.locator('footer .secondary-button').click();expect(dialog).to_have_count(0)
            actual=my();assert actual['planId']==plans['high']['planId'] and actual['subscription']['planHistoryId']==hid
            entry['resource_ids']=[uid,hid];entry['steps']=['Admin opens exact active subscription','Choose lower plan then cancel','Plan, history and feature flags remain high after API read-back']
        stepcase(suite,admin,'PLAN-DOWNGRADE-CANCEL','U-PLAN.04','Cancel downgrade preserves current entitlement',cancel,'plan-lifecycle')
        def downgrade(entry):
            hid,dialog=open_switch()
            ap.once('dialog',lambda confirmation:confirmation.accept())
            suite.response(admin,'/admin/subscriptions/'+hid+'/change-plan',lambda:dialog.locator('footer .primary-button').click(),method='POST')
            actual=my();assert actual['planId']==plans['low']['planId'] and actual['usedStorage']==used
            assert actual['subscription']['planHistoryId']!=hid and not any(actual['features'].get(k) for k in ['download','background_play','pip'])
            old=suite.api(admin,'get','/admin/subscriptions/'+hid).json();assert old['subscription']['status']=='expired'
            suite.go(actor,'/plans','app-plans-page','/plans/my-plan');p.reload();assert my()['planId']==plans['low']['planId']
            entry['resource_ids']=[uid,hid,actual['subscription']['planHistoryId'],uploaded['videoId']]
            entry['steps']=['Admin confirms real downgrade through UI','Old subscription expires; one new active low subscription',
                'Used bytes and actual uploaded video preserved','User plan reload shows low plan and false feature flags']
        stepcase(suite,actor,'PLAN-DOWNGRADE-PERSISTENCE','U-PLAN.04','Confirmed downgrade persists without losing uploaded data',downgrade,'plan-lifecycle')
        def upload_limits(entry):
            suite.api(actor,'post','/videos/upload-preflight',data=preflight(1024**2),expected=(400,403,409))
            suite.api(actor,'post','/videos/upload-preflight',data=preflight(1024,'720p'),expected=403)
            allowed=suite.api(actor,'post','/videos/upload-preflight',data=preflight()).json();assert allowed['storageLimit']==plans['low']['storageLimit']
            file=next(suite.run_dir.glob('web-fixture.mp4'))
            suite.go(actor,'/studio/upload?channelId='+cid,'app-video-upload-wizard');p.locator('#videoFile').set_input_files(str(file))
            expect(p.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            p.locator('.btn-wizard-next').click()
            expect(p.locator('[role=alert]')).to_be_visible(timeout=45000)
            expect(p.locator('#videoTitle')).to_have_count(0)
            entry['resource_ids']=[uid,cid];entry['steps']=['Low plan rejects oversized preflight and excessive quality',
                'Small valid file still allowed with correct low quota','Real upload wizard rejects the oversized actual MP4 and cannot reach details']
        stepcase(suite,actor,'PLAN-DOWNGRADE-UPLOAD-LIMITS','U-PLAN.04','Downgrade enforces upload size, quality and quota in UI/API',upload_limits,'plan-lifecycle')
        def download_denied(entry):
            suite.api(actor,'get','/videos/'+public_video+'/download-options',expected=403)
            suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=403)
            row=next(d for d in suite.api(actor,'get','/downloads').json() if d['videoDownloadId']==created_download['videoDownloadId'])
            assert row['status']=='revoked' and not row['fileUrl']
            suite.api(actor,'post','/downloads/'+created_download['videoDownloadId']+'/retry',data={},expected=403)
            watch();p.locator('button[aria-controls=download-popover]').click();expect(p.locator('.action-message')).to_be_visible()
            entry['resource_ids']=[uid,created_download['videoDownloadId']]
            entry['steps']=['Download options and new download denied 403','Existing record is revoked with no newly issued URL',
                'Watch UI reports denial after reload; no fake download success']
        stepcase(suite,actor,'PLAN-DOWNGRADE-DOWNLOAD-REVOKED','U-PLAN.04','Downgrade revokes new and persisted download access',download_denied,'plan-lifecycle')
        def issued_url(entry):
            # An already issued public playback URL is different from a newly
            # authorized download. Local provider has no signed URL lifetime.
            response=actor['context'].request.get(created_download['fileUrl'])
            entry['previously_issued_url_status']=response.status
            assert response.status==200 and hashlib.sha256(response.body()).hexdigest()==created_download['_local_sha256']
            assert hashlib.sha256((suite.run_dir/'download-before-downgrade.mp4').read_bytes()).hexdigest()==created_download['_local_sha256']
            suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=403)
            entry['resource_ids']=[uid,created_download['videoDownloadId']]
            entry['steps']=['Fetch real URL issued before downgrade: local public playback URL stays readable',
                'Already downloaded local bytes remain unchanged','New authorized download is rejected 403']
            entry['coverage_limit']='Observed Local provider behavior, not immediate old-URL revocation or real R2 signed-URL TTL certification; public video playback remains allowed'
            suite.go(actor,'/plans','app-plans-page','/plans/my-plan')
        stepcase(suite,actor,'PLAN-DOWNGRADE-ISSUED-URL-LOCAL-FILE','U-PLAN.04','Observe prior public URL and local-file behavior separately from new entitlement',issued_url,'plan-lifecycle')
        def pip_denied(entry):
            watch();expect(p.locator('.player-pip-button')).to_be_disabled()
            assert p.locator('video.video-player').evaluate('(v)=>v.disablePictureInPicture') and p.evaluate('()=>!document.pictureInPictureElement')
            entry['resource_ids']=[uid];entry['steps']=['User reloads Watch after downgrade','PiP control and native video capability are disabled','No native PiP session exists']
        stepcase(suite,actor,'PLAN-DOWNGRADE-PIP-DENIED','U-PLAN.04','Downgrade disables native PiP after reload',pip_denied,'plan-lifecycle')
        stepcase(suite,actor,'PLAN-DOWNGRADE-BACKGROUND-DENIED','U-PLAN.04','Downgrade stops playback in actual hidden tab',lambda e:background(False,e),'plan-lifecycle')
        switch_api(plans['high']);expiring=my();hid=expiring['subscription']['planHistoryId']
        with pause_worker(config):
            db.sql("UPDATE plan_histories SET ended_at=now()+interval '25 seconds' WHERE plan_history_id=:'hid'::uuid AND user_id=:'uid'::uuid AND status='active';",{'hid':hid,'uid':uid})
            def live_expiry(entry):
                watch();current=my();assert current['planId']==plans['high']['planId'] and current['features'].get('pip')
                expect(p.locator('.player-pip-button')).to_be_enabled()
                p.wait_for_function('()=>document.querySelector(".global-picture-in-picture-video")?.readyState>=1')
                p.locator('video.video-player').hover();p.locator('.player-pip-button').click()
                p.wait_for_function('()=>!!document.pictureInPictureElement')
                p.wait_for_function('()=>!document.pictureInPictureElement && document.querySelector(".player-pip-button")?.disabled',timeout=40000)
                suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=403)
                entry['resource_ids']=[uid,hid];entry['fixture_preparation']='Only owned ended_at clock prepared 25 seconds ahead; real expiry awaited before worker tick'
                entry['steps']=['Open Watch before actual expiry and enter real PiP','Leave current document open without reload',
                    'Natural client expiry closes PiP and disables control','Backend denies expired download before worker tick']
            stepcase(suite,actor,'PLAN-EXPIRY-LIVE-TAB-PIP-REVOKE','U-PLAN.04','Open Watch revokes native PiP at expiry without reload',live_expiry,'plan-lifecycle')
            def immediate(entry):
                suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=403)
                actual=my();watch()
                entry['resource_ids']=[uid,hid];entry['fixture_preparation']='Exact owned expiry set 25 seconds ahead, then real clock awaited; worker advisory lock held to test before its periodic tick; no output/entitlement seeded'
                entry['observed_plan']={'planId':actual['planId'],'features':actual['features'],'subscription':actual['subscription']}
                entry['steps']=['Await genuine subscription expiry while periodic worker is paused','Expired download API is denied',
                    'Read current plan and reload actual Watch','Try native PiP only if UI still enables it; capture and exit any created native session']
                entry['expired_native_pip_entered']=False
                if not p.locator('.player-pip-button').is_disabled():
                    p.wait_for_function('()=>document.querySelector(".global-picture-in-picture-video")?.readyState>=1')
                    p.locator('video.video-player').hover();p.locator('.player-pip-button').click()
                    try:
                        p.wait_for_function('()=>!!document.pictureInPictureElement',timeout=5000)
                        entry['expired_native_pip_entered']=True
                    except Exception:pass
                    finally:
                        if p.evaluate('()=>!!document.pictureInPictureElement'):
                            p.locator('.player-pip-button').click();p.wait_for_function('()=>!document.pictureInPictureElement')
                assert not actual['features'].get('pip') and not actual['features'].get('background_play'),'Expired subscription still advertised privileged features before expiry worker tick'
                expect(p.locator('.player-pip-button')).to_be_disabled()
                entry['steps']=['Expiry is before actual backend clock','Download API denies immediately',
                    'my-plan and reloaded Watch must not advertise/allow expired features before periodic worker runs']
            stepcase(suite,actor,'PLAN-EXPIRY-IMMEDIATE-FEATURE-GATE','U-PLAN.04','Expiry immediately denies feature entitlement before worker tick',immediate,'plan-lifecycle')
        def worker(entry):
            deadline=time.monotonic()+90
            while time.monotonic()<deadline:
                actual=my()
                if actual['planId']==default_id and actual.get('subscription') and actual['subscription']['planHistoryId']!=hid:break
                p.wait_for_timeout(2000)
            else:raise AssertionError('Natural expiry worker did not restore default plan within 90 seconds')
            assert actual['usedStorage']==used
            assert not actual['features'].get('download') and not actual['features'].get('pip')
            suite.go(actor,'/plans','app-plans-page','/plans/my-plan');p.reload()
            suite.fixtures['g2_expired_default']=actual
            entry['resource_ids']=[uid,hid,actual['subscription']['planHistoryId'],uploaded['videoId']]
            entry['steps']=['Release owned worker lock','Wait for real periodic worker; no invocation/mocking of worker',
                'Default plan and new active history appear through API','Uploaded bytes preserved; User reload keeps default plan']
        stepcase(suite,actor,'PLAN-EXPIRY-WORKER-RESTORE','U-PLAN.04','Natural worker restores default plan and preserves data',worker,'plan-lifecycle')
        def expiry_limits(entry):
            actual=my();assert actual['planId']==default_id
            suite.api(actor,'post','/videos/upload-preflight',data=preflight(actual['maxUploadSize']+1),expected=(400,403,409))
            valid=suite.api(actor,'post','/videos/upload-preflight',data=preflight()).json();assert valid['storageLimit']==actual['storageLimit']
            suite.api(actor,'post','/videos/'+public_video+'/downloads',data={'quality':'360p'},expected=403)
            suite.api(actor,'get','/videos/'+uploaded['videoId'])
            watch();expect(p.locator('.player-pip-button')).to_be_disabled()
            entry['resource_ids']=[uid,cid,uploaded['videoId']];entry['steps']=['Default plan upload limit enforced; small valid upload preflight remains available',
                'Quota equals restored default limit','Download denied; PiP disabled on reloaded Watch','Previously uploaded owned video remains accessible']
        stepcase(suite,actor,'PLAN-EXPIRY-DEFAULT-UPLOAD-DOWNLOAD-PIP','U-PLAN.04','Post-worker default limits agree across UI/API',expiry_limits,'plan-lifecycle')
        stepcase(suite,actor,'PLAN-EXPIRY-BACKGROUND-DENIED','U-PLAN.04','Expired default plan stops actual hidden-tab playback',lambda e:background(False,e),'plan-lifecycle')
        def no_duplicate(entry):
            before=my()['subscription']['planHistoryId'];p.wait_for_timeout(62000);after=my()
            assert after['subscription']['planHistoryId']==before and after['usedStorage']==used
            entries=suite.api(admin,'get','/admin/subscriptions',params={'search':suite.credentials['g2_plan']['email'],'pageSize':100}).json()['items']
            active=[item for item in entries if item['status'] in ('active','expiring')];assert len(active)==1 and active[0]['planHistoryId']==before
            suite.go(actor,'/plans','app-plans-page','/plans/my-plan')
            entry['resource_ids']=[uid,before];entry['steps']=['Wait a second natural expiry-worker interval','Exactly one active default history','Same history ID and used storage; no repeated grant']
        stepcase(suite,actor,'PLAN-EXPIRY-WORKER-IDEMPOTENCE','U-PLAN.04','Repeated worker tick cannot duplicate default subscription',no_duplicate,'plan-lifecycle')
    finally:
        suite.fixtures['channel']=original_channel
        if created_download:suite.api(actor,'delete','/downloads/'+created_download['videoDownloadId'],expected=(204,404))
        for plan in plans.values():suite.api(admin,'post','/admin/plans/'+plan['planId']+'/archive',data={},expected=(200,204))
        suite.release_actor(actor)
