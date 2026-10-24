"""Taxonomy UI mutations on the isolated database, including cross-role denial."""
from support.ui_confirmation import app_confirm
from playwright.sync_api import expect


def run(suite, admin, member, fixture_suffix=None):
    page = admin['page']
    category = {}
    slug = 'hutube-e2e-functional-category' + ('-'+fixture_suffix if fixture_suffix else '')
    name = 'HuTube E2E — Danh mục chức năng'

    def open_topics():
        suite.go(admin, '/topics', 'app-admin-topics-page')
        expect(page.locator('.table-card .data-table')).to_be_visible()

    def submit(method, path):
        with page.expect_response(lambda r: r.request.method == method and r.url.endswith(path)) as pending:
            page.locator('[role=dialog] button[type=submit]').click()
        assert pending.value.status in (200, 201, 204)
        expect(page.locator('[role=dialog]')).to_have_count(0)
        return pending.value

    def create():
        open_topics()
        response = suite.api(admin, 'get', '/admin/topics')
        assert response.status == 200
        existing = next((item for item in response.json() if item['slug'] == slug), None)
        if existing:
            category.update(existing)
            page.locator('input[type=search]').fill(slug)
            expect(page.locator('tbody tr')).to_contain_text(existing['name'])
            return 'reused'
        page.locator('.heading-actions .btn-primary').click()
        page.locator('[name=topicName]').fill(name)
        page.locator('[name=topicSlug]').fill(slug)
        page.locator('[name=topicDescription]').fill('Fixture kiểm thử taxonomy, không chứa dữ liệu cá nhân.')
        category.update(submit('POST', '/admin/topics').json())
        assert category['slug'] == slug and category['status'] == 'active'
        suite.state['category_id'] = category['categoryId']; suite.save()
        page.locator('input[type=search]').fill(slug)
        expect(page.locator('tbody tr')).to_contain_text(name)
    suite.case(admin, 'A-TOPICS-CREATE-01', 'Tạo danh mục qua UI và lưu checkpoint', create,
               expected='POST thành công; danh mục đúng slug xuất hiện; chạy lại không tạo trùng')

    if category:
        def edit():
            open_topics()
            page.locator('input[type=search]').fill(slug)
            page.locator('tbody tr .icon-action:not(.danger)').click()
            page.locator('[name=topicDescription]').fill('Mô tả đã cập nhật — Unicode tiếng Việt')
            page.locator('[name=topicStatus]').select_option('active')
            submit('PUT', '/admin/topics/' + category['categoryId'])
            open_topics()
            page.locator('input[type=search]').fill(slug)
            expect(page.locator('tbody tr')).to_contain_text('Mô tả đã cập nhật — Unicode tiếng Việt')
            stored = next(item for item in suite.api(admin, 'get', '/admin/topics').json() if item['categoryId'] == category['categoryId'])
            assert stored['description'] == 'Mô tả đã cập nhật — Unicode tiếng Việt'
        suite.case(admin, 'A-TOPICS-EDIT-01', 'Sửa danh mục, reload và đối chiếu API', edit,
                   expected='PUT persist mô tả Unicode; giữ ID và slug')

        def cancel_archive():
            open_topics()
            page.locator('input[type=search]').fill(slug)
            app_confirm(page, lambda: page.locator('tbody tr .danger').click(), accept=False)
            stored = next(item for item in suite.api(admin, 'get', '/admin/topics').json() if item['categoryId'] == category['categoryId'])
            assert stored['status'] == 'active'
        suite.case(admin, 'A-TOPICS-CANCEL-01', 'Hủy lưu trữ danh mục', cancel_archive,
                   expected='Dismiss confirmation giữ status active')

        def archive():
            with page.expect_response(lambda r: r.request.method == 'POST' and r.url.endswith('/' + category['categoryId'] + '/archive')) as pending:
                app_confirm(page, lambda: page.locator('tbody tr .danger').click(), accept=True)
            assert pending.value.status in (200, 204)
            open_topics()
            page.locator('input[type=search]').fill(slug)
            page.locator('.select-field select').select_option('inactive')
            expect(page.locator('tbody tr .status-pill.is-inactive')).to_be_visible()
            stored = next(item for item in suite.api(admin, 'get', '/admin/topics').json() if item['categoryId'] == category['categoryId'])
            assert stored['status'] == 'inactive'
        suite.case(admin, 'A-TOPICS-ARCHIVE-01', 'Lưu trữ danh mục và kiểm tra filter', archive,
                   expected='Status inactive persist; filter inactive hiển thị đúng row')

        def denied():
            response = suite.api(member, 'put', '/admin/topics/' + category['categoryId'], data={'name': 'Forbidden mutation', 'slug': slug, 'description': None, 'status': 'active'})
            assert response.status == 403
            stored = next(item for item in suite.api(admin, 'get', '/admin/topics').json() if item['categoryId'] == category['categoryId'])
            assert stored['name'] == name and stored['status'] == 'inactive'
        suite.case(member, 'X-TOPICS-ACCESS-01', 'User không sửa được danh mục Admin', denied,
                   module='access', expected='API 403; không thay đổi dữ liệu')

    tag = {}
    def create_tag():
        open_topics()
        page.get_by_role('tab').nth(1).click()
        tags = suite.api(admin, 'get', '/admin/tags')
        assert tags.status == 200
        tag_name='hutube-e2e-functional'+('-'+fixture_suffix if fixture_suffix else '')
        tag.update(next((item for item in tags.json() if item['name'] == tag_name), {}))
        if tag:
            page.locator('input[type=search]').fill(tag['name'])
            expect(page.locator('tbody tr')).to_contain_text(tag['name'])
            return 'reused'
        page.locator('.heading-actions .btn-primary').click()
        page.locator('[name=tagName]').fill(tag_name)
        tag.update(submit('POST', '/admin/tags').json())
        suite.state['tag_id']=tag['tagId']; suite.save()
        page.locator('input[type=search]').fill(tag['name'])
        expect(page.locator('tbody tr')).to_contain_text(tag['name'])
    suite.case(admin, 'A-TAGS-CREATE-01', 'Tạo tag qua UI', create_tag,
               expected='Tag được tạo đúng tên, không trùng fixture')

    if tag:
        def delete_tag():
            app_confirm(page, lambda: page.locator('tbody tr .danger').click(), accept=False)
            assert any(item['tagId'] == tag['tagId'] for item in suite.api(admin, 'get', '/admin/tags').json())
            with page.expect_response(lambda r: r.request.method == 'DELETE' and r.url.endswith('/admin/tags/' + tag['tagId'])) as pending:
                app_confirm(page, lambda: page.locator('tbody tr .danger').click(), accept=True)
            assert pending.value.status in (200, 204)
            assert not any(item['tagId'] == tag['tagId'] for item in suite.api(admin, 'get', '/admin/tags').json())
            expect(page.locator('.tag-name')).to_have_count(0)
        suite.case(admin, 'A-TAGS-DELETE-01', 'Hủy rồi xác nhận xóa tag chưa được sử dụng', delete_tag,
                   expected='Cancel giữ tag; confirm xóa đúng ID; GET không còn tag')
