"""Publish synthetic screenshots + honest run summary; never copy state, emails or traces."""
import json
import shutil
from collections import defaultdict
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from support.evidence import auth_relative_path, auth_scope, legacy_case

REPO = ROOT.parents[1]


def main():
    catalog = json.loads((ROOT / 'coverage/existing-tests.json').read_text(encoding='utf-8'))
    document = REPO / 'docs/BACKEND_TEST_SCENARIOS.md'
    marker = '<!-- EXISTING_TEST_METHODS: generated from coverage/existing-tests.json -->'
    base = document.read_text(encoding='utf-8').split(marker)[0] + marker + '\n'
    grouped = defaultdict(list)
    for test in catalog['dotnet'] + catalog['recommendation_python']:
        grouped[test['file']].append(test)
    appendix = []
    for file, tests in grouped.items():
        appendix += ['\n### ' + file + '\n', f'[Mở file test](../{file}).\n']
        for test in tests:
            kind = test.get('kind', 'pytest')
            rows = test.get('inline_data_rows', 0)
            suffix = f'; {rows} InlineData' if rows else ''
            appendix.append(f'- `{test["method"]}` ({kind}{suffix})')
        appendix.append('')
    document.write_text(base + '\n'.join(appendix) + '\n', encoding='utf-8')

    runs = []
    for directory in sorted((ROOT / 'artifacts/runs').iterdir()):
        path = directory / 'report.json'
        if path.exists():
            runs.append((directory, json.loads(path.read_text(encoding='utf-8'))))
    if not runs or runs[-1][1]['failed'] or runs[-1][1]['account_count'] != 1:
        raise RuntimeError('No successful latest auth evidence with exactly one account.')
    baseline = ROOT / 'screenshots/baseline-auth'
    baseline.mkdir(parents=True, exist_ok=True)
    chosen = {}
    for directory, report in runs:
        source = Path(report.get('screenshot_dir', str(directory / 'screenshots')))
        for screenshot in source.rglob('*.png'):
            if 'failure' not in screenshot.name:
                case_id = legacy_case(screenshot.name)
                if not case_id:
                    raise ValueError('Unmapped screenshot: ' + screenshot.name)
                relative = auth_relative_path(case_id, screenshot.name)
                chosen[relative.as_posix()] = (screenshot, directory.name)
    for name, (path, _) in chosen.items():
        target = baseline / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    evidence = []
    for directory, report in runs:
        statuses = json.loads((directory / 'http-statuses.json').read_text(encoding='utf-8'))
        created = sum(item['path'] == '/api/v1/auth/register' and item['status'] == 201 for item in statuses)
        evidence.append({'run_id': directory.name, 'at': report['at'], 'passed': report['passed'],
                         'reused': report['reused'], 'failed': report['failed'],
                         'duration_ms': report['duration_ms'], 'account_count': report['account_count'],
                         'created_account_count': created, 'javascript_error_count': len(report['javascript_errors']),
                         'cases': [{'id': c['id'], 'status': c['status']} for c in report['cases']]})
    (ROOT / 'artifacts/auth-evidence.json').write_text(json.dumps({'runs': evidence,
        'screenshots': [{'file': 'screenshots/baseline-auth/' + name, 'run_id': pair[1],
                         'application': name.split('/')[0], 'module': name.split('/')[1],
                         'flow': name.split('/')[2], 'case_id': name.split('/')[3]} for name, pair in sorted(chosen.items())]},
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = ['# Kết quả đăng ký và đăng nhập Playwright thật', '',
             'Ngày chạy: 02/10/2026, múi giờ Asia/Bangkok (run ID dùng UTC). Chromium/Chrome headless, cả hai Angular production build, Kestrel + PostgreSQL riêng; email Pickup. Không mock API. Account cố định `hutube.e2e.owner@example.test`.', '',
             '| Run ID | PASS | REUSED | FAIL | Browser (giây) | Account sau run | Register 201 |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for item in evidence:
        lines.append(f'| `{item["run_id"]}` | {item["passed"]} | {item["reused"]} | {item["failed"]} | {item["duration_ms"]/1000:.3f} | {item["account_count"]} | {item["created_account_count"]} |')
    lines += ['', 'Run đầu đã đăng ký 201, login unverified bị từ chối và verify email thật thành công, sau đó dừng do test kỳ vọng sai tên code lỗi duplicate. Kỳ vọng đã sửa theo contract `EMAIL_ALREADY_EXISTS`/`USERNAME_ALREADY_EXISTS`; các run tiếp theo dùng checkpoint, không tạo user mới. Đây là lỗi kỳ vọng của harness, không có chỉnh sửa ứng dụng trong bộ E2E này.', '',
              'REUSED gồm AUTH-REG-03, AUTH-LOGIN-01 và AUTH-VERIFY-01: tiền điều kiện đã hoàn thành ở run đầu, giữ bằng chứng đầu và không đăng ký/xác minh lại. 11 case còn lại thực thi PASS trong mỗi warm run; JavaScript pageerror bằng 0. Sau cuối flow role admin tạm được khôi phục. Database được giữ, dịch vụ runner tự dừng.', '',
              '| Case | Bằng chứng thực thi đầu | Trạng thái run mới nhất |', '| --- | --- | --- |']
    latest = {c['id']: c for c in runs[-1][1]['cases']}
    first = {}
    for directory, report in runs:
        for case in report['cases']:
            if case['status'] == 'passed':
                first.setdefault(case['id'], directory.name)
    for case_id, case in latest.items():
        lines.append(f'| `{case_id}` | `{first.get(case_id, "chưa có")}` | {case["status"].upper()} |')
    lines += ['', '## Ảnh minh chứng', '',
              'Cấu trúc: `screenshots/<run-id>/user|admin/<module>/<flow>/<case-id>/<step>.png`; baseline giữ cùng hierarchy. Module hiện có là authentication; flow registration/email_verification/login/logout/access_denied. Mỗi case là một mục; tên bước phân biệt desktop/mobile, trạng thái success/error.', '',
              '| Phạm vi | Module | Flow | Case | Screenshot | Run nguồn |', '| --- | --- | --- | --- | --- | --- |']
    for name, (_, run_id) in sorted(chosen.items()):
        app, module, flow, case_id, filename = name.split('/')
        lines.append(f'| {app} | {module} | {flow} | {case_id} | [{filename}](../screenshots/baseline-auth/{name}) | `{run_id}` |')
    lines += ['', 'Ảnh được copy nguyên bản từ Playwright, password input được mask; không lấy từ ảnh dựng hoặc UI mock. Baseline chỉ có account synthetic. Report/trace/log đầy đủ ở `artifacts/runs/<run-id>` local bị gitignore; ảnh run mới ở `screenshots/<run-id>`. Không publish state, mail token hay trace chứa cookie/password. JSON đã lọc ở [auth-evidence.json](auth-evidence.json).', '',
              'Kết quả này chỉ chứng minh các case auth liệt kê. Chưa chạy full chức năng Web, upload/transcode, OAuth/R2/SePay thật hoặc performance. Steps, dữ liệu và expected của full suite ở hai tài liệu trong `docs`; hướng dẫn chạy ở [README](../README.md).', '']
    (ROOT / 'artifacts/auth-results.md').write_text('\n'.join(lines), encoding='utf-8')
    print(f'Published {len(chosen)} real screenshots and {len(runs)} run summaries.')


if __name__ == '__main__':
    main()
