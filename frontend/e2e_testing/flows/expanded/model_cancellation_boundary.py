"""Actual running-job UI cancellation while a real training submission is in flight."""
import json,time,uuid
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing
from support import model_transport_proxy

def run(suite,config,actors):
    snapshot_module(suite,__file__);snapshot_module(suite,model_transport_proxy.__file__)
    if not config.get('model_transport_root'):raise PrerequisiteMissing('Actual model transport boundary proxy required')
    admin,member=actors['admin'],actors['member'];p=admin['page'];root=Path(config['model_transport_root']);root.mkdir(exist_ok=True)
    state={};before=suite.api(admin,'get','/admin/recommendations/status').json()['modelVersion'];assert before
    def wait_file(name,id):
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            try:
                data=json.loads((root/name).read_text(encoding='utf-8'))
                if data['id']==id:return data
            except (FileNotFoundError,PermissionError,json.JSONDecodeError):pass
            p.wait_for_timeout(40)
        raise AssertionError('Actual model transport checkpoint not reached: '+name)
    def poll(jid,status):
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            job=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()
            if job['status'] in ('completed','cancelled','failed'):
                assert job['status']==status,'Actual model ended '+job['status']+': '+str(job.get('error'));return job
            p.wait_for_timeout(250)
        raise AssertionError('Model job terminal deadline exceeded')
    def cancel(entry):
        id=uuid.uuid4().hex;state['arm_id']=id
        suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        (root/'arm.json').write_text(json.dumps({'id':id}),encoding='utf-8')
        queued=suite.response(admin,'/admin/recommendations/model-jobs',lambda:p.locator('.update-panel button.primary').click(),method='POST',status=202).json();jid=queued['jobId'];state['job_id']=jid
        checkpoint=wait_file('applied.json',id);assert checkpoint['jobId']==jid
        actual=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json();assert actual['status']=='running' and actual['step']=='train_model'
        suite.api(member,'post','/admin/recommendations/jobs/'+jid+'/stop',data={},expected=403)
        expect(p.locator('.job-card .stop-button')).to_be_visible()
        suite.response(admin,'/admin/recommendations/jobs/'+jid+'/stop',lambda:p.locator('.job-card .stop-button').click(),method='POST',status=202)
        poll(jid,'cancelled')
        (root/'release.json').write_text(json.dumps({'id':id}),encoding='utf-8')
        released=wait_file('released.json',id);assert released['by_test']
        p.wait_for_timeout(3500)
        assert suite.api(admin,'get','/admin/recommendations/status').json()['modelVersion']==before
        # Replayed stop is a real idempotent endpoint call, never a state fixture.
        suite.api(admin,'post','/admin/recommendations/jobs/'+jid+'/stop',data={},expected=202)
        assert poll(jid,'cancelled')['jobId']==jid
        service=admin['context'].request.get('http://127.0.0.1:53493/internal/model/jobs/'+jid,headers={'X-Model-Admin-Token':'hutube-qc-model-admin'})
        assert service.status==200 and service.json()['status']=='cancelled'
        entry['resource_ids']=[jid,before];entry['transport_checkpoint']=checkpoint
        entry['steps']=['Start actual model update in Admin UI with prior real trained model active','Transparent loopback proxy holds only the real HTTP training submission before upstream delivery; no response is fabricated','Actual persisted job is running/train_model; Member cancellation forbidden','Actual visible model Stop button sends 202 and backend persists cancelled','Release delayed original submission: real Python durable cancellation rejects it and active manifest remains unchanged','Repeat stop preserves same cancelled immutable job; provider service confirms cancelled']
    try:
        if not case(suite,admin,'RECOMMENDATION-MODEL-CANCEL-REAL','A-RECOMMENDATION.02','Actual running model cancellation never publishes a delayed submission',cancel,'recommendation'):return
        def restart(entry):
            queued=suite.api(admin,'post','/admin/recommendations/model-jobs',data={},expected=202).json();jid=queued['jobId'];assert jid!=state['job_id']
            poll(jid,'completed');current=suite.api(admin,'get','/admin/recommendations/status').json();assert current['modelVersion'] and current['modelVersion']!=before
            old=poll(state['job_id'],'cancelled')
            suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status');expect(p.locator('.model-meta')).to_contain_text(current['modelVersion'])
            entry['resource_ids']=[old['jobId'],jid,current['modelVersion']]
            entry['steps']=['New immutable job after cancellation','Actual Python training completes and publishes a different version','Old job remains cancelled/addressable','Reloaded Admin active version agrees with backend/storage']
        case(suite,admin,'RECOMMENDATION-RESTART-REAL','A-RECOMMENDATION.02','Actual training restarts after cancellation under a new persisted job ID',restart,'recommendation')
    finally:
        if state.get('arm_id'):(root/'release.json').write_text(json.dumps({'id':state['arm_id']}),encoding='utf-8')
