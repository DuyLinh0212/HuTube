# Ma trận phân quyền quản trị

Chạy trên develop, bằng dữ liệu giả lập trong PostgreSQL riêng và trình duyệt thật:

```powershell
python frontend/e2e_testing/run_local.py --suite rbac
python frontend/e2e_testing/coverage/verify_rbac_evidence.py
```

Chỉ dùng `--reuse-build` khi binary API và hai bản build Angular đã cập nhật. Runner
chỉ cho phép địa chỉ loopback, tự khởi động/dừng các server của mình, tắt RabbitMQ
và FCM. Không gửi email/thông báo đến tài khoản thật. Email dùng Pickup local.

## Phạm vi

- Đối chiếu danh mục API với 50 hằng số trong `AdminPermissions`; thêm/xóa quyền
  sẽ làm test dừng để cập nhật kịch bản, không âm thầm bỏ qua quyền mới.
- Cả 50 quyền: cấp → thu hồi → cấp lại; đối chiếu quyền chính xác trong
  `/admin/me` và trạng thái trên trình biên tập role thật.
- 50 quyền gắn API: chưa đăng nhập (401), thiếu quyền trong khi vẫn có các
  quyền quản trị khác (403), được cấp quyền (2xx và đối chiếu dữ liệu lưu), thu hồi
  ngay trên token hiện hành. Với API có các quyền thay thế dạng OR, ca từ chối
  bỏ toàn bộ quyền thay thế; ca được phép chỉ cấp quyền đang kiểm tra và quyền
  nền cần thiết. Các quyết định duyệt/từ chối/chuyển cấp được kiểm tra riêng.
- `video.view_private`: giữ `video.view`, thiếu quyền xem riêng tư phải trả 404,
  có quyền trả đúng video private. Không coi 404 này là thành công nghiệp vụ.
- 16 trang quản trị: quyền tối thiểu mở được trang; thiếu quyền chuyển
  `/forbidden`, không dựng component bảo vệ.
- Kiểm tra ẩn/hiện nút thao tác khi giữ quyền xem cho role, gói, chính sách,
  taxonomy, strike và khóa kênh.
- Chặn cấp quyền mình không có, bảo vệ role hệ thống, chỉ Super Admin nhìn/gán
  role User. Xóa role có người dùng: bắt buộc lý do, hủy không thay đổi dữ liệu,
  xác nhận xóa mềm và gỡ role, mất truy cập admin, có thể gán lại sau.

Các ca từ chối kiểm tra snapshot dữ liệu nghiệp vụ không thay đổi. Audit từ chối
quyền vẫn được phép ghi. Chuẩn bị fixture qua SQL chỉ dùng CSDL local do runner
sở hữu; hành động được kiểm tra phải đi qua API thật. Không mock bộ kiểm tra quyền.

## Các chức năng bổ sung cho sáu quyền còn thiếu

Các mã sau đã có chức năng, API và kiểm tra giao diện riêng:

`channel.edit`, `channel.strike`, `channel.remove_strike`, `channel.export`,
`video.strike`, `video.export`.

- `PUT /admin/channels/{id}/metadata`: sửa tên, mô tả, email liên hệ, bắt buộc
  lý do, lưu audit; giữ handle và chủ sở hữu.
- `POST /admin/channels/{id}/strikes`: áp dụng cảnh cáo bằng quyền `channel.strike`.
- `GET /admin/channels/{id}/strikes` và `POST /admin/channels/{id}/strikes/{strikeId}/revoke`:
  liệt kê/gỡ cảnh cáo của đúng kênh bằng `channel.remove_strike`.
- `POST /admin/videos/{id}/strikes`: áp dụng cảnh cáo cho kênh sở hữu video,
  ghi audit liên kết video và cảnh cáo, kiểm tra mức độ/lý do.
- `GET /admin/channels/export` và `/admin/videos/export`: API kiểm tra quyền
  xuất riêng, giữ bộ lọc, đọc toàn bộ các trang trong snapshot nhất quán.
  Video riêng tư chỉ xuất khi có thêm `video.view_private`. Web tải CSV trực tiếp,
  giữ cơ chế chống công thức trong ô CSV.

Test bổ sung kiểm tra 105 hàng có cùng thời điểm tạo qua ranh giới trang 100,
không trùng/mất ID; ẩn/hiện private; CSV theo bộ lọc và trung hòa công thức;
không được gỡ strike của kênh khác; xác thực và audit các thao tác mới.
`catalogue_only_permissions` trong báo cáo cuối phải rỗng.

## Bằng chứng và CI

Mỗi ca có ID ổn định, permission, tầng kiểm tra, trạng thái và ảnh chụp. File
`artifacts/rbac-latest.json` trỏ đến lần chạy gần nhất; `rbac-coverage.json` ghi
HTTP method/path/status cho các ca API (không lưu token). Kết quả Web cũ trong
`web-latest.json` được giữ riêng. CI chạy ma trận và kiểm tra không thiếu ca,
không reuse kết quả cũ, không mất ảnh, không có ca lỗi/bị chặn.

Không coi kiểm tra quyền là kiểm thử toàn bộ tổ hợp nghiệp vụ của từng tính năng.
Ví dụ kiểm thử phân quyền xem thanh toán không tạo giao dịch ngân hàng thật.
