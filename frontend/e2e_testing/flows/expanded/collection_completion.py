"""Real multi-page collections, private exclusion and actual per-download mutations."""
from support.ui_confirmation import app_confirm
import shutil,subprocess,time
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from support.actor_readiness import ensure_actor_pages

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','admin','reviewer1','member'])
    owner,admin,reviewer,foreign=(actors[k] for k in ['owner','admin','reviewer1','member'])
    cid=suite.fixtures['channel']['channelId'];handle=suite.fixtures['channel']['handle'];tag=suite.run_id
    lists=[];videos=[];downloads=[];plan={};viewer=None;guest=None
    def ids(page,selector):return page.locator(selector).evaluate_all('(rows)=>rows.map(a=>a.pathname.split("/").pop())')
    def exact_cards(page,selector,expected):
        page.wait_for_function('({selector,expected})=>JSON.stringify([...document.querySelectorAll(selector)].map(a=>a.pathname.split("/").pop()))===JSON.stringify(expected)',arg={'selector':selector,'expected':expected})
    try:
        def playlists(entry):
            for i in range(25):
                value=suite.api(owner,'post','/playlists',data={'name':'QC '+tag+' Danh sách đích '+str(i),'visibility':'private' if i%2 else 'public'},expected=200).json()
                lists.append(value['playlistId'])
            all_items=suite.go(owner,'/playlists','app-playlists-page','/playlists');p=owner['page']
            expected=[x for x in all_items if x['playlistId'] in lists];assert len(expected)==25
            p.locator('#playlist-query').fill(tag)
            exact_cards(p,'a.playlist-card',[x['playlistId'] for x in expected[:20]])
            suite.evidence(owner,entry,'filtered-first-twenty')
            p.locator('.collection-pagination button').last.click()
            exact_cards(p,'a.playlist-card',[x['playlistId'] for x in expected[20:]])
            assert parse_qs(urlsplit(p.url).query)['page']==['2']
            suite.evidence(owner,entry,'second-page-exact-five')
            p.locator('#playlist-filter').select_option('private')
            private=[x['playlistId'] for x in expected if x['visibility']=='private']
            exact_cards(p,'a.playlist-card',private)
            assert parse_qs(urlsplit(p.url).query)['page']==['1']
            p.locator('#playlist-page-size').select_option(label='50')
            p.wait_for_function('()=>new URLSearchParams(location.search).get("pageSize")==="50"')
            p.reload();expect(p.locator('#playlist-query')).to_have_value(tag);expect(p.locator('#playlist-filter')).to_have_value('private')
            exact_cards(p,'a.playlist-card',private)
            p.locator('#playlist-query').fill('Khong_co_'+tag);expect(p.locator('a.playlist-card')).to_have_count(0)
            expect(p.locator('.library-main [role=status]')).to_be_visible()
            p.locator('#playlist-query').fill('danh sach dich');p.locator('#playlist-filter').select_option('all')
            # Diacritic-insensitive matching is scoped to the complete owned list.
            p.wait_for_function('(expected)=>expected.every(id=>[...document.querySelectorAll("a.playlist-card")].some(a=>a.pathname.endsWith("/"+id)))',arg=lists)
            other=suite.api(foreign,'get','/playlists').json();assert not set(private)&{x['playlistId'] for x in other}
            entry['resource_ids']=lists[:];entry['steps']=['Create 25 disposable actual playlists, not metadata injected into the UI','Search isolates exact IDs, first 20 then final 5 without duplication','Visibility resets page; page size 50 and reload preserve query/filter','Unmatched query is empty; Vietnamese diacritics normalize correctly','Foreign collection never contains owned private playlists']
        case(suite,owner,'PLAYLIST-LIST-FILTER-CONTRACT','U-PLAYLIST.04','Playlist collection filters and paginates complete owned data',playlists,'playlists')

        uid=identity(suite,config,'collection_viewer');viewer=suite.actor('collection-viewer','user','collection_viewer');vp=viewer['page']
        def dataset(entry):
            file=suite.run_dir/'collections-real-source.mp4'
            subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=12','-t','3','-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
            payload=file.read_bytes()
            for i in range(52):
                value=suite.api(owner,'post','/videos',multipart={'ChannelId':cid,'Title':'QC collection '+tag+' '+str(i),'Description':'Actual encoded media for pagination','Visibility':'public' if i<51 else 'private','Duration':'3','SourceQuality':'360p','AllowComments':'true','Video':{'name':'collections-real.mp4','mimeType':'video/mp4','buffer':payload}},expected=201).json()
                videos.append(value['videoId'])
            public=set(videos[:51]);deadline=time.monotonic()+300;targets={}
            while time.monotonic()<deadline:
                targets={}
                for number in range(1,11):
                    queue=suite.api(admin,'get','/admin/moderation/queue',params={'page':number,'pageSize':100}).json()
                    targets.update({x['videoId']:x for x in queue if x['videoId'] in public})
                    if len(queue)<100:break
                if len(targets)==51:break
                vp.wait_for_timeout(1000)
            assert len(targets)==51,'Every real public upload must finish processing before approval'
            for item in targets.values():
                base='/admin/moderation/'+item['moderationCaseId']
                suite.api(reviewer,'post',base+'/claim',data={})
                suite.api(reviewer,'post',base+'/resolve',data={'decision':'approve','reason':'Owned collection pagination fixture'})
            data=suite.api(viewer,'get','/videos/search',params={'q':tag,'channelId':cid,'page':1,'pageSize':50}).json()
            tail=suite.api(viewer,'get','/videos/search',params={'q':tag,'channelId':cid,'page':2,'pageSize':50}).json()
            entry['dataset_counts']={'total':data['total'],'first_page':len(data['items']),'second_page':len(tail['items'])}
            assert data['total']==51 and len(data['items'])==50 and len(tail['items'])==1
            assert {x['videoId'] for x in data['items']+tail['items']}==public
            playback=suite.api(viewer,'get','/videos/'+videos[0]+'/playback').json()
            media=viewer['context'].request.get(playback['renditions'][0]['url']);assert media.status==200 and len(media.body())>1000
            suite.go(viewer,'/watch/'+videos[0],'app-watch-page');vp.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            entry['resource_ids']=videos[:];entry['steps']=['52 actual multipart uploads of FFmpeg-encoded media; 51 public and one private','Wait actual processing, independent Reviewer claims and approves each public resource','Public API contains exactly 51 new eligible IDs and excludes private ID','Read actual rendition bytes and decode one in the real Watch UI','Fixture preparation is distinct from UI upload-flow coverage']
        if not case(suite,viewer,'COLLECTION-REAL-MEDIA-DATASET','U-CHANNEL.03','Actual channel dataset crosses the former fifty-video limit',dataset,'fixtures'):return

        def history(entry):
            for vid in videos[:51]:suite.api(viewer,'put','/videos/'+vid+'/watch-progress',data={'watchedSeconds':2,'saveHistory':True,'newSession':True})
            data=suite.go(viewer,'/history?dateRange=all','app-library-page','/library/history');assert data['total']==51
            first=[x['videoId'] for x in data['items']];exact_cards(vp,'.library-thumb',first)
            vp.locator('.library-pagination button').last.click()
            vp.wait_for_function('()=>new URLSearchParams(location.search).get("page")==="2"')
            second=suite.api(viewer,'get','/library/history',params={'page':2,'pageSize':20,'dateRange':'all'}).json()
            exact_cards(vp,'.library-thumb',[x['videoId'] for x in second['items']]);assert not set(first)&{x['videoId'] for x in second['items']}
            with vp.expect_response(lambda r:r.request.method=='GET' and urlsplit(r.url).path=='/api/v1/library/history' and parse_qs(urlsplit(r.url).query).get('sort')==['oldest']) as changed:
                vp.locator('#history-sort').select_option('oldest')
            assert changed.value.status==200;ordered=changed.value.json();assert ordered['page']==1 and ordered['total']==51
            times=[x['activityAt'] for x in ordered['items']];assert times==sorted(times)
            exact_cards(vp,'.library-thumb',[x['videoId'] for x in ordered['items']])
            vp.locator('#history-date').select_option('today');vp.locator('#history-query').fill(tag)
            vp.wait_for_function('(tag)=>new URLSearchParams(location.search).get("q")===tag',arg=tag)
            vp.reload();expect(vp.locator('#history-sort')).to_have_value('oldest');expect(vp.locator('#history-query')).to_have_value(tag)
            expect(vp.locator('.library-card')).to_have_count(20)
            vp.locator('#history-query').fill('<script>NO_MATCH_'+tag+'</script>');expect(vp.locator('.library-card')).to_have_count(0)
            assert vp.locator('app-library-page script').count()==0
            for params in [{'sort':'invalid'},{'dateRange':'invalid'},{'q':'x'*201}]:suite.api(viewer,'get','/library/history',params=params,expected=400)
            other=suite.api(foreign,'get','/library/history',params={'dateRange':'all','q':tag}).json();assert other['total']==0
            suite.api(viewer,'put','/videos/'+videos[0]+'/watch-progress',data={'watchedSeconds':2,'saveHistory':True,'newSession':False})
            assert suite.api(viewer,'get','/library/history',params={'dateRange':'all'}).json()['total']==51
            entry['resource_ids']=[uid,*videos[:51]];entry['steps']=['Real progress API prepares 51 actual eligible videos on a fresh independent viewer','UI first/next page IDs are exact and disjoint','Oldest sorting resets page and preserves total; date/query survive reload','Literal HTML query produces no result or script; invalid filters rejected 400','Foreign history remains empty; repeated progress does not duplicate library count']
        case(suite,viewer,'HISTORY-SEARCH-SORT-FILTER-CONTRACT','U-LIBRARY.01','History filters and paginates actual deduplicated progress data',history,'library')

        guest=suite.actor('collection-channel-guest','user','guest');guest['api_url']=config['api_url'];gp=guest['page']
        def channel(entry):
            suite.go(guest,'/channel/'+handle+'?tab=videos','app-channel-page','/videos/search')
            result=suite.response(guest,'/videos/search',lambda:gp.locator('#channel-video-query').fill(tag),params={'q':tag,'channelId':cid}).json()
            assert result['total']==51 and result['pageSize']==20;first=[x['videoId'] for x in result['items']]
            exact_cards(gp,'.channel-video-card',first)
            page2=suite.response(guest,'/videos/search',lambda:gp.locator('.collection-pagination button').last.click(),params={'page':'2'}).json()
            exact_cards(gp,'.channel-video-card',[x['videoId'] for x in page2['items']]);assert not set(first)&{x['videoId'] for x in page2['items']}
            changed=suite.response(guest,'/videos/search',lambda:gp.locator('#channel-video-sort').select_option('views'),params={'sort':'views','page':'1'}).json();assert changed['total']==51
            wide=suite.response(guest,'/videos/search',lambda:gp.locator('#channel-video-page-size').select_option(label='50'),params={'pageSize':'50'}).json();assert len(wide['items'])==50
            tail=suite.response(guest,'/videos/search',lambda:gp.locator('.collection-pagination button').last.click(),params={'page':'2','pageSize':'50'}).json();assert len(tail['items'])==1
            exact_cards(gp,'.channel-video-card',[tail['items'][0]['videoId']]);gp.reload();expect(gp.locator('.channel-video-card')).to_have_count(1)
            expect(gp.locator('#channel-video-query')).to_have_value(tag);expect(gp.locator('#channel-video-sort')).to_have_value('views')
            suite.api(guest,'get','/videos/'+videos[-1],expected=(403,404))
            assert videos[-1] not in ids(gp,'.channel-video-card')
            gp.locator('#channel-video-query').fill('NO_MATCH_'+tag);expect(gp.locator('.channel-video-card')).to_have_count(0)
            entry['resource_ids']=[cid,*videos];entry['steps']=['Guest uses actual channel-local search and all server filters retain channelId','Exact 20-row first/second pages; sorting resets to page one','Page size 50 then next shows actual fifty-first video, proving no fixed fifty-row truncation','Reload preserves query/sort/page; private fixture is denied by API and absent from cards','Unmatched query renders a true empty channel result']
        case(suite,guest,'CHANNEL-PUBLIC-SEARCH-SORT-CONTRACT','U-CHANNEL.03','Channel video query and pagination expose every eligible public result',channel,'channel')

        def download(entry):
            plan.update(suite.api(admin,'post','/admin/plans',data={'code':'qc_download_'+tag[9:15],'name':'QC downloads '+tag,'price':0,'durationDays':30,'storageLimit':1024**3,'maxUploadSize':20*1024**2,'maxVideoDuration':60,'maxVideoQuality':'720p','maxDownloadQuality':'720p','maxMembers':1,'features':'{"download":true,"pip":false,"background_play":false}','isDefaultForNewUsers':False},expected=201).json())
            suite.api(viewer,'post','/plans/'+plan['planId']+'/subscribe',data={});assert suite.api(viewer,'get','/downloads').json()==[]
            for vid in videos[:2]:downloads.append(suite.api(viewer,'post','/videos/'+vid+'/downloads',data={'quality':'360p'},expected=201).json()['videoDownloadId'])
            target,control=downloads
            suite.go(viewer,'/account','app-account-page','/account/profile');suite.response(viewer,'/downloads',lambda:vp.locator('.settings-nav-list button').nth(2).click())
            row=vp.locator('[data-download-id="'+target+'"]');expect(row).to_be_visible();expect(vp.locator('[data-download-id="'+control+'"]')).to_be_visible()
            before=sum(x['method']=='DELETE' and x['path'].startswith('/api/v1/downloads') for x in suite.report['http_statuses'])
            app_confirm(vp, lambda: row.locator('button').click(), accept=False);expect(row).to_be_visible()
            assert sum(x['method']=='DELETE' and x['path'].startswith('/api/v1/downloads') for x in suite.report['http_statuses'])==before
            suite.response(viewer,'/downloads/'+target,lambda:app_confirm(vp, lambda: row.locator('button').click(), accept=True),method='DELETE',status=204)
            expect(row).to_have_count(0);assert {x['videoDownloadId'] for x in suite.api(viewer,'get','/downloads').json()}=={control}
            suite.api(foreign,'delete','/downloads/'+control,expected=404)
            vp.reload();suite.response(viewer,'/downloads',lambda:vp.locator('.settings-nav-list button').nth(2).click());expect(vp.locator('[data-download-id="'+control+'"]')).to_be_visible()
            app_confirm(vp, lambda: vp.locator('.download-delete-row button').click(), accept=False);assert len(suite.api(viewer,'get','/downloads').json())==1
            suite.response(viewer,'/downloads',lambda:app_confirm(vp, lambda: vp.locator('.download-delete-row button').click(), accept=True),method='DELETE',status=204)
            expect(vp.locator('.download-row')).to_have_count(0);assert suite.api(viewer,'get','/downloads').json()==[]
            assert suite.api(owner,'get','/videos/'+videos[0]).json()['status']=='published'
            entry['resource_ids']=[uid,plan['planId'],target,control,*videos[:2]];entry['steps']=['Fresh viewer subscribes to actual free download-enabled fixture plan; empty inventory verified','Two real download records on distinct actually transcoded videos','Native confirmation cancel sends no DELETE; confirm removes only selected exact ID','Foreign identity cannot delete remaining record; reload preserves it','Clear-all cancel preserves record; confirm empties UI and API without deleting source video']
        case(suite,viewer,'ACCOUNT-DOWNLOAD-INDIVIDUAL-DELETE-CONTRACT','U-ACCOUNT.04','Account deletes one or all actual downloads only after confirmation',download,'downloads')
    finally:
        if viewer:
            for did in downloads:suite.api(viewer,'delete','/downloads/'+did,expected=(204,404))
            suite.api(viewer,'delete','/library/history',expected=204)
        for pid in lists:suite.api(owner,'delete','/playlists/'+pid,expected=204)
        for vid in videos:suite.api(owner,'delete','/videos/'+vid,expected=(204,404))
        if plan:suite.api(admin,'post','/admin/plans/'+plan['planId']+'/archive',data={},expected=(200,204))
        if viewer:suite.release_actor(viewer)
        if guest:suite.release_actor(guest)
