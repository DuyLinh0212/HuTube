"""Channel list enum/tab queries, fresh detail and downloaded CSV assertions."""
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.admin import channels
from support.live_adapter import FunctionalAdapter

def run(suite,admin,owner):
    owner['user_id']=owner['identity']['userId']
    owner['email']=owner['identity']['email']
    page=admin['page']
    adapter=FunctionalAdapter(suite,'A-CHANNELS.01')
    channels.run(adapter,admin,owner)
    for index,status in enumerate(['all','active','suspended','banned']):
        def tab(case,index=index,status=status):
            suite.go(admin,'/channels','app-admin-channels-page','/admin/channels')
            # Active tab initially all. Switch away first to verify the all action.
            if index==0:
                suite.response(admin,'/admin/channels',lambda:page.locator('.channel-tabs button').nth(1).click())
            data=suite.response(admin,'/admin/channels',lambda:page.locator('.channel-tabs button').nth(index).click(),params={'status':'' if status=='all' else status,'pageSize':8}).json()
            expect(page.locator('.channel-row')).to_have_count(len(data['items']))
            assert data['page']==1
            if status!='all': assert all(item['status']==status for item in data['items']), 'Wrong row statuses for '+status+': '+str([item['status'] for item in data['items']])
            for item in data['items']:
                row=page.locator('.channel-row').filter(has_text=item['handle'])
                expect(row).to_have_count(1)
                expect(row).to_contain_text(item['name'])
            expect(page.locator('.channel-tabs button').nth(index)).to_have_class(__import__('re').compile('active'))
            case['steps']=['Select tab '+status,'Check all actual statuses and channel handles','Assert first-page reset and active tab']
        suite.case(admin,'A-CHANNELS-LIVE-TAB-'+status.upper(),'A-CHANNELS.01','Channel tab '+status,'Selected tab filters the actual API dataset and rendered IDs',tab,module='channels')
