import subprocess,sys,time,socket,os
from pathlib import Path
root=Path(__file__).resolve().parents[2]
output=Path(os.environ.get('BUGFIX_OUTPUT_DIR', str(root/'.codex-build-verify')))
output.mkdir(parents=True, exist_ok=True)
os.environ['BUGFIX_OUTPUT_DIR']=str(output)
ffmpeg=os.environ.get('FFMPEG_BIN') or 'ffmpeg'
subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=blue:s=1280x720:r=25','-t','1','-c:v','libx264','-pix_fmt','yuv420p',str(output/'sample-720.mp4')],check=True)
servers=[]
try:
    for app,port in [('user',4300),('admin',4301)]:
        servers.append(subprocess.Popen([sys.executable,str(root/'scripts/ui-regression/serve.py'),'--root',str(root/f'frontend/{app}-web/dist/{app}-web/browser'),'--port',str(port)]))
        for attempt in range(60):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.5):break
            except OSError:time.sleep(.2)
        else:raise RuntimeError('Server failed')
    result=subprocess.run([sys.executable,str(root/'scripts/ui-regression'/(sys.argv[1] if len(sys.argv)>1 else 'browser-bugfix.py'))],env={**os.environ,'PYTHONIOENCODING':'utf-8'})
finally:
    for server in servers:server.terminate();server.wait(timeout=5)
sys.exit(result.returncode)
