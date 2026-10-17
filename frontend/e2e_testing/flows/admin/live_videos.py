"""Admin video UI journeys: enum matrix, pagination, CSV, detail and fake-save detection."""
import csv
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite, admin):
    page = admin['page']
    def load():
        return suite.go(admin,'/videos','app-admin-videos-page','/admin/videos')
    def rendered(data):
        expect(page.locator('tbody .video-row')).to_have_count(len(data['items']))
        assert data['total']>=len(data['items'])
        for index,item in enumerate(data['items']):
            expect(page.locator('tbody .video-row').nth(index).locator('.video-title')).to_have_text(item['title'])
    for index,key,values in [(1,'status',['published','pending','processing','blocked','hidden']),(2,'visibility',['public','unlisted','private']),(3,'timeRange',['today','7days','30days','thisYear'])]:
        for option_index,value in enumerate(values,1):
            def filter_case(case,index=index,key=key,value=value,option_index=option_index):
                load()
                component=page.locator('app-custom-select').nth(index)
                component.get_by_role('combobox').click()
                response=suite.response(admin,'/admin/videos',lambda:component.get_by_role('option').nth(option_index).click())
                data=response.json()
                assert parse_qs(urlsplit(response.url).query)[key]==[value]
                assert data['page']==1
                rendered(data)
                if key=='visibility':
                    assert all(item['visibility']==value for item in data['items'])
                if key=='status' and value in ('published','processing','blocked'):
                    assert all(item['status']==value for item in data['items'])
                suite.evidence(admin,case,'filtered')
                reset=suite.response(admin,'/admin/videos',lambda:page.locator('.btn-reset').click())
                assert key not in parse_qs(urlsplit(reset.url).query)
                rendered(reset.json())
                case['steps']=['Choose '+key+'='+value,'Validate actual request, page and each row','Reset filters and assert request/results']
            suite.case(admin,'A-VIDEOS-'+key.upper()+'-'+value.upper(),'A-VIDEOS.01','Video filter '+key+' '+value,'Every selected enum sends correct query; rows and reset agree with API',filter_case,module='videos')

    def search(case):
        load()
        field=page.locator('.search-box input')
        field.fill('  __hutube_qc_no_video__  ')
        response=suite.response(admin,'/admin/videos',lambda:field.press('Enter'))
        assert parse_qs(urlsplit(response.url).query)['search']==['__hutube_qc_no_video__']
        assert response.json()['total']==0
        expect(page.locator('.empty-table-cell')).to_be_visible()
        expect(page.locator('.footer-left')).not_to_contain_text('1–0')
        case['steps']=['Search whitespace-padded absent title','Assert trim, zero results and meaningful 0-row footer']
    suite.case(admin,'A-VIDEOS-SEARCH-EMPTY','A-VIDEOS.01','Trimmed empty search and zero-row footer','No match → 0 rows, total 0, footer does not say 1–0',search,module='videos')

    def pagination(case):
        first=load()
        if first['total']<=first['pageSize']:
            raise PrerequisiteMissing('Insufficient videos for two pages')
        expect(page.get_by_role('button',name='Trang trước',exact=True)).to_be_disabled()
        response=suite.response(admin,'/admin/videos',lambda:page.get_by_role('button',name='Trang tiếp',exact=True).click())
        data=response.json()
        assert data['page']==2
        assert not {v['videoId'] for v in first['items']}.intersection({v['videoId'] for v in data['items']})
        rendered(data)
        suite.evidence(admin,case,'page-2')
        response=suite.response(admin,'/admin/videos',lambda:page.get_by_role('button',name='Trang trước',exact=True).click())
        assert response.json()['page']==1
        rendered(response.json())
        case['steps']=['First → next → previous','Assert page numbers, distinct IDs, totals and each row']
    suite.case(admin,'A-VIDEOS-PAGINATION','A-VIDEOS.01','Admin next/previous pagination','Pagination agrees with API and never duplicates first-page IDs',pagination,module='videos')

    for index,key in enumerate(['title','channel','category','status','visibility','views','reports','createdAt']):
        def sort(case,index=index,key=key):
            load()
            mobile=page.viewport_size and page.viewport_size['width']<=720
            def toggle(first=False):
                if not mobile:return page.locator('thead th.col-sortable').nth(index).click()
                select=page.locator('#video-mobile-sort')
                if first and select.input_value()!=key:return select.select_option(key)
                return page.locator('.mobile-sort-direction').click()
            response=suite.response(admin,'/admin/videos',lambda:toggle(True))
            assert parse_qs(urlsplit(response.url).query)['sortBy']==[key]
            rendered(response.json())
            first_direction=parse_qs(urlsplit(response.url).query)['sortDescending']
            response=suite.response(admin,'/admin/videos',toggle)
            assert parse_qs(urlsplit(response.url).query)['sortDescending'] != first_direction
            rendered(response.json())
            case['steps']=['Actual mobile select/direction controls' if mobile else 'Actual table header controls',
                'Change '+key+' sort twice','Check opposite direction and rendered response for each action']
        suite.case(admin,'A-VIDEOS-SORT-'+key.upper(),'A-VIDEOS.01','Sort videos by '+key,'Both sort directions drive actual request and displayed rows',sort,module='videos')

    def export(case):
        data=load()
        rendered(data)
        if not data['items']:
            raise PrerequisiteMissing('No real rows available for CSV export')
        with page.expect_download() as pending:
            page.locator('.btn-export-data').click()
        path=suite.run_dir/'downloads/videos.csv'
        path.parent.mkdir(exist_ok=True)
        pending.value.save_as(path)
        with path.open(encoding='utf-8-sig',newline='') as source:
            rows=list(csv.reader(source))
        assert len(rows)==len(data['items'])+1
        assert len(rows[0])==10
        assert [row[0] for row in rows[1:]] == [v['videoId'] for v in data['items']]
        assert [row[1] for row in rows[1:]] == [v['title'] for v in data['items']]
        assert all(row[3].startswith("'@") for row in rows[1:]), 'CSV handle must escape spreadsheet formula prefix'
        case['download']=str(path.relative_to(suite.run_dir))
        case['steps']=['Export current visible page','Read real downloaded CSV','Compare row IDs/title/count/header and formula escaping']
    suite.case(admin,'A-VIDEOS-CSV','A-VIDEOS.01','CSV export matches visible page','Real 10-column CSV contains exactly the displayed IDs and safe channel handles',export,module='videos')

    def preview(case):
        data=load()
        if not data['items']:
            raise PrerequisiteMissing('No video for detail journey')
        video=data['items'][0]
        response=suite.response(admin,'/admin/videos/'+video['videoId'],lambda:page.locator('tbody .video-row').first.locator('button[title="Xem chi tiết"]').click())
        detail=response.json()
        assert detail['video']['videoId']==video['videoId']
        expect(page.locator('.modal-dialog h3')).to_have_text(video['title'])
        expect(page.locator('.preview-desc')).to_have_text(detail['description'] or 'Chưa có mô tả.')
        expect(page.locator('.drawer-loading')).to_have_count(0)
        suite.evidence(admin,case,'detail')
        page.locator('.modal-close').click()
        expect(page.locator('.modal-dialog')).to_have_count(0)
        case['resource_ids']=[video['videoId']]
        case['steps']=['Open row detail','Compare detail ID/title/description','Close and verify modal removed']
    suite.case(admin,'A-VIDEOS-DETAIL','A-VIDEOS.01','Video detail and close','Correct resource details render; loader completes and modal closes',preview,module='videos')

    def edit_cancel(case):
        data=load()
        if not data['items']:
            raise PrerequisiteMissing('No video for cancel journey')
        video=data['items'][0]
        path='/admin/videos/'+video['videoId']
        detail=suite.response(admin,path,lambda:page.locator('tbody .video-row').first.locator('button[title="Chỉnh sửa thông tin"]').click()).json()
        expect(page.locator('input[name=title]')).to_be_enabled()
        expect(page.locator('.btn-modal-confirm')).to_be_disabled()
        page.locator('input[name=title]').fill('Unsaved QC title')
        page.locator('input[name=reason]').fill('QC kiểm tra hủy chỉnh sửa')
        suite.evidence(admin,case,'unsaved-edit')
        page.locator('.btn-modal-cancel').click()
        reloaded=suite.api(admin,'get',path).json()
        assert reloaded['video']['title']==detail['video']['title']
        assert reloaded['description']==detail['description']
        case['resource_ids']=[video['videoId']]
        case['steps']=['Open edit → check reason-required disabled','Change title/reason → cancel','Read back original metadata']
    suite.case(admin,'A-VIDEOS-EDIT-CANCEL','A-VIDEOS.02','Cancel metadata edit and reason validation','Cancel preserves exact resource metadata; reason required before save',edit_cancel,module='videos')

