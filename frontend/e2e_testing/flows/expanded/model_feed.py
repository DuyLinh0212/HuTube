"""Positive CF dataset with an intentionally unseen, eligible candidate."""
import json,time
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if not config.get('recommendation_sandbox'):raise PrerequisiteMissing('Real model service required')
    ensure_actor_pages(suite,actors,['admin'])
    admin=actors['admin'];p=admin['page'];prepared=[]
    try:
        for key in ['feed_viewer','feed_peer']:
            identity(suite,config,key);prepared.append(suite.actor(key,'user',key))
        viewer,peer=prepared
        def feed(entry):
            pool=suite.api(admin,'get','/admin/videos',params={'pageSize':100,'status':'published','visibility':'public'}).json()['items']
            eligible=[]
            for item in pool:
                value=suite.api(admin,'get','/videos/'+item['videoId']).json()
                if value['status']=='published' and value['moderationStatus']=='approved' and value['visibility']=='public':eligible.append(value)
                if len(eligible)==3:break
            if len(eligible)<3:raise PrerequisiteMissing('Need three actual eligible public videos for unseen CF fixture')
            ids=[v['videoId'] for v in eligible]
            # Fixture preparation uses real rating mutations; never write the
            # matrix/model/recommendation results or alter viewer history in SQL.
            suite.api(viewer,'put','/videos/'+ids[0]+'/rating',data={'score':5})
            for vid in ids:suite.api(peer,'put','/videos/'+vid+'/rating',data={'score':5})
            suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
            p.locator('.algorithm-config select').select_option('item_based')
            p.locator('.score-config select').select_option('weighted')
            for field in p.locator('.score-weights input').all():field.fill('1')
            queued=suite.response(admin,'/admin/recommendations/model-jobs',lambda:p.locator('.update-panel button.primary').click(),method='POST',status=202).json()
            jid=queued['jobId'];deadline=time.monotonic()+180
            while time.monotonic()<deadline:
                job=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()
                if job['status'] in ('failed','completed'):
                    assert job['status']=='completed','Actual CF training failed';break
                p.wait_for_timeout(500)
            else:raise AssertionError('Actual CF fixture training timeout')
            state=suite.api(admin,'get','/admin/recommendations/status').json()
            response=viewer['context'].request.post('http://127.0.0.1:53493/internal/recommendations',headers={'X-Service-Token':'hutube-qc-model-service'},
                data={'userId':viewer['identity']['userId'],'limit':100,'excludeItemIds':[]})
            assert response.status==200
            actual=response.json();assert actual['modelVersion']==state['modelVersion']
            ranked=[v['itemId'] for v in actual['items']]
            assert any(vid in ranked for vid in ids[1:]),'Actual trained model did not rank the eligible unseen fixture'
            value=suite.go(viewer,'/home','app-home-page','/feed/home')
            ordered=[v['videoId'] for v in value['items'] if v['videoId'] in ranked and not v.get('isPromoted')]
            assert ordered,'User Home did not include actual model candidates'
            assert ordered==sorted(ordered,key=ranked.index),'User feed changed the model candidate ranking'
            link=viewer['page'].locator('a[href="/watch/'+ordered[0]+'"]')
            expect(link.first).to_be_visible()
            entry['resource_ids']=[viewer['identity']['userId'],peer['identity']['userId'],jid,state['modelVersion'],*ids]
            entry['model_candidate_count']=len(ranked);entry['feed_model_candidate_count']=len(ordered)
            entry['steps']=['Create independent synthetic viewer/peer through actual registration and verification','Viewer rates only one real public video; peer rates three through actual APIs','Actual Admin weighted item-based model trains and publishes the fixture interactions','Real internal inference returns unseen eligible IDs under the active version','Actual User Home contains model candidates in service order; exact watch links visible']
        case(suite,viewer,'MODEL-CONFIG-FEED-ACTIVE-ORDER','A-RECOMMENDATION.01','Active weighted model supplies the actual User feed',feed,'recommendation')
    finally:
        for actor in prepared:suite.release_actor(actor)
