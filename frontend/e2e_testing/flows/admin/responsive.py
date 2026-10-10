"""Viewport smoke checks for every Admin Web route.

These checks intentionally cover portrait, landscape, and tablet widths. A
wide data table may scroll inside its card, but the document itself must never
be wider than the viewport.
"""

from playwright.sync_api import expect


ROUTES = [
    ('USERS', '/users', 'app-admin-users-page'),
    ('CHANNELS', '/channels', 'app-admin-channels-page'),
    ('VIDEOS', '/videos', 'app-admin-videos-page'),
    ('RBAC', '/roles', 'app-admin-rbac-page'),
    ('PLANS', '/plans', 'app-admin-plans-page'),
    ('SUBSCRIPTIONS', '/subscriptions', 'app-admin-subscriptions-page'),
    ('PAYMENTS', '/payments', 'app-admin-payments-page'),
    ('TOPICS', '/topics', 'app-admin-topics-page'),
    ('POLICY', '/policies', 'app-admin-policies-page'),
    ('MODERATION', '/moderation/videos', 'app-admin-moderation-page'),
    ('REPORTS', '/moderation/reports', 'app-admin-reports-page'),
    ('APPEALS', '/moderation/appeals', 'app-admin-appeals-page'),
    ('STRIKES', '/moderation/strikes', 'app-admin-strikes-page'),
    ('NOTIFICATIONS', '/system/notifications', 'app-system-notifications-page'),
    ('SYSTEM-REPORTS', '/system/reports', 'app-system-reports-page'),
    ('LOGS', '/system/logs', 'app-system-logs-page'),
    ('RECOMMENDATION', '/recommendations', 'app-recommendations-page'),
    ('CF-SEEDER', '/cf-seeder', 'app-cf-seeder-page'),
    ('ACCOUNT', '/account', 'app-account-page'),
]

VIEWPORTS = [
    ('PORTRAIT', 390, 844),
    ('LANDSCAPE', 844, 390),
    ('TABLET-PORTRAIT', 768, 1024),
    ('TABLET-LANDSCAPE', 1024, 768),
]


def run(suite, admin, owner):
    page = admin['page']

    for label, width, height in VIEWPORTS:
        def check_viewport(width=width, height=height):
            page.set_viewport_size({'width': width, 'height': height})
            for _, route, selector in ROUTES:
                suite.go(admin, route, selector)
                expect(page.locator(selector)).to_be_visible()
                page.wait_for_timeout(80)
                metrics = page.evaluate("""() => {
                  const viewport = window.innerWidth;
                  const elements = [...document.querySelectorAll('body *')]
                    .filter(element => {
                      const rect = element.getBoundingClientRect();
                      const style = getComputedStyle(element);
                      return rect.width > viewport + 1 && style.position !== 'fixed';
                    })
                    .slice(0, 3)
                    .map(element => ({ tag: element.tagName, className: element.className?.toString?.() || '' }));
                  return {
                    viewport,
                    documentWidth: document.documentElement.scrollWidth,
                    bodyWidth: document.body.scrollWidth,
                    widestElements: elements,
                  };
                }""")
                assert metrics['documentWidth'] <= width + 1 and metrics['bodyWidth'] <= width + 1, (
                    f'{route} overflows {width}px: {metrics}'
                )

        suite.case(
            admin,
            f'A-ADMIN-RESPONSIVE-{label}-01',
            f'Admin responsive sweep {label} ({width}x{height})',
            check_viewport,
            module='responsive',
            expected=f'Tất cả {len(ROUTES)} route Admin không tràn ngang ở viewport {width}x{height}',
            steps='Đổi viewport; mở từng route Admin; đo document scrollWidth và body scrollWidth',
            data=f'{width}x{height}; {len(ROUTES)} routes',
        )
