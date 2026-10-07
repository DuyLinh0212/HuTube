"""Publish execution progress without equating case counts to binding coverage."""
import argparse
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path)
    args = parser.parse_args()
    run = args.run or Path(json.loads((ROOT / 'artifacts/web-latest.json').read_text(encoding='utf-8'))['run_dir'])
    report = json.loads((run / 'report.json').read_text(encoding='utf-8'))
    inventory = json.loads((ROOT / 'coverage/web-inventory.json').read_text(encoding='utf-8'))
    counts = Counter(case['status'] for case in report['cases'])
    smoke = sum('-SMOKE-' in case['id'] for case in report['cases'])
    scope = {
        'run_id': report['run_id'], 'complete_issue_34': False,
        'executed_cases': len(report['cases']), 'statuses': dict(counts),
        'route_smoke_cases': smoke, 'other_cases': len(report['cases']) - smoke,
        'source_inventory_counts': {key: len(inventory[key]) for key in ('routes', 'bindings', 'navigation', 'form_controls')},
        'exclusions': [{'scope': 'CF Seeder', 'reason': 'User explicitly excluded on 2026-10-07'},
                       {'scope': 'Simulation', 'reason': 'User explicitly excluded on 2026-10-07'}],
        'remaining': [
            {'scope': 'Recommendation jobs/matrix/model configuration', 'status': 'BLOCKED', 'reason': 'Isolated runner disables recommendation; no dedicated service/model/R2 test configuration supplied'},
            {'scope': 'Payment webhook and download/entitlement', 'status': 'BLOCKED', 'reason': 'No dedicated payment sandbox/webhook configuration supplied'},
            {'scope': 'Public policy UI current version', 'status': 'PLANNED', 'reason': 'API synchronization asserted; User activeList uses static rules instead of policies signal'},
            {'scope': 'Discovery/library filters and pagination; playlist multi-item ordering', 'status': 'PLANNED'},
            {'scope': 'Complete channel role matrix, branding MIME/size boundaries, channel restrictions/delete', 'status': 'PLANNED'},
            {'scope': 'Large video/chunk/recovery; Studio metadata/captions/settings; watch reply/report flows', 'status': 'PLANNED'},
            {'scope': 'Admin videos mutation/CSV; users role assignment/statistics; RBAC constraints', 'status': 'PLANNED'},
            {'scope': 'Reports/appeals/strikes; reviewer conflict and separation of duties', 'status': 'PLANNED'},
            {'scope': 'Realtime notifications/session operations; full keyboard/responsive/theme/language and performance', 'status': 'PLANNED'},
            {'scope': 'Binding/endpoint variant reconciliation and GitHub CI execution', 'status': 'PLANNED'},
        ],
    }
    (run / 'scope-progress.json').write_text(json.dumps(scope, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['# Tiến độ Web E2E issue #34', '', f"Run: `{report['run_id']}`.", '',
             f"{len(report['cases'])} case: {counts['passed']} PASS, {counts['failed']} FAIL, {counts['blocked']} BLOCKED, {counts['reused']} REUSED.", '',
             f'{smoke} case SMOKE chỉ kiểm tra route. REUSED không được cộng vào PASS của thao tác tạo mới.', '',
             'CF Seeder và simulation được loại khỏi phạm vi theo yêu cầu người dùng ngày 07/10/2026.', '',
             'Chưa hoàn tất toàn bộ issue. Inventory là nghĩa vụ rà soát source, không phải số binding đã cover:', '',
             '| Inventory | Số lượng |', '| --- | ---: |']
    lines += [f'| {key} | {value} |' for key, value in scope['source_inventory_counts'].items()]
    lines += ['', '## Phạm vi còn lại', '', '| Phạm vi | Trạng thái | Ghi chú |', '| --- | --- | --- |']
    lines += [f"| {item['scope']} | {item['status']} | {item.get('reason', 'Chưa có đủ assertion và evidence cho toàn bộ nhánh')} |" for item in scope['remaining']]
    lines += ['', '## Case đã chạy', '', '| App | ID | Kết quả | Scenario |', '| --- | --- | --- | --- |']
    lines += [f"| {case['application']} | {case['id']} | {case['status'].upper()} | {case['name'].replace('|', '/')} |" for case in report['cases']]
    (REPO / 'docs/WEB_E2E_PROGRESS.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('Execution progress exported; full issue coverage remains incomplete.')


if __name__ == '__main__':
    main()
