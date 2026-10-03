# HuTube E2E: Python Playwright và screenshot

Luồng browser E2E được duy trì trong thư mục này. CI gọi `run_local.py` để kiểm tra đăng ký, xác minh email và đăng nhập/đăng xuất trên UI thật của User và Admin, cùng API và PostgreSQL local riêng. Runner tự build và khởi động dịch vụ, dùng account test synthetic và checkpoint khi chạy local.

Screenshot nằm ở `screenshots/<run-id>/user|admin/...`; report JSON nằm ở `artifacts/runs/<run-id>/report.json`. Workflow GitHub Actions upload report và screenshot đã tạo thành artifact `hutube-e2e-evidence-*`, kể cả khi suite thất bại. Trace không được upload vì có thể chứa cookie/token; nếu suite dừng trước khi sinh bằng chứng thì bước upload cảnh báo và không làm job thất bại thêm.

- [Kịch bản toàn Web](../../docs/WEB_TEST_SCENARIOS.md).
- [Kịch bản backend, test hiện có và performance](../../docs/BACKEND_TEST_SCENARIOS.md).
- [Kết quả đã chạy và ảnh minh chứng](artifacts/auth-results.md).

## Cấu trúc

```text
e2e_testing/
  run_local.py                 # build, migrate, startup/cleanup server; lock môi trường
  config.example.json          # cổng localhost và account synthetic cố định
  requirements.txt             # Python Playwright pin version
  tests/auth.py                # 14 case auth, real UI + API/database assertions
  support/                    # checkpoint, OS lock, SQL fixture, SPA server
  screenshots/<run-id>/       # user|admin/module/flow/case-id/step.png (local)
  screenshots/baseline-auth/   # cùng hierarchy, bộ ảnh minh chứng đã chọn
  artifacts/runs/<run-id>/     # report, logs, OpenAPI, trace (local, gitignore)
  artifacts/auth-results.md    # báo cáo kiểm chứng không chứa token
  artifacts/latest.json        # trỏ run mới nhất (local, gitignore)
  coverage/                   # inventory route/binding/API/test method
  fixtures/                   # manifest/schema dữ liệu có ý nghĩa cho full suite
  flows/user/                 # kế hoạch mở rộng flow User
  flows/admin/                # kế hoạch mở rộng flow Admin
  flows/cross_app/             # kế hoạch moderation/payment/membership xuyên app
  performance/                # thiết kế load/soak; chưa có script load
  .state/                     # PostgreSQL persistent, checkpoint, email Pickup
```

`artifacts/runs`, `.state`, runtime config và trace không được commit. `baseline-auth` chỉ giữ ảnh đã kiểm tra với account synthetic, password input bị mask. Ảnh thể hiện timestamp/run gốc trong báo cáo, không dùng baseline làm assertion PASS cho các lần sau.

## Chuẩn bị lần đầu (PowerShell)

Yêu cầu Python 3.12+, .NET SDK 10, Node/npm theo package của hai frontend, PostgreSQL binaries có `initdb`, `pg_ctl`, `psql`. Các cổng 53400, 53401, 53480, 55439 phải trống. Runner chỉ dùng `127.0.0.1`, từ chối gắn vào API/frontend đang chiếm cổng; không đọc connection string hoặc account thật từ `.env.local`.

Chạy các lệnh sau **từ root HuTube**:

```powershell
python -m venv frontend/e2e_testing/.venv
& frontend/e2e_testing/.venv/Scripts/python.exe -m pip install -r frontend/e2e_testing/requirements.txt
& frontend/e2e_testing/.venv/Scripts/python.exe -m playwright install chromium
npm --prefix frontend/user-web ci
npm --prefix frontend/admin-web ci
$env:E2E_POSTGRES_BIN='D:\PostgreSQL\18\bin'
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/run_local.py --help
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/run_local.py
```

Nếu dùng Chrome đã có thay cho browser bundled, đặt `CHROME_BIN`; không cần tải Chromium trong trường hợp này:

