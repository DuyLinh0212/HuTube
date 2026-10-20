import time
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.admin.live_recommendation import run as matrix
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);admin,member=actors['admin'],actors['member'];original=suite.case
    from flows.admin import live_recommendation
    snapshot_module(suite,live_recommendation.__file__)
    def fresh(actor,id,*args,**kwargs):return original(actor,'FULL-'+id,*args,**kwargs)
    suite.case=fresh
    try:matrix(suite,admin)
    finally:suite.case=original
    job={}
    def failure(entry):
        p=admin['page'];suite.go(admin,'/recommendations','app-recommendations-page')
        suite.api(member,'post','/admin/recommendations/model-jobs',data={},expected=403)
        response=suite.response(admin,'/admin/recommendations/model-jobs',lambda:p.locator('.update-panel button.primary').click(),method='POST',status=202).json();job.update(response)
        jid=job['jobId'];entry['resource_ids']=[jid]
        deadline=time.monotonic()+60
        while time.monotonic()<deadline:
            actual=suite.api(admin,'get','/admin/recommendations/jobs/'+jid).json()
            if actual['status'] in ('failed','completed','cancelled'):break
            p.wait_for_timeout(1000)
        assert actual['jobId']==jid
        if actual['status']=='failed':
            assert actual['error'];expect(p.locator('.job-error')).to_be_visible(timeout=15000)
            entry['observed_dependency']='Actual queued job failed because the local test environment has no configured recommendation/R2 training service; successful training is not claimed'
        else:assert actual['status']=='completed','Job did not reach a terminal state'
        entry['steps']=['Ordinary Member cannot start training','Super Admin actual UI starts job → 202 immutable ID','Poll real persisted job','Failed dependency produces actual UI error instead of false success']
    case(suite,admin,'RECOMMENDATION-JOB-ID-ERROR-STATE','A-RECOMMENDATION.02','Recommendation job preserves ID and shows failure',failure,'recommendation')
    def train(entry):raise PrerequisiteMissing('Successful model training/cancel/restart requires configured recommendation service and isolated model storage; see actual matrix/job attempt results, no successful training is claimed')
    case(suite,admin,'RECOMMENDATION-SUCCESSFUL-TRAINING-DEPENDENCY','A-RECOMMENDATION.02','Successful training and job recovery prerequisites',train,'recommendation')
