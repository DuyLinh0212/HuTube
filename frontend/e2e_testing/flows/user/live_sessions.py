"""Revoke only sessions created by this run; never log out existing devices."""
from datetime import datetime
from playwright.sync_api import expect

def run(suite,owner,admin):
    for application,other_user in [('user',admin),('admin',owner)]:
        controller=suite.actor('session-controller-'+application,application)
        target=suite.actor('session-target-'+application,application)
        target_sessions=suite.api(target,'get','/auth/sessions').json()['items']
        target_session=next(item for item in target_sessions if item['isCurrent'])
        target_id=target_session['sessionId']
        page=controller['page']
        parent='U-ACCOUNT.03' if application=='user' else 'A-ACCOUNT.01'
        def revoke(case,controller=controller,target=target,target_id=target_id,application=application,other_user=other_user,page=page):
            case['resource_ids']=[target_id]
            case['steps']=['Create two fresh browser sessions of the same supplied identity','Foreign identity cannot revoke target','Find exact target device from sessions API','Open revoke → cancel → target remains authenticated','Confirm UI revoke for this exact session','Target JWT/refresh/reload denied; controller remains authenticated']
            denial=suite.api(other_user,'delete','/auth/sessions/'+target_id,expected=404).json()
            assert denial['code']=='SESSION_NOT_FOUND'
            assert suite.api(target,'get','/auth/me').json()['userId']==target['identity']['userId']
            data=suite.go(controller,'/account','app-account-page','/auth/sessions')
            if application=='user':
                page.locator('.settings-nav-list > button').nth(5).click()
            # Match the UI's documented grouping/order, including historical
            # devices. The selected ID must belong to this newly created target.
            groups={}
            for item in data['items']:
                key=(item['platform'],item.get('deviceId') or item['sessionId'])
                group=groups.setdefault(key,{'latest':item,'current':False})
                if datetime.fromisoformat(item['issuedAt'])>datetime.fromisoformat(group['latest']['issuedAt']): group['latest']=item
                group['current']=group['current'] or item['isCurrent']
            ordered=sorted(groups.values(),key=lambda group:datetime.fromisoformat(group['latest']['issuedAt']),reverse=True)
            index=next(i for i,group in enumerate(ordered) if group['latest']['sessionId']==target_id)
            assert not ordered[index]['current']
            rows=page.locator('.sessions-list').first.locator('.session-item')
            expect(rows).to_have_count(len(ordered))
            row=rows.nth(index)
            row.locator('button').click()
            expect(page.locator('.revoke-warning')).to_be_visible()
            suite.evidence(controller,case,'revoke-pending')
            warning=page.locator('.revoke-warning')
            warning.locator('button').nth(1).click()
            expect(warning).to_have_count(0)
            assert suite.api(target,'get','/auth/me').status==200
            row.locator('button').click()
            suite.response(controller,'/auth/sessions/'+target_id,lambda:page.locator('.revoke-warning button').first.click(),method='DELETE')
            expect(page.locator('.revoke-warning')).to_have_count(0)
            assert target_id not in [item['sessionId'] for item in suite.api(controller,'get','/auth/sessions').json()['items']]
            suite.api(target,'get','/auth/me',expected=401)
            headers={'X-HuTube-Client':'web'}
            if application=='admin': headers['X-HuTube-App']='admin'
            refreshed=target['context'].request.post(target['api_url']+'/auth/refresh',headers=headers,data={})
            assert refreshed.status==401
            target['page'].goto(target['origin']+('/account' if application=='user' else '/users'))
            target['page'].wait_for_url('**/login**')
            assert suite.api(controller,'get','/auth/me').status==200
            suite.evidence(controller,case,'target-revoked-controller-active')
            suite.evidence(target,case,'revoked-target-login')
        suite.case(controller,'LIVE-SESSION-REVOKE-'+application.upper(),parent,'Cancel and revoke a newly created '+application+' session','Only the selected test device loses access; foreign account denied; cancel persists no revocation',revoke,module='sessions')
        suite.release_actor(controller)
        suite.release_actor(target)
