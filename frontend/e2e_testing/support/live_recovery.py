"""Recover only uniquely named QC resources recorded by a specified live run."""
import json
import re
from pathlib import Path

def recover_subscription(suite,owner,admin,run_dir):
    root=Path(run_dir).resolve()
    assert root.parent==suite.run_dir.parent.resolve()
    report=json.loads((root/'report.json').read_text(encoding='utf-8'))
    setup=next(item for item in report['setup'] if item['actor']=='second-supplied-account')
    assert setup['user_id']==admin['identity']['userId']
    events=[event for event in report['http_statuses'] if event.get('case')=='LIVE-SUBSCRIPTION-PERSIST-IDEMPOTENT' and re.fullmatch('/api/v1/channels/[0-9a-f-]+/subscribe',event['path']) and event['method'] in ['POST','DELETE']]
    assert events and events[0]['method']=='POST','Legacy recovery only permits a proven originally inactive subscription; use a saved manifest for active originals'
    channel_id=events[0]['path'].split('/')[-2]
    channel=suite.api(owner,'get','/channels/me').json()
    assert channel['channelId']==channel_id and channel['isOwner']
    suite.api(admin,'delete','/channels/'+channel_id+'/subscribe',expected=(200,204))
    actual=suite.api(admin,'get','/channels/'+channel_id+'/subscribe-status').json()
    assert actual['status']!='active' and not actual['isSubscribed']
    suite.report['cleanup'].append({'previous_run':root.name,'resource':'subscription','channel_id':channel_id,'actor_user_id':setup['user_id'],'status':'restored-originally-inactive','proof':'First recorded mutation POST; code would DELETE first when original status active'})

def recover(suite,admin,run_dir):
    root=Path(run_dir).resolve()
    assert root.parent==suite.run_dir.parent.resolve(), 'Recovery must name a live run in artifacts/runs'
    for manifest in root.glob('fixture-*.json'):
        state=json.loads(manifest.read_text(encoding='utf-8'))
        for key,collection,id_key in [('category_id','topics','categoryId'),('plan_id','plans','planId'),('role_id','roles','roleId')]:
            resource_id=state.get(key)
            if not resource_id:
                continue
            items=suite.api(admin,'get','/admin/'+collection).json()
            item=next((v for v in items if v[id_key]==resource_id),None)
            if not item:
                continue
            code=item.get('code') or item.get('slug') or ''
            assert code.startswith('hutube_e2e_') or code.startswith('hutube-e2e-functional-category-'), 'Refuse to modify a resource without the QC fixture prefix'
            if collection=='roles':
                assert item['assignedUserCount']==0 and not item.get('isSystem',False)
                if item.get('status')!='deleted':
                    suite.api(admin,'delete','/admin/roles/'+resource_id,expected=(200,204),params={'reason':'Recover unassigned QC fixture from interrupted run'})
            else:
                if collection=='plans':
                    assert item['isDefaultForNewUsers'] is False and item['price']==0
                if item['status'] not in ('archived','inactive'):
                    suite.api(admin,'post','/admin/'+collection+'/'+resource_id+'/archive',expected=(200,204))
            suite.report['cleanup'].append({'previous_run':root.name,'id':resource_id,'status':'recovered-test-fixture'})
