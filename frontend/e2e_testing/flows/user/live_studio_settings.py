"""Studio settings/preferences and actual subtitle inventory."""
from playwright.sync_api import expect

def run(suite,owner):
    page=owner['page']
    channel=suite.api(owner,'get','/channels/me').json()
    channel_id=channel['channelId']
    route='/studio/settings?channelId='+channel_id
    original=suite.api(owner,'get','/account/settings').json()
    def invalid(case):
        suite.go(owner,route,'app-studio-settings-page')
        expect(page.locator('input[name=name]')).to_have_value(channel['name'])
        page.locator('input[name=name]').fill('   ')
        suite.response(owner,'/channels/'+channel_id,lambda:page.locator('.settings-save').click(),method='PATCH',status=400)
        expect(page.locator('.error[role=alert]')).to_be_visible()
        assert suite.api(owner,'get','/channels/me').json()['name']==channel['name']
        suite.evidence(owner,case,'invalid-name')
        page.reload(); expect(page.locator('input[name=name]')).to_have_value(channel['name'])
        case['steps']=['Settings real channel fields → whitespace name','Display Save action → actual PATCH 400 and error','API name unchanged; reload restores original field']
        case['resource_ids']=[channel_id]
    suite.case(owner,'LIVE-STUDIO-SETTINGS-NAME-REQUIRED','U-STUDIO.09','Studio whitespace name rejected','Settings cannot save a blank channel name or show false success',invalid,module='studio')
    try:
        for index,key,values in [(0,'language',['en','vi']),(1,'theme',['dark','light'])]:
            for value in values:
                def change(case,index=index,key=key,value=value):
                    suite.go(owner,route,'app-studio-settings-page','/account/settings')
                    select=page.locator('.settings-card--display select').nth(index)
                    if select.input_value()!=value:
                        suite.response(owner,'/account/settings',lambda:select.select_option(value),method='PUT')
                    actual=suite.api(owner,'get','/account/settings').json()
                    assert actual[key]==value
                    if key=='theme':expect(page.locator('html')).to_have_attribute('data-theme',value)
                    else:expect(page.locator('.settings-card--display h2')).to_have_text('Display' if value=='en' else 'Hiển thị')
                    page.reload()
                    expect(page.locator('.settings-card--display select').nth(index)).to_have_value(value)
                    assert suite.api(owner,'get','/account/settings').json()[key]==value
                    case['steps']=['Studio Display → '+key+' '+value,'Actual settings API read-back; translated heading or root theme','Reload → selected value and backend setting remain']
                suite.case(owner,'LIVE-STUDIO-'+key.upper()+'-'+value.upper(),'U-STUDIO.09','Studio '+key+' '+value,'Preference applies and persists through full reload',change,module='studio')
        def rapid(case):
            for index in range(3):
                suite.go(owner,route,'app-studio-settings-page')
                select=page.locator('.settings-card--display select').nth(1)
                value='light' if select.input_value()=='dark' else 'dark'
                suite.response(owner,'/account/settings',lambda:select.select_option(value),method='PUT')
                assert suite.api(owner,'get','/account/settings').json()['theme']==value
                page.wait_for_load_state('networkidle',timeout=15000)
                expect(page.locator('html')).to_have_attribute('data-theme',value)
                expect(select).to_have_value(value)
                suite.evidence(owner,case,'rapid-theme-'+str(index))
            case['steps']=['Three fresh Studio settings navigations','Immediately change theme when selectable while initial preferences may be loading','Actual PUT/read-back persists chosen value','After pending requests settle, root theme and selector must still match chosen backend preference']
        suite.case(owner,'LIVE-STUDIO-THEME-RAPID-LOAD','U-STUDIO.09','Theme selection during page initialization','Initial preference response cannot overwrite a newly saved theme',rapid,module='studio')
    finally:
        suite.api(owner,'put','/account/settings',data=original)
        assert suite.api(owner,'get','/account/settings').json()==original
        suite.report['cleanup'].append({'resource':'Studio theme/language preferences','status':'restored'})
        page.reload()
    def subtitles(case):
        values=[]; number=1
        while True:
            result=suite.api(owner,'get','/videos/manage',params={'channelId':channel_id,'page':number,'pageSize':50}).json()
            values.extend(result['items'])
            if number*result['pageSize']>=result['total']:break
            number+=1
        suite.go(owner,'/studio/subtitles?channelId='+channel_id,'app-studio-subtitles-page')
        expect(page.locator('app-studio-subtitles-page article')).to_have_count(len(values))
        for row,video in zip(page.locator('app-studio-subtitles-page article').all(),values):
            expect(row.locator('strong')).to_have_text(video['title'])
            duration_text=row.locator('p').inner_text().split('·')[-1]
            assert int(''.join(c for c in duration_text if c.isdigit()))==video['duration']
            expect(row.locator('span')).to_have_text('Chưa có phụ đề')
        assert page.locator('app-studio-subtitles-page button,app-studio-subtitles-page input[type=file]').count()==0
        page.reload(); expect(page.locator('app-studio-subtitles-page article')).to_have_count(len(values))
        case['resource_ids']=[v['videoId'] for v in values]
        case['steps']=['Read all managed video API pages','Subtitle inventory → every actual title/duration and no-subtitles state','No upload/edit controls exist in current implementation','Reload → complete same inventory']
    suite.case(owner,'LIVE-STUDIO-SUBTITLE-INVENTORY','U-STUDIO.09','Real subtitle inventory and capability','Every managed video is represented; no unsupported subtitle mutation is claimed',subtitles,module='studio')
