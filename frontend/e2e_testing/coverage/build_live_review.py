"""Produce an honest scenario ledger from the supplied checklist and fresh runs.

Passing child cases never complete a master card automatically. Reused/smoke
results are deliberately not accepted. Raw attempts remain available unchanged.
"""
import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

GAPS={
 'AUTH':'New-account verification and manual mailbox; valid/expired/replayed reset links; OAuth; lock/role changes; full field/network boundaries.',
 'U-ACCOUNT':'Valid avatar replacement/restore; password change, revoke current/logout others; actual download deletion and entitlement. Local preferences are not download evidence.',
 'U-CHANNEL':'Channel creation/duplicate handle; valid branding plus MIME/size boundaries; link ordering; invitation role matrix; restricted/deleted secondary channel.',
 'U-DISCOVERY':'Home recommendation fallback/privacy; Explore categories; carousel boundaries; concurrent search stale-response handling.',
 'U-SUBSCRIPTION':'Ordinary Member privacy matrix, cross-account subscription visibility, complete pagination and error states.',
 'U-PLAYLIST':'Watch picker/duplicate additions; playback shuffle/next/onEnded; tombstones; pagination and duplicate/double-click creation.',
 'U-LIBRARY':'Watch-time checkpoints/resume/no double count; search/order/pagination; hidden/deleted source privacy.',
 'U-POLICY':'Publish a new version and verify User UI; detail/search and real PDF output; all support links/focus targets.',
 'U-PLAN':'Sandbox payment ID/webhook idempotency and expiry/cancel/failure; quota allocation/invites; downgrade/expiry enforcement.',
 'U-STUDIO':'All wizard fields/boundaries and drafts/chunk recovery; cancellation/network/quota failures; captions/settings/invitation permission matrix; complete comment moderation.',
 'U-WATCH':'All quality/chapter/fullscreen/PiP/download entitlements; resume/onEnded; reply/edit/report/pagination; complete video-state and ordinary Member matrix.',
 'A-ACCOUNT':'Profile/password/current-session and logout-others mutations; permission/error cases.',
 'A-USERS':'Actual role/lock mutations on disposable actors and User refresh; custom statistics range; all missing/error/stale drawer states.',
 'A-CHANNELS':'Secondary-channel ban/suspend/delete/restore and User enforcement; all sort/page boundaries.',
 'A-VIDEOS':'Category/all page-size/custom-date matrix, stale details, purged restore and missing-permission cases.',
 'A-RBAC':'Permission assignment and independent Member re-login; system/in-use constraints, duplicate codes and self-elevation denial.',
 'A-PLANS':'All numeric boundaries/features/templates and User entitlement; no live payment is performed.',
 'A-TOPICS':'Duplicate/boundary/in-use constraints and missing permissions; complete search/filter matrix.',
 'A-POLICY':'Draft/version CRUD/publish and immutable published records; User UI updates and moderation policy-version snapshots.',
 'A-MODERATION':'Reject/escalate and reason/policy boundaries; two-reviewer claim conflict/SoD; reports/appeals/strikes mutations and effective state; manual notification evidence.',
 'A-RECOMMENDATION':'Recommendation service unavailable: training/stop/config/job concurrency and real model behavior are not executed.',
 'X':'Independent ordinary Member/Reviewer actors, revoked permissions, missing IDs/network errors, realtime notifications, keyboard/theme/language/performance matrices.'
}

