"""A persisted real download must be individually manageable in Account."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner']);owner=actors['owner'];p=owner['page'];created={};prior=set()
    vid=suite.fixtures['video']['videoId']
    def inventory(entry):
        nonlocal prior
        assert suite.api(owner,'get','/plans/my-plan').json()['features'].get('download'),'Entitled owner fixture required'
        prior={d['videoDownloadId'] for d in suite.api(owner,'get','/downloads').json()}
        rendition=suite.api(owner,'get','/videos/'+vid+'/playback').json()['renditions'][0]
        created.update(suite.api(owner,'post','/videos/'+vid+'/downloads',data={'quality':rendition['quality']},expected=201).json())
        assert created['status']=='ready'
        response=owner['context'].request.get(created['fileUrl'],headers=owner['headers']);assert response.status==200 and len(response.body())>0
        assert any(d['videoDownloadId']==created['videoDownloadId'] for d in suite.api(owner,'get','/downloads').json())
        suite.go(owner,'/account','app-account-page','/account/profile');p.locator('.settings-nav-list > button').nth(2).click()
        expect(p.locator('.delete-action button')).to_be_visible()
        entry['resource_ids']=[vid,created['videoDownloadId']]
        entry['steps']=['Actual entitled download created/read through backend and real media URL','Verify its exact ready download ID in owned API inventory','Open actual Account Downloads tab','Checklist requires selecting/deleting one persisted download; preference controls and Clear all alone cannot execute that operation']
        suite.evidence(owner,entry,'persisted-download-not-individually-manageable')
        entry['individual_download_rows']=p.locator('app-account-page [data-download-id],app-account-page .download-item,app-account-page .download-row').count()
        assert entry['individual_download_rows']>0,'U-ACCOUNT.04: persisted downloads are not listed in Account; there is no individual delete action, only preferences and Clear all'
    try:case(suite,owner,'ACCOUNT-DOWNLOAD-INDIVIDUAL-DELETE-CONTRACT','U-ACCOUNT.04','Account can select and delete a single real persisted download',inventory,'downloads')
    finally:
        if created and created['videoDownloadId'] not in prior:suite.api(owner,'delete','/downloads/'+created['videoDownloadId'],expected=204)
