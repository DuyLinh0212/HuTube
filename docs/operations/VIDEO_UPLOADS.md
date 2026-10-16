# Tải video trên User Web

## Luồng tải lên

- Web gia hạn access token trước khi tạo phiên, gửi từng phần và hoàn tất nếu token còn dưới 2 phút. Refresh dùng cơ chế chia sẻ request/khóa trình duyệt hiện có.
- `POST /api/v1/videos/upload-sessions` kiểm tra quyền và quota bằng upload preflight, nhận `uploadId` do web tạo cùng metadata file. Máy chủ trả kích thước phần 8 MiB và `nextChunk` đã nhận.
- `POST /api/v1/videos/upload-sessions/{uploadId}/chunks/{index}` nhận từng phần tuần tự. Gửi lại phần đã nhận không ghi thêm dữ liệu. Web thử lại tối đa 2 lần cho mất kết nối, 429, 502, 503 hoặc 504; sau đó hiện lỗi cùng nút **Thử lại**.
- `POST /api/v1/videos/upload-sessions/{uploadId}/complete` nhận metadata và thumbnail, kiểm tra đủ byte, xác nhận đúng tài khoản/kênh, rồi gọi luồng tạo video hiện có. Luồng này kiểm tra lại quyền, quota, file media, chương và các video liên quan. `uploadId` cũng là idempotency key để lần hoàn tất gửi lại không tạo thêm video.
- Video gốc được lưu trước, các chất lượng thấp chạy bằng hàng đợi nền hiện có. Request không chờ encode toàn bộ. Worker khôi phục rendition đang xử lý từ database/R2 sau khi khởi động lại.
- **Hủy** dừng request phía web và yêu cầu xóa file tạm. File tạm không phải video đã lưu trên R2. Khi lỗi, phiên còn được giữ cho nút **Thử lại**; bấm X hủy phiên đó.

Mỗi tài khoản có tối đa 2 phiên chưa hoàn tất, file tạm có thời hạn 2 giờ không hoạt động. Phiên tạm nằm trên một instance API; web chỉ tiếp tục từ phần cũ nếu phiên đó còn tồn tại. Tải lại trang làm mất File của trình duyệt; Render restart/redeploy làm mất phiên trong bộ nhớ. Trường hợp này cần chọn/tải lại file. File tạm bỏ lại được dọn định kỳ. Không xem đây là cơ chế lưu trữ upload bền vững hoặc hỗ trợ nhiều replica.

## Triển khai

1. Deploy backend từ `main` trước, rồi deploy User Web từ cùng phiên bản. Backend cũ thiếu `/videos/upload-sessions` sẽ trả 404; web hiển thị thông báo tính năng đang cập nhật. Không có migration mới.
2. CORS dùng danh sách origin rõ ràng từ `Auth__WebBaseUrl`, `Auth__AdminBaseUrl`, `Auth__AllowedOrigins__*`, cho phép header auth/client và credentials. `UseRouting` chạy trước `UseCors`, CORS chạy trước auth.
3. `VideoProcessing__Threads` mặc định **2**, kẹp trong khoảng 1–8; áp dụng cho decode/encode, filter dùng 1 thread. Có thể đặt **1** trên instance ít RAM. Không cần vô hiệu hóa quota, moderation hoặc xác thực.
4. Kiểm tra runtime logs khi lỗi: 401 là phiên đăng nhập, 403 là quyền/hạn chế, 409 có thể là quota/phiên/phần chưa đủ, 507 là ổ đĩa tạm. Lỗi CORS ở browser cũng có thể xuất hiện khi gateway hoặc instance ngắt kết nối; cần đối chiếu status/log của API.
