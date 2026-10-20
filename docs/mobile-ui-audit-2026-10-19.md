# Rà soát giao diện và thao tác mobile — 19/10/2026

Nhánh làm việc: `fix/mobile`. Giữ logo hiện tại và giao diện đăng nhập/đăng ký đã lấy từ `bf75ac7` của `feature/mobile-ui`. HuAI được loại khỏi phạm vi theo yêu cầu.

## Các lỗi đã xử lý

| Khu vực | Trước | Sau |
| --- | --- | --- |
| Trình phát thu nhỏ | Material trong suốt phủ toàn bộ feed, chặn vuốt và chọn video | Material chỉ bọc thẻ video; danh sách bên dưới nhận thao tác bình thường |
| Trang xem video | Bình luận và form nhập dài đẩy gợi ý xuống dưới | Một thẻ xem trước hai dòng; chạm để mở bảng bình luận có đóng/mở và cuộn riêng |
| Video khi mở bình luận | Nội dung phát và phần bình luận dùng chung vùng cuộn | Khung phát giữ ở phía trên; bảng bình luận ban đầu nằm dưới video, mở rộng khi nhập |
| Tải bình luận/gợi ý | Chờ tải toàn bộ bình luận và dịch vụ gợi ý trước khi khởi tạo phát | Tải từng trang bình luận; gợi ý và bình luận tải độc lập với khởi tạo phát |
| Sắp xếp bình luận | Chỉ sắp xếp dữ liệu đã tải trên máy | Gửi `sort` lên API; tải thêm theo trang của thứ tự đang chọn |
| Ghim/thả tim tác giả | Chỉ đổi trạng thái tạm trên giao diện | Lưu backend, kiểm tra quyền quản lý bình luận; mỗi video có tối đa một bình luận gốc được ghim |
| Phản hồi/chỉnh sửa | Có chỗ im lặng khi API lỗi; controller có thể bị hủy khi dialog còn đóng | Hiển thị lỗi, cập nhật nội dung/số phản hồi; dialog sở hữu controller theo vòng đời widget |
| Thư viện | Cột cố định bị tràn khi chữ lớn hoặc xoay ngang | Một vùng cuộn với sliver cho tiêu đề, tab, bộ lọc và kết quả |
| Tài khoản | Nút Gần đây không xử lý; liên kết video thích mở sai tab; thông tin mặc định chứa tên mẫu | Sắp xếp playlist theo cập nhật/tên/số video; mở đúng `/liked` và `/history`; bỏ tên tài khoản mẫu |
| Tạo mới | Các nút chỉ dẫn tới trang tổng | Mở form tạo playlist, form tạo kênh, hoặc mở tải video sau khi xác định kênh quản lý |
| Form playlist | Có thể dùng TextEditingController sau khi đã dispose khi chuyển sang playlist mới | Form có State riêng, kiểm tra tên trống và giải phóng controller khi widget đóng xong |
| Studio/hồ sơ | Hàng nhãn, nút, cảnh báo và dropdown tràn ngang khi tên dài/chữ lớn | Cho nhãn xuống dòng, nút tự chuyển hàng, dropdown co theo chiều rộng |
| Phụ đề | Thẻ chật, hiển thị cố định Tiếng Việt; chỉ lấy trang video đầu | Thẻ gọn có tiêu đề/thời lượng và nút quản lý; tải đủ các trang video |
| Form và lựa chọn | Một số sheet không cuộn; một số form cộng khoảng bàn phím hai lần | Sheet lựa chọn cuộn được; bỏ khoảng bàn phím lặp ở form playlist và báo cáo |

## Phạm vi kiểm chứng

- Phân tích mã Dart trong `lib` và các bài kiểm thử mới.
- Ma trận 32 màn hình tại 320×568, 640×360 và 800×1024; cỡ chữ 1×/2×; trạng thái trống với giao diện sáng và dữ liệu tên dài với giao diện tối. Có cuộn qua nội dung.
- Kiểm thử thao tác mini-player, xem trước/mở/đóng bình luận, sắp xếp, tải trang tiếp theo, phản hồi và gửi khi bàn phím mở.
- Kiểm thử tạo playlist qua API và tự mở tải video từ trang tạo mới.
- Ba integration test trên PostgreSQL 18 tạm cho trạng thái tác giả, CRUD/sắp xếp, phản hồi/phân quyền/quản lý bình luận. Có kiểm tra hai yêu cầu ghim đồng thời.
- Ảnh kiểm tra bố cục dùng dữ liệu mô phỏng; không thay thế kiểm tra trình phát native, PiP, chọn tệp và bàn phím trên thiết bị thật.

Kết quả: **72 kiểm thử Flutter đạt, 1 smoke test bỏ qua** vì cần môi trường API/email pickup; **3 integration test backend đạt**. Analyzer không có lỗi/cảnh báo/info. Cluster PostgreSQL dùng cho kiểm thử đã được dừng và dọn.

APK debug ARM64 được cấu hình cho backend local qua USB: API `127.0.0.1:5080/api/v1`, gợi ý `127.0.0.1:8000/api/v1`. Cần kết nối điện thoại với máy và thiết lập `adb reverse` trước khi dùng. Chưa kiểm chứng bản APK trên thiết bị thật.

Nếu cài APK trực tiếp thay vì dùng `flutter run`, mở terminal PowerShell và chạy:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:5080 tcp:5080
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000
```

## Backend local cần cập nhật

Migration `20261019100000_CommentCreatorState` bổ sung `is_pinned`, `has_creator_heart` và index giới hạn một ghim/video. Kiểm thử dùng database tạm riêng; chưa áp dụng migration lên database ứng dụng local.

Từ thư mục gốc HuTube, dừng API đang chạy rồi chạy:

```powershell
. .\scripts\common.ps1
Import-LocalEnvironment
dotnet run --project backend/src/HuTube.Api --no-launch-profile -- --migrate
.\scripts\run-local.ps1 -Component api
```

Flutter trên điện thoại Android cắm USB có thể chạy ở terminal khác:

```powershell
.\scripts\run-local.ps1 -Component mobile
```

Không có thay đổi nào được commit tự động.
