"""Use Watch playlist picker, then verify ownership and removal in Playlist UI."""
from playwright.sync_api import expect


def run(suite, owner, member):
    playlist_id,video_id=suite.state.get('playlist_id'),suite.state.get('video_id')
    if not playlist_id or not video_id:
        suite.blocked(owner,'U-PLAYLIST-ITEM-01','Thêm video vào playlist','Missing playlist/video checkpoint')
        return
    path='/playlists/'+playlist_id
    page=owner['page']

    def add():
        existing=suite.api(owner,'get',path)
        assert existing.status==200
        suite.go(owner,'/watch/'+video_id,'app-watch-page')
        expect(page.locator('.playlist-action-button')).to_be_visible()
        page.locator('.playlist-action-button').click()
        target=page.locator('.playlist-picker__row').filter(has_text=existing.json()['name'])
        expect(target).to_be_visible()
        if any(item['videoId']==video_id for item in existing.json()['items']):
            # Read reused resource via the detail page; no duplicate mutation.
            suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
            expect(page.locator('.video-row')).to_have_count(1)
            return 'reused'
        with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith(path+'/videos')) as pending:
            target.click()
        assert pending.value.status in (200,201)
        expect(page.locator('#playlist-picker-dialog')).to_have_count(0)
        page.locator('.playlist-action-button').click()
        expect(target).to_be_disabled()
        page.locator('#playlist-picker-dialog .share-popover__close').click()
        stored=suite.api(owner,'get',path).json()
        assert sum(item['videoId']==video_id for item in stored['items'])==1
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        row=page.locator('.video-row').filter(has=page.locator('a[href="/watch/'+video_id+'"]'))
        expect(row).to_have_count(1)
        expect(row.locator('.row-actions button').nth(0)).to_be_disabled()
        expect(row.locator('.row-actions button').nth(1)).to_be_disabled()
    suite.case(owner,'U-PLAYLIST-ITEM-01','Thêm video qua Watch picker, reload playlist',add,
               expected='Một item đúng video ID; nút thêm disabled; một item không reorder vượt biên')

    def denied():
        response=suite.api(member,'post',path+'/videos',data={'videoId':video_id})
        assert response.status in (403,404)
        assert sum(item['videoId']==video_id for item in suite.api(owner,'get',path).json()['items'])==1
    suite.case(member,'X-PLAYLIST-EDIT-01','Member không thêm video vào playlist owner',denied,
               module='access',expected='403/404; playlist không thay đổi')

    def remove():
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        row=page.locator('.video-row').filter(has=page.locator('a[href="/watch/'+video_id+'"]'))
        page.once('dialog',lambda dialog:dialog.dismiss())
        row.locator('.remove-button').click()
        expect(row).to_have_count(1)
        page.once('dialog',lambda dialog:dialog.accept())
        with page.expect_response(lambda response:response.request.method=='DELETE' and response.url.endswith(path+'/videos/'+video_id)) as pending:
            row.locator('.remove-button').click()
        assert pending.value.status in (200,204)
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        expect(page.locator('.empty-items')).to_be_visible()
        assert not any(item['videoId']==video_id for item in suite.api(owner,'get',path).json()['items'])
        assert suite.api(owner,'get','/videos/'+video_id).status==200
    suite.case(owner,'U-PLAYLIST-REMOVE-01','Cancel rồi remove item; giữ video nguồn',remove,
               expected='Cancel giữ item; DELETE chỉ xóa liên kết; video nguồn vẫn tồn tại')
