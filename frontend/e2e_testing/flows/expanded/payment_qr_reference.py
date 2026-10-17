"""Real checkout/webhook with the alphanumeric reference observed in actual QR."""
import hashlib,hmac,json,time
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.security_plan_common import identity
from flows.expanded.payment_contract import ACCOUNT,SECRET

def run(suite,config,actors):
    snapshot_module(suite,__file__);admin=actors['admin'];uid=identity(suite,config,'qr_reference');actor=suite.actor('qr-reference','user','qr_reference');p=actor['page'];payment={}
    plan=suite.api(admin,'post','/admin/plans',data={'code':'qc_qrref_'+suite.run_id[9:15],'name':'QC QR reference '+suite.run_id,
        'description':'Synthetic normalization contract; no real transfer','price':12345,'durationDays':30,'storageLimit':2*1024**3,
        'maxUploadSize':10*1024**2,'maxVideoDuration':60,'maxVideoQuality':'360p','maxDownloadQuality':'360p','maxMembers':1,
        'features':'{}','isDefaultForNewUsers':False},expected=201).json()
    def normalized(entry):
        suite.go(actor,'/plans/'+plan['planId'],'app-plan-detail-page')
        payment.update(suite.response(actor,'/payments',lambda:p.locator('button.cta-subscribe').click(),method='POST').json())
        expect(p.locator('app-payment-modal .modal-card')).to_be_visible()
        assert payment['amount']==12345 and payment['transactionCode'].startswith('QCLOCAL-')
        reference=''.join(ch for ch in payment['transactionCode'] if ch.isalnum())
        payload={'id':int(time.time()*1000),'gateway':'QC-INJECTION','transactionDate':'2026-10-16 12:00:00',
            'accountNumber':ACCOUNT,'subAccount':None,'code':None,'content':reference,'transferType':'in','transferAmount':12345,'accumulated':0,'referenceCode':'QC-only'}
        body=json.dumps(payload,separators=(',',':'));stamp=str(int(time.time()));signature='sha256='+hmac.new(SECRET.encode(),(stamp+'.'+body).encode(),hashlib.sha256).hexdigest()
        response=actor['context'].request.post(actor['api_url']+'/payments/webhook/sepay',data=body,
            headers={'Content-Type':'application/json','X-SePay-Signature':signature,'X-SePay-Timestamp':stamp})
        assert response.status==200
        state=suite.api(actor,'get','/payments/'+payment['paymentId']).json();entry['observed_payment_status']=state['status'];entry['resource_ids']=[uid,payment['paymentId']]
        entry['steps']=['Create actual UI checkout for synthetic Member and fake receiving account','QR diagnostic observed that provider removes punctuation from transfer reference','Send valid signed webhook with exact alphanumeric QC reference through actual payment endpoint','Require actual paid state and matching entitlement; no payment result seeded']
        assert state['status']=='paid','Actual signed webhook with QR-normalized reference did not match pending payment'
        assert suite.api(actor,'get','/plans/my-plan').json()['planId']==plan['planId']
        expect(p.locator('app-payment-modal .result-box.success')).to_be_visible(timeout=15000)
    try:case(suite,actor,'PAYMENT-WEBHOOK-QR-NORMALIZED-REFERENCE','U-PLAN.02','Actual QR reference activates the intended payment',normalized,'payments')
    finally:
        if payment:
            state=suite.api(actor,'get','/payments/'+payment['paymentId']).json()
            if state['status']=='pending':suite.api(actor,'post','/payments/'+payment['paymentId']+'/cancel',data={},expected=204)
        suite.api(admin,'post','/admin/plans/'+plan['planId']+'/archive',data={},expected=204);suite.release_actor(actor)
