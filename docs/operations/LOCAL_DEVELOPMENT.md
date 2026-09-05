# Chạy HuTube local — S4-01/S4-02

Máy phát triển dùng PostgreSQL native ở cổng 5432; xem [LOCAL_SETUP.md](LOCAL_SETUP.md) để cấu hình database và migration. Hướng dẫn tạo role/database dưới đây dành cho thiết lập mới.

## Yêu cầu

- .NET SDK 10, Node.js 22.12 trở lên trong nhánh 22, npm và Chrome (cho Karma ChromeHeadless).
- Flutter stable ít nhất 3.38.4 và Dart tương thích `^3.10.7`, Android SDK/emulator nếu chạy app Android.
- PostgreSQL 18 và `psql`; Docker chỉ cần cho lựa chọn Compose.
- PowerShell 7. Chạy các lệnh dưới đây tại thư mục repository `HuTube`.

## Database và cấu hình

Copy `.env.example` thành `.env.local`; file local bị Git bỏ qua. Đặt connection string ứng dụng, connection string test riêng, JWT key ngẫu nhiên tối thiểu 64 ký tự. Không dùng lại mật khẩu CI cho local. Loader chỉ đọc giá trị literal `KEY=value`, không thực thi shell, không mở rộng biến và không hỗ trợ inline comment. Giá trị có thể đặt trong cặp dấu nháy.

Nếu chưa có database, mở `psql -U postgres -d postgres`, tạo role/database mới với tên chưa tồn tại:

```sql
CREATE ROLE hutube LOGIN;
\password hutube
CREATE DATABASE hutube OWNER hutube;
CREATE ROLE hutube_test LOGIN CREATEDB;
\password hutube_test
CREATE DATABASE hutube_test OWNER hutube_test;
```

`\password` yêu cầu nhập mật khẩu ẩn; không ghi mật khẩu vào command history. Nếu đã có role/database, dùng chúng và cập nhật cấu hình; không chạy lại các câu tạo. Application role không cần superuser/CREATEDB. Test role có quyền tạo database để test dùng database riêng biệt; không đặt `TEST_DATABASE_CONNECTION` trỏ vào dữ liệu ứng dụng.

```powershell
./scripts/setup-local.ps1
```

Script restore dependencies và chạy migration trên database chỉ định. Nó không tạo/drop PostgreSQL service, database hoặc role. Khi thiếu credentials, SDK hoặc migration lỗi, script dừng. Không chạy thủ công SQL bootstrap vào database đã được EF quản lý; xem hướng dẫn migration của backend trước khi nhập database có sẵn.

## Chạy bốn thành phần

Mỗi lệnh chạy ở một terminal riêng, có thể dừng bằng Ctrl+C:

```powershell
./scripts/run-local.ps1 -Component api
./scripts/run-local.ps1 -Component user
./scripts/run-local.ps1 -Component admin
./scripts/run-local.ps1 -Component mobile
```

| Thành phần | Địa chỉ local |
| --- | --- |
| API | `http://localhost:5080` |
| Health | `http://localhost:5080/health` |
| Swagger (Development/Staging) | `http://localhost:5080/swagger` |
| OpenAPI JSON (Development/Staging) | `http://localhost:5080/openapi/v1.json` |
| Diagnostic cho ba client | `http://localhost:5080/api/v1/system/info` |
| User Web | `http://localhost:4200` |
| Admin Web | `http://localhost:4201` |
| Android emulator gọi API | `http://10.0.2.2:5080/api/v1` |

Web dùng `API_BASE_URL`; npm prestart/prebuild cập nhật `public/config.json`, bootstrap tải file này trước khi khởi tạo Angular. Mobile nhận `MOBILE_API_BASE_URL` qua `--dart-define=API_BASE_URL=...`; chọn thiết bị với `-Device <device-id>`. Máy thật cần địa chỉ LAN của máy chạy API thay cho `10.0.2.2`; cho phép truy cập cổng 5080 trong mạng phát triển. Không dùng `localhost` trên điện thoại để gọi máy tính.

Email Development dùng pickup `.eml`: mở thư trong thư mục pickup mà backend cấu hình, lấy link xác minh/đặt lại mật khẩu và mở trong trình duyệt. Không có API công khai trả verification/reset token. Link email chứa token nhạy cảm; không chia sẻ hoặc commit thư. SMTP phải được cấu hình trước khi dùng tài khoản thật trên staging.

Admin login kiểm tra admin access tại API; đăng ký thông thường không tạo quyền quản trị. Seed/admin provisioning phải theo hướng dẫn database; không có tài khoản admin và mật khẩu mặc định công khai.

## Kiểm tra

```powershell
./scripts/test.ps1
./scripts/smoke.ps1
```

`test.ps1` build .NET Release, chạy unit/integration trên PostgreSQL, test/build cả hai Angular app, analyze/test Flutter. Bất kỳ lỗi hoặc công cụ bị thiếu đều làm lệnh thất bại. Nếu Chrome không nằm tại vị trí chuẩn, đặt `CHROME_BIN` trong môi trường. Smoke chỉ kiểm tra health và diagnostic, không thay thế auth E2E.

Kiểm tra giao diện local: đăng ký → mở thư pickup → xác minh → đăng nhập → tải lại trang/app → kiểm tra account → đổi mật khẩu qua link email → đăng nhập lại → xem/revoke phiên → đăng xuất. Thử user thường vào admin và gọi `/api/v1/admin/me` phải bị từ chối. Ghi kết quả thật vào báo cáo nghiệm thu; chưa chạy trên thiết bị/staging thì ghi chưa kiểm tra.

## Docker tùy chọn

```powershell
docker compose --env-file .env.local up -d postgres
docker compose --env-file .env.local --profile api up --build -d
```

PostgreSQL container lưu bền trong named volume, mặc định bind loopback cổng 5433; API container dùng hostname `postgres:5432`. Service `migrate` phải kết thúc thành công trước khi `api` chạy. Không dùng `down -v` nếu cần giữ dữ liệu. Native PostgreSQL và PostgreSQL container là hai database riêng.

Compose hiện phục vụ phát triển local. Nếu dùng email pickup trong API container, lấy thư từ container; thư chưa được mount ra host. Với workflow phát triển email thuận tiện, chạy native API như trên.
