"""Watch reactions/comments and cross-user authorization with the uploaded fixture."""
from playwright.sync_api import expect


def run(suite, owner, member):
    page, video_id = owner['page'], suite.state.get('video_id')
    if not video_id:
        suite.blocked(owner, 'U-WATCH-REACTION-01', 'Like/dislike/clear', 'No uploaded video checkpoint')
        return
    base = '/videos/' + video_id

    def watch():
        suite.go(owner, '/watch/' + video_id, 'app-watch-page')
        expect(page.locator('.reaction-group')).to_be_visible()

    def reactions():
        watch()
        initial = suite.api(owner, 'get', base).json()['viewerState']['reaction']
        try:
            # Normalize only the synthetic fixture before the asserted UI cycle.
            assert suite.api(owner, 'delete', base + '/reaction').status == 200
            watch()
            buttons = page.locator('.reaction-group button')
            for index, expected, method in [(0,'like','PUT'),(1,'dislike','PUT'),(1,None,'DELETE')]:
                with page.expect_response(lambda r: r.request.method == method and r.url.endswith(base + '/reaction')) as pending:
                    buttons.nth(index).click()
                assert pending.value.status == 200
                assert pending.value.json()['myReaction'] == expected
                expect(buttons.nth(index)).to_have_attribute('aria-pressed', 'false' if expected is None else 'true')
                assert suite.api(owner, 'get', base).json()['viewerState']['reaction'] == expected
            watch()
            expect(buttons.nth(0)).to_have_attribute('aria-pressed','false')
            expect(buttons.nth(1)).to_have_attribute('aria-pressed','false')
        finally:
            restored = suite.api(owner, 'put', base + '/reaction', data={'type':initial}) if initial else suite.api(owner, 'delete', base + '/reaction')
            assert restored.status == 200
    suite.case(owner, 'U-WATCH-REACTION-01', 'Like → dislike → clear qua UI; reload', reactions,
               expected='Chỉ một reaction của owner; UI/API cùng trạng thái; phục hồi baseline')

    comment = {}
    text = 'HuTube E2E — Bình luận fixture có Unicode <script>text only</script>'
    def create_comment():
        watch()
        expect(page.locator('.comment-composer button[type=submit]')).to_be_disabled()
        result = suite.api(owner, 'get', base + '/comments')
        assert result.status == 200
        comment.update(next((item for item in result.json()['items'] if item['content'] == text and item['userId'] == owner['user_id']), {}))
        if comment:
            expect(page.locator('.comment-row').filter(has_text=text)).to_have_count(1)
            return 'reused'
        page.locator('textarea[name=comment]').fill(text)
        with page.expect_response(lambda r: r.request.method == 'POST' and r.url.endswith(base + '/comments')) as pending:
            page.locator('.comment-composer button[type=submit]').click()
        assert pending.value.status in (200,201)
        comment.update(pending.value.json())
        suite.state['comment_id'] = comment['commentId']; suite.save()
        watch()
        expect(page.locator('.comment-row').filter(has_text=text)).to_have_count(1)
        assert page.locator('.comment-row script').count() == 0
    suite.case(owner, 'U-WATCH-COMMENT-01', 'Tạo bình luận Unicode/XSS dạng text và reload', create_comment,
               expected='POST persist đúng author; không thực thi script; trống không submit')

    if not comment:
        return

    def denied():
        response = suite.api(member, 'delete', '/comments/' + comment['commentId'])
        assert response.status in (403,404)
        items = suite.api(owner, 'get', base + '/comments').json()['items']
        assert any(item['commentId'] == comment['commentId'] for item in items)
    suite.case(member, 'X-COMMENT-ACCESS-01', 'Member không xóa bình luận của owner', denied,
               module='access', expected='403/404; bình luận vẫn tồn tại')

    def delete():
        watch()
        row = page.locator('.comment-row').filter(has_text=text)
        page.once('dialog',lambda dialog:dialog.dismiss())
        row.locator('.is-danger').click()
        expect(row).to_have_count(1)
        page.once('dialog',lambda dialog:dialog.accept())
        with page.expect_response(lambda r:r.request.method=='DELETE' and r.url.endswith('/comments/' + comment['commentId'])) as pending:
            row.locator('.is-danger').click()
        assert pending.value.status in (200,204)
        watch()
        expect(row).to_have_count(0)
        assert not any(item['commentId'] == comment['commentId'] for item in suite.api(owner,'get',base+'/comments').json()['items'])
    suite.case(owner, 'U-WATCH-COMMENT-DELETE-01', 'Hủy rồi xóa bình luận đúng ID', delete,
               expected='Cancel giữ bình luận; confirm xóa; reload không còn bình luận')
