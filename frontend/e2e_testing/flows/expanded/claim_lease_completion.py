"""Real concurrent acquisition and expired/stale decisions on disposable media.

Only the deadline of this run's owned lease is shortened to avoid a fifteen-minute
sleep. Status, reviewer, claim ID and decision are always written by the API.
Exact fifteen-minute boundaries are additionally covered by ClaimLeasePolicyTests.
"""
import concurrent.futures,json,shutil,subprocess,threading,time
from datetime import datetime,timezone
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from flows.expanded.channels import create_channel
from flows.expanded.media_deep import review_row
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    ensure_actor_pages(suite,actors,['admin','member','reviewer1','reviewer2'])
    admin,member,r1,r2=(actors[k] for k in ['admin','member','reviewer1','reviewer2'])
    identity(suite,config,'leaseowner');owner=suite.actor('lease-owner','user','leaseowner')
    channel=create_channel(suite,owner,'leaseowner');videos=[];queue={};db=LocalDb(config)
    def claim(actor,base):return suite.api(actor,'post',base+'/claim',data={}).json()
    def expire(table,key,id,token):
        assert table in ('moderation_cases','appeals') and key in ('moderation_case_id','appeal_id')
        value=db.sql('UPDATE '+table+' SET claim_expires_at=now()+interval \'2 seconds\' WHERE '+key+'=:\'id\'::uuid AND claim_id=:\'token\'::uuid RETURNING claim_id;',{'id':id,'token':token})
        assert value==token
        owner['page'].wait_for_timeout(2400)
    def denied(actor,base,action,data,code):
        response=suite.api(actor,'post',base+'/'+action,data=data,expected=409)
        assert response.json()['code']==code,(response.json(),code)
    def state(vid):return suite.api(owner,'get','/videos/'+vid).json()
    try:
        def prepare(entry):
            file=suite.run_dir/'lease-real-source.mp4'
            subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=12','-t','3','-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
            for i in range(3):
                video=suite.api(owner,'post','/videos',multipart={'ChannelId':channel['channelId'],'Title':'QC lease '+suite.run_id+' '+str(i),'Description':'Owned actual media lease fixture','Visibility':'public','Duration':'3','SourceQuality':'360p','AllowComments':'true','Video':{'name':'lease.mp4','mimeType':'video/mp4','buffer':file.read_bytes()}},expected=201).json();videos.append(video['videoId'])
            deadline=time.monotonic()+180
            while time.monotonic()<deadline:
                items=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
                queue.update({v['videoId']:v for v in items if v['videoId'] in videos})
                if len(queue)==3:break
                owner['page'].wait_for_timeout(300)
            assert len(queue)==3
            entry['resource_ids']=videos[:];entry['steps']=['Fresh verified owner and actual UI-created channel','Three actual MP4 multipart uploads finish real processing','Actual pending moderation queue yields three distinct case IDs']
        if not case(suite,owner,'LEASE-REAL-MEDIA-DATASET','X-MODERATION.01','Create independent actual media for lease transitions',prepare,'moderation'):return

        def moderation(entry):
            vid=videos[0];item=queue[vid];mid=item['moderationCaseId'];base='/admin/moderation/'+mid
            row=review_row(suite,r1,item,0)
            lease=suite.response(r1,base+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST').json()
            expires=datetime.fromisoformat(lease['claimExpiresAt'].replace('Z','+00:00'));assert 890<(expires-datetime.now(timezone.utc)).total_seconds()<=900
            same=claim(r1,base);assert same==lease
            denied(r2,base,'claim',{},'CASE_ALREADY_CLAIMED')
            denied(r1,base,'resolve',{'decision':'approve','reason':'Missing claim','claimId':None},'CLAIM_STALE')
            row=review_row(suite,r1,item,1);row.locator('.table-action:not(.subtle)').first.click()
            r1['page'].locator('.decision-column input[type=text]').fill('QC expired tab must not approve')
            expire('moderation_cases','moderation_case_id',mid,lease['claimId'])
            suite.response(r1,base+'/resolve',lambda:r1['page'].locator('.decision-button.approve').click(),method='POST',status=409)
            assert state(vid)['moderationStatus']!='approved'
            row2=review_row(suite,r2,item,0);expect(row2).to_contain_text(__import__('re').compile('hết hạn|expired',__import__('re').I))
            new=suite.response(r2,base+'/claim',lambda:row2.locator('.table-action.primary').click(),method='POST').json();assert new['claimId']!=lease['claimId']
            denied(r1,base,'release',{'claimId':lease['claimId']},'CLAIM_STALE')
            denied(r1,base,'resolve',{'decision':'approve','reason':'Stale tab','claimId':lease['claimId']},'CLAIM_STALE')
            suite.api(r2,'post',base+'/release',data={'claimId':new['claimId']})
            latest=claim(r2,base);assert latest['claimId']!=new['claimId']
            denied(r2,base,'resolve',{'decision':'approve','reason':'Old own token','claimId':new['claimId']},'CLAIM_STALE')
            suite.api(r2,'post',base+'/resolve',data={'decision':'approve','reason':'Valid reclaimed lease','claimId':latest['claimId']})
            assert state(vid)['moderationStatus']=='approved'
            suite.api(r2,'post',base+'/resolve',data={'decision':'approve','reason':'Duplicate','claimId':latest['claimId']},expected=409)
            suite.go(member,'/watch/'+vid,'app-watch-page');member['page'].wait_for_function('()=>document.querySelector("video")?.readyState>=2')
            entry['resource_ids']=[vid,mid,lease['claimId'],new['claimId'],latest['claimId']]
            entry['steps']=['Actual UI claim returns server deadline approximately 900 seconds; repeat does not renew','Independent reviewer cannot steal active lease; missing token cannot decide','Shorten only owned deadline; original open tab actual approval rejected 409 without target mutation','Expired row visible as pending; Reviewer2 UI reclaims with a new token','Old actor/token and same actor after release/reclaim are denied','Valid new token approves once; duplicate decision denied; Member decodes actual restored video']
        case(suite,r1,'LEASE-EXPIRED-STALE-MODERATION','X-MODERATION.01','Expired tab and stale claim cannot decide actual video',moderation,'moderation')

        def race(entry):
            mid=queue[videos[1]]['moderationCaseId'];base='/admin/moderation/'+mid;barrier=threading.Barrier(2)
            inputs=[(actor['name'],dict(actor['headers'])) for actor in (r1,r2)]
            def attempt(value):
                name,headers=value;headers['Content-Type']='application/json';barrier.wait(timeout=5)
                try:
                    with urlopen(Request(config['api_url']+base+'/claim',data=b'{}',headers=headers,method='POST'),timeout=20) as response:return name,response.status,json.loads(response.read())
                except HTTPError as error:return name,error.code,json.loads(error.read())
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(attempt,inputs))
            assert sorted(value[1] for value in results)==[200,409],results
            winner=next(value for value in results if value[1]==200);loser=next(value for value in results if value[1]==409)
            assert loser[2]['code']=='CASE_ALREADY_CLAIMED'
            actor=next(a for a in (r1,r2) if a['name']==winner[0]);lease=winner[2]
            actual=db.sql('SELECT json_build_object(\'reviewer\',reviewer_id,\'claim\',claim_id,\'status\',status) FROM moderation_cases WHERE moderation_case_id=:\'id\'::uuid;',{'id':mid});actual=json.loads(actual)
            assert actual=={'reviewer':actor['identity']['userId'],'claim':lease['claimId'],'status':'reviewing'}
            suite.api(actor,'post',base+'/release',data={'claimId':lease['claimId']})
            entry['resource_ids']=[mid,lease['claimId']];entry['simultaneous_statuses']=[v[1] for v in results]
            entry['steps']=['Two distinct authenticated reviewer HTTP clients released simultaneously by one barrier','Exactly one 200 and one 409 on actual PostgreSQL row lock','Persisted reviewer, token and status match sole winner','Actual release cleans owned lease; no state injected']
        if not config.get('claim_lease_failed_only'):
            case(suite,r2,'LEASE-CONCURRENT-ATOMIC-CLAIM','X-MODERATION.01','Concurrent independent reviewers have one actual claim winner',race,'moderation')

        def report(entry):
            vid=videos[0];violations=suite.api(member,'get','/violation-types').json();violation=violations[0]
            suite.api(member,'post','/reports',data={'targetType':'video','targetId':vid,'violationTypeId':violation['violationTypeId'],'description':'QC lease report '+suite.run_id},expected=(200,201))
            items=suite.api(r1,'get','/admin/reports/cases',params={'page':1,'pageSize':100}).json()['items'];item=next(v for v in items if v['targetId']==vid);mid=item['caseId'];base='/admin/reports/cases/'+mid
            old=claim(r1,base);detail=suite.api(r1,'get',base).json();ids=[v['reportId'] for v in detail['reports']]
            payload={'reportIds':ids,'disposition':'rejected','reason':'Owned classification','claimId':old['claimId']}
            expire('moderation_cases','moderation_case_id',mid,old['claimId'])
            denied(r1,base,'dispositions',payload,'CLAIM_EXPIRED')
            denied(r1,base,'resolve',{'decision':'dismiss','reason':'Expired','claimId':old['claimId']},'CLAIM_EXPIRED')
            new=claim(r2,base);assert old['claimId']!=new['claimId']
            denied(r1,base,'dispositions',payload,'CLAIM_STALE')
            payload['claimId']=new['claimId'];suite.api(r2,'post',base+'/dispositions',data=payload,expected=204)
            suite.api(r2,'post',base+'/resolve',data={'decision':'dismiss','reason':'Reviewed and dismissed','claimId':new['claimId']})
            final=suite.api(r2,'get',base).json();assert final['case']['status']=='resolved'
            assert state(vid)['moderationStatus']=='approved';suite.api(member,'get','/videos/'+vid+'/playback')
            suite.go(r2,'/moderation/reports','app-admin-reports-page','/admin/reports/cases')
            entry['resource_ids']=[vid,mid,*ids,old['claimId'],new['claimId']]
            entry['steps']=['Member submits real content report, creating actual grouped case','Expired claim cannot classify or resolve','Independent reviewer reclaims; old classification token denied','New token classifies then dismisses; target stays published and playable','Reload actual Report UI after persisted resolution']
        case(suite,r2,'LEASE-REPORT-CLASSIFICATION-EXPIRY','X-MODERATION.01','Report classification and resolution both enforce lease',report,'reports')

        def appeal(entry):
            vid=videos[2];mid=queue[vid]['moderationCaseId'];base='/admin/moderation/'+mid
            claim(r1,base);policies=suite.api(r1,'get','/policies').json();policy=policies[0]['code']
            suite.api(r1,'post',base+'/resolve',data={'decision':'reject','policyCode':policy,'reason':'Owned lease appeal fixture'})
            value=suite.api(owner,'post','/appeals',data={'targetType':'video','targetId':vid,'moderationCaseId':mid,'reason':'Owned appeal lease boundary','evidenceNote':'Actual test media'},expected=201).json();aid=value['appealId'];base='/admin/appeals/'+aid
            suite.api(r1,'post',base+'/claim',data={},expected=(403,409))
            old=claim(r2,base);expire('appeals','appeal_id',aid,old['claimId'])
            denied(r2,base,'resolve',{'decision':'approve','reviewNote':'Expired','claimId':old['claimId']},'CLAIM_EXPIRED')
            new=claim(admin,base);assert old['claimId']!=new['claimId']
            denied(r2,base,'release',{'claimId':old['claimId']},'CLAIM_STALE')
            denied(r2,base,'resolve',{'decision':'approve','reviewNote':'Stale','claimId':old['claimId']},'CLAIM_STALE')
            suite.api(admin,'post',base+'/resolve',data={'decision':'approve','reviewNote':'Independent valid reclaimed lease','claimId':new['claimId']})
            assert state(vid)['moderationStatus']=='approved';suite.api(member,'get','/videos/'+vid+'/playback')
            suite.api(admin,'post',base+'/resolve',data={'decision':'approve','reviewNote':'Duplicate','claimId':new['claimId']},expected=(400,409))
            suite.go(admin,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
            entry['resource_ids']=[vid,mid,aid,old['claimId'],new['claimId']]
            entry['steps']=['Original deciding reviewer cannot claim own decision appeal','Independent Reviewer2 actual claim expires; decision denied','Admin independently reclaims with rotated token; previous reviewer cannot release/resolve','Valid claim approval restores published actual playback; terminal replay denied','Reload actual Appeal UI; only this run owned claim deadline was shortened']
        if not config.get('claim_lease_failed_only'):
            case(suite,admin,'LEASE-APPEAL-EXPIRY-SOD','X-MODERATION.01','Appeal lease preserves separation of duties and rejects stale decisions',appeal,'appeals')
    finally:
        for vid in videos:suite.api(owner,'delete','/videos/'+vid,expected=(204,404))
        suite.release_actor(owner)
