from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    ids={'FULL-STRIKE-EFFECTIVE-UPLOAD-RESTRICTION','FULL-STRIKE-REVOKE-RESTORES-UPLOAD'}
    if ids.issubset({c.get('logical_id',c['id']) for c in suite.report['cases'] if c['status']=='passed'}):
        suite.report.setdefault('group_skips',[]).append({'group':'strike-retest','reason':'Fresh create/revoke already passed in this run; no duplicate mutation or REUSED/PASS record added'})
        return
    snapshot_module(suite,__file__);owner,admin=actors['owner'],actors['admin'];cid=suite.fixtures['channel']['channelId'];strike={};reason='QC unique strike retest '+suite.run_id
    preflight={'channelId':cid,'fileSize':1024,'duration':10,'contentType':'video/mp4','sourceQuality':'360p'}
    def create(entry):
        strike.update(suite.api(admin,'post','/admin/strikes',data={'channelId':cid,'severity':'high','reason':reason,'internalNote':'Owned fixture retest'},expected=201).json())
        assert suite.api(owner,'get','/channels/'+cid+'/strikes').json()['activeStrikesCount']>=1
        suite.api(owner,'post','/videos/upload-preflight',data=preflight,expected=(400,403,409))
        suite.go(admin,'/moderation/strikes','app-admin-strikes-page','/admin/strikes');expect(admin['page'].locator('tbody tr').filter(has_text=reason)).to_have_count(1)
        entry['resource_ids']=[strike['strikeId'],cid];entry['steps']=['Actual unique manual strike','Real active count and effective preflight denial','Actual Admin active row is exactly this fixture']
    case(suite,admin,'STRIKE-EFFECTIVE-UPLOAD-RESTRICTION','A-MODERATION.05','Active strike enforces upload restriction',create,'strikes')
    def revoke(entry):
        suite.api(admin,'post','/admin/strikes/'+strike['strikeId']+'/revoke',data={'reason':'QC revoke exact fixture'},expected=200)
        assert suite.api(owner,'get','/channels/'+cid+'/strikes').json()['activeStrikesCount']==0
        suite.api(owner,'post','/videos/upload-preflight',data=preflight)
        suite.go(admin,'/moderation/strikes','app-admin-strikes-page','/admin/strikes');admin['page'].locator('.status-tabs button').nth(2).click();expect(admin['page'].locator('tbody tr').filter(has_text=reason)).to_have_count(1)
        entry['resource_ids']=[strike['strikeId'],cid];entry['steps']=['Actual revoke preserves history','Real active count zero and preflight allowed','Revoked UI row matched by unique fixture reason, not repeated legacy text']
    try:case(suite,admin,'STRIKE-REVOKE-RESTORES-UPLOAD','A-MODERATION.05','Revocation restores upload and exact history',revoke,'strikes')
    finally:
        if strike:suite.api(admin,'post','/admin/strikes/'+strike['strikeId']+'/revoke',data={'reason':'Cleanup exact fixture'},expected=(200,400,409))
