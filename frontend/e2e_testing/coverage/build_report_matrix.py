"""Audit recorded E2E outcomes against the supported report target matrix."""
import argparse
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
PRIVILEGED={'upload_restriction','strike','lock_channel'}
EXPECTED={
    'video':['dismiss','warn','age_restrict','recommendation_restricted','hide','remove','upload_restriction','strike','lock_channel','escalate'],
    'channel':['dismiss','warn','hide','remove','upload_restriction','strike','lock_channel','escalate'],
    'comment':['dismiss','warn','hide','remove','escalate'],
}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='append',required=True)
    args=parser.parse_args();latest={};sources=[]
    for rid in sorted(set(args.run)):
        path=ROOT/'artifacts/runs'/rid/'report.json'
        report=json.loads(path.read_text(encoding='utf-8'))
        assert report.get('finished_at'),'Refuse an unfinished run: '+rid
        device=report['action_device']['name']
        sources.append({'run_id':rid,'device':device,'report':path.resolve().as_posix()})
        for c in report['cases']:
            latest[(device,c.get('logical_id',c['id']))]=(c,path)
    rows=[]
    for device in ['mobile','tablet']:
        for target,decisions in EXPECTED.items():
            for decision in decisions:
                case_id='FULL-REPORT-'+('' if target=='video' and decision not in PRIVILEGED else target.upper()+'-')+'DECISION-'+decision.upper()
                found=latest.get((device,case_id))
                row={'device':device,'target':target,'decision':decision,'case_id':case_id,'status':'not_executed'}
                if found:
                    c,path=found
                    row.update(status=c['status'],run_id=c['run_id'],resource_ids=c['resource_ids'],
                        raw_report=path.resolve().as_posix(),steps=c['steps'],screenshots=c['screenshots'])
                rows.append(row)
    data={'basis':['WEB_TEST_SCENARIOS.md: A-MODERATION.03','Supported target/decision contract in ReportService.IsDecisionSupportedForTarget'],
        'scope':'23 supported target/decision combinations per action device; ordinary flow and privileged permission paths. Does not certify every master clause, audit/notification/fault branch or physical device.',
        'sources':sources,'matrix':rows,
        'counts':{d:{s:sum(r['device']==d and r['status']==s for r in rows) for s in ['passed','failed','blocked','not_executed']} for d in ['mobile','tablet']},
        'all_selected_combinations_passed':all(r['status']=='passed' for r in rows)}
    output=REPO/'outputs/20261015-remaining-completion/report-target-matrix-20261016.json'
    output.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(data['counts']))


if __name__=='__main__':main()
