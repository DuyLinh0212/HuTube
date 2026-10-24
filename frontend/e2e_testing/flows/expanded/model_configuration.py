"""Execute actual score-mode/algorithm combinations without simulator data."""
import json,subprocess,time
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing

FEATURES=['rating','like','dislike','watch','comment','subscribe']
ALGORITHMS=['item_based','incremental','batch_incremental','batch_incremental_partial_topk']
def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if not config.get('recommendation_sandbox'):raise PrerequisiteMissing('Actual Python/model storage sandbox required')
    ensure_actor_pages(suite,actors,['admin','member','reviewer1'])
    admin,member,limited=actors['admin'],actors['member'],actors['reviewer1'];p=admin['page'];root=Path(__file__).resolve().parents[2]
    def ui():suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
    def poll(jid):
        deadline=time.monotonic()+150
        while time.monotonic()<deadline:
            value=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()
            if value['status'] in ('failed','completed','cancelled'):
                assert value['status']=='completed','Actual training ended '+value['status'];return value
            p.wait_for_timeout(1000)
        raise AssertionError('Actual model training timeout')
    def boundaries(entry):
        ui()
        suite.api(member,'get','/admin/recommendations/status',expected=403)
        suite.api(limited,'post','/admin/recommendations/model-jobs',data={'mode':'average'},expected=403)
        for body,code in [({'mode':'invalid'},'INVALID_SCORE_MODE'),({'modelAlgorithm':'invalid'},'INVALID_MODEL_ALGORITHM'),
                          ({'mode':'weighted','weights':{'rating':-1}},'INVALID_SCORE_WEIGHTS'),
                          ({'mode':'weighted','weights':{}},'INVALID_SCORE_WEIGHTS'),
                          ({'mode':'weighted','weights':{'unknown':1}},'INVALID_SCORE_FEATURE')]:
            response=suite.api(admin,'post','/admin/recommendations/model-jobs',data=body,expected=400)
            assert response.json()['code']==code
        p.locator('.score-config select').select_option('weighted')
        for field in p.locator('.score-weights input').all():field.fill('0')
        before=len([e for e in suite.report['http_statuses'] if e['method']=='POST' and e['path'].endswith('/model-jobs')])
        p.locator('.update-panel button.primary').click()
        expect(p.locator('.error,.alert.error,app-result-notice[tone=error]').first).to_be_visible()
        assert before==len([e for e in suite.report['http_statuses'] if e['method']=='POST' and e['path'].endswith('/model-jobs')])
        entry['steps']=['Ordinary Member and non-super Reviewer denied by actual API','Unknown mode/algorithm/feature and negative/all-zero weights rejected with exact codes','UI all-zero weights validation prevents training POST']
    case(suite,admin,'MODEL-CONFIG-PERMISSION-VALIDATION','A-RECOMMENDATION.01','Configuration guards and weight validation',boundaries,'recommendation')
    latest={}
    for algorithm in ALGORITHMS:
        for mode in ['average','weighted']:
            def train(entry,algorithm=algorithm,mode=mode):
                ui();p.locator('.algorithm-config select').select_option(algorithm);p.locator('.score-config select').select_option(mode)
                weights={name:(index+1)/10 for index,name in enumerate(FEATURES)}
                if mode=='weighted':
                    for index,field in enumerate(p.locator('.score-weights input').all()):field.fill(str(weights[FEATURES[index]]))
                queued=suite.response(admin,'/admin/recommendations/model-jobs',lambda:p.locator('.update-panel button.primary').click(),method='POST',status=202).json()
                jid=queued['jobId'];job=poll(jid);payload=json.loads(job['payloadJson'])
                assert payload['mode']==mode and payload['modelAlgorithm']==algorithm
                target=suite.run_dir/('model-config-'+algorithm+'-'+mode)
                result=subprocess.run([str(root/'.state/recommendation-sandbox/.venv/Scripts/python.exe'),str(root/'support/recommendation_sandbox.py'),'--audit',str(target)],capture_output=True,text=True,encoding='utf-8',timeout=30)
                assert result.returncode==0,'Actual published manifest/artifact integrity audit failed'
                audit=json.loads(result.stdout);manifest=audit['manifest']
                assert manifest['modelAlgorithm']==algorithm and manifest['scoreAggregation']['mode']==mode
                if mode=='weighted':
                    for feature,value in weights.items():assert abs(manifest['scoreAggregation']['weights'][feature]-value/max(weights.values()))<1e-10
                state=suite.api(admin,'get','/admin/recommendations/status').json();assert state['modelVersion']==manifest['modelVersion']
                ui();expect(p.locator('.model-meta')).to_contain_text(state['modelVersion'])
                entry['resource_ids']=[jid,manifest['modelVersion']];entry['model_audit']=str(target.relative_to(suite.run_dir)/'audit.json')
                entry['steps']=['Select actual UI '+algorithm+' / '+mode,'Start/poll real Python model training under immutable job ID','Read persisted normalized request payload','Audit actual manifest, CSV and ZIP hashes; verify published algorithm/mode/weights','Reload Admin active model version agrees with backend/storage','Loopback Moto storage; no simulation/seeder invoked']
                latest.update(mode=mode,algorithm=algorithm,weights=weights)
            case(suite,admin,'MODEL-CONFIG-'+algorithm.upper()+'-'+mode.upper(),'A-RECOMMENDATION.01','Actual model publish '+algorithm+' / '+mode,train,'recommendation')
    def reload_config(entry):
        assert latest.get('mode')=='weighted','Weighted model publication prerequisite failed'
        ui();entry['steps']=['Last real published manifest uses weighted score mode','Reload actual configuration UI','UI should reflect active weighted configuration rather than silently reset to average']
        expect(p.locator('.score-config select')).to_have_value('weighted')
    case(suite,admin,'MODEL-CONFIG-ACTIVE-RELOAD','A-RECOMMENDATION.01','Active configuration survives UI reload',reload_config,'recommendation')
    def active_feed(entry):
        from support.local_db import LocalDb
        ensure_actor_pages(suite,actors,['member']);viewer=actors['member'];uid=viewer['identity']['userId']
        excluded=json.loads(LocalDb(config).sql("SELECT coalesce(json_agg(DISTINCT video_id),'[]') FROM viewing_histories WHERE user_id=:'id'::uuid;",{'id':uid}))
        state=suite.api(admin,'get','/admin/recommendations/status').json()
        response=viewer['context'].request.post('http://127.0.0.1:53493/internal/recommendations',
            headers={'X-Service-Token':'hutube-qc-model-service'},data={'userId':uid,'limit':100,'excludeItemIds':excluded})
        entry['service_http_status']=response.status
        assert response.status==200,'Actual model could not recommend for the real fixture Member'
        actual=response.json();assert actual['modelVersion']==state['modelVersion']
        ids=[item['itemId'] for item in actual['items']]
        if not ids:raise PrerequisiteMissing('Actual trained model returned no unseen candidates for fixture Member; feed ordering cannot be certified from empty recommendations')
        feed=suite.go(viewer,'/home','app-home-page','/feed/home')
        ordered=[item['videoId'] for item in feed['items'] if item['videoId'] in ids and not item.get('isPromoted')]
        assert ordered,'Actual User feed did not contain eligible model candidates'
        assert ordered==sorted(ordered,key=ids.index),'Actual feed lost the active model ranking order'
        assert all(item['visibility']=='public' for item in feed['items'])
        links=viewer['page'].locator('a[href="/watch/'+ordered[0]+'"]');expect(links.first).to_be_visible()
        suite.evidence(viewer,entry,'active-model-in-user-feed')
        entry['resource_ids']=[uid,state['modelVersion'],*ordered]
        entry['steps']=['Actual active weighted manifest/version after real Python training','Read real viewer history exclusions','Call actual internal inference service with QC service credential; version agrees','Actual User Home/API includes eligible model candidates in service ranking order','Public visibility and exact watch link asserted; no mocked recommendation response']
    case(suite,member,'MODEL-CONFIG-FEED-ACTIVE-ORDER','A-RECOMMENDATION.01','Published weighted model actually supplies User feed order',active_feed,'recommendation')
