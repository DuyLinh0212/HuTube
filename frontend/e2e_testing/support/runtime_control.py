"""Restart only the runner-owned API, using original env plus bounded test faults."""
import json
from pathlib import Path

def handle(config,run,api,dll,origin,content_root,env,server,stop,health):
    if not config.get('runtime_control_request'):return api
    request=Path(config['runtime_control_request']);response=Path(config['runtime_control_response'])
    if not request.exists():return api
    data=json.loads(request.read_text(encoding='utf-8'));request.unlink()
    assert data['action']=='restart-owned-api' and data['mode'] in ('normal','ffprobe-failure','ffmpeg-failure')
    count=config.get('_runtime_restart_count',0)+1;assert count<=12
    config['_runtime_restart_count']=count
    restart_env=env.copy()
    if data['mode']=='ffprobe-failure':restart_env['VideoProcessing__FfprobePath']=str(run/'missing-qc-ffprobe.exe')
    if data['mode']=='ffmpeg-failure':restart_env['VideoProcessing__FfmpegPath']=str(run/'missing-qc-ffmpeg.exe')
    stop(api)
    api=server(['dotnet',str(dll),'--urls',origin],f'api-restart-{count}-{data["mode"]}.log',content_root,restart_env)
    health(origin+'/health',api,config['startup_seconds'])
    temp=response.with_suffix('.tmp');temp.write_text(json.dumps({'id':data['id'],'status':'ready','mode':data['mode'],'restart_index':count}),encoding='utf-8');temp.replace(response)
    return api
