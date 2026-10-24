"""Read-only review dialog geometry in normal and theater modes."""
from playwright.sync_api import expect
import re
from support.live_suite import PrerequisiteMissing

def run(suite,admin,title=None):
    def layout(case):
        page=admin['page'];suite.go(admin,'/moderation/videos','app-admin-moderation-page',endpoint='/admin/moderation/queue')
        expect(page.locator('.loading-state')).to_have_count(0)
        if title: page.locator('input[type=search]').fill(title)
        page.locator('.status-tabs [role=tab]').nth(1).click()
        buttons=page.locator('.queue-table .table-action:not(.subtle)')
        expect(page.locator('.status-tabs [role=tab]').nth(1)).to_have_attribute('aria-selected','true')
        if title:
            expect(buttons.first).to_be_visible()
        elif not buttons.count():
            page.locator('.status-tabs [role=tab]').nth(3).click()
        if not buttons.count():raise PrerequisiteMissing('No reviewing case available for read-only preview; no existing case is claimed or modified')
        buttons.first.click()
        dialog=page.locator('.review-modal')
        expect(dialog).to_be_visible()
        width=dialog.bounding_box()['width']
        def bounded():
            rect=dialog.bounding_box();viewport=page.viewport_size;assert rect and viewport
            assert rect['x']>=-1 and rect['y']>=-1,'Review dialog starts outside the viewport'
            assert rect['x']+rect['width']<=viewport['width']+1,'Review dialog clipped horizontally'
            assert rect['y']+rect['height']<=viewport['height']+1,'Review dialog clipped vertically'
        suite.evidence(admin,case,'normal-dialog',responsive_assert=bounded,full_page=False)
        page.locator('.expand-button').click()
        expect(dialog).to_have_class(re.compile('is-theater'))
        if page.viewport_size['width']>=1024:
            page.wait_for_function('(width)=>document.querySelector(".review-modal").getBoundingClientRect().width>width',arg=width)
        else:
            assert dialog.bounding_box()['width']>=width-1,'Theater should retain the available small-screen width'
        suite.evidence(admin,case,'theater-dialog',responsive_assert=bounded,full_page=False)
        page.locator('.expand-button').click()
        expect(dialog).not_to_have_class(re.compile('is-theater'))
        page.locator('.review-modal .close-button').click()
        expect(dialog).to_have_count(0)
        case['steps']=['Read-only existing reviewing case → open preview','Normal dialog stays inside all three viewports','Expand → larger desktop and bounded mobile/tablet dialog','Collapse and close; no claim/release/decision mutation']
    suite.case(admin,'LIVE-MODERATION-REVIEW-THEATER-LAYOUT','A-MODERATION.01','Normal/theater review dialog geometry','Theater expands on desktop and neither mode clips any viewport',layout,module='moderation')
