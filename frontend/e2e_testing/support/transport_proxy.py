"""Loopback forwarding proxy: one armed, real TCP drop during upload body.

All application responses originate from the actual API; no response mocking.
"""
import argparse,hashlib,http.client,json,re,socket,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit,parse_qs

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,required=True);parser.add_argument('--target',required=True);parser.add_argument('--control',type=Path,required=True);args=parser.parse_args()
    target=urlsplit(args.target);assert target.hostname in ('127.0.0.1','localhost')
    lock=threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def handle_request(self):
            connection=http.client.HTTPConnection(target.hostname,target.port,timeout=180)
            length=int(self.headers.get('Content-Length','0'));cut=False;hold=False;delay=None
            drop_response=None
            if self.command=='GET':
                delay_file=args.control.with_suffix('.delay.json')
                with lock:
                    if delay_file.exists():
                        candidate=json.loads(delay_file.read_text(encoding='utf-8'))
                        allowed=candidate['path']=='/api/v1/videos/search' or re.fullmatch(r'/api/v1/playlists/[0-9a-f-]{36}',candidate['path'])
                        assert allowed and 0<candidate['delay_ms']<=5000
                        query=parse_qs(urlsplit(self.path).query)
                        if urlsplit(self.path).path==candidate['path'] and all(query.get(k)==[str(v)] for k,v in candidate['query'].items()):
                            delay=candidate;delay_file.unlink()
            if self.command=='POST' and urlsplit(self.path).path=='/api/v1/playlists':
                drop_file=args.control.with_suffix('.drop-response.json')
                with lock:
                    if drop_file.exists():
                        candidate=json.loads(drop_file.read_text(encoding='utf-8'))
                        assert candidate['path']=='/api/v1/playlists'
                        drop_response=candidate;drop_file.unlink()
            if self.command=='POST' and urlsplit(self.path).path=='/api/v1/videos':
                with lock:
                    if args.control.exists():args.control.unlink();cut=True
                    hold_file=args.control.with_suffix('.hold.json')
                    if hold_file.exists():hold_file.unlink();hold=True
            try:
                connection.putrequest(self.command,self.path,skip_host=True,skip_accept_encoding=True)
                for key,value in self.headers.items():
                    if key.lower() not in ('host','connection','upgrade'):connection.putheader(key,value)
                connection.putheader('Host',target.netloc);connection.putheader('Connection','close');connection.endheaders()
                forwarded=0
                while forwarded<length:
                    payload=self.rfile.read(min(8192,length-forwarded))
                    if not payload:break
                    connection.send(payload);forwarded+=len(payload)
                    if hold and forwarded>=32768:
                        args.control.with_suffix('.hold.applied.json').write_text(json.dumps({
                            'bytes_forwarded':forwarded,'declared_bytes':length,
                            'kind':'Real upstream upload held before full body; client UI cancellation must precede release'}),encoding='utf-8')
                        release=args.control.with_suffix('.hold.release');deadline=time.monotonic()+20
                        while not release.exists() and time.monotonic()<deadline:time.sleep(.05)
                        if release.exists():release.unlink()
                        connection.close();self.close_connection=True
                        try:self.connection.shutdown(socket.SHUT_RDWR)
                        except OSError:pass
                        return
                    if cut and forwarded>=32768:
                        event={'method':'POST','path':'/api/v1/videos','bytes_forwarded':forwarded,'declared_bytes':length,
                               'idempotency_key_sha256':hashlib.sha256(self.headers.get('Idempotency-Key','').encode()).hexdigest(),
                               'kind':'Actual upstream TCP body truncated; no application response fabricated'}
                        args.control.with_suffix('.applied.json').write_text(json.dumps(event,indent=2),encoding='utf-8')
                        connection.close();self.close_connection=True
                        try:self.connection.shutdown(socket.SHUT_RDWR)
                        except OSError:pass
                        return
                response=connection.getresponse();body=response.read()
                if drop_response:
                    # The real API has committed and returned its response. Drop
                    # only the browser-facing acknowledgement to model a lost
                    # response without fabricating or altering an API payload.
                    event={'id':drop_response['id'],'path':drop_response['path'],
                        'origin_status':response.status,'origin_body_sha256':hashlib.sha256(body).hexdigest(),
                        'kind':'Actual successful upstream response dropped after commit; no client response fabricated'}
                    args.control.with_suffix('.drop-response.applied.json').write_text(json.dumps(event,indent=2),encoding='utf-8')
                    self.close_connection=True
                    try:self.connection.shutdown(socket.SHUT_RDWR)
                    except OSError:pass
                    return
                if delay:
                    event={'id':delay['id'],'path':delay['path'],'origin_status':response.status,
                        'delay_ms':delay['delay_ms'],'response_sha256':hashlib.sha256(body).hexdigest(),
                        'kind':'Actual upstream response held; no application payload fabricated'}
                    args.control.with_suffix('.delay.applied.json').write_text(json.dumps(event),encoding='utf-8')
                    time.sleep(delay['delay_ms']/1000)
                    args.control.with_suffix('.delay.released.json').write_text(json.dumps({'id':delay['id'],'released':True}),encoding='utf-8')
                self.send_response(response.status,response.reason)
                for key,value in response.getheaders():
                    if key.lower() not in ('connection','content-length','transfer-encoding','keep-alive'):self.send_header(key,value)
                self.send_header('Content-Length',str(len(body)));self.send_header('Connection','close');self.end_headers()
                self.wfile.write(body);self.close_connection=True
            except (OSError,http.client.HTTPException):
                self.close_connection=True
                try:self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:pass
            finally:connection.close()
        do_GET=do_POST=do_PUT=do_PATCH=do_DELETE=do_OPTIONS=do_HEAD=handle_request
        def log_message(self,*args):pass
    class Server(ThreadingHTTPServer):
        request_queue_size=128
        daemon_threads=True
    Server(('127.0.0.1',args.port),Handler).serve_forever()

if __name__=='__main__':main()
