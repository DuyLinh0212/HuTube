"""Uncovered double-submit/retry and overlapping real playlist route responses."""
import json,time,uuid
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support import transport_proxy

def run(suite,config,actors):
    snapshot_module(suite,__file__);snapshot_module(suite,transport_proxy.__file__)
    ensure_actor_pages(suite,actors,['owner','member'])
    owner,member=actors['owner'],actors['member'];p=owner['page'];created=[]
    def count(name):return [v for v in suite.api(owner,'get','/playlists').json() if v['name']==name]
    try:
        def double(entry):
            suite.go(owner,'/playlists','app-playlists-page','/playlists');name='QC one intent '+suite.run_id
            p.locator('#playlist-name').fill(name);p.locator('#playlist-visibility').select_option('unlisted')
            before=sum(v['actor']==owner['name'] and v['method']=='POST' and v['path']=='/api/v1/playlists' for v in suite.report['http_statuses'])
            value=suite.response(owner,'/playlists',lambda:p.locator('.create-card button.full-button').dblclick(),method='POST',status=200).json();created.append(value['playlistId'])
            expect(p.locator('.hero-copy h1')).to_contain_text(name);assert value['visibility']=='unlisted'
            p.wait_for_timeout(300)
            after=sum(v['actor']==owner['name'] and v['method']=='POST' and v['path']=='/api/v1/playlists' for v in suite.report['http_statuses'])
            assert after-before==1 and len(count(name))==1
            suite.api(member,'get','/playlists/'+value['playlistId'])
            entry['resource_ids']=[value['playlistId']];entry['steps']=['Actual unlisted create form; rapid physical browser double-click','Exactly one real POST, one persisted owned ID and matching detail route','Independent Member can read unlisted resource by exact URL']
        if not config.get('playlist_route_only') and not config.get('playlist_lost_ack_only'):
            case(suite,owner,'PLAYLIST-CREATE-DOUBLE-CLICK-ONE-INTENT','U-PLAYLIST.01','Rapid actual double click creates exactly one playlist',double,'playlists')

        def retry(entry):
            suite.go(owner,'/playlists','app-playlists-page','/playlists');name='QC retry '+suite.run_id
            p.locator('#playlist-name').fill(name);p.locator('#playlist-visibility').select_option('public')
            pattern='**/api/v1/playlists'
            def cut(route):
                if route.request.method=='POST':route.abort('internetdisconnected')
                else:route.continue_()
            p.route(pattern,cut)
            try:
                p.locator('.create-card button.full-button').click();expect(p.locator('[role=alert]')).to_be_visible()
                expect(p.locator('.create-card button.full-button')).to_be_enabled();expect(p.locator('#playlist-name')).to_have_value(name)
                assert count(name)==[],'Transport aborted before upstream receipt must not create a row'
            finally:p.unroute(pattern,cut)
            value=suite.response(owner,'/playlists',lambda:p.locator('.create-card button.full-button').click(),method='POST',status=200).json();created.append(value['playlistId'])
            assert len(count(name))==1;expect(p.locator('.hero-copy h1')).to_contain_text(name)
            entry['resource_ids']=[value['playlistId']];entry['steps']=['Abort only real outgoing create transport before receipt; no fabricated HTTP response','Visible error, busy released, exact draft retained and actual server inventory unchanged','Restore transport, actual Retry click succeeds once with one owned persisted ID','This checks pre-receipt interruption; lost acknowledgement after commit is a separate unverified obligation']
        if not config.get('playlist_route_only') and not config.get('playlist_lost_ack_only'):
            case(suite,owner,'PLAYLIST-CREATE-NETWORK-RETRY','U-PLAYLIST.01','Unsent failed creation retains draft and retry creates one record',retry,'playlists')

        def lost_ack(entry):
            control=Path(config['transport_fault_file']);arm=control.with_suffix('.drop-response.json');applied=control.with_suffix('.drop-response.applied.json')
            name='QC committed lost ack '+suite.run_id;token=uuid.uuid4().hex
            suite.go(owner,'/playlists','app-playlists-page','/playlists');p.locator('#playlist-name').fill(name);p.locator('#playlist-visibility').select_option('private')
            arm.write_text(json.dumps({'id':token,'path':'/api/v1/playlists'}),encoding='utf-8')
            failed=[]
            def on_failed(request):
                if request.method=='POST' and request.url.split('?')[0].endswith('/api/v1/playlists'):failed.append(request)
            p.on('requestfailed',on_failed)
            try:
                p.locator('.create-card button.full-button').click()
                deadline=time.monotonic()+30
                while time.monotonic()<deadline and not failed:p.wait_for_timeout(50)
            finally:p.remove_listener('requestfailed',on_failed)
            assert failed,'The actual browser request did not report a dropped acknowledgement'
            request=failed[0]
            deadline=time.monotonic()+10
            while time.monotonic()<deadline and not applied.exists():p.wait_for_timeout(50)
            assert applied.exists(),'Proxy did not observe and drop the successful real API response'
            fault=json.loads(applied.read_text(encoding='utf-8'));assert fault['id']==token and fault['origin_status']==200
            expect(p.locator('[role=alert]')).to_be_visible();expect(p.locator('#playlist-name')).to_have_value(name)
            matches=count(name);assert len(matches)==1,'The API committed one record before the client acknowledgement was lost'
            value=matches[0];created.append(value['playlistId'])
            p.reload();expect(p.locator('a.playlist-card[href="/playlists/'+value['playlistId']+'"]').first).to_be_visible()
            expect(p.locator('a.playlist-card[href="/playlists/'+value['playlistId']+'"]').first).to_have_count(1)
            suite.api(owner,'get','/playlists/'+value['playlistId'])
            entry['resource_ids']=[value['playlistId']];entry['transport_fault']=fault
            entry['steps']=['Arm loopback proxy to drop only the real successful POST /playlists response after upstream commit','Browser observes request failure and shows recoverable error; no response body is synthesized','Real API list contains exactly one committed ID; browser reload exposes it, so no blind retry creates a duplicate','Request failure: '+str(request.failure)]
        if config.get('playlist_lost_ack_only'):
            case(suite,owner,'PLAYLIST-CREATE-LOST-ACK-RECONCILE','U-PLAYLIST.01','Committed create with lost acknowledgement reconciles from actual server state',lost_ack,'playlists')

        def overlap(entry):
            root=Path(config['transport_fault_file']);arm=root.with_suffix('.delay.json');applied=root.with_suffix('.delay.applied.json');released=root.with_suffix('.delay.released.json')
            def wait(file,id):
                deadline=time.monotonic()+12
                while time.monotonic()<deadline:
                    try:
                        value=json.loads(file.read_text(encoding='utf-8'))
                        if value['id']==id:return value
                    except (FileNotFoundError,PermissionError,json.JSONDecodeError):pass
                    p.wait_for_timeout(30)
                raise AssertionError('Actual playlist delay checkpoint absent')
            ids=[]
            for label in ['A','B']:
                value=suite.api(owner,'post','/playlists',data={'name':'QC latest '+label+' '+suite.run_id,'visibility':'private','description':'Actual route overlap'},expected=200).json();ids.append(value['playlistId']);created.append(value['playlistId'])
            a,b=ids;name_b='QC latest B '+suite.run_id
            suite.go(owner,'/playlists','app-playlists-page','/playlists');expect(p.locator('a.playlist-card[href="/playlists/'+a+'"]')).to_be_visible();p.wait_for_timeout(700)
            token=uuid.uuid4().hex;arm.write_text(json.dumps({'id':token,'path':'/api/v1/playlists/'+a,'query':{},'delay_ms':5000}),encoding='utf-8')
            p.locator('a.playlist-card[href="/playlists/'+a+'"]').click();fault=wait(applied,token);assert fault['origin_status']==200
            p.go_back();expect(p.locator('a.playlist-card[href="/playlists/'+b+'"]')).to_be_visible()
            suite.response(owner,'/playlists/'+b,lambda:p.locator('a.playlist-card[href="/playlists/'+b+'"]').click())
            expect(p.locator('.hero-copy h1')).to_contain_text(name_b)
            wait(released,token);p.wait_for_timeout(400)
            expect(p).to_have_url(owner['origin']+'/playlists/'+b);expect(p.locator('.hero-copy h1')).to_contain_text(name_b)
            assert suite.api(owner,'get','/playlists/'+b).json()['name']==name_b
            entry['resource_ids']=ids;entry['transport_fault']=fault
            entry['steps']=['Two independent real playlists have distinguishable content','Proxy holds only actual successful A response for five seconds after upstream completion','Browser Back restores list and actual card B is clicked before A delivery','B route/title renders first; release actual A response','Late A cannot overwrite title/owner state on current B route; no API payload fabricated']
        if not config.get('playlist_lost_ack_only'):
            case(suite,owner,'PLAYLIST-ROUTE-REAL-RESPONSE-OVERLAP','U-PLAYLIST.03','Late actual playlist response cannot replace the current route',overlap,'playlists')
    finally:
        for id in created:suite.api(owner,'delete','/playlists/'+id,expected=(204,404))
