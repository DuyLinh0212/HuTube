# Trang chủ giữ skeleton sau khi đăng nhập

## Nguyên nhân

`App` đổi giữa auth layout và shell layout khi nhận `NavigationEnd`. Mỗi layout có một `RouterOutlet` riêng. Khi chuyển từ `/login` sang `/home`, component Home trong auth outlet bị hủy; shell outlet tạo một Home mới sau khi sự kiện kết thúc điều hướng đã phát.

Trước bản sửa, Home chỉ khởi động tải dữ liệu từ subscription của `NavigationEnd`. Home mới không nhận lại sự kiện cũ, nên `loading` giữ nguyên `true`. Request feed của Home cũ có thể đã trả 200 nhưng không cập nhật Home mới đang hiển thị. F5 tạo layout shell ngay từ đầu, nên Home nhận được sự kiện và tải bình thường.

Đã tái hiện bằng bản production build với API giả lập trả thành công: đăng nhập qua giao diện thật dẫn tới `/home` nhưng không hiện video và vẫn còn `.feed-loading`; reload cùng trang thì video xuất hiện. Phép đo không cần Redis hoặc backend thật. Luồng feed trong backend hiện tại cũng không đọc Redis; phần Upstash/Redis nằm trong thống kê vận hành.

## Bản sửa

- Khi Home được gắn vào view sau một điều hướng `/home` đã hoàn tất, tự bắt đầu lần tải đầu tiên nếu chưa nhận sự kiện. Điều hướng đang chạy vẫn do `NavigationEnd` xử lý, tránh tải trùng trong cùng component.
- Thiếu `IntersectionObserver` chỉ tắt cuộn vô hạn, không ngăn tải feed ban đầu.
- Khi Home bị hủy, tăng phiên tải để kết quả bất đồng bộ của view cũ không tiếp tục cập nhật feed hoặc gọi tải kênh đăng ký.

## Kiểm chứng

Trước sửa, 3 trong 4 test hồi quy ban đầu thất bại. Sau sửa, toàn bộ 41 test User Web pass, gồm 5 test cho khởi tạo muộn, thiếu IntersectionObserver, điều hướng bình thường, làm mới cùng URL, lỗi cả feed chính/fallback và kết quả đến sau khi view bị hủy. Production build thành công. Kiểm tra trình duyệt login → home hiển thị video mà không cần reload; reload vẫn hoạt động.

Các kiểm tra trình duyệt dùng tài khoản/API giả lập để không thay đổi tài khoản thật. Dữ liệu tái hiện và ảnh trước/sau được lưu ngoài repository ở `.work/home-login-regression` của workspace.
