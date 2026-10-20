"""All real user filter enums, pagination, own account detail and statistics."""
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite, admin, owner):
    page=admin['page']
    def load():
        return suite.go(admin,'/users','app-admin-users-page','/admin/users')
    def rendered(data):
        expect(page.locator('.user-row')).to_have_count(len(data['items']))
        for index,item in enumerate(data['items']):
            expect(page.locator('.user-row').nth(index)).to_contain_text(item['email'])
        assert data['total']>=len(data['items'])
    role_codes=[role['code'] for role in suite.api(admin,'get','/admin/roles').json()]
    for index,key,values in [(0,'status',['active','banned','suspended','pending']),(1,'role',role_codes)]:
        for value in values:
            def filter_case(case,index=index,key=key,value=value):
                load()
                response=suite.response(admin,'/admin/users',lambda:page.locator('.filter-field select').nth(index).select_option(value))
                data=response.json()
                assert parse_qs(urlsplit(response.url).query)[key]==[value]
                assert data['page']==1
                rendered(data)
                assert all(item['status' if key=='status' else 'roleCode']==value for item in data['items'])
                suite.evidence(admin,case,'filtered')
                response=suite.response(admin,'/admin/users',lambda:page.locator('.filter-field select').nth(index).select_option('ALL'))
                assert key not in parse_qs(urlsplit(response.url).query)
                rendered(response.json())
                case['steps']=['Select '+key+' '+value,'Assert actual enum/query/page/results','Reset to ALL and compare request/results']
            suite.case(admin,'A-USERS-'+key.upper()+'-'+value.upper(),'A-USERS.01','User '+key+' filter '+value,'API filtering and rendered identity/count are consistent for this enum',filter_case,module='users')

    def search(case):
        load()
        field=page.locator('app-admin-users-page input[type=search]')
        # Debounced ngModelChange: register the response listener before fill.
        with page.expect_response(lambda r:urlsplit(r.url).path=='/api/v1/admin/users' and 'search=' in r.url and r.status==200,timeout=30000) as pending:
            field.fill(suite.credentials['user']['email'])
        data=pending.value.json()
        assert data['total']==1
        assert data['items'][0]['userId']==owner['identity']['userId']
        rendered(data)
        case['steps']=['Search supplied User email','Assert exactly its known identity','Compare DOM and API']
    suite.case(admin,'A-USERS-SEARCH-IDENTITY','A-USERS.01','Search supplied user identity','One matching account with correct immutable user ID',search,module='users')

    def pagination(case):
        first=load()
        if not first['hasMore']:
            raise PrerequisiteMissing('Need more than one user page')
        response=suite.response(admin,'/admin/users',lambda:page.get_by_role('button',name='Trang tiếp',exact=True).click())
        data=response.json()
        assert data['page']==2
        assert not {u['userId'] for u in first['items']}.intersection({u['userId'] for u in data['items']})
        rendered(data)
        suite.evidence(admin,case,'page-2')
        reset=suite.response(admin,'/admin/users',lambda:page.locator('.filter-field select').first.select_option('active'))
        assert reset.json()['page']==1
        rendered(reset.json())
        case['steps']=['Next page','Verify disjoint IDs','Change status → first page and correct rows']
    suite.case(admin,'A-USERS-PAGINATION-RESET','A-USERS.01','Pagination and status reset','Next page has no duplicate IDs; status changes reset page',pagination,module='users')

    def own_detail():
        load()
        suite.response(admin,'/admin/users',lambda:page.locator('input[type=search]').fill(suite.credentials['user']['email']),params={'search':suite.credentials['user']['email']})
        row=page.locator('.user-row').filter(has_text=suite.credentials['user']['email'])
        expect(row).to_have_count(1)
        path='/admin/users/'+owner['identity']['userId']
        row.click()
        data=suite.api(admin,'get',path).json()
        expect(page.locator('.detail-panel')).to_contain_text(suite.credentials['user']['email'])
        assert data['userId']==owner['identity']['userId']
        return path,data
    for action_name in ['role','lock']:
        def cancel(case,action_name=action_name):
            path,original=own_detail()
            page.locator('.detail-actions .link-action').nth(1 if action_name=='role' else 2).click()
            expect(page.locator('.action-modal button[type=submit]')).to_be_disabled()
            page.locator('.action-modal textarea').fill('QC kiểm tra hủy, không thay đổi tài khoản')
            suite.evidence(admin,case,'cancel-'+action_name)
            page.locator('.action-modal .secondary-button').click()
            expect(page.locator('.action-modal')).to_have_count(0)
            restored=suite.api(admin,'get',path).json()
            assert restored['status']==original['status']
            assert restored['roleCode']==original['roleCode']
            case['resource_ids']=[original['userId']]
            case['steps']=['Open '+action_name+' for supplied user','Check required reason','Cancel','Read back unchanged role/status']
        suite.case(admin,'A-USERS-'+action_name.upper()+'-CANCEL','A-USERS.02','Cancel user '+action_name,'Cancel must not alter account state or role',cancel,module='users')
    for index,days in enumerate([7,30,90]):
        def statistics(case,index=index,days=days):
            path,original=own_detail()
            suite.response(admin,path+'/statistics',lambda:page.locator('.statistics-action').click())
            response=suite.response(admin,path+'/statistics',lambda:page.locator('.range-presets button').nth(index).click())
            data=response.json()
            expect(page.locator('.summary-grid')).to_be_visible()
            expect(page.locator('.statistics-loading')).to_have_count(0)
            expect(page.locator('.summary-grid article').nth(1).locator('strong')).to_have_text(str(data['summary']['videosWatched']))
            expect(page.locator('.summary-grid article').nth(4).locator('strong')).to_have_text(str(data['summary']['comments']))
            case['resource_ids']=[original['userId']]
            case['steps']=['Open actual user statistics','Select last '+str(days)+' days','Compare cards with actual payload','Close dialog']
            suite.evidence(admin,case,'statistics')
            page.locator('.statistics-header .close-button').click()
            expect(page.locator('.statistics-modal')).to_have_count(0)
        suite.case(admin,'A-USERS-STATISTICS-'+str(days),'A-USERS.01','Statistics range '+str(days),'Real user/date-range metrics render and dialog closes',statistics,module='users')
