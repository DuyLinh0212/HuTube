"""Previously authorized reviewer loses private-evidence access after actual demotion."""
import hashlib
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['owner','admin','reviewer2'])
    owner,admin,reviewer=(actors[k] for k in ['owner','admin','reviewer2']);p=reviewer['page'];db=LocalDb(config)
    creds=suite.credentials['reviewer2'];original=db.account(creds['email'])['role'];uid=reviewer['identity']['userId']
    assert creds['email'].endswith('@example.test') and original.startswith('qc_reviewer_')
    owned=suite.api(owner,'get','/appeals/my').json();selected=None
    for item in owned:
        if not item.get('evidenceUrl'):continue
        response=suite.api(reviewer,'get','/admin/appeals/'+item['appealId']+'/evidence',expected=(200,404))
        if response.status==200:selected=(item,hashlib.sha256(response.body()).hexdigest());break
    if selected is None:raise PrerequisiteMissing('Owned appeal with an actually readable private attachment required')
    appeal,expected_hash=selected;aid=appeal['appealId'];role_path='/admin/users/'+uid+'/role'
    def login_again():
        p.goto(reviewer['origin']+'/login');p.locator('#email').fill(creds['email']);p.locator('#password').fill(creds['password'])
        response=suite.response(reviewer,'/auth/login',lambda:p.locator('button[type=submit]').click(),method='POST')
        reviewer['headers']['Authorization']='Bearer '+response.json()['accessToken']
        p.wait_for_url('**/account');expect(p.locator('app-account-page')).to_be_visible()
    def revoke(entry):
        suite.go(reviewer,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
        before=suite.api(reviewer,'get','/admin/appeals/'+aid+'/evidence');assert hashlib.sha256(before.body()).hexdigest()==expected_hash
        demoted=False
        try:
            suite.api(admin,'put',role_path,data={'roleCode':'user','reason':'QC private evidence privilege revocation'});demoted=True
            suite.api(reviewer,'get','/admin/appeals/'+aid+'/evidence',expected=(401,403))
            p.goto(reviewer['origin']+'/moderation/appeals');p.wait_for_url(__import__('re').compile(r'/(login|forbidden)(?:\?|$)'))
            expect(p.locator('app-admin-appeals-page')).to_have_count(0)
            suite.evidence(reviewer,entry,'reviewer-access-revoked')
            proof=suite.api(owner,'get','/appeals/'+aid+'/evidence');assert hashlib.sha256(proof.body()).hexdigest()==expected_hash
        finally:
            if demoted:
                suite.api(admin,'put',role_path,data={'roleCode':original,'reason':'Restore exact QC reviewer role after evidence test'})
                login_again()
        restored=suite.api(reviewer,'get','/admin/appeals/'+aid+'/evidence');assert hashlib.sha256(restored.body()).hexdigest()==expected_hash
        assert db.account(creds['email'])['role']==original
        suite.evidence(reviewer,entry,'restored-role-private-evidence')
        entry['resource_ids']=[aid,uid];entry['evidence_sha256']=expected_hash
        entry['steps']=['Read exact Owner attachment successfully as existing authorized Reviewer2','Actual Super Admin demotes only this synthetic reviewer through role API','Previously held JWT cannot read private evidence; direct Admin route is guarded','Owner still reads identical attachment bytes','Finally restore original role through API and perform real UI login','Restored Reviewer reads identical bytes; no attachment or other user changed']
    case(suite,reviewer,'APPEAL-EVIDENCE-ROLE-REVOKED-RESTORED','A-MODERATION.04','Private evidence access follows actual role revocation and restoration',revoke,'appeals')
