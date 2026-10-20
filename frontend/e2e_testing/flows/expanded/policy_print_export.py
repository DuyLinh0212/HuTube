"""Distinguish a genuine PDF download from a print call and success toast."""
import json,subprocess,time
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing

PYTHON='C:/Users/Danh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
NODE='C:/Users/Danh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
MARKER='C:/Users/Danh/.codex/plugins/cache/openai-primary-runtime/pdf/26.1013.11914/skills/pdf/container_tools/mark_artifact_operation_started.mjs'

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    guest=suite.actor('policy-print-export','user','guest');guest['api_url']=config['api_url'];p=guest['page'];downloads=[]
    guest['context'].add_init_script('window.__qcPrintEvents=[];for(const type of ["beforeprint","afterprint"])window.addEventListener(type,()=>window.__qcPrintEvents.push(type));')
    p.on('download',lambda download:downloads.append(download))
    public=suite.api(guest,'get','/policies').json()
    policy=next((item for item in public if item['code'].startswith('QC_POLICY_')),None)
    if policy is None:raise PrerequisiteMissing('Actual published QC policy fixture needed for document content comparison')
    group=policy.get('group','guidelines');group=group if group in ['guidelines','terms','privacy','monetization','enforcement'] else 'guidelines'
    def load():
        suite.go(guest,'/policies?tab='+group,'app-public-policy-page','/policies')
        card=p.locator('.policy-card').filter(has_text=policy['name']).first
        expect(card).to_contain_text(policy['content']);expect(card.locator('.policy-version')).to_contain_text(policy['version'])
    try:
        def print_command(entry):
            load();before=p.evaluate('()=>window.__qcPrintEvents.filter(x=>x==="beforeprint").length')
            p.locator('.hub-actions .btn-action-icon').click()
            p.wait_for_function('(n)=>window.__qcPrintEvents.filter(x=>x==="beforeprint").length>n',arg=before)
            expect(p.locator('.toast-banner')).to_be_visible()
            entry['print_events']=p.evaluate('()=>window.__qcPrintEvents');entry['resource_ids']=[policy['policyId']]
            entry['steps']=['Public UI renders exact API published content and version','Press actual Print button','Actual browser beforeprint event emitted; print function not replaced','Printer hardware/dialog completion is outside this headless command assertion']
        case(suite,guest,'POLICY-ACTUAL-BROWSER-PRINT-COMMAND','U-POLICY.01','Print button invokes the real browser print pipeline',print_command,'policy')
        def pdf(entry):
            load();downloads.clear()
            # Exactly one operation marker before attempting the actual app export.
            subprocess.run([NODE,MARKER,'--operation-kind','create','--expected-output-count','1','--output-format','pdf'],check=True,timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
            p.locator('.hub-actions .btn-action-primary').click()
            expect(p.locator('.toast-banner')).to_be_visible()
            entry['observed_export_toast']=p.locator('.toast-banner').inner_text()
            entry['resource_ids']=[policy['policyId']]
            entry['steps']=['Exact published API policy/version on actual UI','Press actual Download PDF button and observe its feedback','Require one real browser download, then validate PDF bytes and published content','Do not substitute page.pdf/window.print output for an absent download']
            suite.evidence(guest,entry,'actual-pdf-export-feedback')
            deadline=time.monotonic()+6
            while not downloads and time.monotonic()<deadline:p.wait_for_timeout(100)
            entry['browser_download_count']=len(downloads);entry['print_events']=p.evaluate('()=>window.__qcPrintEvents')
            assert len(downloads)==1,'Download PDF shows success but produces no download; current handler calls window.print rather than creating a PDF file'
            path=suite.run_dir/'policy-actual-download.pdf';downloads[0].save_as(path)
            expected=suite.run_dir/'policy-pdf-expected.json';expected.write_text(json.dumps({key:policy[key] for key in ['name','content','version']},ensure_ascii=False),encoding='utf-8')
            result=subprocess.run([PYTHON,str(Path(__file__).resolve().parents[2]/'support/inspect_policy_pdf.py'),str(path),str(expected)],capture_output=True,text=True,encoding='utf-8',timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
            assert result.returncode==0,'Downloaded PDF does not contain actual published content/version'
            entry['pdf_validation']=json.loads(result.stdout);entry['pdf_artifact']=path.name
        case(suite,guest,'POLICY-DOWNLOAD-PDF-ACTUAL-FILE-CONTENT','U-POLICY.01','PDF success requires a real file with actual policy data',pdf,'policy')
    finally:suite.release_actor(guest)
