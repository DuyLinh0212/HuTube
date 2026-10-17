"""Force real old/new response overlap without mocking application responses."""
import json,time,uuid
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.live_suite import PrerequisiteMissing
from support import transport_proxy

def run(suite,config,actors):
    snapshot_module(suite,__file__);snapshot_module(suite,transport_proxy.__file__)
    if not config.get('transport_fault_file'):raise PrerequisiteMissing('Real delayed-response forwarding proxy required')
    ensure_actor_pages(suite,actors,['member']);actor=actors['member'];p=actor['page'];base=Path(config['transport_fault_file'])
    arm=base.with_suffix('.delay.json');applied=base.with_suffix('.delay.applied.json');released=base.with_suffix('.delay.released.json')
    def wait_file(file,id):
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            try:
                value=json.loads(file.read_text(encoding='utf-8'))
                if value['id']==id:return value
            except (FileNotFoundError,PermissionError,json.JSONDecodeError):pass
            p.wait_for_timeout(50)
        raise AssertionError('Actual proxy delay checkpoint not observed')
    def order(entry):
        old=suite.api(actor,'get','/videos/search',params={'q':'music','duration':'long','page':1,'pageSize':20}).json()
        assert old['items']==[],'Need distinct empty old filter for an observable stale-response test'
        initial=suite.go(actor,'/search?q=music','app-explore-page','/videos/search')
        assert initial['items'],'Populated music fixture required'
        duration=p.locator('.filter-grid select').nth(1);expect(duration).to_have_value('')
        id=uuid.uuid4().hex;arm.write_text(json.dumps({'id':id,'path':'/api/v1/videos/search','query':{'duration':'long'},'delay_ms':2500}),encoding='utf-8')
        duration.select_option('long');fault=wait_file(applied,id);assert fault['origin_status']==200
        with p.expect_response(lambda r:r.request.method=='GET' and urlsplit(r.url).path=='/api/v1/videos/search' and not parse_qs(urlsplit(r.url).query).get('duration')) as pending:
            duration.select_option('')
        response=pending.value;assert response.status==200;latest=response.json()
        ids=[v['videoId'] for v in latest['items']];assert ids
        wait_file(released,id)
        for _ in range(5):
            p.wait_for_timeout(150)
            assert p.locator('.search-video-card').evaluate_all('(rows)=>rows.map(a=>a.pathname.split("/").pop())')==ids,'Old delayed response replaced newer nonempty results'
            expect(duration).to_have_value('')
        p.reload();expect(p.locator('.filter-grid select').nth(1)).to_have_value('')
        expect(p.locator('.search-video-card')).to_have_count(len(ids))
        entry['transport_fault']=fault;entry['resource_ids']=ids
        entry['steps']=['Actual older long-duration filter has no matches, newer all-duration filter has real matches','Proxy holds the actual first 200 response after upstream completion for 2.5 seconds','Change actual duration control while older response remains undelivered','Newer actual response renders exact nonempty IDs before old response release','Release old response; repeatedly verify no stale overwrite and selected filter remains latest','Reload retains final filter/results; no fabricated API payload or route.fulfill']
    try:case(suite,actor,'DISCOVERY-REAL-DELAYED-RESPONSE-LATEST-WINS','U-DISCOVERY.03','Late actual response cannot overwrite newer filter results',order,'discovery')
    finally:
        if arm.exists():arm.unlink()
