import hashlib
from pathlib import Path
from playwright.sync_api import expect

def open_upload_progress(page):
    orb = page.locator('app-upload-progress-tray .upload-orb')
    expect(orb).to_be_visible()
    if orb.get_attribute('aria-expanded') != 'true':
        orb.click()
    expect(page.locator('app-upload-progress-tray .tray-details')).to_be_visible()

def minimize_upload_progress(page):
    orb = page.locator('app-upload-progress-tray .upload-orb')
    if orb.get_attribute('aria-expanded') == 'true':
        page.locator('app-upload-progress-tray .tray-close').click()

def snapshot_module(suite,file):
    source=Path(file);relative=source.relative_to(Path(__file__).resolve().parents[2])
    target=suite.run_dir/'test-sources'/relative;target.parent.mkdir(parents=True,exist_ok=True)
    payload=source.read_bytes();target.write_bytes(payload)
    record={'path':relative.as_posix(),'sha256':hashlib.sha256(payload).hexdigest(),'snapshot_phase':'before_module_execution'}
    suite.report['test_source_snapshot']=[s for s in suite.report['test_source_snapshot'] if s['path']!=record['path']]+[record]

def case(suite,actor,id,parent,title,action,module='expanded'):
    def execute(entry):
        action(entry)
        if not entry['steps']:entry['steps']=[title,'Actual UI/API expected/observed assertions','Capture all three viewports']
    return suite.case(actor,'FULL-'+id,parent,title,title,execute,module=module)

def actual_ui(suite,actor,route,selector,endpoint=None):
    return suite.go(actor,route,selector,endpoint)
