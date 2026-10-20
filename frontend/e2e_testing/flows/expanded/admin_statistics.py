from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);admin,owner=actors['admin'],actors['owner'];p=admin['page'];uid=owner['identity']['userId'];email=owner['identity']['email'];path='/admin/users/'+uid
    def detail():
        suite.go(admin,'/users','app-admin-users-page','/admin/users')
        suite.response(admin,'/admin/users',lambda:p.locator('input[type=search]').fill(email),params={'search':email})
        row=p.locator('.user-row').filter(has_text=email);expect(row).to_have_count(1);row.click();expect(p.locator('.detail-panel')).to_contain_text(email)
        suite.response(admin,path+'/statistics',lambda:p.locator('.statistics-action').click())
    def thirty(entry):
        detail();data=suite.response(admin,path+'/statistics',lambda:p.locator('.range-presets button').nth(1).click()).json()
        expect(p.locator('.summary-grid article').nth(1).locator('strong')).to_have_text(str(data['summary']['videosWatched']))
        expect(p.locator('.summary-grid article').nth(4).locator('strong')).to_have_text(str(data['summary']['comments']))
        entry['resource_ids']=[uid];entry['steps']=['Search exact owner email on populated multi-page dataset','Filtered result auto-selects same target','Actual 30-day preset response','UI summary equals target statistics; no first-page prerequisite']
        p.locator('.statistics-header .close-button').click()
    case(suite,admin,'FOUNDATION-A-USERS-STATISTICS-30','A-USERS.01','Thirty-day statistics on exact target',thirty,'users')
    def custom(entry):
        detail();p.locator('[name=statisticsFrom]').fill('2026-10-01');p.locator('[name=statisticsTo]').fill('2026-10-14')
        data=suite.response(admin,path+'/statistics',lambda:p.locator('.range-fields button[type=submit]').click()).json()
        expect(p.locator('.summary-grid article').nth(1).locator('strong')).to_have_text(str(data['summary']['videosWatched']))
        p.locator('.statistics-header .close-button').click();entry['steps']=['Target exact ID','Custom date fields 01/10–14/10','Actual API response and rendered watched count agree','Close completes without stale target']
    case(suite,admin,'USERS-STATISTICS-CUSTOM-DATES','A-USERS.01','Custom statistics dates use actual target data',custom,'users')
