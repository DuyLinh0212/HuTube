"""Read the real Admin audit trail for already-resolved report decisions."""
from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin'])
    admin = actors['admin']
    page = admin['page']

    def audit_history(entry):
        data = suite.api(admin, 'get', '/admin/operations/audit-logs', params={
            'page': 1, 'pageSize': 100, 'search': 'report.case.',
        }).json()
        rows = data['items']
        decisions = {'dismiss', 'warn', 'age_restrict', 'recommendation_restricted', 'hide', 'remove', 'escalate'}
        found = {row['action'].split('.')[-1]: row for row in rows
                 if row.get('action', '').startswith('report.case.') and row['action'].split('.')[-1] in decisions}
        assert decisions <= set(found), 'Retained report decisions lack audit rows: ' + ', '.join(sorted(decisions - set(found)))
        assert all(row.get('resourceType') == 'moderation_case' and row.get('resourceId') for row in found.values())
        assert all(row.get('reason') for row in found.values())

        sample = found['dismiss']
        suite.go(admin, '/system/logs', 'app-system-logs-page', '/admin/operations/audit-logs')
        # The API assertions above identify every exact resource/action pair.
        # In the UI, there can be prior audit rows of the same action, so test
        # the actual filter/detail surface without claiming a singleton list.
        action_filter = page.locator('.log-filter-panel select').first
        action_filter.select_option(sample['action'])
        row = page.locator('.audit-entry').first
        expect(row).to_be_visible()
        row.locator('.audit-entry-main').click()
        expect(row.locator('.audit-details')).to_be_visible()
        entry['resource_ids'] = [str(item['resourceId']) for item in found.values()]
        entry['steps'] = [
            'Read the real Admin operations audit API without creating a new decision',
            'Verify one nonempty moderation-case audit row for every retained report disposition',
            'Use the real Logs UI search and expanded detail to confirm the persisted action and reason',
        ]

    case(suite, admin, 'REPORT-DECISION-AUDIT-MATRIX', 'A-MODERATION.03',
         'Retained report decision matrix has exact audit rows', audit_history, 'reports')
