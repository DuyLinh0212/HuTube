"""Recover closed idle fixture tabs before a journey, never during assertions."""
from flows.expanded.common import snapshot_module


def ensure_actor_pages(suite,actors,keys):
    snapshot_module(suite,__file__)
    for key in keys:
        previous=actors[key]
        if previous['page'].is_closed():
            suite.release_actor(previous)
            actor=suite.actor(previous['name'],previous['application'],
                'user' if key=='owner' else key)
            assert actor['identity']['userId']==previous['identity']['userId']
            actors[key]=actor
            suite.report['setup'].append({'actor':actor['name'],'status':'recovered-closed-idle-tab',
                'user_id':actor['identity']['userId'],'scope':'Fixture preparation before journey; old failed assertions remain unchanged'})
        else:
            # API assertions use the bearer observed from this page. Idle
            # reviewer tabs may retain an expired bearer even though their
            # refresh cookie is valid. Exercise the normal route guard first.
            endpoint='/auth/sessions' if previous['application']=='admin' else '/account/profile'
            suite.go(previous,'/account','app-account-page',endpoint)
            assert suite.api(previous,'get','/auth/me').json()['userId']==previous['identity']['userId']
