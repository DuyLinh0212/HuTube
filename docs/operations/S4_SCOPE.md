# Phạm vi bàn giao S4-01 và S4-02

Ngày: 2026-09-05. Nguồn yêu cầu: `docs/features/Sprint4.md` và chỉ đạo người dùng tạm dùng API/database local vì chưa có Render.

## Phạm vi triển khai

| Slice | Nội dung |
| --- | --- |
| S4-01 | API dùng chung, môi trường Development/Staging/Production, cấu hình secret/DB/CORS/JWT, lỗi chuẩn, validation, OpenAPI, health, conventions/migrations; URL cấu hình cho ba client; CI và chuẩn bị deploy |
| S4-02 | Đăng ký/xác minh/resend, đăng nhập, refresh, logout, forgot/reset, session restore và thu hồi phiên; status/disabled-admin enforcement; web/mobile auth UI |

API local mặc định `http://localhost:5080`. PostgreSQL local lưu dữ liệu bền. Web và Flutter dùng cùng contract `/api/v1`, riêng auth session transport phù hợp từng nền tảng.

## Hoãn hoặc ngoài phạm vi

- Staging URL, Swagger trên staging, deployment Render thật và E2E staging: hoãn theo xác nhận người dùng. Workflow opt-in chưa chứng minh deploy thành công.
- S4-03 chỉnh sửa profile/settings; S4-04 Channel; S4-05 membership/invitation; S4-06 permission engine/admin shell đầy đủ: ngoài yêu cầu hai slice lần này.
- Google/Facebook external login: conditional scope chưa được chốt credential/provider.
- Danh sách session thuộc S4-02; không diễn giải màn hình account auth thành hoàn tất profile/settings.
- Admin access guard thuộc S4-02; không diễn giải nó thành hoàn tất RBAC permission engine.

## Bằng chứng nghiệm thu

Trạng thái kiểm chứng local ghi nhận trong lượt triển khai ngày 2026-09-05.

| Hạng mục | Kết quả đã xác nhận / phần còn chờ |
| --- | --- |
| PostgreSQL local | PostgreSQL native loopback cổng 5432, database `hutube`; bootstrap xác nhận đúng 42 bảng nghiệp vụ và roles auth được seed |
| Migration và API | Migration local đạt; `/health`, `/api/v1/system/info`, `/openapi/v1.json` hoạt động |
| Backend | Release build và test auth chạy trên PostgreSQL thật; số test cuối cập nhật theo CI/PR |
| Hai Angular app | 34/34 test mỗi app đạt; production build của cả hai app đạt |
| Browser E2E | API/PostgreSQL thật đạt: register, verify qua pickup email, login/restore, refresh, revoke/logout, forgot/reset; user thường bị chặn Admin; Admin được cấp quyền đăng nhập được và bị chặn ngay sau disable |
| Flutter unit/widget | 17 test mặc định đạt; analyze không có issue |
| Mobile HTTP smoke | Tổng 18/18 đạt khi bật live test; controller mobile gọi API/PostgreSQL thật qua toàn bộ auth/session flow. Đây không phải kiểm thử giao diện native trên thiết bị |
| APK/native | Debug APK build đạt; emulator headless không boot xong nên chưa xác nhận secure storage/UI trên thiết bị Android; iOS cần macOS/Xcode |
| PowerShell và YAML | Parse scripts/CI/Compose đạt; loader literal và truyền lỗi lệnh con đạt; PostgreSQL Status xác nhận đúng instance cổng 55432 |
| GitHub/CI/container | Nhánh `develop` baseline đã được tạo/push; workflow có backend/web/mobile, browser E2E, image và deploy opt-in. Chờ commit feature và kết quả GitHub Actions; container chưa được chạy local vì máy không có Docker CLI |
| Render/SMTP staging | Chưa triển khai; không có URL staging hoặc kiểm thử SMTP thật |

Workflow Flutter chạy analyze/unit/widget; test HTTP thật trong `api_smoke_test.dart` được bỏ qua có lý do khi không đặt `LIVE_API_BASE_URL` và `EMAIL_PICKUP_DIRECTORY`. Smoke này được chạy riêng trên local với cấu hình đúng. CI hiện không build APK hoặc chạy emulator.

Ghi nhận test run thực tế trong bàn giao triển khai hoặc PR, gồm lệnh, kết quả và hạn chế. CI artifacts chỉ có sau workflow thực sự chạy; test client được ghi trong job logs. Không đánh dấu các exit criteria toàn Sprint 4 đã hoàn thành khi chỉ xử lý S4-01/S4-02.

Các bước tối thiểu cần kiểm tra: migration local; API health/diagnostic; unit/integration auth; build/test hai Angular app; analyze/test Flutter; smoke register → verify → login → restore → refresh → logout/revoke và kiểm tra user thường/disabled admin bị chặn. Thiết bị mobile, deep link thật, SMTP thật hoặc staging chưa kiểm tra phải được nêu rõ.
