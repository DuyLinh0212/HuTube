"""Actual registration fixtures supply >50 users for complete UI pagination."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.local_db import LocalDb


def run(suite,config,actors):
    snapshot_module(suite,__file__)
    admin=actors['admin'];p=admin['page'];guest=suite.actor('users-pagination-preparation','user','guest')
    guest['api_url']=config['api_url'];db=LocalDb(config)
    def pagination(entry):
        current=suite.api(admin,'get','/admin/users',params={'page':1,'pageSize':100}).json()
        created=[];entry['resource_ids']=created
        for index in range(max(0,55-current['total'])):
            email=('qc.pagination.'+suite.run_id+'.'+str(index)+'@example.test').lower()
            response=guest['context'].request.post(config['api_url']+'/auth/register',data={
                'email':email,'username':'qc_pg_'+suite.run_id.lower().replace('.','_')+'_'+str(index),
                'displayName':'QC pagination '+str(index),'password':'QCPaginationFixture2026!'})
            suite.report['http_statuses'].append({'actor':guest['name'],'case':suite.current,
                'method':'POST','path':'/api/v1/auth/register','status':response.status,'purpose':'Actual registration fixture preparation'})
            assert response.status==201,'Registration dataset preparation HTTP '+str(response.status)
            account=db.account(email);assert account and not account['verified'] and db.account_count(email)==1
            created.append(account['user_id'])
        entry['fixture_preparation']='Actual public registration API under the existing raised QC rate limits; DB reads only verify new pending IDs. No SQL user inserts or UI registration certification.'
        data=suite.go(admin,'/users','app-admin-users-page','/admin/users')
        assert data['total']>=55 and data['page']==1 and data['hasMore']
        def rendered(value):
            expect(p.locator('.user-row')).to_have_count(len(value['items']))
            for index,item in enumerate(value['items']):expect(p.locator('.user-row').nth(index)).to_contain_text(item['email'])
        rendered(data);seen={item['userId'] for item in data['items']};total=data['total'];pages=1
        expect(p.get_by_role('button',name='Trang trước',exact=True)).to_be_disabled()
        while data['hasMore']:
            data=suite.response(admin,'/admin/users',lambda:p.get_by_role('button',name='Trang tiếp',exact=True).click()).json()
            pages+=1;assert data['page']==pages
            ids={item['userId'] for item in data['items']};assert not seen.intersection(ids)
            seen.update(ids);rendered(data)
        assert len(seen)==total
        expect(p.get_by_role('button',name='Trang tiếp',exact=True)).to_be_disabled()
        previous=suite.response(admin,'/admin/users',lambda:p.get_by_role('button',name='Trang trước',exact=True).click()).json()
        assert previous['page']==pages-1;rendered(previous)
        reset=suite.response(admin,'/admin/users',lambda:p.locator('.filter-field select').first.select_option('active')).json()
        assert reset['page']==1 and all(item['status']=='active' for item in reset['items']);rendered(reset)
        entry['dataset_total']=total;entry['pages_traversed']=pages
        entry['steps']=['Prepare enough real pending accounts for >50-row dataset','Actual UI first/next/all pages/last/previous; compare every row with API',
            'All immutable IDs appear exactly once across pages','Last next disabled; active filter resets page to one and renders matching data']
    try:case(suite,admin,'FOUNDATION-A-USERS-PAGINATION-RESET','A-USERS.01','More-than-fifty users paginate without duplicate rows and reset filters',pagination,'users')
    finally:suite.release_actor(guest)
