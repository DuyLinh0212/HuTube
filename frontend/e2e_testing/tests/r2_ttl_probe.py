"""Real R2 signed URL/expiry, strictly one new synthetic object, no bucket scan."""
import hashlib,json,sys,time,uuid,math
from datetime import datetime,timezone,timedelta
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit,parse_qs
from pathlib import Path
from urllib.request import urlopen,Request
from urllib.error import HTTPError
import boto3
from botocore.config import Config

ROOT=Path(__file__).resolve().parents[3]
def main():
    config={}
    for line in (ROOT/'.env.local').read_text(encoding='utf-8-sig').splitlines():
        if line.lstrip().startswith('#') or '=' not in line:continue
        key,value=line.split('=',1);config[key.strip()]=value.strip().strip('"').strip("'")
    prefix='Storage__R2__'
    required=['AccountId','AccessKeyId','SecretAccessKey','BucketName']
    missing=[key for key in required if not config.get(prefix+key)]
    run=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    out=ROOT/'outputs/20261016-all-remaining/r2';out.mkdir(parents=True,exist_ok=True)
    report={'run_id':run,'kind':'Actual Cloudflare R2 integration; no app UI or physical-device claim',
            'cases':[],'cleanup':None,'secrets_recorded':False}
    key='qc-e2e/'+run+'/'+uuid.uuid4().hex+'.txt'
    client=None;created=False
    def record(id,status,**details):report['cases'].append({'id':id,'status':status,**details})
    def fetch(url):
        try:
            with urlopen(Request(url,headers={'Cache-Control':'no-cache'}),timeout=20) as response:return response.status,response.read(),dict(response.headers)
        except HTTPError as error:return error.code,error.read(),dict(error.headers)
    try:
        if missing:
            record('R2-SIGNED-URL-TTL','blocked',reason='Missing configuration names: '+','.join(missing));return 2
        client=boto3.client('s3',endpoint_url='https://'+config[prefix+'AccountId']+'.r2.cloudflarestorage.com',
            aws_access_key_id=config[prefix+'AccessKeyId'],aws_secret_access_key=config[prefix+'SecretAccessKey'],
            region_name='auto',config=Config(signature_version='s3v4',connect_timeout=15,read_timeout=20,retries={'max_attempts':0}))
        bucket=config[prefix+'BucketName'];payload=('HuTube QC synthetic TTL probe '+run).encode()
        client.put_object(Bucket=bucket,Key=key,Body=payload,ContentType='text/plain');created=True
        # Do not log the URL or bearer query credentials.
        url=client.generate_presigned_url('get_object',Params={'Bucket':bucket,'Key':key},ExpiresIn=5)
        signed_at=datetime.now(timezone.utc).isoformat()
        status,body,headers=fetch(url)
        assert status==200 and body==payload
        record('R2-SIGNED-URL-VALID-READ','passed',http_status=status,sha256=hashlib.sha256(body).hexdigest(),local_utc=signed_at,server_date=headers.get('Date'),age=headers.get('Age'))
        # Machine clock may run ahead of R2. Expiry is evaluated by the service,
        # so wait until its observed clock has passed the signed absolute expiry.
        signed_stamp=parse_qs(urlsplit(url).query)['X-Amz-Date'][0]
        absolute_expiry=datetime.strptime(signed_stamp,'%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)+timedelta(seconds=5)
        server_now=parsedate_to_datetime(headers['Date'])
        wait=max(8,math.ceil((absolute_expiry-server_now).total_seconds())+3)
        assert wait<=180,'Clock skew too large for bounded TTL probe'
        report['clock_observation']={'client_ahead_seconds':round((datetime.fromisoformat(signed_at)-server_now).total_seconds(),2),'wait_for_server_expiry_seconds':wait}
        remaining=wait
        while remaining:
            delay=min(10,remaining);time.sleep(delay);remaining-=delay
        status,expired_body,headers=fetch(url)
        observations=[{'wait_seconds':wait,'http_status':status,'server_date':headers.get('Date'),'age':headers.get('Age')}]
        record('R2-SIGNED-URL-EXPIRED-DENIED','passed' if status in (400,403) else 'failed',http_status=status,requested_ttl_seconds=5,observations=observations)
        assert status in (400,403),'Expired signed URL remained usable or returned unexpected status'
        url=client.generate_presigned_url('get_object',Params={'Bucket':bucket,'Key':key},ExpiresIn=60)
        client.delete_object(Bucket=bucket,Key=key);created=False
        status,_,_=fetch(url);assert status==404
        record('R2-DELETED-OBJECT-OLD-SIGNED-URL','passed',http_status=status)
        report['cleanup']={'status':'deleted_exact_owned_object','key':key,'bucket_name_omitted':True}
        return 0
    except Exception as error:
        response=getattr(error,'response',{})
        record('R2-PROBE-FAILURE','failed',error_type=type(error).__name__,
               http_status=response.get('ResponseMetadata',{}).get('HTTPStatusCode'))
        return 1
    finally:
        if created and client is not None:
            try:
                client.delete_object(Bucket=config[prefix+'BucketName'],Key=key)
                report['cleanup']={'status':'deleted_exact_owned_object','key':key,'bucket_name_omitted':True}
            except Exception as error:report['cleanup']={'status':'failed','error_type':type(error).__name__,'key':key}
        (out/(run+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':sys.exit(main())
