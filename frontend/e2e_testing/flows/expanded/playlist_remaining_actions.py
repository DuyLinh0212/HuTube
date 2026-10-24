"""New assertions for duplicate membership, both reorder directions and decoded navigation."""
import re
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','member'])
    owner,member=actors['owner'],actors['member'];p=owner['page'];q=member['page'];created=[]
    values=suite.api(member,'get','/videos/search',params={'channelId':suite.fixtures['channel']['channelId'],'pageSize':20}).json()['items']
    ids=[v['videoId'] for v in values[:3]]
    if len(ids)<3:raise PrerequisiteMissing('Three actual approved public sources required')
    value=suite.api(owner,'post','/playlists',data={'name':'QC remaining actions '+suite.run_id,'visibility':'public'},expected=200).json();pid=value['playlistId'];created.append(pid);path='/playlists/'+pid
    for vid in ids:suite.api(owner,'post',path+'/videos',data={'videoId':vid})
    def order():return [v['videoId'] for v in suite.api(owner,'get',path).json()['items']]
    def decode(vid):
        expect(q).to_have_url(re.compile('/watch/'+vid+r'(?:\?|$)'))
        playback=suite.api(member,'get','/videos/'+vid+'/playback').json()
        allowed={urlsplit(v['url']).path for v in playback['renditions']}
        q.wait_for_function('(paths)=>{const v=document.querySelector("video");return v&&v.readyState>=2&&v.videoWidth>0&&Number.isFinite(v.duration)&&v.duration>0&&paths.includes(new URL(v.currentSrc).pathname)}',arg=sorted(allowed))
        actual=q.locator('video').first.evaluate('(v)=>v.currentSrc')
        assert urlsplit(actual).path in allowed,'Decoded stream does not belong to route video ID'
    try:
        def duplicate(entry):
            baseline=suite.api(owner,'get',path).json();original=[v['playlistVideoId'] for v in baseline['items']]
            for _ in range(2):suite.api(owner,'post',path+'/videos',data={'videoId':ids[1]},expected=(200,409))
            after=suite.api(owner,'get',path).json();assert [v['playlistVideoId'] for v in after['items']]==original and order()==ids
            suite.go(owner,path,'app-playlists-page',path);expect(p.locator('.video-row')).to_have_count(3)
            entry['resource_ids']=[pid,*ids,*original];entry['steps']=['Actual three-item playlist prepared once','Replay actual Add for middle video twice','Exact immutable membership IDs/order/count unchanged, not merely distinct video titles','Actual UI reload contains three real rows']
        case(suite,owner,'PLAYLIST-DUPLICATE-ADD-EXACT-MEMBERSHIPS','U-PLAYLIST.02','Duplicate add never recreates membership or reorders items',duplicate,'playlists')
        def reorder(entry):
            suite.go(owner,path,'app-playlists-page',path)
            suite.response(owner,path+'/order',lambda:p.locator('.video-row').nth(1).locator('.row-actions button').nth(0).click(),method='PUT')
            expected=[ids[1],ids[0],ids[2]];assert order()==expected
            p.reload();expect(p.locator('.video-row')).to_have_count(3)
            suite.response(owner,path+'/order',lambda:p.locator('.video-row').nth(0).locator('.row-actions button').nth(1).click(),method='PUT');assert order()==ids
            p.reload();expect(p.locator('.video-row .row-actions').first.locator('button').nth(0)).to_be_disabled();expect(p.locator('.video-row .row-actions').last.locator('button').nth(1)).to_be_disabled()
            # Add-after-remove checks a different membership lifecycle from the retained remove/cancel case.
            suite.api(owner,'delete',path+'/videos/'+ids[1],expected=204);assert order()==[ids[0],ids[2]]
            suite.api(owner,'post',path+'/videos',data={'videoId':ids[1]});assert order()==[ids[0],ids[2],ids[1]]
            suite.api(owner,'put',path+'/order',data={'videoIds':ids});assert order()==ids
            entry['resource_ids']=[pid,*ids];entry['steps']=['Actual middle row Up persists exact new IDs/order across reload','Actual first row Down restores exact order across reload; boundaries disabled','Remove middle ID then re-add appends once; source remains actual original ID','Restore fixture order through actual API for independent navigation assertions']
        if not config.get('playlist_actions_failed_only'):
            case(suite,owner,'PLAYLIST-REORDER-BOTH-DIRECTIONS-READD','U-PLAYLIST.02','Both reorder directions and re-add persist the exact intended order',reorder,'playlists')
        def navigation(entry):
            suite.go(member,'/watch/'+ids[0]+'?playlist='+pid+'&index=0','app-watch-page');decode(ids[0])
            next_button=q.get_by_role('button',name=re.compile('Next video|Video tiếp|Video kế tiếp',re.I))
            next_button.click();decode(ids[1]);assert parse_qs(urlsplit(q.url).query)['index']==['1']
            q.get_by_role('button',name=re.compile('Previous video|Video trước',re.I)).click();decode(ids[0]);assert parse_qs(urlsplit(q.url).query)['index']==['0']
            q.reload();decode(ids[0]);assert parse_qs(urlsplit(q.url).query)['playlist']==[pid]
            entry['resource_ids']=[pid,*ids];entry['steps']=['Open actual first Watch route with playlist context; decode source belongs to this exact ID','Actual Next button changes ID/index and decodes second source','Actual Previous returns ID/index and decodes first source','Reload retains playlist context, exact source and valid duration']
        case(suite,member,'PLAYLIST-NEXT-PREVIOUS-EXACT-DECODED-SOURCES','U-WATCH.02','Manual playlist navigation changes the actual decoded source, not only icon/URL',navigation,'watch')
    finally:
        for id in created:suite.api(owner,'delete','/playlists/'+id,expected=(204,404))
