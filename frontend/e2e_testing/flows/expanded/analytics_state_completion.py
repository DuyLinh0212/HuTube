"""Real Studio analytics loading/error/retry; unsupported controls are source-reviewed N/A."""
import hashlib
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['owner'])
    owner = actors['owner']; p = owner['page']
    route = '/studio/analytics?channelId=' + suite.fixtures['channel']['channelId']
    pattern = '**/api/v1/videos/manage?*'
    def loading(entry):
        held = []
        p.route(pattern, lambda request: held.append(request))
        try:
            suite.go(owner, route, 'app-studio-analytics-page')
            expect(p.locator('#studio-analytics .state-panel .spinner')).to_be_visible()
            for _ in range(100):
                if held: break
                p.wait_for_timeout(50)
            assert held
            expect(p.locator('.metric-card')).to_have_count(0)
            suite.evidence(owner, entry, 'real-manage-loading-no-sample-values')
            while held:
                request = held.pop(0)
                try: request.continue_()
                except Exception:
                    assert request.request.failure, 'Only an actual cancelled request may be ignored'
            p.unroute(pattern)
            expect(p.locator('.metric-card')).to_have_count(5)
            expect(p.locator('#studio-analytics .state-panel .spinner')).to_have_count(0)
            entry['resource_ids'] = [suite.fixtures['channel']['channelId']]
            entry['steps'] = ['Hold genuine managed-video request while Analytics loads', 'Actual loading state has no fabricated metric cards on all three viewports', 'Release real request; loading clears and actual metrics render']
        finally:
            for request in held:
                try: request.continue_()
                except Exception: pass
            p.unroute(pattern)
    case(suite, owner, 'STUDIO-ANALYTICS-REAL-LOADING', 'U-STUDIO.07', 'Analytics loading never displays sample metrics', loading, 'analytics')
    def error(entry):
        p.route(pattern, lambda request: request.abort('internetdisconnected'))
        try:
            p.reload()
            expect(p.locator('#studio-analytics .error-panel[role=alert]')).to_be_visible()
            expect(p.locator('.metric-card')).to_have_count(0)
            expect(p.locator('#studio-analytics .error-panel button')).to_be_enabled()
            suite.evidence(owner, entry, 'real-network-error-retry-enabled')
        finally:
            p.unroute(pattern)
        suite.response(owner, '/videos/manage', lambda: p.locator('#studio-analytics .error-panel button').click())
        expect(p.locator('.metric-card')).to_have_count(5)
        expect(p.locator('#studio-analytics .error-panel')).to_have_count(0)
        expect(p.locator('#studio-analytics input[type=date],#studio-analytics a[download]')).to_have_count(0)
        root = Path(__file__).resolve().parents[4]
        files = ['frontend/user-web/src/app/features/studio/pages/studio-analytics-page.html', 'frontend/user-web/src/app/features/studio/pages/studio-analytics-page.ts', 'frontend/user-web/src/app/core/studio-data.service.ts']
        entry['source_review'] = [{'path': file, 'sha256': hashlib.sha256((root/file).read_bytes()).hexdigest()} for file in files]
        entry['verified_na'] = ['No analytics time-range/tab/export control exists in current template/component/service. CSV/header/row/formula assertions are N/A for this surface; existing Admin export cases remain separate.']
        entry['steps'] = ['Abort genuine manage transport on reload; bounded error replaces old metrics, no sample data', 'Restore network and click actual retry; real manage response renders analytics', 'Review exact source hashes and actual DOM: only video selector is offered, no time-range or export action']
    case(suite, owner, 'STUDIO-ANALYTICS-NETWORK-ERROR-RETRY', 'U-STUDIO.07', 'Analytics retries actual failed data requests', error, 'analytics')
