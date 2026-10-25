"""Verify comment trees and the Admin video toolbar against isolated API fixtures."""
import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse, parse_qs

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--user-url', default='http://127.0.0.1:4307')
    parser.add_argument('--admin-url', default='http://127.0.0.1:4308')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    video_id = '11111111-1111-4111-8111-111111111111'
    date = datetime.now(timezone.utc).isoformat()
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    user = dict(userId='viewer', username='viewer', email='viewer@example.test', displayName='Viewer',
                emailVerified=True, isAdmin=True, role='super_admin', permissions=['video.view'])
    session = dict(accessToken='isolated-browser-test', expiresAt=expires, user=user)
    channel = dict(channelId='channel', name='Test channel', handle='test-channel', subscriberCount=0,
                   videoCount=1, avatarUrl=None, ownerUserId='creator')
    video = dict(videoId=video_id, channelId='channel', channelName='Test channel', channelHandle='test-channel',
                 title='Comment regression', description='Test description', videoUrl='', thumbnailUrl=None,
                 fileSize=0, duration=120, visibility='public', status='published', moderationStatus='approved',
                 languageCode='vi', createdAt=date, publishedAt=date, ageRestricted=False, categoryId=None,
                 tags=[], chapters=[], stats=dict(views=12, likes=0, dislikes=0, comments=13,
                 averageRating=None, ratingCount=0, shares=0), viewerState=None)

    def comment(id, parent=None, count=0):
        return dict(commentId=id, videoId=video_id, userId='author', displayName='Vinh Mường',
                    parentCommentId=parent, content=f'Comment {id}', createdAt=date, updatedAt=date,
                    likes=1200000, dislikes=4321, myReaction=None, replyCount=count, status='visible')

    root = comment('root', count=7)
    groups = {'root': [comment(f'child-{i}', 'root', 4 if i == 0 else 0) for i in range(7)],
              'child-0': [comment(f'nested-{i}', 'child-0') for i in range(4)]}
    posts, pages, reactions, errors = [], [], [], []
    failed = False

    def api(route):
        nonlocal failed
        request = route.request
        origin = request.headers.get('origin', args.user_url)
        cors = {'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Credentials': 'true',
                'Access-Control-Allow-Headers': request.headers.get('access-control-request-headers', '*'),
                'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}

        def respond(data, status=200):
            route.fulfill(status=status, content_type='application/json', headers=cors, body=json.dumps(data))

        if request.method == 'OPTIONS':
            route.fulfill(status=204, headers=cors)
            return
        parsed = urlparse(request.url)
        path = parsed.path.split('/api/v1', 1)[-1]
        query = parse_qs(parsed.query)
        data = dict(items=[], page=1, pageSize=20, total=0)
        if path == '/auth/refresh':
            data = session
        elif path in ['/auth/me', '/admin/me']:
            data = user
        elif path == '/auth/session/player-preferences':
            data = dict(volume=1, muted=False)
        elif path == '/plans/my-plan':
            data = dict(features={}, subscription=None)
        elif path == f'/videos/{video_id}':
            data = video
        elif path == f'/videos/{video_id}/playback':
            data = dict(videoId=video_id, title=video['title'], visibility='public', duration=120,
                        resumeAtSeconds=0, progress=0, renditions=[])
        elif path == f'/videos/{video_id}/comments' and request.method == 'POST':
            body = request.post_data_json
            posts.append(body)
            if body['content'] == 'Retry draft' and not failed:
                failed = True
                respond(dict(code='TEMPORARY_FAILURE'), 503)
                return
            parent = body['parentCommentId']
            data = {**comment(f'posted-{len(posts)}', parent), 'content': body['content'], 'userId': 'viewer'}
            groups.setdefault(parent, []).append(data)
            if parent == 'root':
                root['replyCount'] += 1
        elif path == f'/videos/{video_id}/comments':
            data = dict(items=[root], page=1, pageSize=20, total=1)
        elif path.startswith('/comments/') and path.endswith('/replies'):
            parent = path.split('/')[2]
            page, size = int(query.get('page', ['1'])[0]), int(query.get('pageSize', ['20'])[0])
            pages.append((parent, page, size))
            items = groups.get(parent, [])
            data = dict(items=items[(page - 1) * size:page * size], page=page, pageSize=size, total=len(items))
        elif path.endswith('/reaction'):
            body = request.post_data_json if request.method != 'DELETE' else {'type': None}
            reactions.append(body)
            data = dict(myReaction=body['type'], likes=1200001, dislikes=4322)
        elif path == '/channels/me':
            respond({}, 404)
            return
        elif path.startswith('/channels/'):
            data = dict(status='inactive', notificationsEnabled=False) if path.endswith('/subscribe-status') else channel
        elif path in ['/categories', '/violation-types', '/subscriptions', '/downloads']:
            data = []
        respond(data)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, locale='vi-VN')
        context.route('**/api/v1/**', api)
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(f'{args.user_url}/watch/{video_id}')
        page.wait_for_load_state('networkidle')
        root_row = page.locator('[data-comment-id="root"]')
        own_body = root_row.locator(':scope > .comment-body')
        branch = own_body.locator(':scope > .replies-list')
        expect(branch.locator(':scope > .comment-row')).to_have_count(3)
        assert pages == [('root', 1, 3)], pages
        root_row.scroll_into_view_if_needed()
        page.evaluate('(node) => scrollTo(0, scrollY + node.getBoundingClientRect().top - 120)', root_row.element_handle())
        root_row.screenshot(path=str(args.artifacts / 'comments-tree-preview.png'))
        actions = own_body.locator(':scope > .comment-actions')
        like = actions.get_by_role('button', name='Thích', exact=True)
        dislike = actions.get_by_role('button', name='Không thích', exact=True)
        expect(like).to_have_text('1,2Tr')
        expect(dislike).to_have_text('')
        expect(dislike.locator('svg')).to_have_count(1)
        like.click()
        expect(like).to_have_attribute('aria-pressed', 'true')
        dislike.click()
        expect(dislike).to_have_attribute('aria-pressed', 'true')
        expect(branch.get_by_role('button', name='Xem thêm 4 câu trả lời', exact=True)).to_be_visible()
        branch.get_by_role('button', name='Xem thêm 4 câu trả lời', exact=True).click()
        expect(branch.locator(':scope > .comment-row')).to_have_count(6)
        branch.get_by_role('button', name='Xem thêm 1 câu trả lời', exact=True).click()
        expect(branch.locator(':scope > .comment-row')).to_have_count(7)
        child = page.locator('[data-comment-id="child-0"]')
        child_actions = child.locator(':scope > .comment-body > .comment-actions')
        child_actions.get_by_role('button', name='Xem 4 câu trả lời', exact=True).click()
        nested = child.locator(':scope > .comment-body > .replies-list')
        expect(nested.locator(':scope > .comment-row')).to_have_count(3)
        assert nested.locator(':scope > .comment-row > .comment-body').first.bounding_box()['x'] > child.locator(':scope > .comment-body').bounding_box()['x']
        child_actions.get_by_role('button', name='Trả lời', exact=True).click()
        child.get_by_role('textbox', name='Viết câu trả lời…', exact=True).fill('s')
        child.get_by_role('textbox', name='Viết câu trả lời…', exact=True).press('Enter')
        expect(child.locator('.reply-composer')).to_have_count(0)
        assert posts[-1] == dict(content='s', parentCommentId='child-0'), posts
        expect(nested.locator(':scope > .comment-row')).to_have_count(3)
        expect(nested.locator(':scope > .comment-row').first).to_contain_text('s')
        actions.get_by_role('button', name='Trả lời', exact=True).click()
        root_input = own_body.locator(':scope > .reply-composer input')
        root_input.fill('Retry draft')
        own_body.locator(':scope > .reply-composer').get_by_role('button', name='Gửi', exact=True).click()
        expect(own_body.locator(':scope > .reply-error')).to_be_visible()
        expect(root_input).to_have_value('Retry draft')
        own_body.locator(':scope > .reply-composer').get_by_role('button', name='Gửi', exact=True).click()
        expect(own_body.locator(':scope > .reply-composer')).to_have_count(0)
        page.evaluate('scrollTo(0, 0)')
        page.screenshot(path=str(args.artifacts / 'comments-tree-desktop.png'), full_page=True)
        page.set_viewport_size({'width': 375, 'height': 900})
        page.evaluate("document.documentElement.setAttribute('data-theme', 'dark'); document.body.classList.add('dark-theme')")
        page.evaluate('scrollTo(0, 0)')
        page.screenshot(path=str(args.artifacts / 'comments-tree-narrow-dark.png'), full_page=True)
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Horizontal page overflow'
        for rect in child.locator('.reply-composer, .comment-actions').evaluate_all('(nodes) => nodes.map(n => n.getBoundingClientRect().right)'):
            assert rect <= 375, rect
        page.evaluate("localStorage.setItem('hutube_lang', 'en')")
        page.reload()
        page.wait_for_load_state('networkidle')
        expect(page.locator('[data-comment-id="root"] > .comment-body > .comment-actions').get_by_role('button', name='Like', exact=True)).to_have_text('1.2M')
        admin = context.new_page()
        admin.on('pageerror', lambda error: errors.append(str(error)))
        admin.goto(f'{args.admin_url}/videos')
        admin.wait_for_load_state('networkidle')
        expect(admin.locator('.filters-row-2')).to_be_visible()
        expect(admin.locator('.filters-row-2 button')).to_have_count(1)
        expect(admin.locator('a[href*="/studio/upload"], .btn-add-video')).to_have_count(0)
        expect(admin.locator('.btn-export-data')).to_be_visible()
        admin.screenshot(path=str(args.artifacts / 'admin-video-toolbar.png'))
        assert not errors, errors
        browser.close()
    (args.artifacts / 'result.json').write_text(json.dumps(dict(status='passed', posts=posts, pages=pages, reactions=reactions), indent=2), encoding='utf-8')
    print('PASS: comment reply submission/retry, nested trees, paging, icons, vi/en counts, narrow/dark layout and Admin toolbar')


if __name__ == '__main__':
    main()
