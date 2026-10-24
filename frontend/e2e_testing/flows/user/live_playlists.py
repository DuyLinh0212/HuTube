"""Disposable playlist creation, every visibility, boundaries and multi-item ordering."""
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner,other):
    page=owner['page']
    fixture={}
    def detail():
        path='/playlists/'+fixture['id']
        suite.go(owner,path,'app-playlists-page',path)
        return path
    def create(case):
        suite.go(owner,'/playlists','app-playlists-page','/playlists')
        page.locator('#playlist-name').fill('   ')
        expect(page.locator('.create-card button.full-button')).to_be_disabled()
        name='HuTube QC — Playlist validation '+suite.run_id
        page.locator('#playlist-name').fill(name)
        page.locator('#playlist-description').fill('Fixture riêng cho kiểm thử; không sửa playlist cá nhân.')
        page.locator('#playlist-visibility').select_option('private')
        value=suite.response(owner,'/playlists',lambda:page.locator('.create-card button.full-button').click(),method='POST',status=(200,201)).json()
        fixture['id']=value['playlistId']
        fixture['name']=name
        (suite.run_dir/'playlist-recovery.json').write_text(__import__('json').dumps({'playlist_id':fixture['id'],'owner_id':owner['identity']['userId']}),encoding='utf-8')
        assert value['userId']==owner['identity']['userId']
        page.wait_for_url('**/playlists/'+fixture['id'])
        expect(page.locator('.hero-copy h1')).to_contain_text(name)
        assert suite.api(owner,'get','/playlists/'+fixture['id']).json()['name']==name
        case['resource_ids']=[fixture['id']]
        case['steps']=['Whitespace → create disabled','Create private Unicode playlist','Assert response owner/ID, UI and read-back']
    suite.case(owner,'U-PLAYLIST-LIVE-CREATE','U-PLAYLIST.01','Create new private playlist through UI','Exactly one new playlist belongs to supplied owner and persists',create,module='playlists')
    if 'id' not in fixture:
        return
    try:
        for visibility in ['public','unlisted','private']:
            def change(case,visibility=visibility):
                path=detail()
                page.locator('.title-edit-button').click()
                page.locator('#edit-playlist-visibility').select_option(visibility)
                value=suite.response(owner,path,lambda:page.locator('.edit-form button[type=submit]').click(),method='PATCH').json()
                assert value['visibility']==visibility
                detail()
                stored=suite.api(owner,'get',path).json()
                assert stored['visibility']==visibility
                suite.evidence(owner,case,'owner-persisted')
                status=(403,404) if visibility=='private' else 200
                foreign=suite.api(other,'get',path,expected=status)
                if visibility!='private':
                    assert foreign.json()['playlistId']==fixture['id']
                else:
                    assert 'items' not in foreign.json()
                case['resource_ids']=[fixture['id']]
                case['steps']=['Edit → '+visibility,'Save → reload/API','Second supplied account checks visibility access']
            suite.case(owner,'U-PLAYLIST-LIVE-VISIBILITY-'+visibility.upper(),'U-PLAYLIST.02','Playlist '+visibility+' access/persistence','Visibility persists; other identity can only read allowed visibility',change,module='playlists')
        def cancel(case):
            path=detail()
            baseline=suite.api(owner,'get',path).json()
            page.locator('.title-edit-button').click()
            page.locator('#edit-playlist-name').fill('Unsaved QC name')
            page.locator('#edit-playlist-description').fill('Unsaved QC description')
            page.locator('#edit-playlist-visibility').select_option('public')
            suite.evidence(owner,case,'unsaved-dialog')
            page.locator('.playlist-modal .modal-close').click()
            detail()
            stored=suite.api(owner,'get',path).json()
            for key in ['name','description','visibility']:
                assert stored[key]==baseline[key]
            case['steps']=['Change every metadata field','Close without save','Reload → exact baseline metadata']
        suite.case(owner,'U-PLAYLIST-LIVE-CANCEL','U-PLAYLIST.02','Cancel playlist editor','All unsaved metadata is discarded',cancel,module='playlists')
        def blank(case):
            path=detail()
            baseline=suite.api(owner,'get',path).json()
            page.locator('.title-edit-button').click()
            page.locator('#edit-playlist-name').fill('   ')
            response=suite.response(owner,path,lambda:page.locator('.edit-form button[type=submit]').click(),method='PATCH',status=400)
            expect(page.locator('[role=alert]')).to_be_visible()
            assert suite.api(owner,'get',path).json()['name']==baseline['name']
            case['steps']=['Edit name to whitespace','Submit → 400','Visible error + original persisted name']
        suite.case(owner,'U-PLAYLIST-LIVE-NAME-INVALID','U-PLAYLIST.01','Whitespace playlist name rejection','Server rejects whitespace; UI exits busy/error state and original name remains',blank,module='playlists')

        # Select two real public videos. Fixture insertion is setup, not upload evidence.
        search=suite.api(owner,'get','/videos/search',params={'sort':'newest','pageSize':20}).json()
        ids=[v['videoId'] for v in search['items'][:2]]
        for video_id in ids:
            suite.api(owner,'post','/playlists/'+fixture['id']+'/videos',expected=(200,201),data={'videoId':video_id})
        def ordering(case):
            if len(ids)<2:
                raise PrerequisiteMissing('Need two actual public videos for multi-item ordering')
            path=detail()
            original=suite.api(owner,'get',path).json()
            assert [v['videoId'] for v in original['items']]==ids
            expect(page.locator('.video-row .row-actions').first.locator('button').nth(0)).to_be_disabled()
            expect(page.locator('.video-row .row-actions').last.locator('button').nth(1)).to_be_disabled()
            suite.response(owner,path+'/order',lambda:page.locator('.video-row .row-actions').first.locator('button').nth(1).click(),method='PUT')
            stored=suite.api(owner,'get',path).json()
            assert [v['videoId'] for v in stored['items']]==list(reversed(ids))
            detail()
            expect(page.locator('.video-row h3').first).to_have_text(stored['items'][0]['title'])
            case['resource_ids']=[fixture['id']]+ids
            case['steps']=['Two actual video links seeded once','Move first item down via UI','Reload → reversed IDs and correct row title','Boundary move buttons disabled']
        suite.case(owner,'U-PLAYLIST-LIVE-REORDER','U-PLAYLIST.03','Two-item playlist reorder','Order persists after UI reorder; first/last boundaries enforced',ordering,module='playlists')
        def foreign_mutation(case):
            path=detail()
            baseline=suite.api(owner,'get',path).json()
            for method,suffix,data in [('patch','',{'name':'Foreign unsaved QC','description':baseline.get('description'),'visibility':baseline['visibility']}),('post','/videos',{'videoId':ids[0]} if ids else {}),('put','/order',{'videoIds':list(reversed(ids))})]:
                suite.api(other,method,path+suffix,expected=(403,404),data=data)
            current=suite.api(owner,'get',path).json()
            assert current['name']==baseline['name']
            assert [v['videoId'] for v in current['items']]==[v['videoId'] for v in baseline['items']]
            case['steps']=['Second supplied identity attempts metadata/add/reorder','Assert 403/404','Read-back unchanged resource']
        suite.case(owner,'X-PLAYLIST-LIVE-ISOLATION','U-PLAYLIST.04','Cross-account mutation isolation','Other supplied account cannot modify owner playlist even with global admin role',foreign_mutation,module='playlists')
    finally:
        response=suite.api(owner,'delete','/playlists/'+fixture['id'],expected=(200,204))
        suite.api(owner,'get','/playlists/'+fixture['id'],expected=404)
        suite.report['cleanup'].append({'resource':'test playlist','id':fixture['id'],'status':'deleted-test-fixture'})
        (suite.run_dir/'playlist-recovery.json').unlink(missing_ok=True)
