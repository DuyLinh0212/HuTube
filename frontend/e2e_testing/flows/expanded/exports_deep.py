import csv,io
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,admin=actors['owner'],actors['admin'];video=suite.fixtures['video'];vid=video['videoId'];original=suite.api(owner,'get','/videos/'+vid).json()['title']
    formula='=1+1, "QC CSV" '+suite.run_id
    try:
        suite.api(owner,'patch','/videos/'+vid,data={'title':formula})
        def export(entry):
            p=admin['page'];suite.go(admin,'/videos','app-admin-videos-page','/admin/videos')
            search=p.locator('input[type=search]');search.fill('QC CSV')
            suite.response(admin,'/admin/videos',lambda:search.press('Enter'))
            expect(p.locator('tbody .video-row')).to_have_count(1)
            with p.expect_download() as event:p.locator('.btn-export-data').click()
            download=event.value;path=suite.run_dir/'admin-videos-actual.csv';download.save_as(str(path))
            rows=list(csv.reader(io.StringIO(path.read_text(encoding='utf-8-sig'))));assert len(rows)==2 and len(rows[0])==10
            assert rows[1][0]==vid and rows[1][1]=="'"+formula,'CSV title must preserve delimiters/quotes and escape leading formula'
            assert int(rows[1][7])==suite.api(owner,'get','/videos/'+vid).json()['stats']['views']
            entry['resource_ids']=[vid];entry['download_artifact']=str(path)
            entry['steps']=['Owned fixture title contains formula prefix, comma and quotes','Admin searches exact fixture → one actual row','UI downloads real CSV file','Parse header/count/ID/views; verify formula escaped and original content preserved']
        case(suite,admin,'ADMIN-VIDEOS-CSV-FORMULA-CONTENT','A-VIDEOS.02','Actual CSV preserves rows and neutralizes formulas',export,'exports')
    finally:suite.api(owner,'patch','/videos/'+vid,data={'title':original})
