"""Check evidence integrity of a completed live run, without inventing coverage."""
import argparse
import json
import re
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report',type=Path)
    parser.add_argument('--latest-only',action='store_true',help='Validate final logical attempts only; disclose historical overwritten evidence instead of certifying every attempt.')
    args=parser.parse_args()
    data=json.loads(args.report.read_text(encoding='utf-8'))
    assert data.get('finished_at') and data['suite']=='web-live-functional'
    ids=[case['id'] for case in data['cases']]
    # An explicit rerun may retain a logical ID. Require distinct evidence files
    # so a later attempt cannot overwrite the earlier observed failure/success.
    repeated={id for id in ids if ids.count(id)>1}
    for id in repeated:
        paths=[image['path'] for case in data['cases'] if case['id']==id for image in case['screenshots']]
        if not args.latest_only:assert len(paths)==len(set(paths)), 'Repeated logical case overwrote evidence: '+id
    if repeated:print('Repeated logical IDs; latest-only selection' if args.latest_only else 'Repeated logical IDs with distinct attempt evidence:',sorted(repeated))
    screenshots=0
    selected=list({c.get('logical_id',c['id']):c for c in data['cases']}.values()) if args.latest_only else data['cases']
    if args.latest_only:print('LATEST-ONLY audit; historical repeated-attempt evidence is not certified')
    for case in selected:
        if case['status']=='passed':
            assert case.get('functional_status')=='passed'
            assert case['steps'], 'Passing case needs executed steps'
            assert {image['viewport'] for image in case['screenshots']}=={'desktop','mobile','tablet'}
            assert not case.get('responsive_failures')
        for image in case['screenshots']:
            path=(ROOT/image['path']).resolve()
            assert path.is_relative_to(ROOT.resolve()) and path.exists()
            assert path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
            screenshots+=1
    for status in ['passed','failed','blocked']:
        assert data[status]==sum(case['status']==status for case in data['cases'])
    assert 'accessToken' not in args.report.read_text(encoding='utf-8')
    assert not re.search(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',args.report.read_text(encoding='utf-8')), 'JWT leaked into report'
    for source in data.get('test_source_snapshot',[]):
        path=(args.report.parent/'test-sources'/source['path']).resolve()
        assert path.is_relative_to((args.report.parent/'test-sources').resolve())
        assert hashlib.sha256(path.read_bytes()).hexdigest()==source['sha256'], 'Executed source snapshot hash mismatch'
    print(f"Verified {len(selected)} selected case records and {screenshots} PNG files; full scenario coverage is not implied.")

if __name__=='__main__': main()
