"""Actual backend job + Python CF training; isolated S3 protocol sandbox."""
import json
import subprocess
import time
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.admin import live_recommendation
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);snapshot_module(suite,live_recommendation.__file__)
    if not config.get('recommendation_sandbox'):raise PrerequisiteMissing('Requires isolated recommendation service/storage sandbox')
    admin=actors['admin'];member=actors['member'];p=admin['page']
    if config.get('model_transport_proxy'):
        # An empty per-run S3 emulator needs a real active baseline before the
        # previously failing cancellation can be checked. This is preparation,
        # not a rerun/PASS of historical successful-training/UI cases.
        from support.local_db import LocalDb
        ids=LocalDb(config).sql("SELECT job_id FROM recommendation_jobs WHERE actor_user_id=:'actor'::uuid AND kind='model_update' AND status IN ('queued','running','cancelling');",{'actor':admin['identity']['userId']})
        for old in ids.splitlines():
            suite.api(admin,'post','/admin/recommendations/jobs/'+old+'/stop',data={},expected=202)
            suite.report['cleanup'].append({'resource':'interrupted owned sandbox model job','job_id':old,'status':'cancelled through actual API before isolated baseline preparation'})
        p.wait_for_timeout(1000)
        job=suite.api(admin,'post','/admin/recommendations/model-jobs',data={},expected=202).json()
        deadline=time.monotonic()+180
        while time.monotonic()<deadline:
            actual=suite.api(admin,'get','/admin/recommendations/jobs/'+job['jobId']).json()
            if actual['status'] in ('completed','failed','cancelled'):break
            p.wait_for_timeout(500)
        if actual['status']!='completed':raise PrerequisiteMissing('Actual baseline training did not complete: '+str(actual.get('error')))
        suite.report['setup'].append({'resource':'isolated actual active model','job_id':job['jobId'],
            'status':'prepared','meaning':'Prerequisite for cancellation only; historical successful-training cases were not rerun or counted as new PASS'})
        return
    suite.go(member,'/account','app-account-page','/account/profile')
    suite.report['recommendation_environment']=config['recommendation_storage_kind']
    original=suite.case
    def prefixed(actor,id,*args,**kwargs):return original(actor,'FULL-'+id,*args,**kwargs)
    suite.case=prefixed
    try:live_recommendation.run(suite,admin)
    finally:suite.case=original
    def poll(jid,allowed=('completed',),limit=180):
        deadline=time.monotonic()+limit
        while time.monotonic()<deadline:
            item=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()
            if item['status'] in ('completed','failed','cancelled'):
                assert item['status'] in allowed,'Actual job ended '+item['status']+': '+str(item.get('error'))
                return item
            p.wait_for_timeout(1000)
        raise AssertionError('Actual model job failed to reach terminal state')
    def training(entry):
        suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        suite.api(member,'post','/admin/recommendations/model-jobs',data={},expected=403)
        job=suite.response(admin,'/admin/recommendations/model-jobs',lambda:p.locator('.update-panel button.primary').click(),method='POST',status=202).json()
        jid=job['jobId'];actual=poll(jid);assert actual['jobId']==jid and not actual.get('error')
        state=suite.api(admin,'get','/admin/recommendations/status').json();assert state['state']=='ready' and state['modelVersion'] and state['csvSha256']
        root=Path(__file__).resolve().parents[2]
        result=subprocess.run([str(root/'.state/recommendation-sandbox/.venv/Scripts/python.exe'),
            str(root/'support/recommendation_sandbox.py'),'--audit',str(suite.run_dir/'recommendation-trained-model')],capture_output=True,text=True,encoding='utf-8',timeout=30)
        assert result.returncode==0,'Actual published artifact audit failed'
        audit=json.loads(result.stdout);assert audit['manifest']['modelVersion']==state['modelVersion']
        assert audit['manifest']['csvSha256']==state['csvSha256']
        assert suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()['status']=='completed'
        suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        expect(p.locator('.model-meta')).to_contain_text(state['modelVersion'])
        entry['resource_ids']=[jid,state['modelVersion']]
        entry['model_audit']='recommendation-trained-model/audit.json'
        entry['steps']=['Member cannot queue training','Admin UI starts real persisted job; preserve job ID',
            'Actual Python CF training completes and publishes CSV/model/manifest to isolated S3 emulator',
            'Read actual artifact bytes; verify both SHA256 and ZIP contents','Reload Admin shows published version and persisted completed job']
    case(suite,admin,'RECOMMENDATION-SUCCESSFUL-TRAINING-DEPENDENCY','A-RECOMMENDATION.02','Successful actual CF training and published artifact integrity',training,'recommendation')
    if config.get('recommendation_training_only'):
        suite.report.setdefault('group_skips',[]).append({'group':'recommendation-coverage',
            'reason':'Training/UI subset only. Cancellation and restart are evaluated separately by model-cancellation-boundary against actual service responses; this subset makes no cancellation assertion.'})
        return
    queued_job={}
    def cancel(entry):
        queued=suite.api(admin,'post','/admin/recommendations/model-jobs',data={},expected=202).json();jid=queued['jobId']
        queued_job.update(queued)
        suite.api(member,'post','/admin/recommendations/jobs/'+jid+'/stop',data={},expected=403)
        entry['resource_ids']=[jid]
        entry['steps']=['Queue actual model update','Member cannot cancel','Try model cancellation on actual stop API; require 202 and persisted cancelled state']
        entry['implementation_note']='Current StopAsync only selects Kind=simulation and model tab has no cancel button; actual unsupported response must not be disguised as a passing cancel'
        suite.api(admin,'post','/admin/recommendations/jobs/'+jid+'/stop',data={},expected=202)
        poll(jid,allowed=('cancelled',))
    case(suite,admin,'RECOMMENDATION-MODEL-CANCEL-REAL','A-RECOMMENDATION.02','Cancel actual model update without fabricating terminal state',cancel,'recommendation')
    if queued_job:poll(queued_job['jobId'],allowed=('cancelled','completed'))
    def restart(entry):
        restarted=suite.api(admin,'post','/admin/recommendations/model-jobs',data={},expected=202).json();newid=restarted['jobId']
        poll(newid)
        old_id=queued_job['jobId'];assert newid!=old_id
        old=suite.api(admin,'get','/admin/recommendations/jobs/'+old_id).json();assert old['status'] in ('cancelled','completed')
        suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        entry['resource_ids']=[old_id,newid]
        entry['steps']=['Prior terminal job remains addressable','Start a new immutable job ID','Actual training completes again','Reload Admin status shows published model']
    case(suite,admin,'RECOMMENDATION-RESTART-REAL','A-RECOMMENDATION.02','Restart model training under a distinct persisted job ID',restart,'recommendation')
