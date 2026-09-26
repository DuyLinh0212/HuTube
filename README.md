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
               │ Nạp ma trận tương tác (user_video_matrix.csv hoặc API)
               ▼
┌─────────────────────────────┐
│   Recommendation Service    │  (Python FastAPI :8000 - Item-Based & User-Based CF)
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

- API suy luận: `http://localhost:8000/internal/recommendations` (kèm Header `X-Service-Token: hutube-cf-internal-secret-key`)
- Thuật toán: **Item-Based CF** và **User-Based CF** với 3 độ đo tương đồng (**Cosine**, **Jaccard**, **Pearson**) theo chuẩn tài liệu giải thuật.
- Tự động huấn luyện lại mô hình từ dữ liệu tương tác mới:
  ```powershell
  python recommendation-service/training/train_hutube.py
  ```
- Xem tài liệu kiến trúc tại: [Kiến trúc Collaborative Filtering](docs/architecture/CF_ARCHITECTURE.md) và [Recommendation Service](recommendation-service/README.md).

## Công cụ giả lập tương tác (Bot Simulator & Seeder)

Dự án tích hợp công cụ giả lập hành vi người dùng (view, like/dislike, rating, comment, subscribe) nhằm sinh dữ liệu ma trận phục vụ mô hình gợi ý **Collaborative Filtering (CF)**:

```powershell
./scripts/run-simulator.ps1
```

- Web Dashboard trực quan tại: `http://localhost:5050`
- **Kịch bản thực nghiệm mẫu (`TVH Sports`)**:
  - Giả lập người dùng `TVH Sports` tương tác với **20 video âm nhạc**.
  - `watch_ratio = 75%` (xem 75% thời lượng video).
  - Có Like (`like = true`), không dislike trùng lặp.
  - Có Bình luận (`comment = true`) theo ngữ cảnh âm nhạc tiếng Việt.
  - Đánh giá sao (`rating = 5 sao`).
  - Đăng ký kênh (`subscribe = true`).
  - Toàn bộ hành vi được đẩy qua HTTP API vào PostgreSQL và nạp vào mô hình CF để kiểm thử đề xuất trên Web User.
- Chi tiết cấu hình, tính năng chọn nhiều người dùng và logic tương tác xem tại: [Hướng dẫn Bot Simulator](tools/bot-simulator/README.md).

## Hướng dẫn Demo Đồ án (Kịch bản 4 bước kiểm chứng Thuật toán)

Khi báo cáo hoặc thuyết trình đồ án, bạn thực hiện theo kịch bản chuẩn 4 bước sau để chứng minh trọn vẹn luồng từ thu thập dữ liệu hành vi đến thuật toán gợi ý cá nhân hóa:

### 1. Khởi chạy các dịch vụ (mỗi tab 1 terminal)
```powershell
./scripts/run-local.ps1 -Component api        # HuTube Backend API (Cổng 5080)
./scripts/run-recommender.ps1                 # Recommendation Service AI (Cổng 8000)
./scripts/run-simulator.ps1                   # Bot Simulator & Data Seeder (Cổng 5050)
./scripts/run-local.ps1 -Component user       # HuTube Web Frontend (Cổng 4200)
```

### 2. Kịch bản thực hiện Demo
- **Bước 1 (Trạng thái Chưa Đăng Nhập / Cold Start)**:
  - Mở trình duyệt vào [http://localhost:4200](http://localhost:4200) (ẩn danh hoặc chưa login).
  - *Thuyết minh*: Trang chủ hiển thị video phổ biến dựa trên lượt xem cao nhất và video mới xuất bản.
- **Bước 2 (Giả lập hành vi người dùng bằng Bot Simulator)**:
  - Truy cập Studio tại [http://localhost:5050](http://localhost:5050).
  - Chọn tài khoản mục tiêu (ví dụ: `TVH Sports` hoặc `nguyenvanhung509`).
  - Thiết lập kịch bản hành vi:
    - Chủ đề tương tác: **Âm nhạc** (Music) hoặc **Thể thao** (Sports).
    - Số lượng: `15 - 20` video.
    - Hành vi: Xem `75%` thời lượng, Thích (Like = Có), Đánh giá (Rating = 5 sao), Bình luận (Comment = Có), Đăng ký kênh (Subscribe = Có).
  - Bấm **"Bắt đầu tương tác"**: Hệ thống đẩy HTTP API thật vào HuTube Backend, ghi nhận vào PostgreSQL và ma trận `user_video_matrix.csv`.
- **Bước 3 (Huấn luyện / Re-fit Model Collaborative Filtering)**:
  - Trên terminal, chạy lệnh cập nhật mô hình từ dữ liệu tương tác vừa sinh:
    ```powershell
    python recommendation-service/training/train_hutube.py
    ```
  - *Thuyết minh*: Mô hình tính toán lại ma trận tương đồng User-User và Item-Item (Cosine, Jaccard, Pearson) và xuất artifact mới nhất.
- **Bước 4 (Kiểm chứng kết quả cá nhân hóa trên Web)**:
  - Quay lại [http://localhost:4200](http://localhost:4200), đăng nhập tài khoản vừa mô phỏng (`TVH Sports` hoặc `nguyenvanhung509`).
  - F5 tải lại Trang chủ: Các video thuộc chủ đề Âm nhạc lập tức được đưa lên đầu trang chủ.
  - Bấm `F12` (Network Tab): Chỉ ra request gọi ngầm sang Recommendation Service (`POST /internal/recommendations`) hoàn thành trong < 5ms.

## Kiểm thử và vận hành

```powershell
./scripts/test.ps1
./scripts/smoke.ps1
```

Workflow được cấu hình để build/unit/integration PostgreSQL, test/build hai web và analyze/test Flutter, sau đó publish container lên GHCR từ `develop`. Deploy Render chỉ chạy khi đã cấu hình và chọn thủ công; push GitHub không tự tạo môi trường cloud.

Đã xác minh migration/health/OpenAPI local, luồng auth User Web trên trình duyệt với API thật, 17 test unit/widget Flutter và luồng controller mobile gọi HTTP thật. Kết quả Release/backend, lượt test web cuối, APK native và GitHub Actions được ghi riêng trong [bảng nghiệm thu](docs/operations/S4_SCOPE.md); không suy từ test local thành CI/native đã đạt.

- [Công cụ Bot Simulator & Seeder](tools/bot-simulator/README.md)
- [API auth/session](docs/api/S4_AUTH.md)
- [Local và PostgreSQL](docs/operations/LOCAL_DEVELOPMENT.md)
- [CI/CD và Render sau này](docs/operations/CI_CD.md)
- [Phạm vi nghiệm thu S4-01/S4-02](docs/operations/S4_SCOPE.md)
- [Quyết định PostgreSQL/local](docs/decisions/ADR-008-postgresql-and-local-s4.md)
- [Kiến trúc](docs/architecture/PROJECT_ARCHITECTURE.md), [tech stack](docs/architecture/TECH_STACK.md), [branch/commit convention](docs/conventions/DEVELOPMENT_CONVENTIONS.md)

Làm việc trên `feature/s4-staging-auth`, tích hợp vào `develop`; không merge vào `main` trong phạm vi này. Secret, thư pickup, database thực và build artifacts không được commit.
