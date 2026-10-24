# Xác nhận merge Web E2E — 20/10/2026

`origin/develop` tại `1503d5d` được fast-forward tới `origin/main`
`41383ef` (đủ 5 commit còn thiếu). Hai nhánh bằng nhau tại thời điểm đó,
trước khi merge `origin/test/web-e2e` tại `3d41222`.
Trong lúc kiểm thử, main có thêm commit `1f5cd7c` về giới hạn thử lại
đăng nhập và khôi phục tải lên. Commit này được merge thêm và các bộ
backend, frontend, build, Web E2E được chạy lại trên mã mới nhất.

## Xử lý xung đột và lỗi kiểm thử

- Giữ các cập nhật main về giao diện Dalitu, thứ tự đề xuất, QR thanh toán,
  hạn mức lưu trữ và trang chủ kênh; tích hợp tìm kiếm/phân trang video,
  quyền PiP, chính sách và quy trình kiểm duyệt của nhánh E2E.
- Sửa lỗi biên dịch do thiếu namespace Regex và biến trùng sau merge;
  tách trạng thái tải video của tab tìm kiếm khỏi các mục trang chủ kênh.
- Sửa danh mục mô hình Python: manifest có `jobId` vẫn là manifest khi có
  `modelVersion`, tránh mất các bản mô hình đã lưu.
- Chuyển test chấp nhận/thu hồi gói chia sẻ sang PostgreSQL thật vì luồng
  này dùng bulk update và khóa giao dịch; giữ các xác nhận hạn mức và quyền.
- Cho runner chờ PostgreSQL ghi dữ liệu khi dừng tối đa 120 giây mặc định
  (cấu hình giới hạn 30–300 giây). Sửa bộ chọn kiểm tra chính sách khi dùng
  lại dữ liệu có nhiều phiên bản lịch sử.

## Kết quả thực thi

| Bộ kiểm thử | Đạt | Lỗi | Bỏ qua |
|---|---:|---:|---:|
| Backend main `1f5cd7c`: unit .NET | 135 | 0 | 0 |
| Backend main `1f5cd7c`: integration PostgreSQL | 124 | 0 | 0 |
| Backend sau merge: unit .NET | 179 | 0 | 0 |
| Backend sau merge: integration PostgreSQL | 125 | 0 | 0 |
| Recommendation Python | 54 | 0 | 1 |
| User Web unit | 70 | 0 | 0 |
| Admin Web unit | 67 | 0 | 0 |
| Runner E2E unit | 6 | 0 | 1 |
| Web E2E: lượt chạy mới | 112 | 0 | 0 |

Backend sau merge được chạy lại toàn bộ bằng `dotnet test backend/HuTube.sln
--configuration Release --no-restore`; kết quả TRX cuối cùng là 179 unit và
125 integration cùng đạt. Cả hai production build Angular, API build và
Ruff đều thành công. Các cảnh báo build có sẵn được giữ trong log.

Web E2E lượt `20261020T092859.514490Z` thực thi mới đủ 112 ca; runner gặp
timeout khi dừng PostgreSQL sau khi các ca đã đạt. Sau sửa runner và bộ
chọn chính sách và đồng bộ main mới nhất, lượt `20261020T095632.560494Z`
kết thúc mã 0: 102 ca
thực thi đạt, 10 bước chuẩn bị dùng lại bằng chứng trước đó; không lỗi,
không bị chặn và CSDL dừng thành công. Không tính dữ liệu dùng lại là
lượt tạo dữ liệu mới.

## Đối chiếu Excel backend

Nguồn là `docs/BACKEND_TEST_SCENARIOS.md` trên **main**, không lấy danh mục
từ nhánh E2E. Tài liệu chứa 530 ID duy nhất: 525 ca ở mục 12–16 và 5 ca
media ở mục 6. Trạng thái nguồn ngày 05/10/2026 gồm 482 PASS, 48 PLANNED.
Đây là danh mục kịch bản API/nghiệp vụ/media/Python/hiệu năng, không tương
đương số test .NET được runner phát hiện.

Excel bên ngoài repo giữ đủ 530 ID trong `Backend Tests`, kết quả 259 test
tự động chạy trên main trong `Backend Executions`, 112 ca chạy Web mới
trong `Regression 20-10`, các bước tiếng Việt và Summary bằng công thức.
Ngày chạy mới chỉ gắn với bằng chứng thực thi; không ghi 530 PASS mới.
902 ca Web lịch sử và 85 luồng cha được thống kê riêng để tránh đếm trùng.

Log/TRX, ảnh và dữ liệu chạy thử được lưu cục bộ trong thư mục công việc
và `frontend/e2e_testing/artifacts`, không đưa tài khoản hay dữ liệu tạm
vào commit.