```powershell
$env:CHROME_BIN='C:\Program Files\Google\Chrome\Application\chrome.exe'
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/run_local.py
```

Lần kiểm chứng trên máy hiện tại dùng Python có sẵn tại `recommendation-service/.venv/Scripts/python.exe` và Chrome ở đường dẫn trên; README hướng dẫn env riêng để không phụ thuộc env recommendation. PostgreSQL 18 binaries được xác nhận tại `D:\PostgreSQL\18\bin`. Không cần Docker hay SMTP.

## Chạy lại và tái sử dụng tài khoản

```powershell
# Chỉ dùng khi backend và cả hai frontend đã build, source ứng dụng không đổi.
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/run_local.py --reuse-build
```

Không xóa `.state` hoặc đổi email sau mỗi run. Runner giữ cluster/database/account; `checkpoint.json` ghi scope, identity, account, flows và bằng chứng đầu tiên. Database được đối chiếu trước đăng ký; tài khoản đã verified thì REG-03/LOGIN-01/VERIFY-01 ghi `REUSED`. Case đăng ký trùng vẫn gửi một POST **409**, đây không phải account mới. `created_account_count` chỉ đếm response register 201 của run hiện tại, `account_count` phải luôn 1.

Account: `hutube.e2e.owner@example.test`; username `hutube_e2e_owner`; password ban đầu `HuTubeE2e2026!`. Tên: `HuTube — Người sáng tạo nội dung kiểm thử`. Đây là dữ liệu synthetic chỉ trong local. Sau flow đổi password tương lai, mật khẩu checkpoint là giá trị có thẩm quyền, không ghi đè bằng sample config.

Muốn chỉnh cổng/binary/timeouts: copy config, giữ email cố định và gọi `--config`. Runtime config trong `.state` được ghi sau khi lấy OS lock; hai run cùng state không được chạy song song. Scope thay đổi không khớp checkpoint sẽ fail rõ.

```powershell
Copy-Item frontend/e2e_testing/config.example.json frontend/e2e_testing/config.local.json
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/run_local.py --config frontend/e2e_testing/config.local.json
```

Runner tạo database `hutube_e2e_runner` riêng, migrations idempotent, Email Pickup và Storage Local; tắt Google/recommendation/video processing cho scope auth. SPA server trả `config.json` từ bộ nhớ để frontend gọi đúng API local, không sửa source hoặc mock API. Admin auth sử dụng fixture SQL cấp admin tạm cho đúng user này, ghi role gốc trước mutation và restore trong `finally`/lần sau nếu crash. Không coi fixture này là test UI RBAC.

Khi hoàn tất, runner dừng API/SPA/browser và PostgreSQL do nó khởi động; dữ liệu giữ nguyên. Không dừng server ngoài runner. Nếu bị kill cả process, kiểm tra log/port/process runner cũ trước chạy lại; OS lock giải phóng theo process, file `run.lock` còn trên đĩa không phải stale lock. Không xóa checkpoint để khắc phục lỗi login. Cổng bận phải giải quyết process đã xác định, không kill PostgreSQL bất kỳ.

## Các case và giới hạn thời gian

14 case: đăng ký trống, confirm sai, đăng ký thật một lần, login chưa verified, verify Pickup, duplicate; login trống/sai/đúng, restore sau reload, logout/guard; User bị từ chối Admin, Admin login/restore với fixture, Admin logout/guard. Toàn bộ steps/expected có trong tài liệu Web.

Action 15 giây; navigation 45 giây; API/email 30 giây; browser suite 300 giây. Build/migration mỗi command 180 giây và startup mỗi server 120 giây có budget riêng, không nằm trong 300 giây browser. Lần đầu cần build cả hai Angular và backend; các warm run đã đo phần browser khoảng 17–42 giây trên máy này, không cam kết mọi máy cùng tốc độ. Thời gian chính xác mỗi lần ở báo cáo. Không retry đăng ký bằng email mới khi timeout. Bắt response trước submit; chụp sau assertion/DOM ổn định, mask password. Trên player/realtime các flow tương lai dùng trạng thái nghiệp vụ, không chờ `networkidle` vô hạn.

