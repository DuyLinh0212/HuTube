"""Real watch rating controls, boundaries and restoration."""
from playwright.sync_api import expect


def run(suite, owner):
    video_id = suite.state.get('video_id')
    if not video_id:
        return
    page = owner['page']
    base = '/videos/' + video_id

    def cycle():
        suite.go(owner, '/watch/' + video_id, 'app-watch-page')
        expect(page.locator('.rating-stars')).to_be_visible()
        initial = suite.api(owner, 'get', base).json()['viewerState']['rating']
        try:
            for score in [0, 6]:
                assert suite.api(owner, 'put', base + '/rating', data={'score': score}).status == 400
                assert suite.api(owner, 'get', base).json()['viewerState']['rating'] == initial
            for score in [5, 2, None]:
                with page.expect_response(lambda response, score=score: response.request.method == ('DELETE' if score is None else 'PUT')
                                          and response.url.endswith(base + '/rating')) as pending:
                    if score is None:
                        page.locator('.rating-clear').click()
                    else:
                        page.locator('.rating-star').nth(score - 1).click()
                assert pending.value.status == 200 and pending.value.json()['myRating'] == score
                assert suite.api(owner, 'get', base).json()['viewerState']['rating'] == score
                suite.go(owner, '/watch/' + video_id, 'app-watch-page')
                expect(page.locator('.rating-stars')).to_be_visible()
                for index in range(5):
                    expect(page.locator('.rating-star').nth(index)).to_have_attribute(
                        'aria-pressed', 'true' if score is not None and index < score else 'false')
        finally:
            result = suite.api(owner, 'delete', base + '/rating') if initial is None else suite.api(
                owner, 'put', base + '/rating', data={'score': initial})
            assert result.status == 200
    suite.case(owner, 'U-WATCH-RATING-01', 'Score 0/6 bị chặn; 5→2→clear persist sau reload', cycle,
               expected='Biên API 400 không thay đổi; PUT/DELETE 200; aria/UI/API đồng nhất; phục hồi rating gốc')
