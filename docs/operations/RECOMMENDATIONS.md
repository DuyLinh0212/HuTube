# Vận hành thuật toán đề xuất

## Luồng dữ liệu

Super Admin mở `/recommendations` trên Admin Web. Browser chỉ gọi `/api/v1/admin/recommendations/*` của API .NET. `Kiểm tra dữ liệu` tạo ma trận xác định từ lịch sử xem, reaction, rating và bình luận của tài khoản đang hoạt động; đăng ký kênh tăng tín hiệu cho những cặp user–video đã có hành vi video. CSV chỉ gồm ID và tín hiệu số/boolean, không gồm email, mật khẩu hay nội dung bình luận. Diff so sánh từng cặp với CSV mà manifest R2 `collaborative_cf/active.json` trỏ tới. Trang có bảng xem trước 20 cặp và nút xuất toàn bộ CSV.

`Cập nhật mô hình` trả `202` với job ID trong PostgreSQL. Worker kiểm tra tối thiểu 2 user, 2 video, 3 cặp, xuất CSV vào `collaborative_cf/YYYY/MM/DD/interactions_<UTC timestamp>_<12 ký tự SHA-256>.csv`, rồi gọi Recommendation Service bằng admin token. Service xác minh SHA-256, huấn luyện Item-Based Cosine, lưu ZIP artifact trên R2, nạp kiểm tra và cuối cùng ghi `active.json`. Nếu bất kỳ bước nào thất bại, manifest và model trong bộ nhớ cũ không đổi. Job ghi bước lỗi và log để admin theo dõi. Service khởi động lại đọc manifest và artifact từ R2, xác minh hash rồi mới phục vụ.

Endpoint suy luận dùng token khác. Backend gửi toàn bộ ID video đã xem mới nhất trong `excludeItemIds`, loại kết quả CF đã xem, và loại video đã xem khỏi tập phổ biến dùng để bù trên mọi trang. Video đã xem vẫn nằm trong ma trận tính tương đồng. Tìm kiếm video thường không dùng bộ lọc này.

## Cấu hình local

1. Tạo `recommendation-service/.env` theo `.env.example` với `RECOMMENDER_SERVICE_TOKEN`, `RECOMMENDER_ADMIN_TOKEN` **khác nhau**, cùng `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`. Không commit file `.env`.
2. Cấu hình API .NET qua biến môi trường `Recommendation__ServiceUrl=http://127.0.0.1:8000`, `Recommendation__ServiceToken`, `Recommendation__AdminToken` tương ứng, cùng `Storage__R2__AccountId`, `Storage__R2__AccessKeyId`, `Storage__R2__SecretAccessKey`, `Storage__R2__BucketName`.
3. Chạy migration theo hướng dẫn backend trước khi khởi động API. Trong `recommendation-service`, cài `py -3 -m venv .venv` và `.\.venv\Scripts\python.exe -m pip install -e ".[dev]"`; từ gốc repo chạy `./scripts/run-recommender.ps1` (bind `127.0.0.1`).
4. Đăng nhập Super Admin, mở `/recommendations`, chọn `Kiểm tra dữ liệu`, chạy mô phỏng nếu cần, rồi chọn `Cập nhật mô hình`. Các tài khoản thật cần xác nhận trên giao diện; backend vẫn kiểm tra xác nhận khi gọi API trực tiếp.

Trong phần mô phỏng, kịch bản **User mục tiêu** cho từng user đã chọn tương tác lần lượt với các video đã chọn; kịch bản **Cụm bot / user** chọn video ngẫu nhiên trong tập đó. Tỷ lệ xem là xác suất tạo lượt xem, còn thời lượng xem là phần trăm thời gian video được ghi nhận.

## Render Free

`render.yaml` khai báo `hutube-recommendation-service` dạng public Docker web miễn phí. Điền cùng cặp token và R2 credentials cho hai service trong Render; đặt `Recommendation__ServiceUrl` trên API thành URL HTTPS của service Python. Giữ token trong biến môi trường, không trong web config. API và Python phải dùng chung bucket R2. [Render Free](https://render.com/docs/free) có 512 MB RAM, 0,1 CPU, ngủ sau 15 phút không có request và file cục bộ không bền; vì vậy artifact chỉ được lưu trên R2. Request đầu sau khi service ngủ có thể dùng feed mặc định. [R2 S3 API](https://developers.cloudflare.com/r2/get-started/s3/) cần endpoint account và region `auto`.

Để kiểm tra triển khai, xác nhận `GET /health` của Python trả model version, CSV key, hash và thời điểm cập nhật sau khi job hoàn thành; sau khi restart service, `GET /ready` vẫn trả cùng version. Kiểm tra job thất bại không thay `active.json`. Thử một user đã xem video trước và sau lúc huấn luyện trên trang 1 và trang tiếp theo.

## Dữ liệu cũ

Simulator cũ và CSV xuất ở gốc repository đã bị xóa khỏi trạng thái cuối. Branch nguồn từng chứa 5 tài khoản `.invalid` cùng mật khẩu trong `registered_users.json`. Không dùng lại những mật khẩu đó. Nếu ai đã dùng cùng mật khẩu cho tài khoản thật hoặc dịch vụ khác, người sở hữu cần đổi ngay; squash merge chỉ ngăn dữ liệu đó đi vào lịch sử `develop`, không xóa commit đã tồn tại trên branch nguồn.
