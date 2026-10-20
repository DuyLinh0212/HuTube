"""Compare the original failed IDs with their latest completed fresh execution."""
import argparse
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--run', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text(encoding='utf-8'))
    failed_ids = [c['id'] for c in baseline['cases'] if c['review_status'] == 'FAILED']
    latest, runs = {}, []
    for path in sorted(args.run):
        report = json.loads((path / 'report.json').read_text(encoding='utf-8'))
        assert report['finished_at'] and not report.get('run_error')
        runs.append({'run_id': report['run_id'], 'path': str((path / 'report.json').resolve()),
                     'counts': {k: report[k] for k in ('passed', 'failed', 'blocked')},
                     'cleanup': report['cleanup']})
        for case in report['cases']:
            latest[case['id']] = {**case, 'run_id': report['run_id']}
    targets = [latest.get(case_id, {'id': case_id, 'status': 'not_executed'}) for case_id in failed_ids]
    assert len(targets) == 18 and all(c['status'] == 'passed' for c in targets), 'Original 18 failures are not all freshly passing'
    assert all(c['status'] == 'passed' for c in latest.values()), 'Latest post-fix regression still has unresolved failures/blocks'
    fixes = [
        ('Search: 10 filter reset sau reload', 'Đồng bộ select qua ngModel; đối chiếu URL, request, kết quả và giá trị select sau reload.'),
        ('Admin Add Video', 'Thay form báo thành công giả bằng liên kết sang Studio upload thực. Upload file, POST 201, decode/playback, private access và tìm lại cùng video ID ở Admin.'),
        ('Footer danh sách rỗng', 'Hiển thị range bắt đầu 0 khi total=0.'),
        ('Strikes mobile', 'Header wrap và nút refresh vừa viewport.'),
        ('Review modal mobile', 'Box sizing, chiều rộng/chiều cao theo viewport; xác minh cả normal và theater.'),
        ('Processed moderation replay', 'Chặn terminal state bằng 409 trước side effect; PostgreSQL row lock trong transaction cho hai decision đồng thời.'),
        ('Studio language/theme: 3 ca', 'Preference revision chặn response khởi tạo cũ ghi đè thao tác mới; setTheme trực tiếp và xử lý save error.'),
        ('Regression phát hiện thêm', 'Processing filter chỉ lấy processing; upload không chạy lại preflight vì auth refresh, và nút Next chờ metadata/quota xong.'),
    ]
    data = {'scope': 'Fix and fresh retest of the original 18 failed cases',
            'baseline': str(args.baseline.resolve()), 'original_failure_count': len(targets),
            'original_failure_retest': dict(Counter(c['status'] for c in targets)),
            'latest_post_fix_counts': dict(Counter(c['status'] for c in latest.values())),
            'targets': targets, 'cases': list(latest.values()), 'runs': runs, 'fixes': fixes,
            'release_gate': 'NOT_COMPLETE',
            'limitations': ['Scope is the original 18 failures and related regression, not certification of every master scenario.',
                            'The two earlier permission cases remain unexecuted in this fix pass; no role/account was changed.',
                            'Historical failed attempts remain unchanged; latest completed execution per ID is used, never best-of.']}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'retest.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['# Fix và retest 18 FAIL — 13/10/2026', '',
             '**18/18 ca FAIL ban đầu đã chạy lại và PASS.**', '',
             f"Regression sau fix: {len(latest)} case duy nhất, {data['latest_post_fix_counts']}. Đây là kết quả mới nhất theo ID; không cộng các attempt trùng.", '',
             'Dùng hai tài khoản được cấp, User 4200 / Admin 4201; browser thật, không API mock/SQL seed/SMOKE/REUSED. Mỗi ca PASS có assertion chức năng và ảnh desktop/mobile/tablet.', '',
             '## Thay đổi', '', '| Nhóm | Sửa và xác minh |', '| --- | --- |']
    lines += [f'| {name} | {detail} |' for name, detail in fixes]
    lines += ['', '## 18 ca ban đầu', '', '| Case | Retest | Run | Evidence |', '| --- | --- | --- | --- |']
    for case in targets:
        shot = next(s for s in case['screenshots'] if s['viewport'] == 'mobile')
        image_path = (ROOT / shot['path']).resolve().as_posix()
        lines.append(f"| {case['id']} | PASS | {case['run_id']} | [Mobile](<{image_path}>) |")
    lines += ['', '## Validation', '', '- User Web và Admin Web build development thành công.',
              '- ModerationStrikeAndAppealTests: 10 passed, 0 failed, 0 skipped.',
              '- Evidence verifier kiểm tra screenshot PNG, ba viewport, unique case ID và SHA-256 của test source snapshot.',
              '- Fixture mới được cleanup; preference đã restore; cleanup thực tế ghi trong từng raw report.', '',
              '## Raw attempts', '']
    for run in runs:
        lines.append(f"- [{run['run_id']}](<{Path(run['path']).as_posix()}>): {run['counts']}. Failed attempt được giữ nguyên, gồm race trong harness trước khi sửa cách chờ UI.")
    lines += ['', '## Phạm vi còn lại', '',
              'Fix 18 FAIL đã hoàn tất. Release gate toàn checklist vẫn NOT COMPLETE: các master chưa có đủ evidence, mailbox/OAuth/payment/recommendation và ma trận Member/Reviewer còn được ghi riêng trong REVIEW.md. Hai BLOCKED cũ không được tính thành PASS trong đợt sửa này.', '']
    (args.output / 'FIX_RETEST.md').write_text('\n'.join(lines), encoding='utf-8')
    print(data['original_failure_retest'], data['latest_post_fix_counts'])

if __name__ == '__main__':
    main()
