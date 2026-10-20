# Hoàn thiện user-web → mobile

Ngày triển khai: 19/10/2026. Nhánh: `fix/mobile`.

Phạm vi là 14 chênh lệch đã thống nhất, ưu tiên Android và giữ giao diện mobile hiện tại. Không bao gồm admin-web, tác vụ upload chạy bằng foreground service hoặc khôi phục upload sau khi hệ điều hành đóng ứng dụng.

## Chức năng đã bổ sung

| # | Chức năng | Cách dùng trên mobile |
|---|---|---|
| 1 | Tìm/lọc/sắp xếp lịch sử xem | Ô tìm kiếm, thời gian và thứ tự trên tab lịch sử; lọc ở server trước phân trang. |
| 2 | Tìm/lọc trạng thái Studio Content | Ô tìm kiếm và trạng thái; kết hợp với menu quyền hiển thị. |
| 3 | Bản nháp biểu mẫu đăng video | Menu trên màn hình đăng: lưu, khôi phục, bỏ nháp. Khi khôi phục phải chọn lại video. |
| 4 | Ngôn ngữ nội dung | Chọn ngôn ngữ khi đăng, gửi `LanguageCode` thay vì cố định `vi`. |
| 5 | Chất lượng nguồn | Nhận diện kích thước/thời lượng; chọn mức không vượt cạnh ngắn của video, kiểm tra hạn mức qua preflight. |
| 6 | Cho phép bình luận | Công tắc khi đăng, gửi `AllowComments` đến backend. |
| 7 | Tiến trình/hủy upload | Khay cấp ứng dụng hiển thị byte, %, trạng thái xử lý, hủy và thử lại. Chuyển màn hình không mất tác vụ. |
| 8 | Thumbnail từ video | Android tạo ba ảnh từ khung hình; vẫn có thể chọn ảnh từ thư viện. |
| 9 | Playlist trong luồng đăng/sửa | Chọn playlist trực tiếp; lỗi thêm playlist có thể thử lại mà không tải/lưu video lần nữa. |
| 10 | Trả lời tại Studio | Nút trả lời tại từng bình luận, dành cho người có quyền quản lý. |
| 11 | Thứ tự link kênh | Kéo bằng tay nắm hoặc dùng nút lên/xuống rồi lưu cài đặt. |
| 12 | Tìm/lọc playlist | Tìm tên không phân biệt dấu/hoa thường và lọc public/unlisted/private. |
| 13 | Nhóm video gợi ý | Chọn tất cả, liên quan hoặc cùng kênh; có trạng thái tải/lỗi/thử lại. |
| 14 | Xuất/in chính sách | Android tạo PDF ngoại tuyến và mở chia sẻ hoặc hộp thoại in hệ thống. |

## API và vòng đời dữ liệu

- `GET /api/v1/library/history` nhận thêm `q`, `sort=newest|oldest`, `dateRange=all|today|week|month`. Giữ `page`, `pageSize`, `before` và cấu trúc phản hồi. Không truyền bộ lọc mới vẫn dùng cửa sổ 30 ngày như trước. `today` dùng ngày UTC của cửa sổ truy vấn; `week` là 7 ngày gần nhất, `all`/`month` là 30 ngày.
- Tìm lịch sử theo tiêu đề video hoặc tên kênh, không phân biệt hoa thường. Đếm tổng sau khi lọc; khử trùng video và kiểm tra quyền xem trước khi trả dữ liệu.
- Các API khác giữ nguyên; mobile sử dụng thêm các trường và khả năng đã có ở backend. Không cần migration.
- Upload chỉ có một tác vụ hoạt động. Hủy dùng `Abortable` của HTTP client; giữ idempotency key qua refresh token và thử lại. Hủy truyền file không đồng nghĩa xóa một video mà server đã nhận xong.
- Đăng xuất/đổi phiên hủy tác vụ; phản hồi muộn không cập nhật tài khoản mới. Lỗi thêm playlist chỉ thử lại các playlist còn thất bại.
- Nháp nằm trong secure storage theo người dùng/kênh, có version và kiểm tra định dạng. Không lưu file video vào nháp. Hoàn tất upload chỉ xóa đúng phiên bản nháp ban đầu, giữ bản mới được lưu trong lúc upload.
- Android dùng `MediaMetadataRetriever` và API PDF/in có sẵn thay vì thêm plugin hoặc tải font khi chạy. Metadata và ảnh xử lý ngoài luồng giao diện. iOS tiếp tục dùng metadata của trình phát hiện có; trích thumbnail và xuất/in PDF mới chỉ triển khai cho Android.

## Kiểm chứng

- Kiểm tra Dart: không có lỗi/cảnh báo/info từ analyzer.
- Bổ sung 15 kiểm thử Flutter cho metadata, nháp, tìm kiếm, payload, tiến trình, refresh token, hủy HTTP thật trên localhost, idempotency, retry playlist và đổi phiên.
- Hai integration test lịch sử đã đạt trên PostgreSQL 18 tạm được tạo riêng trong workspace; cụm này đã được dừng và dọn sau khi chạy.
- Backend API và project integration test biên dịch thành công. Restore test ghi nhận cảnh báo NuGet đã có ở dependency `System.Security.Cryptography.Pkcs` 10.0.0; không thay dependency ngoài phạm vi tính năng.
- Chạy toàn bộ Flutter: **55 đạt, 1 bỏ qua**. Bài bỏ qua là smoke test cần API/email pickup đang chạy; 15 bài mới đều đạt, bao gồm hủy request HTTP localhost thật.
- Build APK debug Android đã thành công, gồm mã Kotlin cho metadata/thumbnail/PDF và bản sửa `ChaptersJson`. Artifact: `mobile/user-app/build/app/outputs/apk/debug/app-debug.apk`. Build dùng artifact Flutter/AndroidX chính thức trong cache tạm của workspace; không đổi dependency hoặc cấu hình Gradle được quản lý bởi Git.

## Kiểm tra cần thiết trên thiết bị

Môi trường hiện không có thiết bị/emulator Android kết nối. Cần thử trực tiếp chọn video ngang/dọc/có rotation, ảnh khung hình, chuyển màn hình trong khi upload, chọn ứng dụng nhận PDF và hộp thoại máy in. Build và test tự động không thay thế việc kiểm tra các tích hợp hệ điều hành này. iOS chưa được kiểm chứng trên thiết bị.
