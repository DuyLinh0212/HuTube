# HuTube Bot Simulator & Interaction Seeder

Công cụ giả lập hành vi người dùng (User Simulator & Bot Seeder) tương tác với hệ thống HuTube, nhằm sinh dữ liệu thực tế (View, Like, Dislike, Rating, Comment, Subscribe) phục vụ huấn luyện và kiểm thử mô hình gợi ý **Collaborative Filtering (CF)** và **Recommendation Engine**.

---

## 🌟 Tính Năng Chính

1. **Web Dashboard Studio Hiện Đại (Dark Glassmorphism)**:
   - Truy cập trực tiếp tại `http://localhost:5050`.
   - Bảng điều khiển trực quan, thiết kế sang trọng, tối ưu trải nghiệm.
   - Luồng Console Logs thời gian thực qua **Server-Sent Events (SSE)**.

2. **Mô Phỏng Đa Người Dùng (Multi-User Simulation)**:
   - Hỗ trợ chọn đồng thời nhiều người dùng từ danh sách đã đăng ký hoặc bấm `✅ Chọn tất cả`.
   - Hiển thị số lượng người dùng được chọn trực tiếp trên nút khởi chạy.
   - Engine tự động cấp tài khoản cho từng user và lần lượt thực thi kịch bản tương tác độc lập.

3. **Cấu Hình Tỷ Lệ Tương Tác Linh Hoạt**:
   - **Tỷ lệ xem (Watch Ratio %)**: Tỷ lệ phần trăm video ngẫu nhiên được chọn xem trong kho video.
   - **Tỷ lệ Thích (Like %) & Không thích (Dislike %)**:
     - Tự động kiểm tra ràng buộc `Tỷ lệ Like + Tỷ lệ Dislike <= 100%`.
     - Tuyệt đối không để xảy ra trường hợp vừa like vừa dislike cùng 1 video.
     - **Logic thông minh**: Nếu video đã được Like từ trước $\to$ Bỏ qua không like lại (tránh bị bấm nhầm thành unlike), chỉ ghi nhận view hoặc tương tác thêm.
   - **Tỷ lệ Đánh giá sao (Rating %)**:
     - Logic hài hòa với cảm xúc: Video đã Like $\to$ Đánh giá 4–5 sao; Video Dislike $\to$ Đánh giá 1–2 sao; Video trung lập $\to$ 3 sao hoặc không đánh giá (0 sao).
   - **Tỷ lệ Bình luận (Comment %) & Quản Lý Mẫu Bình Luận**:
     - Cho phép thêm trực tiếp bình luận mới vào danh sách mẫu ngay trên giao diện web.
     - Tự động gán bình luận ngẫu nhiên phù hợp theo ngữ cảnh.
   - **Tỷ lệ Đăng Ký Kênh (Subscribe %)**:
     - Tự động theo dõi (subscribe) kênh sở hữu video theo xác suất thiết lập.

4. **Tạo Người Dùng Nhanh (On-demand User Creation)**:
   - Nhập tên người dùng bất kỳ để tạo tài khoản bot mới ngay lập tức qua API backend.
   - Tự động lưu trữ danh sách tài khoản vào file cấu hình.

5. **Xuất & Trực Quan Hóa Ma Trận Tương Tác**:
   - Ghi nhận chi tiết từng lượt tương tác vào file CSV: `user_video_matrix.csv`.
   - Hỗ trợ xem trước bảng ma trận tương tác User - Video trực tiếp trên Dashboard.

6. **Kịch Bản Mô Phỏng Mẫu (Ví dụ: `TVH Sports`)**:
   - **User Mục Tiêu**: `TVH Sports` (`tvhsports@seed.hutube.invalid`).
   - **Tương tác**: 20 video thuộc danh mục **Âm nhạc (Music)**.
   - **Hành vi**:
     - `watch_ratio = 75%` (video 200s xem 150s).
     - `like = 100%` (có like, không dislike).
     - `rating = 5 sao`.
     - `comment = 100%` (chọn bình luận âm nhạc phù hợp).
     - `subscribe = 100%` (đăng ký kênh âm nhạc).
   - **Đầu ra**: Dữ liệu được ghi thẳng vào database PostgreSQL của HuTube và nạp vào mô hình Collaborative Filtering để cá nhân hóa bảng tin video trên Web.

---

## 📋 Yêu Cầu Hệ Thống

- **Python**: Phiên bản 3.10 trở lên.
- **HuTube Backend API**: Đang chạy tại `http://localhost:5080/api/v1` (hoặc cổng cấu hình).

---

## 🚀 Hướng Dẫn Cài Đặt & Khởi Chạy

### Cách 1: Dùng PowerShell Script (Khuyên dùng)

Từ thư mục gốc của dự án `HuTube`, chạy lệnh:

```powershell
./scripts/run-simulator.ps1
```

*Tùy chọn nâng cao (nếu đổi cổng hoặc backend URL):*
```powershell
./scripts/run-simulator.ps1 -Port 5050 -BackendUrl "http://localhost:5080/api/v1"
```

### Cách 2: Chạy Thủ Công Bằng Python

1. Mở terminal và di chuyển vào thư mục tool:
   ```powershell
   cd tools/bot-simulator
   ```

2. Cài đặt các thư viện phụ thuộc:
   ```powershell
   pip install -r requirements.txt
   ```

3. Khởi động Web Dashboard:
   ```powershell
   python run_simulator.py --port 5050 --backend http://localhost:5080/api/v1
   ```

4. Mở trình duyệt và truy cập:
   ```text
   http://localhost:5050
   ```

---

## 🛠️ Cấu Trúc Mã Nguồn

```text
tools/bot-simulator/
├── run_simulator.py          # Entrypoint chạy Uvicorn server
├── web_app.py                # FastAPI server cung cấp REST API, SSE streaming & Web UI
├── simulator_engine.py       # Engine mô phỏng, xử lý API HuTube, quản lý log & CSV
├── persona_data.py           # Dữ liệu persona, danh sách mẫu bình luận theo chủ đề
├── requirements.txt          # Danh sách thư viện Python phụ thuộc
├── registered_users.json     # File lưu trữ danh sách tài khoản bot đã đăng ký
├── user_video_matrix.csv     # File xuất dữ liệu ma trận User - Video phục vụ mô hình CF
└── README.md                 # Tài liệu hướng dẫn sử dụng công cụ
```

---

## 💡 Lưu Ý Quan Trọng

- Đảm bảo Backend HuTube (`./scripts/run-local.ps1 -Component api`) đã chạy trước khi khởi động Bot Simulator.
- Các hành vi của bot mô phỏng hoàn toàn gọi qua REST API chính thức của HuTube, bảo đảm dữ liệu ghi nhận đầy đủ vào PostgreSQL database như người dùng thật.
