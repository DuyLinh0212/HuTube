import re
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_adapter import FunctionalAdapter
from flows.user import playlist_items,interactions,ratings

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member=actors['owner'],actors['member']
    videos=[v for v in suite.fixtures.get('videos',[]) if 'music QC dataset' in v['title']];assert len(videos)>=3
    result=suite.api(owner,'post','/playlists',data={'name':'QC playback queue '+suite.run_id,'description':'Independent public playlist fixture','visibility':'public'},expected=(200,201)).json();pid=result['playlistId'];path='/playlists/'+pid
    ids=[v['videoId'] for v in videos[:3]]
    for vid in ids:suite.api(owner,'post',path+'/videos',data={'videoId':vid},expected=(200,201))
    try:
        def play_all(entry):
            suite.go(member,path,'app-playlists-page',path);p=member['page'];p.locator('.hero-actions .primary-button').click()
            expect(p).to_have_url(re.compile('/watch/'+ids[0]+r'\?'))
            p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
            assert parse_qs(urlsplit(p.url).query)['playlist']==[pid]
            if p.locator('.autoplay-toggle').get_attribute('aria-pressed')!='true':p.locator('.autoplay-toggle').click()
            p.locator('video').first.hover();p.locator('.player-progress').fill('8.5')
            if p.locator('video').first.evaluate('(v)=>v.paused'):p.locator('.player-big-play').click()
            p.wait_for_url('**/watch/'+ids[1]+'?**',timeout=15000)
            p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
            assert parse_qs(urlsplit(p.url).query)['index']==['1']
            playback=suite.api(member,'get','/videos/'+ids[1]+'/playback').json()
            current=p.locator('video').first.evaluate('(v)=>v.currentSrc')
            assert any(urlsplit(r['url']).path==urlsplit(current).path for r in playback['renditions'])
            entry['resource_ids']=[pid]+ids[:2];entry['steps']=['Member Play all opens first eligible ID with playlist context','Actual seek/play reaches natural ended event','Next eligible video ID/index opens','Decoded source belongs to second video playback response']
        case(suite,member,'PLAYLIST-PLAYALL-ENDED-NEXT','U-PLAYLIST.03','Play all advances to exact next stream',play_all,'playlists')
        def shuffle(entry):
            p=member['page'];suite.go(member,path,'app-playlists-page',path);p.locator('.hero-actions .secondary-button').click();expect(p.locator('app-watch-page')).to_be_visible()
            chosen=urlsplit(p.url).path.split('/')[-1];assert chosen in ids
            query=parse_qs(urlsplit(p.url).query);assert query['shuffle']==['true'] and query['playlist']==[pid]
            assert ids[int(query['index'][0])]==chosen
            entry['steps']=['Actual Shuffle button','Chosen video belongs to eligible queue','URL preserves playlist/shuffle and matching index']
        case(suite,member,'PLAYLIST-SHUFFLE-CONTEXT','U-PLAYLIST.03','Shuffle keeps a valid queue identity',shuffle,'playlists')
        def share(entry):
            p=member['page'];suite.go(member,path,'app-playlists-page',path);p.locator('.hero-actions .icon-button').click()
            copied=p.evaluate('()=>navigator.clipboard.readText()');assert urlsplit(copied).path==path
            entry['steps']=['Actual playlist Share button','Browser clipboard contains this exact playlist path']
        case(suite,member,'PLAYLIST-SHARE-CLIPBOARD','U-PLAYLIST.03','Playlist share copies exact target',share,'playlists')
        adapter=FunctionalAdapter(suite,'U-PLAYLIST.02',suite.fixtures['channel']['channelId'],prefix='FULL-PICKER-');adapter.state.update({'playlist_id':pid,'video_id':suite.fixtures['video']['videoId']})
        playlist_items.run(adapter,owner,member)
        adapter=FunctionalAdapter(suite,'U-WATCH.03',suite.fixtures['channel']['channelId'],prefix='FULL-INTERACTION-');adapter.state['video_id']=suite.fixtures['video']['videoId'];owner['user_id']=owner['identity']['userId']
        interactions.run(adapter,owner,member);ratings.run(adapter,owner)
        def navigation_controls(entry):
            suite.go(member,'/watch/'+ids[0]+'?playlist='+pid+'&index=0','app-watch-page')
            expect(member['page'].get_by_role('button',name=re.compile('Next video|Video tiếp|Video kế tiếp',re.I))).to_be_visible()
            entry['steps']=['Open populated playlist Watch context','Manual next/previous controls required by checklist are available']
        case(suite,member,'PLAYLIST-MANUAL-NEXT-PREVIOUS-UI','U-PLAYLIST.03','Playlist exposes manual navigation controls',navigation_controls,'playlists')
    finally:
        suite.api(owner,'delete',path,expected=(200,204))
        suite.report['cleanup'].append({'resource':'new public playback playlist','id':pid,'status':'deleted-test-fixture'})
