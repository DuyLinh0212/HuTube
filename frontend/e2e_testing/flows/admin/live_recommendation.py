"""Real matrix check/export/preview. Model job requires a reachable service."""
import csv
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,admin):
    page=admin['page']
    def check(case):
        data=suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        expect(page.locator('#recommendations-model-tab')).to_have_attribute('aria-selected','true')
        result=suite.response(admin,'/admin/recommendations/status',lambda:page.locator('.status-panel .actions .primary').click()).json()
        assert result['current']['pairs']>=0 and result['current']['users']>=0 and result['current']['videos']>=0
        expect(page.locator('.matrix-strip')).to_be_visible()
        case['steps']=['Open model tab','Click real check data','Assert matrix counts and rendered data strip']
        case['matrix_counts']=result['current']
    suite.case(admin,'A-RECOMMENDATION-LIVE-CHECK','A-RECOMMENDATION.02','Check actual matrix status','Real matrix counts load through API and checking button',check,module='recommendation')
    def export(case):
        # CSV uses current local data and can work even when the stored active
        # model's external snapshot is unavailable to the status endpoint.
        suite.go(admin,'/recommendations','app-recommendations-page')
        with page.expect_download() as pending:
            page.locator('.status-panel .actions .secondary').click()
        path=suite.run_dir/'downloads/interactions_current.csv'
        path.parent.mkdir(exist_ok=True)
        pending.value.save_as(path)
        rows=list(csv.reader(path.open(encoding='utf-8-sig',newline='')))
        assert rows and len(rows[0])>=3
        preview=suite.api(admin,'get','/admin/recommendations/matrix-preview').json()
        assert rows[0]==preview['columns']
        assert len(rows)-1==preview['total']
        assert all(len(row)==len(rows[0]) for row in rows[1:])
        case['download']='downloads/interactions_current.csv'
        case['steps']=['Download actual matrix CSV','Parse header and each row','Compare total and columns with preview API']
    suite.case(admin,'A-RECOMMENDATION-LIVE-CSV','A-RECOMMENDATION.02','Matrix CSV content consistency','Downloaded matrix has correct actual header, row widths and total',export,module='recommendation')
    def preview(case):
        suite.go(admin,'/recommendations','app-recommendations-page','/admin/recommendations/status')
        data=suite.api(admin,'get','/admin/recommendations/matrix-preview').json()
        page.locator('.model-preview-toggle button').click()
        expect(page.locator('.model-preview tbody tr')).to_have_count(max(1,len(data['rows'])))
        expect(page.locator('.model-preview-toggle button')).to_have_attribute('aria-expanded','true')
        suite.evidence(admin,case,'matrix-visible')
        page.locator('.model-preview-toggle button').click()
        expect(page.locator('.model-preview')).to_have_count(0)
        expect(page.locator('.model-preview-toggle button')).to_have_attribute('aria-expanded','false')
        case['steps']=['Show → actual preview response','Assert row count and expanded state','Hide → region removed']
    suite.case(admin,'A-RECOMMENDATION-LIVE-PREVIEW','A-RECOMMENDATION.02','Matrix show/hide','Preview loads real rows and closes correctly',preview,module='recommendation')