## Xem screenshot, report và trace

```powershell
$latest = Get-Content frontend/e2e_testing/artifacts/latest.json -Raw | ConvertFrom-Json
$report = Get-Content (Join-Path $latest.run_dir 'report.json') -Raw | ConvertFrom-Json
$report | Select-Object passed,reused,failed,account_count,created_account_count,duration_ms
Get-ChildItem -LiteralPath $report.screenshot_dir -Recurse -File
& frontend/e2e_testing/.venv/Scripts/python.exe -m playwright show-trace (Join-Path $latest.run_dir 'user-trace.zip')
```

`report.json` chứa case/status/duration/user_id/counts và từng screenshot kèm application/module/flow/case/step/viewport/path. `http-statuses.json` chỉ ghi path/status, không query/body/token/cookie. Có screenshot lỗi, desktop/mobile registration/account và Admin account. Ảnh cũ đã được chuyển vào hierarchy mới, baseline giữ cả ảnh đăng ký/verify ban đầu.

Cấu trúc phân mục áp dụng cả ảnh PASS và lỗi:

```text
screenshots/<run-id>/
  user/authentication/
    registration/AUTH-REG-03/03-register-filled-desktop.png
    registration/AUTH-REG-03/04-register-filled-mobile.png
    email_verification/AUTH-VERIFY-01/07-email-verification-success.png
    login/AUTH-LOGIN-04/11-user-login-success-desktop.png
    logout/AUTH-LOGIN-06/14-user-logout-guard.png
  admin/authentication/
    access_denied/AUTH-ADMIN-01/15-admin-normal-user-denied.png
    login/AUTH-ADMIN-02/16-admin-login-success-desktop.png
    logout/AUTH-ADMIN-03/18-admin-logout-guard.png
```

Ảnh đăng ký/verify chỉ có trong run đầu, warm run đánh dấu REUSED không dựng lại ảnh thành công; baseline tổng hợp dẫn tới đúng run gốc. Full suite tương lai dùng module `account`, `channel`, `studio`, `watch`, `playlists`, `plans`, `moderation`… và flow tương ứng, vẫn tách app User/Admin; flow xuyên app chụp riêng mỗi app nhưng chung case/resource ID. Không gom mọi chức năng vào authentication hoặc thư mục ảnh phẳng.

Trace ZIP có thể chứa password/token/cookie dù screenshot đã mask; chỉ xem local, không commit/chia sẻ trace chưa lọc. Logs chứa dữ liệu môi trường test, cần xem lại trước chia sẻ. Báo cáo/baseline đã chọn không chứa JWT/verification token/secret production.

## Cập nhật inventory

```powershell
$latest = Get-Content frontend/e2e_testing/artifacts/latest.json -Raw | ConvertFrom-Json
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/coverage/generate_inventory.py --openapi (Join-Path $latest.run_dir 'openapi.json')
& frontend/e2e_testing/.venv/Scripts/python.exe frontend/e2e_testing/coverage/verify_catalog.py
```

Inventory hiện có 69 khai báo route (có alias/redirect/conditional/duplicate), 854 event bindings, 160 navigation references, 263 form controls, 225 operations API và 152 method test .NET +31 Python. Regex không đo branch coverage: vẫn rà guards, dynamic template/service effects và feature flags. Validator kiểm tra nhóm kịch bản, phụ lục method, link và hierarchy bằng chứng; không xác nhận mọi chức năng đã được chạy. Khi triển khai full suite cần mapping case chi tiết và evidence cho từng mục; hiện status còn PLANNED ngoài auth. Không chạy upload file 99 MB hoặc performance trong lệnh auth này.
