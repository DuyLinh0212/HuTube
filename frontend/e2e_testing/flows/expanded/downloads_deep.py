import subprocess,shutil,json
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member=actors['owner'],actors['member'];video=suite.fixtures['video'];vid=video['videoId'];created={};p=owner['page']
    def actual_download(entry):
        assert suite.api(owner,'get','/plans/my-plan').json()['features']['download']
        suite.go(owner,'/watch/'+vid,'app-watch-page');p.locator('button[aria-controls=download-popover]').click()
        option=p.locator('#download-popover button.primary-button').first;expect(option).to_be_visible()
        suite.response(owner,'/videos/'+vid+'/downloads',lambda:option.click(),method='POST',status=201)
        # The UI navigates to the returned media URL immediately. Read its
        # persisted record through the real API rather than a destroyed CDP body.
        recorded=suite.api(owner,'get','/downloads').json()
        matches=[d for d in recorded if d['videoId']==vid];assert len(matches)==1
        created.update(matches[0])
        assert created['videoId']==vid and created['status']=='ready'
        response=owner['context'].request.get(created['fileUrl'],headers=owner['headers']);assert response.status==200
        payload=response.body();assert len(payload)>0
        artifact=suite.run_dir/'actual-download.mp4';artifact.write_bytes(payload)
        probe=json.loads(subprocess.run([shutil.which('ffprobe'),'-v','error','-show_format','-show_streams','-of','json',str(artifact)],check=True,capture_output=True,text=True,timeout=30).stdout)
        assert float(probe['format']['duration'])>=9 and any(s['codec_type']=='video' for s in probe['streams'])
        second=suite.api(owner,'post','/videos/'+vid+'/downloads',data={'quality':created['quality']},expected=201).json();assert second['videoDownloadId']==created['videoDownloadId']
        data=suite.api(owner,'get','/downloads').json();assert sum(d['videoId']==vid and d['quality']==created['quality'] for d in data)==1
        member_plan=suite.api(member,'get','/plans/my-plan').json()
        if not member_plan['features'].get('download'):suite.api(member,'post','/videos/'+vid+'/downloads',data={'quality':created['quality']},expected=403)
        suite.go(owner,'/account','app-account-page','/account/profile');p.locator('.settings-nav-list > button').nth(2).click()
        entry['resource_ids']=[vid,created['videoDownloadId']];entry['download_artifact']=str(artifact)
        entry['steps']=['Owner entitled plan → actual Watch download option','Actual API creates ready download ID','Read returned media URL; ffprobe verifies nonempty real video bytes','Repeat request reuses one record','Member without entitlement denied; Account downloads tab opens']
        entry['api_evidence_note']='Signed media URL is kept only in memory; report retains download ID and local file artifact'
    try:
        case(suite,owner,'WATCH-ACTUAL-DOWNLOAD-ENTITLEMENT','U-ACCOUNT.04','Download entitlement yields actual video bytes once',actual_download,'downloads')
        def clear(entry):
            assert created,'Actual download prerequisite missing'
            suite.go(owner,'/account','app-account-page');p.locator('.settings-nav-list > button').nth(2).click();p.locator('.delete-action button').click()
            expect(p.locator('app-result-notice[tone=success]')).to_be_visible()
            assert created['videoDownloadId'] not in {d['videoDownloadId'] for d in suite.api(owner,'get','/downloads').json()},'Clear all showed success but the actual backend download record still exists'
            entry['steps']=['Actual backend download exists','Account Clear all downloads button reports success','API inventory must no longer contain the persisted download ID']
        case(suite,owner,'ACCOUNT-CLEAR-ACTUAL-DOWNLOADS','U-ACCOUNT.04','Clear all deletes actual backend download inventory',clear,'downloads')
    finally:
        if created:suite.api(owner,'delete','/downloads/'+created['videoDownloadId'],expected=(204,404))
