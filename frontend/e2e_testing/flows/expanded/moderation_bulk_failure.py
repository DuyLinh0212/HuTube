"""Real stale queue + competing reviewer; no network responses are mocked."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.media_deep import upload_fixture,submit_public
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    ensure_actor_pages(suite,actors,['owner','member','reviewer1','reviewer2','admin'])
    owner,member,r1,r2,admin=(actors[k] for k in ['owner','member','reviewer1','reviewer2','admin'])
    if config.get('bulk_resume_run'):
        owned=suite.api(owner,'get','/videos/manage',params={'channelId':suite.fixtures['channel']['channelId'],'pageSize':100}).json()['items']
        videos=[next(v for v in owned if v['title']=='QC '+label+' '+config['bulk_resume_run']) for label in ['BULK-A','BULK-B']]
        queue_items=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
        cases=[next(c for c in queue_items if c['videoId']==v['videoId']) for v in videos]
        assert all(c['status']=='pending' and not c.get('reviewerId') for c in cases)
        suite.report.setdefault('fixture_checkpoints',[]).append({'group':'moderation-bulk-failure','source_run':config['bulk_resume_run'],'note':'Reuse only actual pending fixtures; all competing claims and UI assertions execute anew.'})
    else:
        videos=[upload_fixture(suite,owner,member,'BULK-A'),upload_fixture(suite,owner,member,'BULK-B')]
        cases=[submit_public(suite,owner,admin,v) for v in videos]
    mids=[c['moderationCaseId'] for c in cases]
    p=r1['page']
    def queue():return suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
    def current(mid):return next(x for x in queue() if x['moderationCaseId']==mid)
    def partial(entry):
        entry['resource_ids']=mids+[v['videoId'] for v in videos]
        suite.go(r1,'/moderation/videos','app-admin-moderation-page','/admin/moderation/queue')
        p.locator('input[type=search]').fill('QC BULK-')
        p.locator('.status-tabs [role=tab]').nth(0).click()
        for v in videos:p.locator('.queue-table tbody tr').filter(has_text=v['videoId'][:8]).locator('input[type=checkbox]').check()
        # Legitimate concurrent mutation after the first reviewer's UI snapshot.
        suite.api(r2,'post','/admin/moderation/'+mids[1]+'/claim',data={})
        p.once('dialog',lambda d:d.accept())
        p.locator('.bulk-actions .primary').click()
        p.wait_for_function('()=>!document.querySelector(".loading-state")')
        # Successful claims leave the pending tab. Inspect the actual reviewing tab.
        p.locator('.status-tabs [role=tab]').nth(1).click()
        expect(p.locator('.queue-table')).to_be_visible(timeout=30000)
        # Wait for actual read-back rather than infer success from the toast.
        for _ in range(30):
            if current(mids[0])['reviewerId']==r1['identity']['userId']:break
            p.wait_for_timeout(200)
        first,second=(current(m) for m in mids)
        assert first['reviewerId']==r1['identity']['userId'] and second['reviewerId']==r2['identity']['userId']
        assert first['status']==second['status']=='reviewing'
        events=[e for e in suite.report['http_statuses'] if e.get('case')==suite.current and e['actor']==r1['name'] and e['method']=='POST' and e['path'].endswith('/claim')]
        assert any(e['status']==409 for e in events),'Competing reviewer conflict was not observed'
        entry['acknowledgement_note']='forkJoin may unsubscribe the other HTTP request after 409; successful ownership is established by real API read-back, not an invented browser 200.'
        entry['resource_ids']=mids+[v['videoId'] for v in videos]
        entry['steps']=['Reviewer1 selects two fresh pending resources through UI','Reviewer2 claims one exact resource before bulk submit','Reviewer1 actual bulk receives one 200 and one 409','Actual API states prove partial success and preserve independent claim','UI must explicitly distinguish successful and failed items']
        suite.evidence(r1,entry,'bulk-partial-result')
        # A generic error alone leaves the operator unable to know what changed.
        text=p.locator('app-admin-moderation-page').inner_text().lower()
        assert ('1/2' in text or ('1 thành công' in text and '1 thất bại' in text) or ('1 succeeded' in text and '1 failed' in text)), 'Bulk UI does not identify partial success (one claimed, one conflict)'
    try:case(suite,r1,'MODERATION-BULK-CLAIM-PARTIAL-FAILURE','A-MODERATION.01','Bulk concurrent conflict distinguishes partial outcomes',partial,'moderation')
    finally:
        for reviewer,mid in [(r1,mids[0]),(r2,mids[1])]:
            if current(mid).get('reviewerId')==reviewer['identity']['userId']:
                suite.api(reviewer,'post','/admin/moderation/'+mid+'/release',data={},expected=(200,204))
    def select_pending():
        suite.go(r1,'/moderation/videos','app-admin-moderation-page','/admin/moderation/queue')
        p.locator('input[type=search]').fill('QC BULK-');p.locator('.status-tabs [role=tab]').nth(0).click()
        for v in videos:p.locator('.queue-table tbody tr').filter(has_text=v['videoId'][:8]).locator('input[type=checkbox]').check()
    def summary(successes,failures):
        return p.locator('section[role=status]').filter(has_text=re.compile(str(successes)+r' thành công, '+str(failures)+r' thất bại|'+str(successes)+r' succeeded, '+str(failures)+r' failed'))
    def all_success(entry):
        select_pending();p.once('dialog',lambda d:d.dismiss())
        before=sum(e['method']=='POST' and e['path'].endswith('/claim') for e in suite.report['http_statuses'])
        p.locator('.bulk-actions .primary').click()
        assert before==sum(e['method']=='POST' and e['path'].endswith('/claim') for e in suite.report['http_statuses'])
        assert all(current(mid)['status']=='pending' for mid in mids)
        p.once('dialog',lambda d:d.accept());p.locator('.bulk-actions .primary').click()
        expect(summary(2,0)).to_be_visible()
        assert all(current(mid)['reviewerId']==r1['identity']['userId'] for mid in mids)
        p.locator('.status-tabs [role=tab]').nth(1).click()
        for v in videos:p.locator('.queue-table tbody tr').filter(has_text=v['videoId'][:8]).locator('input[type=checkbox]').check()
        p.once('dialog',lambda d:d.accept());p.locator('.bulk-actions .subtle').click()
        expect(summary(2,0)).to_be_visible()
        for _ in range(20):
            if all(current(mid)['status']=='pending' for mid in mids):break
            p.wait_for_timeout(200)
        assert all(current(mid)['status']=='pending' and not current(mid).get('reviewerId') for mid in mids)
        entry['resource_ids']=mids;entry['steps']=['Cancel real bulk confirmation: no request/ownership mutation','Confirm actual bulk claim: both independent rows assigned to Reviewer1','Accessible status summary says 2 succeeded, 0 failed','Select both reviewing rows and actual bulk release','Read-back both pending/unassigned; summary remains explicit']
    try:case(suite,r1,'MODERATION-BULK-SUCCESS-CANCEL-RELEASE','A-MODERATION.01','Bulk cancel, complete success and release remain correct',all_success,'moderation')
    finally:
        for mid in mids:
            if current(mid).get('reviewerId')==r1['identity']['userId']:suite.api(r1,'post','/admin/moderation/'+mid+'/release',data={},expected=(200,204))
    def all_failure(entry):
        select_pending()
        for mid in mids:suite.api(r2,'post','/admin/moderation/'+mid+'/claim',data={})
        p.once('dialog',lambda d:d.accept());p.locator('.bulk-actions .primary').click()
        expect(summary(0,2)).to_be_visible()
        for v in videos:expect(summary(0,2)).to_contain_text(v['title'])
        assert all(current(mid)['reviewerId']==r2['identity']['userId'] for mid in mids)
        entry['resource_ids']=mids;entry['steps']=['Select pending rows on Reviewer1 UI','Independent Reviewer2 genuinely claims both rows before submit','Actual batch receives two conflicts; summary 0 success/2 failed and names each failed resource','Read-back Reviewer2 ownership unchanged']
    try:case(suite,r1,'MODERATION-BULK-ALL-CONFLICTS','X-MODERATION.01','All-conflict batch lists each failure and preserves ownership',all_failure,'moderation')
    finally:
        for mid in mids:
            if current(mid).get('reviewerId')==r2['identity']['userId']:suite.api(r2,'post','/admin/moderation/'+mid+'/release',data={},expected=(200,204))
    def lease(entry):
        entry['resource_ids']=mids
        entry['steps']=['Actual queue has claimedAt/reviewerId fields','Source ClaimCaseAsync has no lease duration, expiry comparison or renewal contract','Need explicit lease TTL/product behavior before deciding expired vs permanent ownership']
        raise PrerequisiteMissing('Claim expiry contract is absent: no TTL/config/worker in current QC product. Cannot invent an expiration threshold or certify this branch.')
    case(suite,r1,'MODERATION-CLAIM-LEASE-EXPIRY-CONTRACT','X-MODERATION.01','Claim expires according to defined lease contract',lease,'moderation')
