# Rà soát hiệu năng và độ ổn định mobile — 20/10/2026

Nhánh làm việc: `fix/mobile`. Giữ lại các thay đổi có sẵn; không commit, không sửa HuAI hoặc logo.

## Phạm vi kiểm tra

- Phân tích tĩnh toàn bộ `mobile/user-app/lib` (94 file Dart) và bộ kiểm thử hồi quy mới.
- Đọc, đối chiếu các luồng tải trang chủ, khám phá/feed, tìm kiếm, đăng ký kênh, thông báo, tài khoản, phát video online/offline, upload và download. Tập trung vào tác vụ bất đồng bộ, vòng đời controller/listener, phân trang và số lần dựng lại giao diện.
- Chạy toàn bộ bộ kiểm thử Flutter, gồm các luồng chức năng đã có và kiểm tra bố cục 32 màn hình ở 320×568, 640×360, 800×1024; cỡ chữ 1×/2×; giao diện sáng với dữ liệu rỗng và giao diện tối với dữ liệu mẫu. Ma trận gồm 384 tổ hợp màn hình, có cuộn để kiểm tra phần dưới.

## Những thay đổi đã thực hiện

| Khu vực | Vấn đề | Cách sửa |
| --- | --- | --- |
| Trang chủ | Gọi API lần lượt; gợi ý chậm giữ lại cả nội dung công khai | Tải các mục song song, cập nhật từng mục ngay khi có kết quả; lỗi một mục không che các mục còn lại |
| Trang chủ | Phản hồi của lần refresh/tài khoản cũ có thể ghi đè dữ liệu | Gắn thế hệ yêu cầu và phiên đăng nhập; tải lại khi danh tính thay đổi; gỡ listener khi đóng màn hình |
| Danh sách video | Tạo sẵn toàn bộ widget cho trang chủ, feed và kết quả tìm kiếm | Dùng sliver với builder để dựng thẻ khi đến gần vùng nhìn thấy; giới hạn kích thước giải mã thumbnail ở rail trang chủ |
| Tìm kiếm | Đã có kết quả video nhưng còn phải đợi truy vấn kênh tùy chọn | Hiện video trước; truy vấn kênh riêng và bỏ qua kết quả cũ |
| Trình phát | Mỗi sự kiện thời gian đều gọi dựng lại Flutter | Giữ vị trí chính xác trong session, giới hạn thông báo tiến độ khoảng 4 lần/giây; bỏ sự kiện trạng thái/thời lượng không thay đổi |
| Trình phát | Chuyển video nhanh có thể tạo controller cho yêu cầu cũ | Kiểm tra thế hệ yêu cầu trước khi tạo controller; đóng trình phát vô hiệu hóa yêu cầu đang chờ; ID controller mới cho mỗi phiên |
| Trình phát | Lưu tiến độ mạng lỗi có thể thành lỗi bất đồng bộ không được xử lý | Bắt lỗi tác vụ nền; giới hạn một checkpoint định kỳ đang gửi; không lưu checkpoint cho phiên tài khoản đã thay đổi |
| Trình phát | Sự kiện gần cuối video lặp có thể chuyển video/seek nhiều lần | Chốt sự kiện hoàn thành đến khi vị trí rời vùng cuối; bỏ timer cũ có thể tác động sang phiên mới |
| Hàng đợi phát | Xóa video trước video đang phát làm lệch chỉ số | Điều chỉnh chỉ số để giữ đúng video hiện tại và video kế tiếp |
| Download | Mỗi chunk tải về ghi/flush manifest và thông báo dựng lại UI | Chỉ cập nhật tiến độ tối đa khoảng 5 lần/giây; không ghi manifest cho từng chunk; vẫn lưu các chuyển trạng thái và kết quả hoàn tất |
| Đăng ký kênh | Đổi kênh trong lúc request cũ còn chờ có thể hiện nhầm video | Chụp bộ lọc tại lúc gửi, dùng thế hệ yêu cầu, cho refresh thay thế phân trang cũ |
| Đăng ký kênh | Thanh chọn kênh có thể tràn chiều cao khi có dữ liệu | Tăng không gian theo cỡ chữ và giới hạn nhãn nút tất cả trên một dòng |
| Thông báo | Bấm tải thêm liên tục tạo request/trùng bản ghi | Khóa tải thêm trong lúc chờ, bỏ phản hồi cũ và loại trùng theo notification ID |
| Tạo kênh | Hủy debounce không hủy được HTTP request đã gửi | Dùng thế hệ kiểm tra handle để kết quả cũ không thay trạng thái handle mới |
| Xem offline | Giữ listener tài khoản sau khi rời màn hình; có thể mở player sau khi đổi tài khoản | Gỡ listener, dọn background guard, kiểm tra phiên sau các bước await và trước khi load file |
| Tài khoản | Request kết thúc sau khi controller bị dispose vẫn gọi notify | Chặn notify sau dispose để không phát sinh lỗi vòng đời |

