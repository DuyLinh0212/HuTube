"""Hold one real training submission; all business responses come from the real service."""
import argparse,http.client,json,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,required=True);parser.add_argument('--control-root',required=True);args=parser.parse_args()
    assert args.port==53494
    root=Path(args.control_root);root.mkdir(parents=True,exist_ok=True)
    def write(name,data):
        path=root/name;temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(data),encoding='utf-8');temporary.replace(path)
    class Handler(BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def read_body(self):
            if self.headers.get('Transfer-Encoding','').lower()!='chunked':
                size=int(self.headers.get('Content-Length','0'));assert 0<=size<=1024**2
                return self.rfile.read(size)
            chunks=[];total=0
            while True:
                size=int(self.rfile.readline(128).split(b';',1)[0].strip(),16)
                if size==0:
                    while self.rfile.readline(8192) not in (b'\r\n',b'\n',b''):pass
                    return b''.join(chunks)
                total+=size;assert total<=1024**2
                chunk=self.rfile.read(size);assert len(chunk)==size
                chunks.append(chunk);assert self.rfile.read(2)==b'\r\n'
        def forward(self):
            path=urlsplit(self.path).path
            if path!='/health' and not path.startswith('/internal/model'):
                self.send_error(404);return
            body=self.read_body()
            arm=root/'arm.json'
            if self.command=='POST' and path=='/internal/model/train' and arm.exists():
                command=json.loads(arm.read_text(encoding='utf-8'));arm.unlink();job=json.loads(body)
                write('applied.json',{'id':command['id'],'jobId':job['jobId'],'phase':'actual-training-request-before-upstream-submit'})
                deadline=time.monotonic()+25;released=False
                while time.monotonic()<deadline:
                    try:
                        if json.loads((root/'release.json').read_text(encoding='utf-8'))['id']==command['id']:released=True;break
                    except (FileNotFoundError,PermissionError,json.JSONDecodeError):pass
                    time.sleep(.02)
                write('released.json',{'id':command['id'],'by_test':released})
            connection=http.client.HTTPConnection('127.0.0.1',53493,timeout=30)
            try:
                headers={key:value for key,value in self.headers.items() if key.lower() not in ('host','connection','content-length','transfer-encoding','expect')}
                connection.request(self.command,self.path,body=body,headers=headers);response=connection.getresponse();payload=response.read()
                self.send_response(response.status);self.send_header('Content-Type',response.getheader('Content-Type','application/json'));self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
            except (OSError,http.client.HTTPException):self.close_connection=True
            finally:connection.close()
        do_GET=forward
        do_POST=forward
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler);server.daemon_threads=True;server.serve_forever()

if __name__=='__main__':main()
