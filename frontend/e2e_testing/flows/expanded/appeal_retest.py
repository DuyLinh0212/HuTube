import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    if any(c.get('logical_id',c['id'])=='FULL-APPEAL-INDEPENDENT-APPROVE-REPLAY' and c['status']=='passed' for c in suite.report['cases']):
        suite.report.setdefault('group_skips',[]).append({'group':'appeal-retest','reason':'Fresh independent approval already executed successfully in this run; no REUSED/PASS record added'})
        return
    snapshot_module(suite,__file__);owner,r2,member=(actors[k] for k in ['owner','reviewer2','member'])
    data=suite.api(r2,'get','/admin/appeals',params={'page':1,'pageSize':100}).json();items=data if isinstance(data,list) else data['items']
    owned=suite.api(owner,'get','/appeals/my').json();ownids={a['appealId'] for a in (owned if isinstance(owned,list) else owned['items'])}
    appeal=next(a for a in items if a['appealId'] in ownids and a['targetType']=='video' and a['status'] in ('pending','reviewing') and (not a.get('reviewerId') or a['reviewerId']==r2['identity']['userId']))
    aid=appeal['appealId'];vid=appeal['targetId']
    def resolve(entry):
        p=r2['page'];suite.go(r2,'/moderation/appeals','app-admin-appeals-page','/admin/appeals')
        if appeal['status']=='pending':
            row=p.locator('tbody tr').filter(has_text=vid);expect(row).to_have_count(1)
            suite.response(r2,'/admin/appeals/'+aid+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
        p.locator('.status-tabs button').nth(1).click();row=p.locator('tbody tr').filter(has_text=vid);expect(row).to_have_count(1);row.locator('.btn-resolve').click()
        dialog=p.locator('.modal-card');dialog.locator('select').select_option('approve');dialog.locator('textarea').fill('QC independent appeal approval after response-contract correction')
        suite.response(r2,'/admin/appeals/'+aid+'/resolve',lambda:dialog.locator('.modal-footer .btn-primary').click(),method='POST')
        assert suite.api(owner,'get','/videos/'+vid).json()['moderationStatus']=='approved'
        suite.api(member,'get','/videos/'+vid+'/playback')
        suite.api(r2,'post','/admin/appeals/'+aid+'/resolve',data={'decision':'approve','reviewNote':'QC replay'},expected=(400,409))
        entry['resource_ids']=[aid,vid];entry['steps']=['Use exact Owner appeal and independent Reviewer2','New claim 204 or retained same-reviewer claim from prior observed 204','Actual Reviewer2 UI approves with review note','Owner state approved; Member playback restored','Processed appeal replay rejected']
    case(suite,r2,'APPEAL-INDEPENDENT-APPROVE-REPLAY','A-MODERATION.04','Independent appeal approval restores actual video once',resolve,'appeals')
