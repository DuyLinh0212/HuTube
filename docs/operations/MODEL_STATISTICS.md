# Thống kê phiên bản mô hình đề xuất

Admin Web, trang `/recommendations`, có bảng danh sách phiên bản đã build. API `GET /api/v1/admin/recommendations/models` vẫn yêu cầu Super Admin và gọi `GET /internal/models` bằng token quản trị riêng của Recommendation Service.

Mỗi phiên bản hiển thị thuật toán, trạng thái đang sử dụng, thời điểm hoàn tất build, thời lượng build, thời lượng huấn luyện, số user/video/cặp tương tác và lần tạo đề xuất thành công gần nhất. `isActive` dựa trên phiên bản thực sự được nạp vào bộ nhớ phục vụ đề xuất.

Thời lượng build đo bằng đồng hồ monotonic, từ lúc lấy được khóa huấn luyện tới sau khi đọc CSV, train, đóng gói, upload và xác minh artifact. Không gồm thời gian xếp hàng/chờ khóa. Thời lượng huấn luyện là thời gian fit thuật toán. Các thời điểm được lưu UTC, trình duyệt hiển thị theo múi giờ của người dùng.

Manifest của mỗi lần build mới được lưu ở `collaborative_cf/models/<modelVersion>.json` trên R2. Bảng cũng đọc manifest trong các training job cũ và `active.json`; không tải các ZIP lớn chỉ để xem thống kê. Dọn CSV cũ không xóa danh sách model. Phiên bản đã build nhưng chưa được kích hoạt có thể xuất hiện ở trạng thái đã lưu.

Chỉ inference thành công mới ghi `lastUsedAt`; lần load/reload model, lỗi xác thực và user không thuộc model không cập nhật thời điểm này. Việc ghi trên đường inference chỉ cập nhật bộ nhớ. Vòng refresh lưu thời điểm vào `collaborative_cf/usage/<modelVersion>.json` khoảng mỗi 10 giây và flush khi shutdown bình thường. Compare-and-swap giữ thời điểm mới nhất khi có nhiều replica; lỗi lưu sẽ được thử lại. Nếu tiến trình bị dừng đột ngột, các lần dùng chưa flush có thể chưa được ghi nhận.

Các bản cũ chưa lưu số liệu tương ứng trả `null`, được hiển thị “Chưa ghi nhận” hoặc “—”; không suy diễn thời lượng build từ thời điểm tạo job. Thống kê có trạng thái loading, empty, lỗi và nút làm mới riêng, không chặn phần cập nhật mô hình/mô phỏng.

Triển khai cả Recommendation Service, API và Admin Web từ cùng thay đổi. Không cần migration database hoặc biến môi trường mới; dùng cấu hình R2 và token quản trị đang có.
