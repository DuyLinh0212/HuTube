# Kết quả kiểm tra mobile — 24/10/2026

## Phạm vi và kết quả

Đã gộp `origin/main` tại `20de970c` vào `fix/mobile` bằng merge `ea439ddd`.
Các thay đổi tiếp theo tập trung ở `mobile/user-app`; giữ cấu hình debug USB
local và hỗ trợ endpoint triển khai Dalitu từ main.

- **208 test mobile đạt, 1 test bỏ qua**; analyzer sạch và build APK debug thành công.
- **41 test tích hợp Content API đạt** trên PostgreSQL local cô lập. Database test
  do fixture tạo/xóa riêng; không chạy test ghi dữ liệu lên database ứng dụng.
- `https://api.dalitu.app/health` trả HTTP 200. Health không chứng minh mọi luồng
  đăng nhập, email, tải hoặc phát video trên server thật đã hoạt động.
- APK mới chưa được cài và kiểm tra trên điện thoại trong lượt này.

Test bị bỏ qua là `api_smoke_test.dart`: cần bật riêng API Development và email
pickup để kiểm tra đăng ký → xác minh → đăng nhập → refresh → reset → revoke.
Đây là **chưa chạy**, không phải lỗi được phát hiện. Không dùng suite mặc định
để tạo tài khoản hoặc gửi email lên server thật.

## Những thay đổi đã kiểm tra

| Nhóm | Nội dung và bằng chứng | Cần kiểm trên máy thật |
| --- | --- | --- |
| Auth và điều hướng | Validation/lỗi API chính xác, nhập link xác minh đúng origin, login Back về trang chủ, logout xác nhận; test HTTP/widget | Email và Google OAuth thật, gesture hệ thống |
| Player | Chọn video mới tự phát sau load; giữ tiến độ video xem dở; chuyển tiếp bắt đầu từ 0; thông báo phát tiếp 2 giây; không play sau dismiss | Native player, PiP, khóa máy, audio focus, phát nền |
| Đề xuất và feed | Giới hạn chờ inference, fallback/cache; các phần dữ liệu tải độc lập; bỏ phản hồi cũ; filter đề xuất canh trái | Thời gian thực tế trên mạng và server thật |
| Tải xuống | Wi-Fi only, tải thông minh tối đa 3 video và hạn mức đã chọn, chất lượng mặc định, đề xuất tải, phân quyền và chống phản hồi cũ | Đổi mạng, tải file thật, offline; tải không bảo đảm tiếp tục khi OS dừng tiến trình |
| Bình luận và playlist | Gửi/trả lời/sửa/xóa/hủy, phân trang; popup lưu playlist chung; nút tạo luôn có khi đã có playlist; xử lý video trùng | Bàn phím/IME thực tế, đồng bộ giữa thiết bị |
| Kênh và studio | Quản lý kênh mở đúng cài đặt; bộ lọc và phân trang; theo dõi kênh theo lô kèm generation guard; giữ upload cancellation | Gallery/camera, upload và resume trên mạng thật |
| Cache sau merge | Không để request cũ ghi đè cache mới sau invalidation; lịch sử tải thêm giữ từ khóa/sort/dateRange; mở settings ở sáng/tối | Làm mới và đổi tài khoản trên app thật |
| UI chung | Surface/divider trung tính; nút phụ viền xám; popup có tiêu đề/nút đóng, xác nhận xóa dùng màu lỗi; gỡ HuAI khỏi mobile | Mức chữ hệ thống, vùng gesture, theme thiết bị |

Bộ audit widget bao phủ 320×568, 640×360, 800×1024, chữ 1×/2×, dữ liệu rỗng/có
sẵn. Popup còn được kiểm tra khi có bàn phím và chữ lớn. Các ảnh render chỉ
kiểm chứng bố cục widget; không thay thế kiểm thử native trên thiết bị.

## Chạy lại

Tại `mobile/user-app`:

```powershell
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --no-pub
```

APK: `build/app/outputs/flutter-apk/app-debug.apk` (artifact build, không commit).
Sau khi merge main, mặc định APK dùng `https://api.dalitu.app/api/v1`,
`https://recommendation.dalitu.app/api/v1` và origin email `https://dalitu.app`.
Kiểm thử backend local cần ghi đè URL bằng dart-define; điện thoại USB cần
`adb reverse` cho cả hai cổng. Xem README để đổi môi trường.

Các bước chưa xác nhận được ghi trong
[MANUAL_DEVICE_TEST_CHECKLIST.md](MANUAL_DEVICE_TEST_CHECKLIST.md), đặc biệt mục 16.

Backend restore có cảnh báo NuGet sẵn có về `System.Security.Cryptography.Pkcs`
10.0.0. Chưa nâng dependency backend trong lượt mobile này.
