"""Channel list, details and actual downloaded CSV for the fixed owner channel."""
import csv
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect


def run(suite, admin, owner):
    page = admin['page']
    channel = suite.api(owner, 'get', '/channels/me').json()

    def listing():
        suite.go(admin, '/channels', 'app-admin-channels-page')
        page.locator('.search-box input').fill(channel['handle'])
        with page.expect_response(lambda response: urlsplit(response.url).path == '/api/v1/admin/channels'
                                  and parse_qs(urlsplit(response.url).query).get('search') == [channel['handle']]) as pending:
            page.locator('.btn-filter').click()
        assert pending.value.status == 200
        data = pending.value.json()
        assert data['total'] == 1 and data['items'][0]['channelId'] == channel['channelId']
        expect(page.locator('.channel-row')).to_have_count(1)
        expect(page.locator('.channel-row')).to_contain_text(owner['email'])
        expect(page.locator('app-custom-select').nth(1).locator('button')).to_be_disabled()
        for size in ['10', '20', '50', '8']:
            with page.expect_response(lambda response, size=size: urlsplit(response.url).path == '/api/v1/admin/channels'
                                      and parse_qs(urlsplit(response.url).query).get('pageSize') == [size]) as pending:
                page.locator('.page-size-select-wrap select').select_option(size)
            assert pending.value.status == 200 and pending.value.json()['total'] == 1
            expect(page.locator('.channel-row')).to_have_count(1)
        page.locator('.channel-row').click()
        expect(page.locator('.drawer-card h2')).to_have_text(channel['name'])
        expect(page.locator('.drawer-card')).to_contain_text(channel['handle'])
        detail = suite.api(admin, 'get', '/admin/channels/' + channel['channelId'])
        assert detail.status == 200 and detail.json()['channel']['ownerUserId'] == owner['user_id']
        page.locator('.drawer-close').click()
        expect(page.locator('.drawer-card')).to_have_count(0)
    suite.case(admin, 'A-CHANNELS-LIST-01', 'Search/pageSize/detail đúng owner; time filter disabled', listing,
               expected='Một kênh đúng ID; pageSize 8/10/20/50; detail cùng owner; time filter chưa hỗ trợ bị khóa')

    def export():
        with page.expect_download() as pending:
            page.locator('.btn-export').click()
        path = suite.run_dir / 'downloads' / 'channels.csv'
        path.parent.mkdir(exist_ok=True)
        pending.value.save_as(path)
        assert path.read_bytes().startswith(b'\xef\xbb\xbf')
        rows = list(csv.reader(path.open(encoding='utf-8-sig', newline='')))
        assert len(rows) == 2 and len(rows[0]) == 10 and len(rows[1]) == 10
        assert rows[1][0] == channel['channelId'] and rows[1][1] == channel['name']
        # csvCell neutralizes the @handle formula prefix, including Unicode.
        assert rows[1][2] == "'@" + channel['handle']
        assert rows[1][4] == owner['email'] and rows[1][8] == channel['status']
    suite.case(admin, 'A-CHANNELS-CSV-01', 'Tải CSV đúng trang, Unicode và escape @handle', export,
               expected='UTF-8 BOM; 10 cột, một dòng đúng ID/tên/email; @handle có apostrophe chống công thức',
               steps='Lọc đúng channel; bấm Export; đọc file CSV tải thực tế')
