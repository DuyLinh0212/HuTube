"""Validate a Web run's result counts, app separation and PNG evidence."""
import argparse
import json
from pathlib import Path


def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',type=Path)
    args=parser.parse_args()
    run=args.run or Path(json.loads((root/'artifacts/web-latest.json').read_text(encoding='utf-8'))['run_dir'])
    report=json.loads((run/'report.json').read_text(encoding='utf-8'))
    assert report['suite']=='web', 'Expected Web suite report'
    assert not report.get('run_error'), 'Suite setup or execution incomplete: ' + str(report.get('run_error'))
    assert report['cases'], 'No Web cases executed'
    assert not report['page_errors'], 'JavaScript page errors recorded'
    identifiers=[(case['application'],case['id']) for case in report['cases']]
    assert len(identifiers)==len(set(identifiers)), 'Duplicate case identifiers'
    for status in ('passed','failed','blocked','reused'):
        assert report[status]==sum(case['status']==status for case in report['cases'])
    for application in ('user','admin'):
        split=json.loads((run/(application+'-report.json')).read_text(encoding='utf-8'))
        assert split['cases']==[case for case in report['cases'] if case['application']==application]
    for case in report['cases']:
        assert case['status'] in ('passed','failed','blocked','reused')
        path=(root/case['screenshot']).resolve()
        assert path.is_relative_to((root/'screenshots'/report['run_id']).resolve())
        assert path.read_bytes()[:8]==b'\x89PNG\r\n\x1a\n'
        assert path.parts[-4:-1]==(case['module'],'functional',case['id'])
        first=case.get('first_passed_evidence')
        if first:
            original=(root/first['screenshot']).resolve()
            assert original.is_relative_to((root/'screenshots').resolve())
            assert original.read_bytes()[:8]==b'\x89PNG\r\n\x1a\n'
    print(f"Web evidence verified: {len(report['cases'])} cases; {report['passed']} passed, {report['failed']} failed, {report['blocked']} blocked, {report['reused']} reused.")
    print('This verifies executed evidence, not full scenario/binding coverage.')


if __name__=='__main__':
    main()
