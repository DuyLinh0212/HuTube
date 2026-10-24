"""Cleanup only; does not rerun numeric cases that already passed."""
from flows.expanded.common import snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);admin=actors['admin']
    items=suite.api(admin,'get','/admin/plans').json()
    for id in config.get('numeric_cleanup_plan_ids',[]):
        item=next(v for v in items if v['planId']==id)
        assert item['name'].startswith('QC numeric ') and not item['isDefaultForNewUsers']
        suite.api(admin,'post','/admin/plans/'+id+'/archive',data={},expected=204)
        stored=next(v for v in suite.api(admin,'get','/admin/plans').json() if v['planId']==id)
        assert stored['status']=='archived'
        assert id not in {v['planId'] for v in suite.api(actors['member'],'get','/plans').json()}
        suite.report['cleanup'].append({'resource':'owned numeric fixture','id':id,'status':'archived through supported API; original successful numeric cases not rerun'})
