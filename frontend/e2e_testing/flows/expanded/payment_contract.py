"""Actual UI/API/DB payment contract using QC-only signed webhook injection.

No bank transfer or external provider success is asserted. No payment state is seeded.
"""
import hashlib,hmac,json,time,io,re
from urllib.parse import urlsplit,parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

SECRET='hutube-qc-loopback-webhook-only-2026'
ACCOUNT='0000000000'

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if not config.get('payment_contract_sandbox'):raise PrerequisiteMissing('Requires isolated fake receiving account and QC webhook secret')
    admin=actors['admin'];member=actors['member'];db=LocalDb(config)
    uid=identity(suite,config,'payment_contract');actor=suite.actor('payment-contract','user','payment_contract');p=actor['page']
    plan=suite.api(admin,'post','/admin/plans',data={'code':'qc_pay_'+suite.run_id[9:15],
        'name':'QC SIGNED WEBHOOK ONLY '+suite.run_id,'description':'No real transfer; owned local contract test',
        'price':12345,'durationDays':30,'storageLimit':2*1024**3,'maxUploadSize':10*1024**2,
        'maxVideoDuration':60,'maxVideoQuality':'360p','maxDownloadQuality':'360p','maxMembers':1,
        'features':json.dumps({'download':True}),'isDefaultForNewUsers':False},expected=201).json()
    pid=plan['planId'];payment={};qr_references={};baseline=suite.api(actor,'get','/plans/my-plan').json()['planId']
    suite.report['payment_environment']='QC-only HMAC webhook injection against real local API/UI/PostgreSQL. Fake account; no bank/provider certification.'
    def read():return suite.api(actor,'get','/payments/'+payment['paymentId']).json()
    def entitlement():return suite.api(actor,'get','/plans/my-plan').json()['planId']
    def webhook(**changes):
        payload={'id':int(time.time()*1000),'gateway':'QC-INJECTION','transactionDate':'2026-10-16 09:00:00',
            'accountNumber':ACCOUNT,'subAccount':None,'code':None,'content':payment['transactionCode'],
            'transferType':'in','transferAmount':int(payment['amount']),'accumulated':0,'referenceCode':'QC-only'}
        payload.update(changes);return payload
    def send(payload,offset=0,bad=False):
        body=json.dumps(payload,separators=(',',':'));stamp=str(int(time.time())+offset)
        signature='sha256='+hmac.new(SECRET.encode(),(stamp+'.'+body).encode(),hashlib.sha256).hexdigest()
        if bad: signature='sha256='+'0'*64
        response=actor['context'].request.post(actor['api_url']+'/payments/webhook/sepay',data=body,
            headers={'Content-Type':'application/json','X-SePay-Signature':signature,'X-SePay-Timestamp':stamp})
        suite.report['http_statuses'].append({'actor':'QC-webhook-injector','case':suite.current,'method':'POST','path':'/api/v1/payments/webhook/sepay','status':response.status})
        return response
    def start(entry):
        suite.go(actor,'/plans/'+pid,'app-plan-detail-page')
        expect(p.locator('button.cta-subscribe')).to_be_enabled()
        payment.update(suite.response(actor,'/payments',lambda:p.locator('button.cta-subscribe').click(),method='POST').json())
        modal=p.locator('app-payment-modal');expect(modal.locator('.modal-card')).to_be_visible();expect(modal.locator('.code')).to_have_text(payment['transactionCode'])
        assert payment['amount']==12345 and payment['currency']=='VND' and payment['qrCodeUrl']
        assert read()['status']=='pending' and entitlement()==baseline
        suite.api(member,'get','/payments/'+payment['paymentId'],expected=404)
        modal.locator('.close-btn').click();expect(modal).to_have_count(0)
        reopened=suite.response(actor,'/payments',lambda:p.locator('button.cta-subscribe').click(),method='POST').json()
        assert reopened['paymentId']==payment['paymentId'];expect(modal.locator('.modal-card')).to_be_visible()
        entry['resource_ids']=[uid,pid,payment['paymentId']]
        entry['steps']=['Fresh Member opens actual paid plan and checkout modal','Read pending ID, amount, currency, transaction code and QR URL','Pending does not grant paid plan; foreign user cannot read payment','Close/reopen actual checkout reuses same active payment ID','QR is for fake QC account; no transfer performed']
    case(suite,actor,'PAYMENT-UI-PENDING-REOPEN-ISOLATION','U-PLAN.02','Pending checkout persists without granting plan',start,'payments')
    if not payment:raise PrerequisiteMissing('Checkout creation failed')
    def qr_image(entry):
        from PIL import Image
        import zxingcpp
        uri=urlsplit(payment['qrCodeUrl']);query=parse_qs(uri.query)
        assert uri.scheme=='https' and uri.hostname in ('vietqr.app','img.vietqr.io')
        assert payment['amount']==12345 and payment['transactionCode'].startswith('QCLOCAL-')
        assert suite.credentials['payment_contract']['email'].endswith('@example.test')
        # Fail closed BEFORE any external request. Only the demonstrably fake
        # account and fresh QC reference may be disclosed to the QR service.
        if uri.hostname=='vietqr.app':
            assert query.get('acc')==[ACCOUNT] and query.get('des')==[payment['transactionCode']]
        else:
            assert '/image/970423-'+ACCOUNT+'-' in uri.path and query.get('addInfo')==[payment['transactionCode']]
        assert query.get('amount')==['12345']
        response=actor['context'].request.get(payment['qrCodeUrl'],timeout=30000)
        entry['qr_http_status']=response.status
        assert response.status==200 and response.headers.get('content-type','').startswith('image/'),'QR endpoint did not return an actual image'
        payload=response.body();image=Image.open(io.BytesIO(payload));decoded=zxingcpp.read_barcode(image)
        assert decoded and decoded.text,'Image did not contain a decodable QR'
        artifact=suite.run_dir/('payment-qr-'+payment['paymentId']+'.png');artifact.write_bytes(payload)
        entry['qr_image_artifact']=artifact.name
        text=decoded.text;fields={};offset=0
        while offset<len(text):
            tag=text[offset:offset+2];length=int(text[offset+2:offset+4]);fields[tag]=text[offset+4:offset+4+length];offset+=4+length
        assert fields['54']==str(int(payment['amount']))
        additional={};data=fields.get('62','');offset=0
        while offset<len(data):
            tag=data[offset:offset+2];length=int(data[offset+2:offset+4]);additional[tag]=data[offset+4:offset+4+length];offset+=4+length
        reference=additional.get('08','')
        entry['qr_reference_matches']=reference==re.sub('[^A-Za-z0-9]','',payment['transactionCode'])
        entry['qr_account_matches']=ACCOUNT in text
        entry['qr_reference_length']=len(fields.get('62',''))
        assert entry['qr_reference_matches'] and entry['qr_account_matches'],'Decoded QR does not contain the exact transaction reference and synthetic receiving account'
        qr_references[payment['paymentId']]=reference
        entry['qr_reference_normalized']=reference!=payment['transactionCode']
        expect(p.locator('app-payment-modal .qr-image')).to_be_visible()
        p.wait_for_function('()=>{const i=document.querySelector("app-payment-modal .qr-image");return i?.complete&&i.naturalWidth>0}')
        entry['resource_ids']=[payment['paymentId']];entry['qr_image_artifact']=artifact.name
        entry['qr_sha256']=hashlib.sha256(payload).hexdigest()
        entry['steps']=['Actual checkout QR URL requested from external image service','Decode actual returned bitmap using independent ZXing reader','EMV amount equals purchase amount; alphanumeric reference corresponds to exact payment and account remains synthetic','Actual browser image loads successfully; no transfer performed']
    case(suite,actor,'PAYMENT-QR-IMAGE-DECODE','U-PLAN.02','Actual rendered QR encodes this purchase amount and reference',qr_image,'payments')
    def rejected(entry):
        for bad,offset in [(True,0),(False,-600),(False,600)]:
            assert send(webhook(),bad=bad,offset=offset).status==401
            assert read()['status']=='pending' and entitlement()==baseline
        entry['resource_ids']=[payment['paymentId']];entry['steps']=['Wrong signature and stale/future timestamp hit real webhook','Every request rejected 401','Payment stays pending; no entitlement granted']
    case(suite,actor,'PAYMENT-WEBHOOK-SIGNATURE-TIMESTAMP','U-PLAN.02','Invalid webhook cannot activate a plan',rejected,'payments')
    def ignored(entry):
        for change in [{'transferAmount':12344},{'transferType':'out'},{'accountNumber':'9999999999'},{'content':'UNRELATED-QC-CODE'}]:
            assert send(webhook(**change)).status==200
            assert read()['status']=='pending' and entitlement()==baseline
        entry['resource_ids']=[payment['paymentId']];entry['steps']=['Signed underpayment/outgoing/wrong recipient/unmatched transfer','Actual webhook responses acknowledged','No payment or entitlement mutation on any ignored transfer']
    case(suite,actor,'PAYMENT-WEBHOOK-NONMATCHING-NO-ENTITLEMENT','U-PLAN.02','Unmatched signed transfers do not grant plan',ignored,'payments')
    def cancel(entry):
        suite.api(member,'post','/payments/'+payment['paymentId']+'/cancel',data={},expected=404)
        suite.response(actor,'/payments/'+payment['paymentId']+'/cancel',lambda:p.locator('app-payment-modal .cancel-btn').click(),method='POST',status=204)
        expect(p.locator('app-payment-modal .result-box.failed')).to_be_visible()
        assert read()['status']=='cancelled'
        suite.api(actor,'post','/payments/'+payment['paymentId']+'/cancel',data={},expected=204)
        assert send(webhook()).status==200
        assert read()['status']=='cancelled' and entitlement()==baseline
        entry['resource_ids']=[payment['paymentId']];entry['steps']=['Foreign cancel denied','Actual checkout cancel button persists cancelled state','Repeated cancel idempotent','Late valid signed transfer cannot activate cancelled purchase']
    case(suite,actor,'PAYMENT-UI-CANCEL-REPLAY-LATE-WEBHOOK','U-PLAN.02','Cancelled payment stays cancelled after webhook',cancel,'payments')
    def expired(entry):
        payment.clear();payment.update(suite.api(actor,'post','/payments',data={'planId':pid,'idempotencyKey':'qc-expire-'+suite.run_id}).json())
        db.sql("UPDATE payments SET expires_at=now()+interval '3 seconds' WHERE payment_id=:'id'::uuid AND user_id=:'uid'::uuid AND status='pending';",{'id':payment['paymentId'],'uid':uid})
        p.wait_for_timeout(4000)
        assert send(webhook()).status==200
        assert read()['status']=='cancelled' and entitlement()==baseline
        entry['resource_ids']=[payment['paymentId']];entry['steps']=['Actual API creates new pending payment','Only fixture expiration deadline shortened in owned DB; no payment/entitlement result seeded','Wait for actual backend clock to pass deadline','Valid late webhook persists cancelled and grants no entitlement']
    case(suite,actor,'PAYMENT-EXPIRED-WEBHOOK-NO-ENTITLEMENT','U-PLAN.02','Expired pending purchase cannot activate plan',expired,'payments')
    def paid(entry):
        suite.go(actor,'/plans/'+pid,'app-plan-detail-page')
        payment.clear();payment.update(suite.response(actor,'/payments',lambda:p.locator('button.cta-subscribe').click(),method='POST').json())
        qr_image(entry)
        payload=webhook(content=qr_references[payment['paymentId']]);assert send(payload).status==200
        assert read()['status']=='paid' and entitlement()==pid
        expect(p.locator('app-payment-modal .result-box.success')).to_be_visible(timeout=15000)
        history=db.sql("SELECT count(*) FROM plan_histories WHERE payment_reference=:'id';",{'id':payment['paymentId']})
        assert history=='1'
        for _ in range(2):assert send(payload).status==200
        assert db.sql("SELECT count(*) FROM plan_histories WHERE payment_reference=:'id';",{'id':payment['paymentId']})=='1'
        suite.api(actor,'post','/payments/'+payment['paymentId']+'/cancel',data={},expected=409)
        assert read()['status']=='paid' and entitlement()==pid
        entry['resource_ids']=[pid,payment['paymentId']]
        entry['steps']=['Create new checkout after prior cancellation','Decode actual generated QR and use its alphanumeric reference in signed QC transfer through real webhook','Actual UI polling shows success; my-plan reports same purchased plan','Read DB one linked plan history; two webhook replays retain exactly one history','Paid payment cannot be cancelled','Provider-origin delivery remains unverified; no real transfer']
    try:case(suite,actor,'PAYMENT-UI-PAID-WEBHOOK-EXACTLY-ONCE','U-PLAN.02','Signed transfer activates one entitlement',paid,'payments')
    finally:
        suite.api(admin,'post','/admin/plans/'+pid+'/archive',data={},expected=204)
        suite.release_actor(actor)
