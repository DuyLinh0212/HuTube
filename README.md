# HuTube

Nền tảng video dùng chung ASP.NET Core 10 + PostgreSQL, hai Angular app độc lập và Flutter mobile.

Phạm vi hiện tại: **S4-01 API/infrastructure và S4-02 auth/session**. Theo xác nhận của người dùng, API và PostgreSQL chạy local; chưa có Render/staging URL. Các slice account chỉnh sửa, channel, membership và RBAC đầy đủ còn thuộc phần sau của Sprint 4.

## Bắt đầu

Máy phát triển hiện dùng PostgreSQL 18 riêng tại `.local/postgres`, cổng `127.0.0.1:55432`, database `hutube`; cấu hình riêng nằm trong `.env.local`. Chạy `./scripts/local-postgres.ps1 -Action Start` trước khi chạy API; xem [thiết lập local của máy này](docs/operations/LOCAL_SETUP.md). Các bước dưới đây dành cho thiết lập mới.

1. Cài .NET 10, Node 22.12+, Flutter stable (ít nhất 3.38.4, Dart tương thích `^3.10.7`), PostgreSQL 18 và Chrome.
2. Copy `.env.example` thành `.env.local`, cấu hình database ứng dụng và test riêng, JWT key ngẫu nhiên ít nhất 64 ký tự.
3. Tạo database/role theo [hướng dẫn local](docs/operations/LOCAL_DEVELOPMENT.md).
4. Chạy `./scripts/setup-local.ps1` tại root repository.
5. Mở terminal riêng cho từng lệnh:

```powershell
./scripts/run-local.ps1 -Component api
./scripts/run-local.ps1 -Component user
./scripts/run-local.ps1 -Component admin
./scripts/run-local.ps1 -Component mobile
```

API: `http://localhost:5080`; User Web: `http://localhost:4200`; Admin Web: `http://localhost:4201`. Android emulator dùng `http://10.0.2.2:5080/api/v1`. URL thay đổi bằng cấu hình môi trường.

## Kiểm thử và vận hành

```powershell
./scripts/test.ps1
./scripts/smoke.ps1
```

Workflow được cấu hình để build/unit/integration PostgreSQL, test/build hai web và analyze/test Flutter, sau đó publish container lên GHCR từ `develop`. Deploy Render chỉ chạy khi đã cấu hình và chọn thủ công; push GitHub không tự tạo môi trường cloud.

Đã xác minh migration/health/OpenAPI local, luồng auth User Web trên trình duyệt với API thật, 17 test unit/widget Flutter và luồng controller mobile gọi HTTP thật. Kết quả Release/backend, lượt test web cuối, APK native và GitHub Actions được ghi riêng trong [bảng nghiệm thu](docs/operations/S4_SCOPE.md); không suy từ test local thành CI/native đã đạt.

- [API auth/session](docs/api/S4_AUTH.md)
- [Local và PostgreSQL](docs/operations/LOCAL_DEVELOPMENT.md)
- [CI/CD và Render sau này](docs/operations/CI_CD.md)
- [Phạm vi nghiệm thu S4-01/S4-02](docs/operations/S4_SCOPE.md)
- [Quyết định PostgreSQL/local](docs/decisions/ADR-008-postgresql-and-local-s4.md)
- [Kiến trúc](docs/architecture/PROJECT_ARCHITECTURE.md), [tech stack](docs/architecture/TECH_STACK.md), [branch/commit convention](docs/conventions/DEVELOPMENT_CONVENTIONS.md)

Làm việc trên `feature/s4-staging-auth`, tích hợp vào `develop`; không merge vào `main` trong phạm vi này. Secret, thư pickup, database thực và build artifacts không được commit.
