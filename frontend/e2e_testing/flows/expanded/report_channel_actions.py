"""Remaining report decisions on disposable channels with independent actors."""
from datetime import datetime, timezone
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.security_plan_common import identity
from flows.expanded.channels import create_channel
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb


def run(suite, config, actors, *, target_kind='channel', decisions=None):
    snapshot_module(suite,__file__)
    db=LocalDb(config)
    ensure_actor_pages(suite,actors,['owner','member','admin','reviewer1'])
    reporter,admin,limited=(actors[k] for k in ['member','admin','reviewer1'])
    main=suite.api(actors['owner'],'get','/channels/me').json()
    base='/admin/reports/cases'
    decisions=decisions or [('rrestrict','upload_restriction'),('rstrike','strike'),('rlock','lock_channel')]
    for key,decision in decisions:
        if target_kind=='video':key='v'+key
        identity(suite,config,key)
        owner=suite.actor('report-channel-'+key,'user',key)
        channel=create_channel(suite,owner,key);cid=channel['channelId'];checkpoint={}
        video=None;target_id=cid;target_title=channel['name']
        prefix='REPORT-'+target_kind.upper()+'-'
        if target_kind=='video':
            from flows.expanded.media_deep import upload_fixture,submit_public
            original=suite.fixtures['channel'];suite.fixtures['channel']=channel
            try:video=upload_fixture(suite,owner,reporter,'REPORT-VIDEO-'+decision.upper())
            finally:suite.fixtures['channel']=original
            pending=submit_public(suite,owner,admin,video);mid=pending['moderationCaseId']
            suite.api(admin,'post','/admin/moderation/'+mid+'/claim',data={})
            suite.api(admin,'post','/admin/moderation/'+mid+'/resolve',data={'decision':'approve','reason':'QC prepare independent report video'})
            target_id=video['videoId'];target_title=video['title']
        reason='QC channel decision '+decision+' '+suite.run_id
        preflight={'channelId':cid,'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'}
        try:
            def create(entry):
                suite.api(owner,'post','/videos/upload-preflight',data=preflight)
                p=reporter['page']
                if target_kind=='video':
                    suite.go(reporter,'/watch/'+target_id,'app-watch-page')
                    p.get_by_role('button',name=__import__('re').compile('Báo.*vi phạm|Report violation',__import__('re').I)).click()
                else:
                    suite.go(reporter,'/channel/'+channel['handle'],'app-channel-page')
                    p.locator('.btn-more-info').click()
                    p.locator('.btn-report-action').click();p.locator('.report-menu-item').last.click()
                modal=p.locator('.report-modal');expect(modal.locator('.btn-next')).to_be_disabled()
                modal.locator('.option-row').first.click();modal.locator('.btn-next').click()
                modal.locator('textarea').fill(reason)
                suite.response(reporter,'/reports',lambda:modal.locator('.btn-submit').click(),method='POST',status=(200,201))
                rows=suite.api(admin,'get',base,params={'page':1,'pageSize':100}).json()['items']
                checkpoint.update(next(row for row in rows if row['targetType']==target_kind and row['targetId']==target_id))
                entry['resource_ids']=[cid,target_id,checkpoint['caseId']]
                entry['steps']=['Fresh disposable channel initially permits upload preflight',
                    'Independent Member uses actual '+target_kind+' report menu and reason dialog',
                    'Persisted Admin report case has exact target type and ID']
            if not case(suite,reporter,prefix+'CREATE-'+decision.upper(),'U-CHANNEL.05' if target_kind=='channel' else 'U-WATCH.05','Report disposable '+target_kind+' for '+decision,create,'reports'):continue
            path=base+'/'+checkpoint['caseId']
            def permission(entry):
                suite.go(limited,'/moderation/reports','app-admin-reports-page',base)
                p=limited['page'];p.locator('input.report-search').fill(target_title)
                row=p.locator('tbody tr').filter(has_text=target_title)
                suite.response(limited,path+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
                p.locator('.status-tabs button').nth(1).click()
                row=p.locator('tbody tr').filter(has_text=target_title);row.locator('.btn-resolve').click()
                options=p.locator('.case-resolution select option').evaluate_all('els=>els.map(e=>e.value)')
                assert decision not in options,'Limited reviewer is offered a privileged channel action'
                suite.api(limited,'post',path+'/resolve',data={'decision':decision,'reason':reason},expected=403)
                p.locator('.report-case-dialog .close-btn').click()
                suite.response(limited,path+'/release',lambda:row.locator('.btn-release').click(),method='POST',status=204)
                actual=suite.api(admin,'get',path).json()['case'];assert actual['status']=='pending'
                entry['resource_ids']=[cid,checkpoint['caseId']]
                entry['steps']=['Limited reviewer claims exact channel case',
                    'Privileged decision absent from real UI; direct API returns 403',
                    'Actual UI release returns case to pending for another reviewer']
            if decision in ('upload_restriction','strike','lock_channel'):
                if not case(suite,limited,prefix+'PERMISSION-'+decision.upper(),'A-MODERATION.03','Privileged action requires permission: '+decision,permission,'reports'):continue
            def resolve(entry):
                suite.go(admin,'/moderation/reports','app-admin-reports-page',base)
                p=admin['page'];p.locator('input.report-search').fill(target_title)
                row=p.locator('tbody tr').filter(has_text=target_title)
                suite.response(admin,path+'/claim',lambda:row.locator('.btn-claim').click(),method='POST',status=200)
                detail=suite.api(admin,'get',path).json()
                suite.api(admin,'post',path+'/dispositions',data={'reportIds':[r['reportId'] for r in detail['reports']],
                    'disposition':'accepted','reason':'QC classification of exact channel report'},expected=204)
                suite.go(admin,'/moderation/reports','app-admin-reports-page',base)
                p.locator('.status-tabs button').nth(1).click();p.locator('input.report-search').fill(target_title)
                p.locator('tbody tr').filter(has_text=target_title).locator('.btn-resolve').click()
                stage=p.locator('.case-resolution');stage.locator('select').select_option(decision)
                stage.locator('textarea').fill(reason)
                if decision=='upload_restriction':stage.locator('input[type=number]').fill('14')
                resolved=suite.response(admin,path+'/resolve',lambda:stage.locator('.modal-footer .btn-primary').click(),method='POST').json()
                assert resolved['reportId']==checkpoint['caseId'] and resolved['decision']==decision
                actual=suite.api(admin,'get',path).json()['case']
                assert actual['status']==('escalated' if decision=='escalate' else 'resolved') and actual['targetId']==target_id
                assert db.sql("SELECT decision FROM moderation_cases WHERE moderation_case_id=:'id'::uuid;",{'id':checkpoint['caseId']})==decision
                suite.api(admin,'post',path+'/resolve',data={'decision':decision,'reason':reason},expected=(400,409))
                status=suite.api(owner,'get','/channels/'+cid+'/strikes').json()
                if decision in ('lock_channel','hide','remove'):
                    expected_status='banned' if decision=='remove' else 'suspended'
                    assert suite.api(owner,'get','/channels/me').json()['status']==expected_status
                    suite.go(owner,'/channel/'+channel['handle']+'/customize','app-channel-settings-page')
                    expect(owner['page'].locator('.channel-suspended-banner')).to_be_visible()
                elif decision in ('upload_restriction','strike'):
                    matching=[s for s in status['strikes'] if s['reason']==reason and s['status']=='active']
                    assert len(matching)==1
                    if decision=='strike':assert matching[0]['severity']=='high' and status['activeStrikesCount']==1
                    else:
                        until=datetime.fromisoformat(status['uploadRestrictedUntil'].replace('Z','+00:00'))
                        assert 13.99<(until-datetime.now(timezone.utc)).total_seconds()/86400<14.01
                else:assert suite.api(owner,'get','/channels/me').json()['status']=='active'
                restricted=decision in ('upload_restriction','strike','lock_channel','hide','remove')
                suite.api(owner,'post','/videos/upload-preflight',data=preflight,expected=(400,403,409) if restricted else 200)
                if video:suite.api(reporter,'get','/videos/'+target_id+'/playback',expected=(403,404,409) if decision=='lock_channel' else 200)
                unchanged=suite.api(actors['owner'],'get','/channels/me').json()
                assert unchanged['channelId']==main['channelId'] and unchanged['status']==main['status']
                entry['resource_ids']=[cid,target_id,checkpoint['caseId']]
                entry['steps']=['Independent privileged Admin claims and classifies actual report',
                    'Real UI applies '+decision+(' for 14 days' if decision=='upload_restriction' else ''),
                    'Persisted case decision and actual channel/strike/restriction state agree',
                    'Owner upload preflight matches consequence; main owner channel unchanged; duplicate resolution rejected']
            case(suite,admin,prefix+'DECISION-'+decision.upper(),'A-MODERATION.03',target_kind+' consequence '+decision,resolve,'reports')
        finally:
            status=suite.api(owner,'get','/channels/'+cid+'/strikes').json()
            for strike in status['strikes']:
                if strike['status']=='active' and strike['reason']==reason:
                    suite.api(admin,'post','/admin/strikes/'+strike['strikeId']+'/revoke',data={'reason':'QC restore disposable report target'})
            current=suite.api(owner,'get','/channels/me').json()
            if current['status'] in ('suspended','banned'):
                suite.api(admin,'post','/admin/channels/'+cid+'/unlock',data={'reason':'QC restore disposable report target'},expected=204)
            suite.api(owner,'post','/videos/upload-preflight',data=preflight)
            if video:suite.api(owner,'delete','/videos/'+target_id,expected=(200,204))
            suite.report['cleanup'].append({'resource':'disposable report channel restrictions','id':cid,'status':'restored through actual revoke/unlock APIs'})
            suite.release_actor(owner)
