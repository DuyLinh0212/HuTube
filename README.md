# HuTube

Nền tảng video dùng chung ASP.NET Core 10 + PostgreSQL, hai Angular app độc lập và Flutter mobile.

Phạm vi hiện tại: **S4-01 API/infrastructure và S4-02 auth/session**. Theo xác nhận của người dùng, API và PostgreSQL chạy local; chưa có Render/staging URL. Các slice account chỉnh sửa, channel, membership và RBAC đầy đủ còn thuộc phần sau của Sprint 4.

## Bắt đầu

Máy phát triển dùng PostgreSQL native tại `127.0.0.1:5432`, database `hutube`; cấu hình riêng nằm trong `.env.local`. Xem [thiết lập local](docs/operations/LOCAL_SETUP.md). Các bước dưới đây dành cho thiết lập mới.

1. Cài .NET 10, Node 22.12+, Flutter stable (ít nhất 3.38.4, Dart tương thích `^3.10.7`), PostgreSQL 18 và Chrome.
2. Copy `.env.example` thành `.env.local`, cấu hình database ứng dụng và test riêng, JWT key ngẫu nhiên ít nhất 64 ký tự.
3. Tạo database/role theo [hướng dẫn local](docs/operations/LOCAL_DEVELOPMENT.md).
4. Chạy `./scripts/setup-local.ps1` tại root repository.
5. Mở terminal riêng cho từng lệnh:

```powershell
./scripts/run-local.ps1 -Component api
./scripts/run-local.ps1 -Component recommender
./scripts/run-local.ps1 -Component user
./scripts/run-local.ps1 -Component admin
./scripts/run-local.ps1 -Component mobile
```

API: `http://localhost:5080`; Recommendation Service: `http://localhost:8000`; User Web: `http://localhost:4200`; Admin Web: `http://localhost:4201`. Android emulator dùng `http://10.0.2.2:5080/api/v1`. URL thay đổi bằng cấu hình môi trường.

## Kiến trúc Luồng Dữ liệu & Đề xuất (Collaborative Filtering)

```text
┌─────────────────────────────┐
│ Bot Simulator / Data Seeder │  (Web Studio :5050 - Giả lập user mục tiêu TVH Sports & cụm bot)
└──────────────┬──────────────┘
               │ HTTP API (POST /auth, /watch-progress, /reaction, /rating, /comments, /subscribe)
               ▼
┌─────────────────────────────┐
│     HuTube Backend API      │  (ASP.NET Core 10 :5080)
└──────────────┬──────────────┘
               │ Lưu trữ tương tác & media
               ▼
┌─────────────────────────────┐
│    PostgreSQL 18 Database   │  (viewing_histories, video_reactions, ratings, comments, subscriptions)
│    Cloudflare R2 / Cloudinary│  (Video media, renditions & thumbnails)
└──────────────┬──────────────┘
               │ Admin xuất CSV xác định lên R2; service nạp artifact từ R2
               ▼
┌─────────────────────────────┐
│   Recommendation Service    │  (Python FastAPI :8000 - Item-Based Cosine)
└──────────────┬──────────────┘
               │ Truy vấn Top-K đề xuất cá nhân hóa (X-Service-Token)
               ▼
┌─────────────────────────────┐
│    User Web & Mobile App    │  (Trang chủ :4200 hiển thị video đề xuất theo sở thích của User)
└─────────────────────────────┘
```

## Thuật toán Đề xuất (Collaborative Filtering)

Dự án tích hợp hệ thống đề xuất cá nhân hóa chạy bằng Python FastAPI và kết nối trực tiếp với Backend .NET:

```powershell
./scripts/run-recommender.ps1
# hoặc:
./scripts/run-local.ps1 -Component recommender
```

- API suy luận: `POST /internal/recommendations` với token nội bộ `Recommendation__ServiceToken`. API cập nhật dùng token riêng `Recommendation__AdminToken`.
- Model triển khai: **Item-Based Cosine**. Sáu biến thể User-Based/Item-Based với Cosine, Jaccard và Pearson vẫn dùng cho benchmark local.
- Super Admin truy cập `/recommendations` trên admin web để kiểm tra ma trận, cập nhật model và mô phỏng tương tác. CSV và artifact của từng phiên bản nằm trên R2; `collaborative_cf/active.json` là manifest đang hoạt động.
- Chạy trainer local chỉ với CSV thật: `python -m training.train_hutube --matrix-csv <file.csv>`. Không có nhánh tự sinh dữ liệu.
- Xem tài liệu kiến trúc tại: [Kiến trúc Collaborative Filtering](docs/architecture/CF_ARCHITECTURE.md) và [Recommendation Service](recommendation-service/README.md).

## Mô phỏng tương tác trong Admin Web

Super Admin chọn nhiều user đang hoạt động, tạo bot mới, chọn video và tỷ lệ xem/thích/không thích/đánh giá/bình luận/đăng ký tại `/recommendations`. Mọi hành vi chạy qua service .NET, trạng thái job nằm trong PostgreSQL và audit ghi người khởi chạy cùng user đích. Giao diện yêu cầu xác nhận rõ trước khi chọn tài khoản thật. Không cần mật khẩu của user để mô phỏng.

