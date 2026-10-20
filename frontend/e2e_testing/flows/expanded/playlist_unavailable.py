"""Empty queues and a genuinely deleted, newly uploaded playlist item."""
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.media_deep import upload_fixture,submit_public
from support.actor_readiness import ensure_actor_pages

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','member','admin','reviewer1'])
    owner,member,admin,reviewer=(actors[k] for k in ['owner','member','admin','reviewer1'])
    p=member['page'];created=[];uploaded={};deleted=False
    original=suite.fixtures['video']['videoId']
    def playlist(label):
        item=suite.api(owner,'post','/playlists',data={'name':'QC '+label+' '+suite.run_id,'description':'Exact disposable unavailable-item fixture','visibility':'public'},expected=200).json()
        created.append(item['playlistId']);return item['playlistId']
    try:
        def empty(entry):
            pid=playlist('empty queue');path='/playlists/'+pid
            data=suite.go(member,path,'app-playlists-page',path);assert data['items']==[]
            expect(p.locator('.empty-items')).to_be_visible()
            before=sum(e['path'].endswith('/playback') for e in suite.report['http_statuses'])
            p.locator('.hero-actions .primary-button').click();p.locator('.hero-actions .secondary-button').click();p.wait_for_timeout(300)
            assert urlsplit(p.url).path==path and p.locator('video').count()==0
            assert before==sum(e['path'].endswith('/playback') for e in suite.report['http_statuses'])
            expect(p.locator('.empty-items')).to_be_visible();entry['resource_ids']=[pid]
            entry['steps']=['Create actual public empty playlist','Member loads exact zero-item response and empty explanation','Actual Play all and Shuffle clicks retain empty playlist','No watch navigation, video element or playback request; no fake stream']
        case(suite,member,'PLAYLIST-EMPTY-PLAYALL-SHUFFLE-NO-STREAM','U-PLAYLIST.03','Empty playlist cannot start a nonexistent stream',empty,'playlists')
        uploaded.update(upload_fixture(suite,owner,member,'PLAYLIST_TOMBSTONE'))
        pending=submit_public(suite,owner,admin,uploaded);mid=pending['moderationCaseId']
        suite.api(reviewer,'post','/admin/moderation/'+mid+'/claim',data={})
        suite.api(reviewer,'post','/admin/moderation/'+mid+'/resolve',data={'decision':'approve','reason':'Approve exact disposable playlist tombstone fixture'})
        def tombstone(entry):
            nonlocal deleted
            pid=playlist('deleted item');path='/playlists/'+pid;vid=uploaded['videoId']
            for item in [original,vid]:suite.api(owner,'post',path+'/videos',data={'videoId':item})
            before=suite.api(member,'get',path).json();assert all(v['available'] for v in before['items'])
            suite.api(owner,'delete','/videos/'+vid,expected=204);deleted=True
            data=suite.go(member,path,'app-playlists-page',path)
            row=next(v for v in data['items'] if v['videoId']==vid);assert row['available'] is False and row['duration']==0
            for key in ['title','thumbnailUrl','visibility','status','moderationStatus']:assert row[key] is None,key+' leaked for deleted item'
            expect(p.locator('.video-row--unavailable')).to_have_count(1)
            expect(p.locator('a[href="/watch/'+vid+'"]')).to_have_count(0)
            suite.evidence(member,entry,'deleted-item-redacted')
            p.locator('.hero-actions .primary-button').click();p.wait_for_url('**/watch/'+original+'?**')
            p.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            playback=suite.api(member,'get','/videos/'+original+'/playback').json();source=p.locator('video').first.evaluate('(v)=>v.currentSrc')
            assert any(urlsplit(r['url']).path==urlsplit(source).path for r in playback['renditions'])
            suite.evidence(member,entry,'playall-surviving-stream')
            suite.go(member,path,'app-playlists-page',path)
            p.locator('.hero-actions .secondary-button').click();p.wait_for_url('**/watch/'+original+'?**')
            assert parse_qs(urlsplit(p.url).query)['shuffle']==['true']
            p.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            source=p.locator('video').first.evaluate('(v)=>v.currentSrc')
            assert any(urlsplit(r['url']).path==urlsplit(source).path for r in playback['renditions'])
            assert suite.api(owner,'get','/videos/'+original).json()['videoId']==original
            entry['resource_ids']=[pid,vid,original,mid]
            entry['steps']=['New real MP4 upload and independent Reviewer approval, then save it alongside existing eligible video','Delete only the newly created disposable source through actual Owner API','Playlist retains tombstone with available=false and no sensitive metadata/thumbnail/watch link','Actual Play all and Shuffle each skip tombstone and decode the exact surviving video rendition','Original source remains intact']
        case(suite,member,'PLAYLIST-DELETED-TOMBSTONE-SKIP-STREAM','U-PLAYLIST.02','Deleted playlist item is redacted and skipped without affecting live source',tombstone,'playlists')
    finally:
        for pid in created:suite.api(owner,'delete','/playlists/'+pid,expected=204)
        if uploaded and not deleted:suite.api(owner,'delete','/videos/'+uploaded['videoId'],expected=204)