def requirements(path):
    rows={}
    in_cards=False
    for number,line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(),1):
        if re.match(r'^## 5\. ',line):in_cards=True
        # Earlier mail-checklist rows repeat master IDs but only describe mail
        # triggers. Keep the actual scenario cards and their full requirements.
        if not in_cards:continue
        if not line.startswith('|'): continue
        cells=[cell.strip() for cell in line.strip('|').split('|')]
        position=next((i for i,v in enumerate(cells) if re.fullmatch(r'(?:AUTH-(?:REG|LOGIN|VERIFY|ADMIN|EXT)-\d+|[UA]-[A-Z]+\.\d+|X-[A-Z]+\.\d+)',v)),None)
        if position is None: continue
        scenario=cells[position]
        if scenario in rows: continue
        rows[scenario]={'id':scenario,'source_line':number,'source':path.name,'requirement':' | '.join(cells[position+1:position+3]),'source_history':' | '.join(cells[position+3:]),'status':'PLANNED','evidence':[]}
    return rows

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenarios',type=Path,required=True)
    parser.add_argument('--run',type=Path,action='append',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    rows=requirements(args.scenarios)
    latest={}
    runs=[]
    for root in sorted(args.run):
        report=json.loads((root/'report.json').read_text(encoding='utf-8'))
        assert report['suite']=='web-live-functional'
        assert report.get('finished_at'), 'Only completed runs may enter final review'
        runs.append({'run_id':report['run_id'],'report':(root/'report.json').resolve().as_posix(),'cleanup':report['cleanup'],'run_error':report.get('run_error')})
        for case in report['cases']:
            value=dict(case)
            if case['id'].startswith('U-DISCOVERY-SEARCH-'):
                value['original_parent']=value['parent']; value['parent']='U-DISCOVERY.02'
            elif case['id'].startswith('U-STUDIO-LIVE-EDIT-'):
                value['original_parent']=value['parent']; value['parent']='U-STUDIO.05'
            elif case['id'].startswith('LIVE-U-WATCH-') or case['id']=='LIVE-X-COMMENT-ACCESS-01':
                value['original_parent']=value['parent']
                value['parent']='U-WATCH.04' if 'COMMENT' in case['id'] else 'U-WATCH.05' if 'PRIVATE' in case['id'] else 'U-WATCH.01' if 'PLAYBACK' in case['id'] else 'U-WATCH.03'
            assert value['status']!='reused'
            events=[event for event in report['http_statuses'] if event.get('case')==case['id']]
            value['api_evidence']=events
            if case['status']=='failed' and (any(event['status']==429 for event in events) or any(message in case.get('actual','') for message in ['ECONNRESET','ECONNREFUSED','ERR_CONNECTION_REFUSED'])):
                value['review_status']='BLOCKED_ENV'
                value['review_note']='Rate limit or service connection failure occurred in this attempt. Preserve raw failure; requires a fresh rerun after environment recovers.'
            else:
                value['review_status']=case['status'].upper()
            related={
                'USER-AUTH-REQUIRED':['AUTH-LOGIN-02'],
                'LIVE-AUTH-SESSION-USER':['AUTH-LOGIN-05'],
                'LIVE-U-STUDIO-UPLOAD-01':['U-STUDIO.01','U-STUDIO.02'],
                'LIVE-SESSION-REVOKE-USER':['AUTH-EXT-04'],
                'LIVE-SESSION-REVOKE-ADMIN':['AUTH-EXT-04'],
                'LIVE-A-RBAC-EDIT-01':['A-RBAC.02'],
                'LIVE-ADMIN-UPLOAD-U-STUDIO-UPLOAD-01':['U-STUDIO.01','U-STUDIO.02'],
                'LIVE-ADMIN-UPLOAD-U-WATCH-PLAYBACK-01':['U-WATCH.01'],
                'LIVE-ADMIN-UPLOAD-U-WATCH-PRIVATE-01':['U-WATCH.05']
            }
            value['secondary_parents']=related.get(case['id'],[])
            latest[case['id']]=value
    for case in latest.values():
        for parent in dict.fromkeys([case['parent'],*case.get('secondary_parents',[])]):
            row=rows.get(parent)
            if row: row['evidence'].append(case['id'])
    excluded={'A-CF.01','A-CF.02','A-RECOMMENDATION.03'}
    for scenario,row in rows.items():
        statuses=[latest[key]['review_status'] for key in row['evidence']]
        if scenario in excluded:
            row['status']='OUT_OF_SCOPE'
        elif 'FAILED' in statuses:
            row['status']='FAIL'
        elif 'PASSED' in statuses:
            row['status']='PARTIAL'
        elif statuses:
            row['status']='BLOCKED'
        elif scenario in {'U-PLAN.02','U-PLAN.04','AUTH-EXT-05','A-RECOMMENDATION.01'}:
            row['status']='BLOCKED'
        family=scenario.split('.')[0] if not scenario.startswith('AUTH-') else 'AUTH'
        if family.startswith('X-'): family='X'
        row['remaining']='Excluded by agreed scope.' if scenario in excluded else GAPS.get(family,'Required branches listed in this master card have not all been implemented/executed.')
        if not row['evidence'] and scenario not in excluded:
            row['remaining']='No executed child case for this master. '+row['remaining']
    inventory=json.loads((ROOT/'coverage/web-inventory.json').read_text(encoding='utf-8'))
    counts={key:len(inventory[key]) for key in ['routes','bindings','navigation','form_controls']}
    data={'release_gate':'NOT_COMPLETE','scope':'Live functional assertions against requested 4200/4201 using two supplied identities','scenario_source':args.scenarios.name,'inventory':counts,'runs':runs,'cases':list(latest.values()),'case_counts':dict(Counter(case['review_status'] for case in latest.values())),'parents':list(rows.values()),'parent_counts':dict(Counter(row['status'] for row in rows.values())),'notes':['Latest completed execution per ID; no best-of selection','Every passed case has functional assertions and three viewport evidence','No parent is marked PASS solely from child results','No mailbox access, independent Member/Reviewer identities or payment sandbox were supplied','Recommendation localhost:8000 health was unreachable; model training/stop not executed','Historical route smoke and REUSED counts are excluded']}
    args.output.mkdir(parents=True,exist_ok=True)
    data['inventory_basis']='Stored coverage/web-inventory.json snapshot; counts are not reconciled coverage and must be regenerated before claiming current source totals.'
    (args.output/'review.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# HuTube live E2E review','', '**Release gate: NOT COMPLETE.** Không xác nhận issue #34 đã hoàn tất toàn bộ checklist.','', '## Kết quả ca chức năng','',str(data['case_counts']),'', '## Checklist tổng','',str(data['parent_counts']),'', '## Inventory snapshot chưa reconcile','',str(counts),'',data['inventory_basis'],'', '## Ca lỗi hoặc bị chặn','', '| Case | Status | Observed | Evidence |','| --- | --- | --- | --- |']
    for case in latest.values():
        if case['review_status']=='PASSED': continue
        shots=case['screenshots']
        path='[Screenshot](<'+(ROOT/shots[0]['path']).resolve().as_posix()+'>)' if shots else 'N/A'
        observed=case.get('actual','').replace('\n',' ').replace('|','/').replace('`','')[:400]
        lines.append(f"| {case['id']} | {case['review_status']} | {observed} | {path} |")
    lines.extend(['','## Phạm vi chưa hoàn tất','','| Parent | Status | Cases | Requirement |','| --- | --- | --- | --- |'])
    for row in rows.values():
        lines.append(f"| {row['id']} | {row['status']} | {', '.join(row['evidence'])} | {row['requirement'].replace('|','/')} |")
    lines.extend(['','## Evidence và cleanup',''])
    for run in runs:
        lines.append(f"- `{run['run_id']}`: {run['report']}; run_error={run['run_error'] or 'none'}; cleanup={json.dumps(run['cleanup'],ensure_ascii=False)}")
    (args.output/'REVIEW.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    defect_groups=[
        ('QC-01','P2','Search filter state resets after reload',[k for k in latest if k.startswith(('U-DISCOVERY-SORT-','U-DISCOVERY-DURATION-','U-DISCOVERY-DATERANGE-'))],
         'User /search?q=music → choose a non-default sort/duration/date → confirm URL and API query → reload. The selected dropdown and result must retain that URL state.'),
        ('QC-02','P1','Admin Add Video reports success without creating a record',['A-VIDEOS-ADD-PERSISTENCE'],
         'Admin /videos → Add Video → enter unique fixture title/private visibility → submit → search/reload and compare the actual API dataset. Success requires a persisted video ID and create request.'),
        ('QC-03','P3','Admin empty video result says 1–0',['A-VIDEOS-SEARCH-EMPTY'],
         'Admin /videos → search an absent unique title → API total=0 and no rows. Footer must display a valid zero range.'),
        ('QC-04','P3','Admin Strikes header overflows mobile',['LIVE-MODERATION-STRIKES-LIST-ENUMS'],
         'Admin /moderation/strikes → viewport 390×844 → test each status. Document scrollWidth=397 and the refresh action exceeds the viewport.'),
        ('QC-05','P3','Moderation review dialog clips horizontally on mobile',['LIVE-MODERATION-CLAIM-RELEASE-APPROVE'],
         'Claim the fresh fixture → open review → viewport 390×844. Dialog bounds must stay inside the viewport; recorded right bound=392.390625.'),
        ('QC-06','P1','Processed moderation approval can execute again',['LIVE-MODERATION-PROCESSED-REPLAY'],
         'Approve the newly uploaded fixture → replay resolve(approve) for the exact processed case ID. Require conflict/validation rejection and no repeated resolution/notification.'),
        ('QC-07','P2','Studio saved preferences disagree with rendered language/theme',['LIVE-STUDIO-LANGUAGE-EN','LIVE-STUDIO-LANGUAGE-VI','LIVE-STUDIO-THEME-DARK','LIVE-STUDIO-THEME-LIGHT','LIVE-STUDIO-THEME-RAPID-LOAD'],
         'Studio settings → select language/theme → actual PUT succeeds and GET confirms the chosen value. Rendered heading/root theme must agree after requests settle. A stale initial preference response is a suspected cause, not a proven root cause.')
    ]
    bugs=['# Defect register — latest live evidence','','Only failed assertions reproduced by the listed live cases are included. No issue has been published externally.','']
    assigned=set()
    for key,priority,title,ids,reproduction in defect_groups:
        failed=[latest[k] for k in ids if k in latest and latest[k]['review_status']=='FAILED']
        if not failed:continue
        assigned.update(c['id'] for c in failed)
        bugs.extend([f'## {key} [{priority}] {title}','',reproduction,''])
        for case in failed:
            bugs.append(f"- Case `{case['id']}`, run `{case['run_id']}`: {case['actual'].replace(chr(10),' ')[:650]}")
            for shot in case['screenshots']:
                if shot['viewport']=='mobile' or len(failed)==1:
                    bugs.append(f"  [{shot['viewport']} / {shot['step']}](<{(ROOT/shot['path']).resolve().as_posix()}>)")
        bugs.append('')
    other=[c for c in latest.values() if c['review_status']=='FAILED' and c['id'] not in assigned]
    if other:
        bugs.extend(['## Assertions requiring investigation','','These are not automatically classified as product defects.',''])
        bugs.extend(f"- `{c['id']}`: {c['actual'].replace(chr(10),' ')[:600]}" for c in other)
    bugs.extend(['','## Environment and coverage limitations','','Native User Web revocation polling calls auth/me every three seconds per active authenticated document. Earlier multi-context runs recorded Auth 429; those attempts remain in raw reports. Service disconnects are also retained. This is not a completed performance/multi-tab certification.','','Mail, OAuth, payment webhook, recommendation jobs and independent ordinary Member/Reviewer matrices are not proven. The inventory ledger deliberately has NOT_RECONCILED rows; source counts are not coverage.'])
    (args.output/'DEFECTS.md').write_text('\n'.join(bugs)+'\n',encoding='utf-8')
    print(data['case_counts'],data['parent_counts'],counts)

if __name__=='__main__': main()
