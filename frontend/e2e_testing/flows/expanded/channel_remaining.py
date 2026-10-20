"""Public-channel sharing, missing handles, and explicit remaining control contract."""
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    channel=suite.api(actors['owner'],'get','/channels/me').json()
    handle=channel['handle'];route='/channel/'+handle
    guest=suite.actor('channel-remaining-guest','user','guest');guest['api_url']=actors['owner']['api_url'];p=guest['page']
    try:
        def share(entry):
            data=suite.go(guest,route,'app-channel-page','/channels/handle/'+handle)
            assert data['channelId']==channel['channelId']
            p.locator('.btn-more-info').click()
            expect(p.locator('.modal-footer')).to_be_visible()
            p.locator('.modal-footer .btn-modal-action').first.click()
            copied=p.evaluate('()=>navigator.clipboard.readText()')
            assert urlsplit(copied).path==route and urlsplit(copied).netloc==urlsplit(guest['origin']).netloc
            expect(p.locator('.modal-footer .btn-modal-action').first).to_contain_text('Đã sao chép')
            entry['resource_ids']=[channel['channelId']]
            entry['steps']=['Guest opens actual public channel and checks exact channel ID','Open channel information modal','Actual Share/Copy button writes exact channel route and origin to browser clipboard','Copied feedback visible; no authentication or subscription mutation']
        case(suite,guest,'CHANNEL-PUBLIC-SHARE-CLIPBOARD','U-CHANNEL.03','Guest shares the exact public channel',share,'channel')
        def absent(entry):
            missing='qc_missing_'+suite.run_id.replace('.','_')
            response=suite.response(guest,'/channels/handle/'+missing,lambda:p.goto(guest['origin']+'/channel/'+missing),status=404)
            assert response.status==404
            expect(p.locator('.channel-error-state')).to_be_visible()
            expect(p.locator('.channel-video-card,.channel-playlist-card,.channel-name')).to_have_count(0)
            entry['steps']=['Guest opens a nonexistent synthetic channel handle','Real channel endpoint returns 404','Error state ends loading and exposes no channel metadata/video/playlist cards']
        case(suite,guest,'CHANNEL-MISSING-HANDLE-NO-CARDS','U-CHANNEL.03','Missing channel handle has bounded error without stale cards',absent,'channel')
        def controls(entry):
            suite.go(guest,route,'app-channel-page','/videos/search')
            p.locator('.channel-tabs-bar button').nth(1).click()
            entry['resource_ids']=[channel['channelId']]
            entry['steps']=['Actual Guest channel Videos tab loads real public catalogue','Inspect channel component rather than unrelated global video search','Checklist requires channel-local search and sort controls']
            suite.evidence(guest,entry,'public-channel-video-controls')
            entry['observed_local_query_controls']=p.locator('app-channel-page input,app-channel-page select').count()
            assert entry['observed_local_query_controls']>0,'U-CHANNEL.03: channel Videos tab has no local search/sort controls; implementation always requests newest page 1, maximum 50'
        case(suite,guest,'CHANNEL-PUBLIC-SEARCH-SORT-CONTRACT','U-CHANNEL.03','Channel Videos supports its required local query operations',controls,'channel')
    finally:suite.release_actor(guest)
