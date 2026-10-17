"""Previously missing preset draft values, every saved field, ordering and User benefits."""
import json
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin'])
    admin = actors['admin']; p = admin['page']; created = {}
    before = suite.api(admin, 'get', '/admin/plans').json()
    suite.go(admin, '/plans', 'app-admin-plans-page', '/admin/plans')
    presets = [
        {'code': 'creator_plus', 'price': '99000', 'durationDays': '30', 'storageLimit': '100', 'maxUploadSize': '20', 'maxVideoQuality': '1080p', 'maxMembers': '1', 'displayOrder': '2'},
        {'code': 'pro_family_monthly', 'price': '299000', 'durationDays': '30', 'storageLimit': '500', 'maxUploadSize': '50', 'maxVideoQuality': '2160p', 'maxMembers': '5', 'displayOrder': '3'},
        {'code': 'pro_family_yearly', 'price': '2990000', 'durationDays': '365', 'storageLimit': '500', 'maxUploadSize': '50', 'maxVideoQuality': '2160p', 'maxMembers': '5', 'displayOrder': '3'},
    ]
    try:
        for index, preset in enumerate(presets):
            def draft(entry, index=index, preset=preset):
                p.locator('.heading-actions .primary-action').click()
                p.locator('.preset-card').nth(index).click()
                for field, value in preset.items():
                    expect(p.locator('[name=' + field + ']')).to_have_value(value)
                toggles = p.locator('.feature-toggle input:not([name])')
                for i in range(4): expect(toggles.nth(i)).to_be_checked(checked=i < 3)
                expect(p.locator('[name=isDefaultForNewUsers]')).not_to_be_checked()
                expect(p.locator('.pass-name')).to_contain_text(preset['code'])
                suite.evidence(admin, entry, 'preset-draft-preview')
                p.locator('.editor-actions .secondary-action').click()
                expect(p.locator('[role=dialog]')).to_have_count(0)
                assert suite.api(admin, 'get', '/admin/plans').json() == before
                entry['steps'] = ['Select actual preset button and compare every preset-specific field and feature toggle', 'Preview reflects selected code and immutable default-plan preference remains false', 'Cancel; actual catalog is byte-for-byte equivalent and no resource is created']
            case(suite, admin, 'PLAN-PRESET-' + str(index) + '-DRAFT-CANCEL', 'A-PLANS.01', 'Plan preset ' + preset['code'] + ' fills exact draft without mutation', draft, 'plans')
        def save(entry):
            p.locator('.heading-actions .primary-action').click()
            values = {'code': 'qc_benefit_' + suite.run_id[9:15], 'name': 'QC benefits ' + suite.run_id, 'description': 'Quyền lợi chính xác — QC', 'price': '54321', 'durationDays': '45', 'displayOrder': '1', 'storageLimit': '3', 'maxUploadSize': '1', 'maxVideoDuration': '61', 'maxMembers': '7'}
            for field, value in values.items(): p.locator('[name=' + field + ']').fill(value)
            p.locator('[name=maxVideoQuality]').select_option('1440p')
            p.locator('[name=maxDownloadQuality]').select_option('720p')
            for index, flag in enumerate([True, False, True, False]): p.locator('.feature-toggle input:not([name])').nth(index).set_checked(flag)
            p.locator('[name=isDefaultForNewUsers]').uncheck()
            created.update(suite.response(admin, '/admin/plans', lambda: p.locator('[role=dialog] button[type=submit]').click(), method='POST', status=201).json())
            assert created['storageLimit'] == 3 * 1024**3 and created['maxUploadSize'] == 1024**3
            assert created['maxVideoDuration'] == 3660 and created['durationDays'] == 45 and created['maxMembers'] == 7
            assert created['price'] == 54321 and created['displayOrder'] == 1
            assert created['maxVideoQuality'] == '1440p' and created['maxDownloadQuality'] == '720p'
            assert created['features'] == {'download': True, 'background_play': False, 'pip': True, 'video_promotion': False}
            p.reload(); expect(p.locator('tbody tr').filter(has_text=values['code'])).to_have_count(1)
            persisted = suite.api(admin, 'get', '/admin/plans').json()
            expected = sorted(persisted, key=lambda item: (item['displayOrder'], item['price'], item['code']))
            assert [v['planId'] for v in persisted] == [v['planId'] for v in expected]
            for index, item in enumerate(persisted): expect(p.locator('tbody tr').nth(index)).to_contain_text(item['code'])
            entry['resource_ids'] = [created['planId']]
            entry['verified_na'] = ['Admin plans has one table and an editor, no plan tab controls exist in current template.']
            entry['steps'] = ['Create via actual Admin form with distinct units, duration, price, order, members, qualities and every feature', 'Read exact persisted API values including GiB/seconds conversion', 'Reload table and compare every row with actual displayOrder/price/code sorting; no default-plan reassignment']
        case(suite, admin, 'PLAN-ALL-FIELDS-ORDER-UI-PERSIST', 'A-PLANS.01', 'Every plan field persists with correct units and order', save, 'plans')
        if created:
            guest = suite.actor('plan-benefits-guest', 'user', 'guest'); guest['api_url'] = config['api_url']; g = guest['page']
            try:
                def benefits(entry):
                    suite.go(guest, '/plans/' + created['planId'], 'app-plan-detail-page')
                    values = g.locator('.spec-val')
                    expected = ['3 GB', '1 GB', '1 giờ 1 phút', '1440p', '720p', '7 người', '✓ Hỗ trợ', '✕ Không hỗ trợ', '✓ Hỗ trợ', '✕ Không hỗ trợ']
                    expect(values).to_have_text(expected)
                    for i in range(6, 10):
                        assert ('checkmark' in (values.nth(i).get_attribute('class') or '')) == (i in (6, 8))
                    g.reload(); expect(g.locator('.spec-val')).to_have_text(expected)
                    entry['resource_ids'] = [created['planId']]
                    entry['steps'] = ['Guest opens exact newly saved plan', 'All ten benefits match actual persisted quotas/duration/qualities/members and feature values', 'Supported/unsupported text and classes agree with each of four flags', 'Reload retains exact values without purchasing']
                case(suite, guest, 'PLAN-DETAIL-ALL-BENEFITS-EXACT', 'U-PLAN.01', 'User plan benefits show exact persisted limits and feature flags', benefits, 'plans')
            finally: suite.release_actor(guest)
    finally:
        if created: suite.api(admin, 'post', '/admin/plans/' + created['planId'] + '/archive', data={}, expected=204)
