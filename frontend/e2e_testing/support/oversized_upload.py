"""Read the actual early size rejection when a full-body client sees a reset."""
import http.client
from urllib.parse import urlsplit
from flows.expanded.common import snapshot_module


def reject_oversized(suite,actor,path,payload,entry):
    snapshot_module(suite,__file__)
    try:
        response=suite.api(actor,'post',path,multipart={'file':payload},expected=(400,413,415,422))
        entry['oversized_http_status']=response.status
        return
    except RuntimeError as error:
        diagnostic=str(error)
        if not any(term in diagnostic for term in ('ECONNRESET','aborted','socket hang up')):raise
        entry['full_body_transport']='Full multipart client observed connection reset/abort before reading the early response'
    origin=urlsplit(actor['api_url'])
    assert origin.scheme=='http' and origin.hostname in ('127.0.0.1','localhost')
    boundary='HuTubeQCOversizedBoundary'
    prefix=(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="qc-oversized.png"\r\nContent-Type: image/png\r\n\r\n').encode()
    suffix=('\r\n--'+boundary+'--\r\n').encode()
    connection=http.client.HTTPConnection(origin.hostname,origin.port,timeout=15)
    try:
        connection.putrequest('POST',origin.path+path)
        connection.putheader('Content-Type','multipart/form-data; boundary='+boundary)
        connection.putheader('Content-Length',str(len(prefix)+len(payload['buffer'])+len(suffix)))
        connection.putheader('Connection','close')
        for name,value in actor['headers'].items():connection.putheader(name,value)
        connection.endheaders()
        # Read the early rejection rather than continuing to write megabytes
        # after Kestrel has already closed its request body stream.
        connection.send(prefix+payload['buffer'][:16])
        response=connection.getresponse()
        status=response.status
        body=response.read(8192).decode('utf-8',errors='replace')
        assert status in (400,413),'Declared oversized multipart must be rejected early; got '+str(status)
        if status==400:
            assert any(term in body.lower() for term in ('body too large','max request body size','maximum request body size')),'400 must explicitly identify request-size rejection, not a malformed multipart'
    finally:connection.close()
    suite.report['http_statuses'].append({'actor':actor['name'],'case':suite.current,
        'method':'POST','path':origin.path+path,'status':status,'transport':'HTTP early-response probe'})
    entry['oversized_http_status']=status
    entry['early_rejection_proof']='Actual early HTTP '+str(status)+' for oversized Content-Length; 400 additionally requires explicit body-size error. Prefix sent, response read before full upload. Browser file input and persistence checked separately.'
