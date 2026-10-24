"""Fresh owned fixture identities and real session operations for priority QC."""
import time
from support.delta_scope import enabled as delta_only
from playwright.sync_api import expect
from tests.full_functional import register, register_fixture
from support.local_db import LocalDb
from flows.expanded.common import case, snapshot_module

def identity(suite, config, key):
    snapshot_module(suite, __file__)
    suffix=suite.run_id[:15].replace('T','')
    suite.credentials[key]={'email':('qc.'+key+'.'+suite.run_id+'@example.test').lower(),
        'username':'qc_'+key+'_'+suffix, 'password':'QCSessionPlanFixture2026!'}
    # Retained registration/verification cases must not be replayed during a
    # delta run.  Create the disposable actor through the real API + Pickup
    # fixture path instead, keeping it out of scenario evidence.
    uid=(register_fixture if delta_only() else register)(suite,config,key,LocalDb(config))
    return uid

def remember_refresh(actor):
    name='hutube_admin_refresh' if actor['application']=='admin' else 'hutube_refresh'
    cookie=next((item for item in actor['context'].cookies() if item['name']==name),None)
    if cookie:actor['_transition_refresh_cookie']=(name,cookie['value'])

def freeze(actor):
    remember_refresh(actor)
    headers=dict(actor['headers'])
    actor['page'].goto('about:blank')
    actor['headers']=headers
    return headers

def refresh(suite, actor, expected=200):
    headers={'X-HuTube-Client':'web','Origin':actor['origin']}
    if actor['application']=='admin':headers['X-HuTube-App']='admin'
    try:response=actor['context'].request.post(actor['api_url']+'/auth/refresh',headers=headers,data={})
    except Exception as error:raise RuntimeError('Refresh transport failure: '+type(error).__name__) from None
    suite.report['http_statuses'].append({'actor':actor['name'],'case':suite.current,
        'method':'POST','path':'/api/v1/auth/refresh','status':response.status})
    assert response.status in (expected if isinstance(expected,tuple) else (expected,)), 'Refresh HTTP '+str(response.status)
    if response.status==200:
        value=response.json();actor['headers']['Authorization']='Bearer '+value['accessToken']
        assert value['user']['userId']==actor['identity']['userId']
        remember_refresh(actor)
    return response

def denied(suite, actor, paths=('/auth/me','/account/profile')):
    for path in paths:suite.api(actor,'get',path,expected=(401,403))
    refresh(suite,actor,(401,403))
    if actor.get('_transition_refresh_cookie'):
        name,value=actor['_transition_refresh_cookie']
        headers={'X-HuTube-Client':'web','Origin':actor['origin'],'Cookie':name+'='+value}
        if actor['application']=='admin':headers['X-HuTube-App']='admin'
        try:response=actor['context'].request.post(actor['api_url']+'/auth/refresh',headers=headers,data={})
        except Exception as error:raise RuntimeError('Captured-cookie refresh transport failure: '+type(error).__name__) from None
        suite.report['http_statuses'].append({'actor':actor['name'],'case':suite.current,
            'method':'POST','path':'/api/v1/auth/refresh','status':response.status,'credential_source':'pre-transition HttpOnly cookie held only in memory'})
        assert response.status in (401,403), 'Captured pre-transition refresh cookie was accepted after access loss'
    route='/users' if actor['application']=='admin' else '/account'
    actor['page'].goto(actor['origin']+route)
    actor['page'].wait_for_url('**/login**')
    expect(actor['page'].locator('app-auth-page')).to_be_visible()

def stepcase(suite,actor,id,parent,title,action,module):
    return case(suite,actor,'PRIORITY-'+id,parent,title,action,module)
