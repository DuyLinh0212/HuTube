"""A fixed 55-user dataset for real multi-page UI/API assertions."""
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect


def run(suite, admin, owner):
    page = admin['page']
    prefix = 'hutube.e2e.pagination.'

    def pagination():
        # Only LocalDb's managed database is reachable here. Seed once; never
        # count these metadata fixtures as browser registration evidence.
        suite.db.sql("""INSERT INTO users
            (username,email,password_hash,display_name,status,email_verified_at,role_id)
            SELECT 'hutube_page_' || lpad(n::text,3,'0'),
              'hutube.e2e.pagination.' || lpad(n::text,3,'0') || '@example.test',
              u.password_hash,'HuTube E2E pagination ' || lpad(n::text,3,'0'),
              'active',now(),u.role_id
            FROM users u CROSS JOIN generate_series(1,55) n
            WHERE u.user_id=:'owner'::uuid ON CONFLICT DO NOTHING;""",
            {'owner': owner['user_id']})
        manifest = suite.db.sql("SELECT json_agg(json_build_object('id',user_id,'email',email) ORDER BY email) FROM users WHERE email LIKE 'hutube.e2e.pagination.%@example.test' AND deleted_at IS NULL;")
        import json
        fixtures = json.loads(manifest)
        assert len(fixtures) == 55
        suite.state['pagination_users'] = fixtures
        suite.save()
        suite.report['pagination_fixture_count'] = len(fixtures)
        suite.go(admin, '/users', 'app-admin-users-page')

        def matches(response, number):
            query = parse_qs(urlsplit(response.url).query)
            return (response.request.method == 'GET'
                    and urlsplit(response.url).path == '/api/v1/admin/users'
                    and query.get('search') == [prefix]
                    and query.get('page', ['1']) == [str(number)])

        with page.expect_response(lambda response: matches(response, 1)) as pending:
            page.locator('input[type=search]').fill(prefix)
        seen = set()
        for number in range(1, 7):
            response = pending.value
            assert response.status == 200
            data = response.json()
            assert data['total'] == 55 and data['page'] == number
            assert len(data['items']) == (10 if number < 6 else 5)
            expect(page.locator('.user-row')).to_have_count(len(data['items']))
            expect(page.locator('.pagination strong')).to_have_text(str(number))
            for item in data['items']:
                assert item['userId'] not in seen
                seen.add(item['userId'])
                expect(page.locator('.user-row').filter(has_text=item['email'])).to_have_count(1)
            if number < 6:
                with page.expect_response(lambda response, number=number: matches(response, number + 1)) as pending:
                    page.locator('.pagination button').last.click()
        assert seen == {item['id'] for item in fixtures}
        expect(page.locator('.pagination button').last).to_be_disabled()
        with page.expect_response(lambda response: matches(response, 5)) as pending:
            page.locator('.pagination button').first.click()
        assert pending.value.status == 200
        expect(page.locator('.pagination strong')).to_have_text('5')
        exact = prefix + '001@example.test'
        with page.expect_response(lambda response: urlsplit(response.url).path == '/api/v1/admin/users'
                                  and parse_qs(urlsplit(response.url).query).get('search') == [exact]) as pending:
            page.locator('input[type=search]').fill(exact)
        assert pending.value.status == 200 and pending.value.json()['total'] == 1
        expect(page.locator('.user-row')).to_have_count(1)
        expect(page.locator('.pagination strong')).to_have_text('1')
        expect(page.locator('.pagination button').first).to_be_disabled()
        expect(page.locator('.pagination button').last).to_be_disabled()
    suite.case(admin, 'A-USERS-PAGINATION-01', '55 users: sáu trang, không trùng/thiếu; tìm kiếm reset trang',
               pagination, expected='API/UI 10+10+10+10+10+5; total 55; IDs đúng manifest; search trở về trang 1',
               steps='Seed cố định vào DB E2E; search prefix; next 5 lần; previous; search email',
               data='55 metadata fixtures @example.test; không tính là đăng ký bằng UI')