## Kiểm thử hồi quy bổ sung

File `mobile/user-app/test/mobile_performance_test.dart` có 13 ca:

1. Màn hình offline gỡ listener khi đóng.
2. Tải hồ sơ hoàn tất sau khi controller bị dispose.
3. Trang chủ có nội dung công khai trong lúc gợi ý còn chờ; chỉ dựng một phần thẻ video.
4. Refresh trang chủ bỏ phản hồi cũ.
5. Tìm kiếm hiển thị video trước khi truy vấn kênh kết thúc.
6. Kiểm tra handle bỏ kết quả cho nội dung đã nhập trước đó.
7. Bấm tải thêm thông báo nhiều lần chỉ gửi một request và không nhân đôi bản ghi.
8. Hai yêu cầu phát chồng nhau chỉ giữ video mới nhất; đóng player hủy yêu cầu đang chờ; mở lại cùng video dùng controller ID mới.
9. API lưu tiến độ trả 503 không phát tán lỗi bất đồng bộ.
10. Chuyển kênh đăng ký nhanh bỏ kết quả của kênh cũ.
11. Gửi 40 sự kiện thời gian native trong một giây: session nhận đúng vị trí, số thông báo dựng lại không quá 5; sự kiện cuối liên tiếp chỉ gọi hoàn thành một lần.
12. Xóa phần tử đứng trước video hiện tại vẫn giữ đúng chỉ số hàng đợi.
13. Tải 1.000 chunk: file đủ byte, số lượt cập nhật UI dưới 20 và số lần lấy thư mục để ghi dữ liệu dưới 12, thay vì phát sinh theo từng chunk.

Các ca native dùng mock platform channel; ca download dùng HTTP giả lập và ghi file thật trong thư mục tạm, có dọn dẹp. Đây là kiểm tra hành vi và mức công việc phát sinh, không phải đo FPS hoặc benchmark trên điện thoại.

## Kết quả và giới hạn

- Toàn bộ Flutter: **85 đạt, 1 bỏ qua**, không có ca thất bại. Ca bỏ qua là smoke test API thật cần cấu hình môi trường.
- Analyzer toàn bộ `lib` và kiểm thử mới: **No issues found**.
- `git diff --check` cho mã mobile: đạt.
- APK Android debug ARM64: **build thành công**, mã thoát Gradle 0. File `mobile/user-app/build/app/outputs/apk/debug/app-debug.apk`, 129.674.332 byte; đã kiểm tra APK chứa thay đổi guard playback mới, thư viện ARM64 và cấu hình API local.
- APK dùng API `http://127.0.0.1:5080/api/v1` và recommender `http://127.0.0.1:8000/api/v1`, phục vụ chạy local qua USB với `adb reverse`; đây không phải bản cấu hình production. Thông báo `adb reverse ... thành công` của hook build không xác nhận thiết bị đã kết nối: đầu ra ADB thực tế báo không có thiết bị.
- ADB không có thiết bị hoặc emulator kết nối. Chưa kiểm chứng thao tác trên điện thoại thật, FPS, bộ nhớ, nhiệt độ, mất mạng thực, PiP/đổi hướng native, và iOS.
- Các luồng API trong bộ test Flutter dùng dữ liệu giả lập. Kết quả này không thay thế kiểm thử đầu cuối với backend và tài khoản thực, thanh toán thực hay OAuth thực.

Không thể kết luận ứng dụng tuyệt đối không có lỗi trên mọi thiết bị từ kiểm thử tự động. Các thay đổi này xử lý những vấn đề cụ thể đã tìm thấy và được bộ test xác nhận, đồng thời giữ nguyên HuAI.

Log xác minh nằm trong thư mục `.work` của workspace: `mobile-performance-analyze-final.log`, `mobile-performance-verified.log`, `mobile-performance-build.log`.