## Hướng dẫn Demo Đồ án (Kịch bản 4 bước kiểm chứng Thuật toán)

Khi báo cáo hoặc thuyết trình đồ án, bạn thực hiện theo kịch bản chuẩn 4 bước sau để chứng minh trọn vẹn luồng từ thu thập dữ liệu hành vi đến thuật toán gợi ý cá nhân hóa:

### 1. Khởi chạy các dịch vụ (mỗi tab 1 terminal)
```powershell
./scripts/run-local.ps1 -Component api        # HuTube Backend API (Cổng 5080)
./scripts/run-recommender.ps1                 # Recommendation Service AI (Cổng 8000)
./scripts/run-local.ps1 -Component admin      # Admin Web (Cổng 4201)
./scripts/run-local.ps1 -Component user       # HuTube Web Frontend (Cổng 4200)
```

### 2. Kịch bản thực hiện Demo
- **Bước 1 (Trạng thái Chưa Đăng Nhập / Cold Start)**:
  - Mở trình duyệt vào [http://localhost:4200](http://localhost:4200) (ẩn danh hoặc chưa login).
  - *Thuyết minh*: Trang chủ hiển thị video phổ biến dựa trên lượt xem cao nhất và video mới xuất bản.
- **Bước 2 (Mô phỏng hành vi trong Admin Web)**:
  - Đăng nhập Super Admin tại [http://localhost:4201/recommendations](http://localhost:4201/recommendations).
  - Chọn tài khoản mục tiêu (ví dụ: `TVH Sports` hoặc `nguyenvanhung509`).
  - Thiết lập kịch bản hành vi:
    - Chủ đề tương tác: **Âm nhạc** (Music) hoặc **Thể thao** (Sports).
    - Số lượng: `15 - 20` video.
    - Hành vi: Xem `75%` thời lượng, Thích (Like = Có), Đánh giá (Rating = 5 sao), Bình luận (Comment = Có), Đăng ký kênh (Subscribe = Có).
  - Bấm **"Chạy mô phỏng"**: Backend tạo tương tác qua service hiện có và lưu vào PostgreSQL.
- **Bước 3 (Huấn luyện / Re-fit Model Collaborative Filtering)**:
  - Trên trang admin, bấm **"Kiểm tra dữ liệu"**, xem tỷ lệ thay đổi rồi bấm **"Cập nhật mô hình"**.
  - *Thuyết minh*: Backend xuất ma trận từ PostgreSQL lên R2; service tính Item-Based Cosine, lưu artifact và kích hoạt manifest mới.
- **Bước 4 (Kiểm chứng kết quả cá nhân hóa trên Web)**:
  - Quay lại [http://localhost:4200](http://localhost:4200), đăng nhập tài khoản dùng để kiểm chứng.
  - F5 tải lại Trang chủ: Các video thuộc chủ đề Âm nhạc lập tức được đưa lên đầu trang chủ.
  - Browser chỉ gọi API .NET; .NET gọi Recommendation Service bằng token nội bộ. Video đã xem được loại khỏi cả model và video bù.

## Kiểm thử và vận hành

```powershell
./scripts/test.ps1
./scripts/smoke.ps1
```

Workflow được cấu hình để build/unit/integration PostgreSQL, test/build hai web và analyze/test Flutter, sau đó publish container lên GHCR từ `develop`. Deploy Render chỉ chạy khi đã cấu hình và chọn thủ công; push GitHub không tự tạo môi trường cloud.

Đã xác minh migration/health/OpenAPI local, luồng auth User Web trên trình duyệt với API thật, 17 test unit/widget Flutter và luồng controller mobile gọi HTTP thật. Kết quả Release/backend, lượt test web cuối, APK native và GitHub Actions được ghi riêng trong [bảng nghiệm thu](docs/operations/S4_SCOPE.md); không suy từ test local thành CI/native đã đạt.

- [Quản trị thuật toán đề xuất](docs/operations/RECOMMENDATIONS.md)
- [API auth/session](docs/api/S4_AUTH.md)
- [Local và PostgreSQL](docs/operations/LOCAL_DEVELOPMENT.md)
- [CI/CD và Render sau này](docs/operations/CI_CD.md)
- [Phạm vi nghiệm thu S4-01/S4-02](docs/operations/S4_SCOPE.md)
- [Quyết định PostgreSQL/local](docs/decisions/ADR-008-postgresql-and-local-s4.md)
- [Kiến trúc](docs/architecture/PROJECT_ARCHITECTURE.md), [tech stack](docs/architecture/TECH_STACK.md), [branch/commit convention](docs/conventions/DEVELOPMENT_CONVENTIONS.md)

Làm việc trên `feature/s4-staging-auth`, tích hợp vào `develop`; không merge vào `main` trong phạm vi này. Secret, thư pickup, database thực và build artifacts không được commit.
