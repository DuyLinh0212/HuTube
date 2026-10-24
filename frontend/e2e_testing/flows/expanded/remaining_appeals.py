"""Missing appeal decisions, real private evidence and failed-decision persistence."""
import json
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.media_deep import upload_fixture, submit_public
from flows.expanded.channels import png_bytes
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    from support.actor_readiness import ensure_actor_pages
    ensure_actor_pages(suite, actors, ['owner','member','reviewer1','reviewer2','admin'])
    owner,member,r1,r2,admin=(actors[k] for k in ['owner','member','reviewer1','reviewer2','admin'])
    video=upload_fixture(suite,owner,member,'APPEAL-BRANCHES')
    pending=submit_public(suite,owner,admin,video); vid=video['videoId']; mid=pending['moderationCaseId']
    policies=suite.api(owner,'get','/policies').json()
    if isinstance(policies,dict): policies=policies['items']
    policy=next(p['code'] for p in policies)
    suite.api(r1,'post','/admin/moderation/'+mid+'/claim',data={})
    suite.api(r1,'post','/admin/moderation/'+mid+'/resolve',data={'decision':'reject','policyCode':policy,'reason':'QC appeal branch prerequisite'})
    request={'targetType':'video','targetId':vid,'reason':'QC appeal branch '+suite.run_id,'moderationCaseId':mid}
    appeal=suite.api(owner,'post','/appeals',data=request,expected=201).json(); aid=appeal['appealId']
    p=r2['page']

    def read():
        return next(a for a in suite.api(owner,'get','/appeals/my').json() if a['appealId']==aid)

    def ui():
        suite.go(r2,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
        p.locator('.status-tabs button').first.click()
        row=p.locator('tbody tr').filter(has_text=vid);expect(row).to_have_count(1)
        return row

    def invalid(entry):
        ui()
        for name,mime,blob,code in [('empty.png','image/png',b'','EVIDENCE_REQUIRED'),
                                   ('fake.png','image/png',b'not-a-png','EVIDENCE_SIGNATURE_INVALID'),
                                   ('evidence.txt','text/plain',b'QC evidence','EVIDENCE_TYPE_INVALID')]:
            result=suite.api(owner,'post','/appeals/'+aid+'/evidence',multipart={'file':{'name':name,'mimeType':mime,'buffer':blob}},expected=400)
            assert result.json()['code']==code
            assert not read()['evidenceUrl']
        entry['resource_ids']=[vid,aid]
        entry['steps']=['Real owner appeal on genuinely rejected uploaded video','Empty, forged PNG, unsupported MIME rejected with specific errors','Read actual appeal after every rejection; no evidence persisted']
    case(suite,r2,'APPEAL-EVIDENCE-INVALID-FILES','A-MODERATION.04','Invalid evidence leaves appeal unchanged',invalid,'appeals')

    def attachment(entry):
        suite.api(owner,'post','/appeals/'+aid+'/evidence',multipart={'file':{'name':'evidence.png','mimeType':'image/png','buffer':png_bytes()}})
        proof=suite.api(r2,'get','/admin/appeals/'+aid+'/evidence')
        assert proof.body()==png_bytes()
        suite.api(member,'get','/appeals/'+aid+'/evidence',expected=403)
        row=ui()
        with p.expect_popup() as opened:
            suite.response(r2,'/admin/appeals/'+aid+'/evidence',lambda:row.locator('.link-evidence').click())
        tab=opened.value
        try:
            tab.wait_for_url('blob:**'); assert tab.evaluate('()=>window.opener===null'), 'Attachment retained DOM opener'
        finally: tab.close()
        suite.api(owner,'post','/appeals/'+aid+'/evidence',multipart={'file':{'name':'duplicate.png','mimeType':'image/png','buffer':png_bytes()}},expected=409)
        entry['resource_ids']=[vid,aid];entry['steps']=['Upload real PNG and compare authenticated reviewer bytes','Foreign member denied','Actual UI attachment opens private blob in new tab; popup closed','Second attachment rejected without replacing first']
    case(suite,r2,'APPEAL-EVIDENCE-OPEN-PRIVATE-POPUP','A-MODERATION.04','Private attachment opens only for authorized actors',attachment,'appeals')

    def missing(entry):
        db=LocalDb(config)
        path=db.sql("SELECT evidence_url FROM appeals WHERE appeal_id=:'id'::uuid;",{'id':aid})
        if not path.startswith('local-private://'): raise PrerequisiteMissing('Requires owned Local private storage fault fixture')
        # Resolve only this newly uploaded evidence under the runner-owned storage.
        root=(Path(config['state_dir'])/'api-root/.private_uploads').resolve()
        relative=path.removeprefix('local-private://')
        candidates=[q for q in root.rglob('*') if q.is_file() and q.as_posix().endswith(relative)]
        assert len(candidates)==1, 'Could not identify exact owned private evidence file'
        file=candidates[0];assert file.is_relative_to(root)
        payload=file.read_bytes();file.unlink()
        try:
            row=ui(); before=len(r2['context'].pages)
            suite.response(r2,'/admin/appeals/'+aid+'/evidence',lambda:row.locator('.link-evidence').click(),status=404)
            expect(p.locator('.alert-danger')).to_be_visible()
            p.wait_for_function('()=>!document.querySelector(".loading-state")')
            p.wait_for_timeout(300)
            assert len(r2['context'].pages)==before, 'Failed evidence popup was not closed'
            assert read()['status']=='pending'
            entry['steps']=['Temporarily remove only exact newly uploaded Local evidence file','Real reviewer UI receives 404 and visible error','Failed attachment popup closes; appeal remains pending','Restore identical file bytes in finally']
        finally: file.write_bytes(payload)
        assert suite.api(r2,'get','/admin/appeals/'+aid+'/evidence').body()==payload
        entry['resource_ids']=[vid,aid]
    case(suite,r2,'APPEAL-EVIDENCE-BROKEN-STORAGE','A-MODERATION.04','Missing evidence reports error and closes tab',missing,'appeals')

    def failed_decision(entry):
        before=read();video_before=suite.api(owner,'get','/videos/'+vid).json()
        suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'invalid','reviewNote':'QC invalid'},expected=400)
        suite.api(r1,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'approve','reviewNote':'QC own case denied'},expected=403)
        after=read(); assert (after['status'],after['reviewerId'],after['resolvedAt'])==(before['status'],before['reviewerId'],before['resolvedAt'])
        assert suite.api(owner,'get','/videos/'+vid).json()['moderationStatus']==video_before['moderationStatus']
        ui();entry['resource_ids']=[vid,aid]
        entry['steps']=['Snapshot actual pending appeal and rejected video','Invalid decision 400; original reviewer SoD 403','Read-back status/reviewer/resolvedAt/video unchanged','This covers validation/SoD failure persistence, not injected database transaction failure']
    case(suite,r2,'APPEAL-FAILED-DECISION-NO-MUTATION','X-MODERATION.01','Rejected requests do not mutate appeal',failed_decision,'appeals')

    def decision(value):
        def execute(entry):
            row=ui()
            suite.response(r2,'/admin/appeals/'+aid+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
            p.locator('.status-tabs button').nth(1).click()
            row=p.locator('tbody tr').filter(has_text=vid);expect(row).to_have_count(1);row.locator('.btn-resolve').click()
            dialog=p.locator('.modal-card');dialog.locator('select').select_option(value);dialog.locator('textarea').fill('QC independent '+value+' '+suite.run_id)
            result=suite.response(r2,'/admin/appeals/'+aid+'/resolve',lambda:dialog.locator('.modal-footer .btn-primary').click(),method='POST').json()
            expected='rejected' if value=='reject' else 'escalated'
            assert result['status']==expected and read()['status']==expected
            assert suite.api(owner,'get','/videos/'+vid).json()['moderationStatus']=='rejected'
            suite.api(member,'get','/videos/'+vid+'/playback',expected=(403,409))
            suite.go(owner,'/studio/content?channelId='+video['channelId'],'app-studio-content-page')
            expect(owner['page'].locator('.video-row').filter(has_text=video['title'])).to_be_visible()
            suite.evidence(owner,entry,'creator-remains-rejected')
            suite.go(r2,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
            # ALL status contains the exact persisted result after reload.
            buttons=p.locator('.status-tabs button');buttons.last.click()
            entry['resource_ids']=[vid,mid,aid]
            entry['steps']=['Independent reviewer UI claims exact appeal','Actual modal selects '+value+' and submits review note','Read-back terminal/escalated status','User still rejected and playback denied; creator state recorded','Reload Admin; no fabricated restoration']
        return execute
    case(suite,r2,'APPEAL-INDEPENDENT-REJECT','A-MODERATION.04','Reject appeal retains rejected content',decision('reject'),'appeals')
    if read()['status']=='rejected':
        appeal=suite.api(owner,'post','/appeals',data=request,expected=201).json();aid=appeal['appealId']
        def rollback(entry):
            db=LocalDb(config);before=read()
            original=suite.api(owner,'get','/videos/'+vid).json()
            db.sql("""CREATE OR REPLACE FUNCTION qc_appeal_save_fault() RETURNS trigger LANGUAGE plpgsql AS $$
                BEGIN IF NEW.appeal_id::text=TG_ARGV[0] THEN RAISE EXCEPTION 'QC owned appeal fault'; END IF; RETURN NEW; END $$;
                CREATE TRIGGER qc_appeal_save_fault BEFORE UPDATE ON appeals FOR EACH ROW EXECUTE FUNCTION qc_appeal_save_fault(:'id');""",{'id':aid})
            try:
                suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'approve','reviewNote':'QC transaction rollback'},expected=500)
            finally:
                db.sql('DROP TRIGGER IF EXISTS qc_appeal_save_fault ON appeals; DROP FUNCTION IF EXISTS qc_appeal_save_fault();')
            after=read();actual=suite.api(owner,'get','/videos/'+vid).json()
            assert (after['status'],after['reviewerId'],after['resolvedAt'])==(before['status'],before['reviewerId'],before['resolvedAt'])
            assert actual['moderationStatus']==original['moderationStatus']=='rejected' and actual['status']==original['status']=='blocked'
            suite.api(member,'get','/videos/'+vid+'/playback',expected=(403,409));ui()
            entry['resource_ids']=[vid,aid];entry['steps']=['Real PostgreSQL trigger injects exception only for exact owned appeal update','Valid independent approval reaches DB save and returns 500','Remove fault trigger/function in finally','Read actual appeal and video: reviewer/status/resolution/restoration rolled back','Member playback remains denied; no success seeded']
        case(suite,r2,'APPEAL-DB-SAVE-FAILURE-ROLLBACK','X-MODERATION.01','Database failure rolls back appeal and video restoration',rollback,'appeals')
        case(suite,r2,'APPEAL-INDEPENDENT-ESCALATE','A-MODERATION.04','Escalated appeal does not restore content',decision('escalate'),'appeals')
        def duplicate(entry):
            result=suite.api(owner,'post','/appeals',data=request,expected=409)
            assert result.json()['code']=='APPEAL_ALREADY_PENDING'
            assert read()['status']=='escalated'
            entry['resource_ids']=[vid,aid];entry['steps']=['Existing escalated appeal remains active','Owner duplicate appeal rejected 409','Read-back original escalated appeal retained']
        case(suite,r2,'APPEAL-ESCALATED-DUPLICATE-DENIED','X-MODERATION.01','Escalation prevents duplicate pending appeal',duplicate,'appeals')
