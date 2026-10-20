"""Live taxonomy, plan catalog and unassigned role mutations with fresh fixtures."""
import re
from support.live_adapter import FunctionalAdapter
from flows.admin import taxonomy,plans,rbac

def run(suite,admin,owner,groups):
    suffix=re.sub('[^a-z0-9]','',suite.run_id.lower())[-20:]
    for name,flow,parent in [('taxonomy',taxonomy.run,'A-TOPICS.01'),('plans',plans.run,'A-PLANS.01'),('rbac',rbac.run,'A-RBAC.01')]:
        if name not in groups:
            continue
        adapter=FunctionalAdapter(suite,parent)
        try:
            flow(adapter,admin,owner,fixture_suffix=suffix)
        finally:
            for key in ['category_id','plan_id','role_id','tag_id']:
                resource_id=adapter.state.get(key)
                if not resource_id:
                    continue
                if key=='tag_id':
                    suite.api(admin,'delete','/admin/tags/'+resource_id,expected=(200,204,404))
                elif key=='role_id':
                    suite.api(admin,'delete','/admin/roles/'+resource_id,expected=(200,204),params={'reason':'Cleanup unassigned role created by this QC run'})
                else:
                    collection='topics' if key=='category_id' else 'plans'
                    suite.api(admin,'post','/admin/'+collection+'/'+resource_id+'/archive',expected=(200,204))
                suite.report['cleanup'].append({'module':name,'id':resource_id,'status':'deleted-test-fixture' if key in ('role_id','tag_id') else 'archived-test-fixture'})
