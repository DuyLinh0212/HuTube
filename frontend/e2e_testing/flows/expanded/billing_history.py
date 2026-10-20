"""Real paid/cancelled checkout history in Account, with cache/reload/isolation."""
import json,re
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages
from support.local_db import LocalDb

def run(suite,config,actors):
    snapshot_module(suite,__file__);ensure_actor_pages(suite,actors,['member'])
    db=LocalDb(config);prior_run='20261016T050737.075162Z'
    prior=json.loads((Path(__file__).resolve().parents[2]/'artifacts/runs'/prior_run/'report.json').read_text(encoding='utf-8'))
    assert prior['environment_kind']=='isolated-local-postgresql-fixtures'
    checkpoint=next(c for c in prior['cases'] if c['id']=='FULL-REGISTER-PAYMENT_CONTRACT' and c['status']=='passed')
    assert any(c['id']=='FULL-PAYMENT-UI-PAID-WEBHOOK-EXACTLY-ONCE' and c['status']=='passed' for c in prior['cases'])
    uid=checkpoint['resource_ids'][0]
    data=json.loads(db.sql("SELECT json_build_object('email',email,'username',username) FROM users WHERE user_id=:'id'::uuid AND email LIKE 'qc.payment_contract.%@example.test';",{'id':uid}))
    assert data['email'].endswith('@example.test')
    suite.credentials['billing_prior']={**data,'password':'QCSessionPlanFixture2026!'}
    actor=suite.actor('billing-prior-checkout','user','billing_prior');p=actor['page'];member=actors['member'];mp=member['page']
    assert actor['identity']['userId']==uid
    rows=suite.api(actor,'get','/payments').json();paid=[v for v in rows if v['status']=='paid'];assert paid and any(v['status']=='cancelled' for v in rows)
    def billing():
        suite.go(actor,'/account','app-account-page','/account/profile');p.locator('.settings-nav-list > button').nth(4).click()
        expect(p.locator('.billing-history-card')).to_have_count(2)
    def assert_rows(section,expected):
        actual=section.locator('.billing-transaction');expect(actual).to_have_count(len(expected))
        for index,item in enumerate(expected):
            row=actual.nth(index);expect(row).to_contain_text(item['transactionCode']);expect(row).to_contain_text(item['planName'])
            amount=row.locator('.billing-transaction-side strong').inner_text();assert re.sub(r'\D','',amount)==str(int(item['amount']))
            assert '₫' in amount or 'VND' in amount
    try:
        def history(entry):
            billing();purchase=p.locator('.billing-history-card').nth(0);all_history=p.locator('.billing-history-card').nth(1)
            expect(purchase.locator('.billing-history-toggle')).to_have_attribute('aria-expanded','false')
            suite.response(actor,'/payments',lambda:purchase.locator('.billing-history-toggle').click())
            assert_rows(purchase,paid);expect(purchase.locator('.billing-status-badge.is-active')).to_have_count(len(paid))
            suite.evidence(actor,entry,'paid-purchases-only')
            before=sum(e['actor']==actor['name'] and e['method']=='GET' and e['path']=='/api/v1/payments' for e in suite.report['http_statuses'])
            all_history.locator('.billing-history-toggle').click();assert_rows(all_history,rows)
            for index,item in enumerate(rows):expect(all_history.locator('.billing-status-badge').nth(index)).to_have_attribute('data-status',item['status'])
            p.wait_for_timeout(150)
            assert before==sum(e['actor']==actor['name'] and e['method']=='GET' and e['path']=='/api/v1/payments' for e in suite.report['http_statuses'])
            suite.evidence(actor,entry,'all-payment-states')
            for section in [purchase,all_history]:section.locator('.billing-history-toggle').click();expect(section.locator('.billing-history-content')).to_have_count(0)
            entry['resource_ids']=[uid,*[v['paymentId'] for v in rows]];entry['fixture_source_run']=prior_run
            entry['steps']=['Real login to exact synthetic account with actual prior QC checkouts; no payment state seeded','Account Billing purchase accordion shows only real paid records','Payment history accordion shows actual cancelled/paid IDs, names, prices, currency and status badges','Second accordion reuses one successful read; hide toggles remove content without mutations','All assertions executed now; previous run supplies fixture IDs only']
        case(suite,actor,'ACCOUNT-BILLING-ACTUAL-PURCHASE-PAYMENT-HISTORY','U-ACCOUNT.02','Billing separates real paid purchases from all payment attempts',history,'account')
        def reload(entry):
            p.reload();expect(p.locator('app-account-page')).to_be_visible();p.locator('.settings-nav-list > button').nth(4).click()
            section=p.locator('.billing-history-card').nth(1)
            actual=suite.response(actor,'/payments',lambda:section.locator('.billing-history-toggle').click()).json()
            assert [v['paymentId'] for v in actual]==[v['paymentId'] for v in rows];assert_rows(section,actual)
            entry['resource_ids']=[uid,*[v['paymentId'] for v in rows]]
            entry['steps']=['Reload real Account component','Reopen Billing and actual payment history','Fresh GET returns exact persisted payment IDs/order and every rendered row matches','No duplicated purchases or fabricated totals']
        case(suite,actor,'ACCOUNT-BILLING-RELOAD-PERSISTED-ROWS','U-ACCOUNT.02','Reloaded payment history keeps exact persisted purchases',reload,'account')
        def isolation(entry):
            foreign=suite.api(member,'get','/payments').json();assert foreign==[],'Independent empty-history fixture required'
            for item in rows:suite.api(member,'get','/payments/'+item['paymentId'],expected=404)
            suite.go(member,'/account','app-account-page','/account/profile');mp.locator('.settings-nav-list > button').nth(4).click()
            for index in [0,1]:
                section=mp.locator('.billing-history-card').nth(index);section.locator('.billing-history-toggle').click()
                expect(section.locator('.billing-transaction')).to_have_count(0);expect(section.locator('.billing-state')).to_be_visible()
            entry['resource_ids']=[member['identity']['userId'],uid]
            entry['steps']=['Another independent Member has empty actual payment inventory','Every checkout ID of paid account returns 404 to this actor','Own Billing purchase/payment accordions show empty states and no foreign rows']
        case(suite,member,'ACCOUNT-BILLING-EMPTY-FOREIGN-ISOLATION','U-ACCOUNT.02','Billing history never leaks another account payment IDs/data',isolation,'account')
    finally:suite.release_actor(actor)
