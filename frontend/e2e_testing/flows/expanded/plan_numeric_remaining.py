"""Additional typed-overflow/fraction branches absent from prior minimum tests."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['admin'])
    admin=actors['admin'];p=admin['page'];created=[];code='qc_numeric_'+suite.run_id[9:15]
    baseline={'code':code,'name':'QC numeric '+suite.run_id,'description':'Disposable numeric boundary fixture','price':1.25,'durationDays':30,'storageLimit':1024**3,'maxUploadSize':20*1024**2,'maxVideoDuration':60,'maxVideoQuality':'720p','maxDownloadQuality':'720p','maxMembers':1,'features':'{"download":true}','isDefaultForNewUsers':False,'displayOrder':0}
    def inventory():return suite.api(admin,'get','/admin/plans').json()
    try:
        def overflow(entry):
            before={v['planId'] for v in inventory()};checks=[]
            for field,number in [('price',10**35),('durationDays',2**31),('maxVideoDuration',2**31),('maxMembers',2**31),('displayOrder',2**31),('storageLimit',2**63),('maxUploadSize',2**63)]:
                response=suite.api(admin,'post','/admin/plans',data={**baseline,field:number},expected=400);checks.append({'field':field,'value':str(number),'status':response.status})
                assert {v['planId'] for v in inventory()}==before,'Overflow created a plan or mutated catalog'
            suite.go(admin,'/plans','app-admin-plans-page','/admin/plans');entry['numeric_checks']=checks
            entry['steps']=['Actual JSON requests exceed declared .NET decimal/int32/int64 boundaries','Every request rejects 400 through real model binding','Full actual plan-ID inventory unchanged after each request','Reload Admin plans; no overflow fixture persisted']
        case(suite,admin,'PLAN-NUMERIC-TYPED-OVERFLOW-NO-MUTATION','A-PLANS.02','Overflow cannot wrap or create plan rows',overflow,'plans')
        def fractions(entry):
            before={v['planId'] for v in inventory()};checks=[]
            for field in ['durationDays','storageLimit','maxUploadSize','maxVideoDuration','maxMembers','displayOrder']:
                response=suite.api(admin,'post','/admin/plans',data={**baseline,field:1.5},expected=400);checks.append({'field':field,'status':response.status})
                assert {v['planId'] for v in inventory()}==before
            value=suite.api(admin,'post','/admin/plans',data=baseline,expected=201).json();created.append(value['planId']);assert value['price']==1.25
            stored=next(v for v in inventory() if v['planId']==value['planId']);assert stored['price']==1.25 and stored['durationDays']==30 and stored['storageLimit']==1024**3
            suite.go(admin,'/plans','app-admin-plans-page','/admin/plans');expect(p.locator('tbody tr').filter(has_text=code)).to_have_count(1)
            entry['resource_ids']=[value['planId']];entry['numeric_checks']=checks
            entry['steps']=['Fractional integral fields reject real JSON with 400 and unchanged catalog','Decimal price 1.25 is valid and persists exactly, without accidental integer truncation','Other integer/quota units remain exact','Reload Admin shows one exact immutable ID/code; no real purchase or default-plan change']
        case(suite,admin,'PLAN-NUMERIC-FRACTION-TYPE-CONTRACT','A-PLANS.02','Fractional currency is accepted while fractional integral limits are rejected',fractions,'plans')
    finally:
        for id in created:suite.api(admin,'post','/admin/plans/'+id+'/archive',data={},expected=204)
