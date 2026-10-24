"""Real uploads provide a multi-page search dataset; no metadata-only seed."""
import time
from flows.expanded.common import case,snapshot_module
from playwright.sync_api import expect

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    owner,admin,member=(actors[k] for k in ['owner','admin','member']);cid=suite.fixtures['channel']['channelId']
    file=suite.run_dir/'web-fixture.mp4';assert file.exists()
    payload=file.read_bytes();created=[]
    def dataset(entry):
        for index in range(22):
            video=suite.api(owner,'post','/videos',multipart={'ChannelId':cid,'Title':'music QC dataset '+suite.run_id+' '+str(index),'Description':'Real transcoded pagination fixture','Visibility':'public','Duration':'10','SourceQuality':'360p','AllowComments':'true','Video':{'name':'qc-dataset.mp4','mimeType':'video/mp4','buffer':payload}},expected=201).json()
            created.append(video);suite.fixtures.setdefault('videos',[]).append(video)
        deadline=time.monotonic()+240
        while time.monotonic()<deadline:
            queue=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
            targets=[q for q in queue if q['videoId'] in {v['videoId'] for v in created}]
            if len(targets)==22:break
            time.sleep(2)
        assert len(targets)==22,'Actual uploads did not all reach moderation queue'
        for item in targets:
            suite.api(admin,'post','/admin/moderation/'+item['moderationCaseId']+'/claim',data={})
            suite.api(admin,'post','/admin/moderation/'+item['moderationCaseId']+'/resolve',data={'decision':'approve','reason':'Owned pagination dataset preparation'})
        data=suite.go(member,'/search?q=music','app-explore-page','/videos/search');assert data['total']>=22
        expect(member['page'].locator('.search-video-card')).to_have_count(len(data['items']))
        entry['resource_ids']=[v['videoId'] for v in created]
        entry['steps']=['Fixture preparation: 22 actual multipart video uploads','Real transcoding and moderation approval through API','Member actual search UI returns more than twenty eligible records','Fixture preparation is distinct from tested UI upload journeys']
    case(suite,member,'REAL-DATASET-SEARCH-PAGINATION','U-DISCOVERY.02','Search contains real multi-page video dataset',dataset,'discovery')
    def many_comments(entry):
        vid=suite.fixtures['video']['videoId'];base='/videos/'+vid+'/comments'
        comments=[]
        for i in range(25):
            comments.append(suite.api(member,'post',base,data={'content':'QC page comment '+suite.run_id+' '+str(i)},expected=201).json())
        suite.fixtures['page_comments']=comments
        data=suite.go(owner,'/studio/comments?channelId='+cid,'app-studio-comments-page','/channels/'+cid+'/comments/manage')
        p=owner['page'];assert data['total']>=25
        p.locator('.list-footer').scroll_into_view_if_needed()
        expect(p.locator('.comment-card')).to_have_count(data['total'],timeout=30000)
        texts=p.locator('.comment-text').all_text_contents();assert len(texts)==len(set(texts))
        entry['resource_ids']=[c['commentId'] for c in comments]
        entry['steps']=['Prepare 25 real Member comments through API','Owner Studio initially loads actual first page','Scroll sentinel → next page','All rows loaded once with no duplicate text/IDs']
    case(suite,owner,'STUDIO-COMMENTS-INFINITE-PAGE','U-STUDIO.08','Studio comments load actual second page once',many_comments,'comments')
