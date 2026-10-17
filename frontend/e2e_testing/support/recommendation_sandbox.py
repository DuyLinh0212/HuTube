"""Bootstrap only owned local S3 emulator; verify conditional-write semantics."""
import boto3
import hashlib
import io
import json
import sys
import zipfile
from pathlib import Path
from botocore.exceptions import ClientError

def main():
    client=boto3.client('s3',endpoint_url='http://127.0.0.1:53492',region_name='us-east-1',
        aws_access_key_id='hutube-qc-only',aws_secret_access_key='hutube-qc-only-secret')
    bucket='hutube-qc-recommendations'
    if len(sys.argv)>1 and sys.argv[1]=='--audit':
        out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
        read=lambda key:client.get_object(Bucket=bucket,Key=key)['Body'].read()
        manifest=json.loads(read('collaborative_cf/active.json'))
        csv=read(manifest['csvKey']);artifact=read(manifest['artifactKey'])
        assert hashlib.sha256(csv).hexdigest()==manifest['csvSha256']
        assert hashlib.sha256(artifact).hexdigest()==manifest['artifactSha256']
        with zipfile.ZipFile(io.BytesIO(artifact)) as archive:files=archive.namelist();assert len(files)>2
        (out/'model-artifact.zip').write_bytes(artifact)
        result={'manifest':manifest,'artifact_bytes':len(artifact),'artifact_files':files,'csv_bytes':len(csv),
            'storage':'Moto S3 loopback emulator; actual service training, no fabricated model or job status'}
        (out/'audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps(result));return
    client.create_bucket(Bucket=bucket)
    item={'Bucket':bucket,'Key':'qc-conditional-probe','Body':b'owned QC probe'}
    result=client.put_object(**item,IfNoneMatch='*')
    try:client.put_object(**item,IfNoneMatch='*')
    except ClientError as error:assert error.response['ResponseMetadata']['HTTPStatusCode']==412
    else:raise AssertionError('S3 emulator did not enforce IfNoneMatch')
    try:client.put_object(**item,IfMatch='"incorrect"')
    except ClientError as error:assert error.response['ResponseMetadata']['HTTPStatusCode']==412
    else:raise AssertionError('S3 emulator did not enforce IfMatch')
    client.put_object(**item,IfMatch=result['ETag']);client.delete_object(Bucket=bucket,Key=item['Key'])
    print('Isolated S3 bucket created; conditional write lease semantics verified. No real R2 contacted.')

if __name__=='__main__':main()
