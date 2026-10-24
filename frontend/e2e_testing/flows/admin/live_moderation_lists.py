"""Functional moderation filters against complete real API datasets, no claims."""
from playwright.sync_api import expect

def run(suite,admin):
    page=admin['page']
    def all_pages(path,params=None):
        result=[]; number=1
        while True:
            data=suite.api(admin,'get',path,params={**(params or {}),'page':number,'pageSize':100}).json()
            items=data if isinstance(data,list) else data['items']
            result.extend(items)
            if isinstance(data,list) and len(items)<100 or isinstance(data,dict) and number*data['pageSize']>=data['total']: break
            number+=1
        return result
    def queue(case):
        active=all_pages('/admin/moderation/queue')
        processed=all_pages('/admin/moderation/queue',{'status':'processed'})
        values=active+processed
        assert len({item['moderationCaseId'] for item in values})==len(values)
        suite.go(admin,'/moderation/videos','app-admin-moderation-page')
        expect(page.locator('.loading-state')).to_have_count(0)
        for index,status in enumerate(['pending','reviewing','processed','escalated']):
            page.locator('.status-tabs [role=tab]').nth(index).click()
            expected=[item for item in values if item['status'] in (['approved','rejected','resolved'] if status=='processed' else [status])]
            expected.sort(key=lambda item:item['submittedAt'])
            expect(page.locator('.queue-table tbody tr')).to_have_count(len(expected))
            assert int(page.locator('.status-tabs [role=tab]').nth(index).locator('b').inner_text())==len(expected)
            # A video may have multiple historical review cases. Assert each
            # ordered row rather than assuming its video ID is unique.
            for row,item in zip(page.locator('.queue-table tbody tr').all(),expected):
                expect(row).to_contain_text(item['videoId'][:8])
                expect(row).to_contain_text(item['title'])
            suite.evidence(admin,case,'queue-'+status)
        page.locator('.status-tabs [role=tab]').first.click()
        pending=[item for item in values if item['status']=='pending']
        for value in ['ALL','short','medium','long']:
            page.locator('.filter-field select').nth(1).select_option(value)
            expected=[item for item in pending if value=='ALL' or value=='short' and item['duration']<300 or value=='medium' and 300<=item['duration']<=900 or value=='long' and item['duration']>900]
            expect(page.locator('.queue-table tbody tr')).to_have_count(len(expected))
            suite.evidence(admin,case,'queue-duration-'+value)
        page.locator('.filter-field select').nth(1).select_option('ALL')
        for value in ['ALL','low','high']:
            page.locator('.filter-field select').nth(2).select_option(value)
            expected=[item for item in pending if value=='ALL' or item['riskLevel']==value]
            expect(page.locator('.queue-table tbody tr')).to_have_count(len(expected))
            suite.evidence(admin,case,'queue-risk-'+value)
        case['steps']=['Read all active and processed API pages','Each queue status → exact row IDs/titles and tab count','Each duration enum → correct boundaries','Every risk enum → real matching count']
    suite.case(admin,'LIVE-MODERATION-QUEUE-ENUMS','A-MODERATION.01','Queue status/duration/risk matrix','All filters render exact items and counts from the real queue dataset',queue,module='moderation')
    def reports(case):
        suite.go(admin,'/moderation/reports','app-admin-reports-page')
        for index,status in enumerate(['pending','reviewing','resolved','escalated','ALL']):
            response=suite.response(admin,'/admin/reports/cases',lambda index=index:page.locator('.status-tabs button').nth(index).click(),params={'status':'' if status=='ALL' else status})
            assert response.json()['page']==1
            values=all_pages('/admin/reports/cases',{} if status=='ALL' else {'status':status})
            expect(page.locator('.loading-state')).to_have_count(0)
            expect(page.locator('.data-table tbody tr')).to_have_count(min(20,len(values)))
            for row,item in zip(page.locator('.data-table tbody tr').all(),values[:20]):
                expect(row.locator('.target-title')).to_have_text(item['targetTitle'] or 'Đối tượng không còn khả dụng')
                assert status=='ALL' or item['status']==status
            if not values: expect(page.locator('.empty-state')).to_be_visible()
            suite.evidence(admin,case,'reports-'+status)
        for target in ['video','comment','channel','ALL']:
            suite.response(admin,'/admin/reports/cases',lambda target=target:page.locator('.report-primary-filters select').select_option(target),params={'targetType':'' if target=='ALL' else target})
            values=all_pages('/admin/reports/cases',{} if target=='ALL' else {'targetType':target})
            expect(page.locator('.loading-state')).to_have_count(0)
            expect(page.locator('.data-table tbody tr')).to_have_count(min(20,len(values)))
            assert all(target=='ALL' or item['targetType']==target for item in values)
            suite.evidence(admin,case,'reports-target-'+target)
        case['steps']=['Every report status tab → real status query and page reset','Compare first displayed page, count and every target title','Every target-type enum → API query and matching dataset']
    suite.case(admin,'LIVE-MODERATION-REPORT-LIST-ENUMS','A-MODERATION.03','Report case status/target matrix','All report tabs and target filters agree with actual API records; no real report is claimed or altered',reports,module='moderation')
    for name,parent,component,endpoint,statuses in [('appeals','A-MODERATION.04','app-admin-appeals-page','/admin/appeals',['pending','reviewing','approved','rejected','escalated','ALL']),('strikes','A-MODERATION.05','app-admin-strikes-page','/admin/strikes',['active','expired','revoked','ALL'])]:
        def status_matrix(case,name=name,component=component,endpoint=endpoint,statuses=statuses):
            values=all_pages(endpoint)
            suite.go(admin,'/moderation/'+name,component)
            expect(page.locator('.loading-state')).to_have_count(0)
            for index,status in enumerate(statuses):
                page.locator('.status-tabs button').nth(index).click()
                filtered=[item for item in values if status=='ALL' or item['status']==status]
                expected=filtered[:20] if name=='appeals' else filtered
                expect(page.locator('tbody tr')).to_have_count(len(expected))
                if not expected: expect(page.locator('.empty-state')).to_be_visible()
                for row,item in zip(page.locator('tbody tr').all(),expected):
                    if name=='appeals': expect(row.locator('.target-id')).to_have_text(item['targetId'])
                    else: expect(row.locator('.channel-id')).to_have_text(item['channelId'])
                suite.evidence(admin,case,name+'-'+status)
            if name=='appeals':
                for target in ['video','channel','strike','comment','ALL']:
                    page.locator('#appeal-target-filter').select_option(target)
                    filtered=[item for item in values if target=='ALL' or item['targetType']==target]
                    expect(page.locator('tbody tr')).to_have_count(min(20,len(filtered)))
                    suite.evidence(admin,case,'appeals-target-'+target)
            case['steps']=['Read every actual '+name+' API page','Click every status tab → compare exact target/channel IDs and count','Validate empty state when no matching records','Every target enum' if name=='appeals' else 'Check active/expired/revoked from backend statuses']
        suite.case(admin,'LIVE-MODERATION-'+name.upper()+'-LIST-ENUMS',parent,name+' status matrix','Every status/target selection renders the real filtered dataset with no mutation',status_matrix,module='moderation')
