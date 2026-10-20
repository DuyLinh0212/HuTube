"""Actual comment reporting and all supported decisions, with target guards."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb


def run(suite, config, actors):
    snapshot_module(suite,__file__)
    db=LocalDb(config)
    ensure_actor_pages(suite,actors,['owner','member','reviewer1'])
    owner,member,reviewer=(actors[k] for k in ['owner','member','reviewer1'])
    vid=suite.fixtures['video']['videoId'];base='/videos/'+vid+'/comments'
    for decision in ['dismiss','warn','hide','remove','escalate']:
        checkpoint={};text='QC comment '+decision+' '+suite.run_id
        try:
            def report(entry):
                suite.go(owner,'/watch/'+vid,'app-watch-page');p=owner['page']
                p.locator('textarea[name=comment]').fill(text)
                comment=suite.response(owner,base,lambda:p.locator('.comment-composer button[type=submit]').click(),method='POST',status=201).json()
                checkpoint['commentId']=comment['commentId']
                suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page']
                row=p.locator('.comment-row').filter(has_text=text)
                row.get_by_role('button',name=re.compile('^Báo cáo$|^Report$')).click()
                modal=p.locator('.report-modal');modal.locator('.option-row').first.click();modal.locator('.btn-next').click()
                modal.locator('textarea').fill('QC report exact comment '+decision)
                suite.response(member,'/reports',lambda:modal.locator('.btn-submit').click(),method='POST',status=(200,201))
                rows=suite.api(reviewer,'get','/admin/reports/cases',params={'page':1,'pageSize':100}).json()['items']
                checkpoint.update(next(c for c in rows if c['targetType']=='comment' and c['targetId']==comment['commentId']))
                entry['resource_ids']=[vid,comment['commentId'],checkpoint['caseId']]
                entry['steps']=['Owner posts actual Watch comment through composer',
                    'Independent Member opens Report on that exact comment and submits real dialog',
                    'Reviewer case target is the comment ID, not the parent video/channel']
            if not case(suite,member,'REPORT-COMMENT-CREATE-'+decision.upper(),'U-WATCH.04','Report comment for '+decision,report,'reports'):continue
            path='/admin/reports/cases/'+checkpoint['caseId']
            def resolve(entry):
                p=reviewer['page'];suite.go(reviewer,'/moderation/reports','app-admin-reports-page','/admin/reports/cases')
                # Target titles are truncated to 50 chars by the report service.
                p.locator('input.report-search').fill(text[:35])
                row=p.locator('tbody tr').filter(has_text=text[:35]);expect(row).to_have_count(1)
                suite.response(reviewer,path+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
                detail=suite.api(reviewer,'get',path).json()
                suite.api(reviewer,'post',path+'/dispositions',data={'reportIds':[r['reportId'] for r in detail['reports']],
                    'disposition':'accepted','reason':'QC examined the exact reported comment'},expected=204)
                suite.go(reviewer,'/moderation/reports','app-admin-reports-page','/admin/reports/cases')
                p.locator('.status-tabs button').nth(1).click();p.locator('input.report-search').fill(text[:35])
                p.locator('tbody tr').filter(has_text=text[:35]).locator('.btn-resolve').click()
                stage=p.locator('.case-resolution')
                options=stage.locator('select option').evaluate_all('els=>els.map(e=>e.value)')
                assert not {'age_restrict','recommendation_restricted','upload_restriction','strike','lock_channel'}.intersection(options)
                suite.api(reviewer,'post',path+'/resolve',data={'decision':'age_restrict','reason':'QC unsupported comment action'},expected=400)
                assert suite.api(reviewer,'get',path).json()['case']['status']=='reviewing'
                stage.locator('select').select_option(decision);stage.locator('textarea').fill('QC comment decision '+decision)
                resolved=suite.response(reviewer,path+'/resolve',lambda:stage.locator('.modal-footer .btn-primary').click(),method='POST').json()
                assert resolved['reportId']==checkpoint['caseId'] and resolved['decision']==decision
                actual=suite.api(reviewer,'get',path).json()['case']
                assert actual['targetId']==checkpoint['commentId']
                assert db.sql("SELECT decision FROM moderation_cases WHERE moderation_case_id=:'id'::uuid;",{'id':checkpoint['caseId']})==decision
                assert actual['status']==('escalated' if decision=='escalate' else 'resolved')
                suite.api(reviewer,'post',path+'/resolve',data={'decision':decision,'reason':'QC replay'},expected=(400,409))
                comments=suite.api(member,'get',base,params={'page':1,'pageSize':100}).json()
                items=comments if isinstance(comments,list) else comments['items']
                present=any(c['commentId']==checkpoint['commentId'] for c in items)
                assert present==(decision not in ('hide','remove'))
                suite.go(member,'/watch/'+vid,'app-watch-page')
                expect(member['page'].locator('.comment-row').filter(has_text=text)).to_have_count(0 if decision in ('hide','remove') else 1)
                suite.api(member,'get','/videos/'+vid+'/playback')
                suite.evidence(member,entry,'member-comment-after-decision')
                suite.evidence(reviewer,entry,'reviewer-resolved-case')
                entry['resource_ids']=[vid,checkpoint['commentId'],checkpoint['caseId']]
                entry['steps']=['Reviewer UI claims exact comment case; actual classification persisted',
                    'Unsupported target decision absent from UI and actual API returns 400 without closing case',
                    'Real supported '+decision+' decision persists once; replay rejected',
                    'Member API and reloaded Watch agree on comment visibility; parent video stays playable']
            case(suite,reviewer,'REPORT-COMMENT-DECISION-'+decision.upper(),'A-MODERATION.03','Comment consequence '+decision,resolve,'reports')
        finally:
            if checkpoint.get('commentId'):
                suite.api(owner,'delete','/comments/'+checkpoint['commentId'],expected=(200,204,404))
                suite.report['cleanup'].append({'resource':'reported QC comment','id':checkpoint['commentId'],'status':'deleted through actual owner API'})
