# Lỗi Web được xác nhận bằng E2E

Baseline chạy binary của source gốc: `20261007T091019.257210Z`.
Baseline ghi 88 PASS, 7 FAIL, 9 REUSED rồi dừng bởi assertion ở cleanup của test
playlist. Đây là baseline chưa hoàn chỉnh; không dùng nó để kết luận toàn bộ Web.

## 1. Không xóa được email liên hệ kênh

Sau khi nhập email hợp lệ, gửi PATCH `contactEmail: ""` để xóa bị HTTP 400.
`EmailAddressAttribute` trên `UpdateChannelRequest` không cho phép chuỗi rỗng;
gửi `null` lại có nghĩa giữ nguyên theo PATCH hiện tại.

Sửa `backend/src/HuTube.Application/Channels/ChannelContracts.cs`: dùng
`OptionalEmailAddressAttribute` cho request cập nhật. Cho phép chuỗi rỗng hoặc
chỉ có khoảng trắng; email không rỗng vẫn được kiểm tra bằng validator chuẩn.

Hồi quy: `U-CHANNEL-VALIDATION-01` giữ email sai ở HTTP 400;
`U-CHANNEL-CONTACT-CLEAR-01` xóa bằng UI, PATCH 200, reload trống và GET trả null;
`U-CHANNEL-BASIC-RESTORE-01` phục hồi metadata qua API thành công.
Cleanup bằng SQL trong lần FAIL chỉ phục hồi fixture; không được tính là PASS.

## 2. Select vai trò không giữ đúng Viewer sau reload

API trả vai trò Viewer nhưng select có thể hiển thị lựa chọn đầu tiên khi danh
sách option được tải bất đồng bộ. Baseline FAIL `U-CHANNEL-ROLE-01`.

Sửa `frontend/user-web/src/app/features/channel/channel-settings-page.html`:
dùng `ngModel` và `ngModelChange` để Angular đồng bộ select với `member.roleCode`.

Hồi quy: đổi Editor sang Viewer, reload và kiểm tra giá trị select; API chặn
Viewer sửa metadata hoặc tự nâng quyền với HTTP 403. Cuối test gỡ member tạm.

## 3. Playlist riêng tư tải trước khi phiên đăng nhập được khôi phục

Mở URL playlist riêng tư trực tiếp làm request detail chạy trước khi auth restore
hoàn tất; owner nhìn thấy lỗi tải dù có quyền. Baseline ghi FAIL ở create/reload,
edit, add/remove item và đổi visibility do cùng prerequisite này.

Sửa `frontend/user-web/src/app/features/playlists/playlists-page.ts`:
`loadDetail` chờ `auth.restore()` rồi `switchMap` sang GET playlist.

Hồi quy: owner mở lại playlist riêng tư; chỉnh sửa và reload; thêm/xóa item;
đổi unlisted/public/private và đối chiếu quyền member. Member vẫn bị chặn đọc
playlist private với HTTP 403/404.

## Sửa độ tin cậy của bộ test

- Case hủy sửa playlist ban đầu dùng `to_have_text(name)` cho h1 chứa cả nút bút
  sửa, gây FAIL sai. Chỉnh kiểm tra tiêu đề chứa tên; vẫn kiểm tra tên chính xác
  qua API và giá trị form sau khi mở lại. Không sửa ứng dụng cho lỗi assertion này.
- Cleanup playlist gửi đầy đủ name/description/visibility theo hợp đồng PATCH.
- Test liên kết kênh chờ số dòng tăng/giảm sau thao tác Angular; lần chạy database
  mới phát hiện test đọc count trước khi render, dẫn đến selector index -1.
- Server static dùng backlog lớn hơn để tải nhiều chunk Angular đồng thời.
- Ghi report atomic có retry ngắn khi Windows tạm khóa file.
- Báo cáo ghi run_error nếu vòng test dừng giữa chừng; không lấy report cũ làm
  kết quả của lần chạy mới.

Kết quả hiện tại và phạm vi chưa triển khai nằm trong `WEB_E2E_PROGRESS.md`.
Các bản sửa đã build local; chưa push hoặc chạy GitHub Actions.

## Kết quả kiểm tra sau bản sửa

- Database E2E mới, run `20261007T095128.039975Z`: 107 PASS, 1 FAIL ở test
  đọc count trước khi link render, 0 REUSED. Các thao tác tạo mới được chạy thật.
- Chạy lại sau khi chỉnh bước chờ, run `20261007T095524.751804Z`: 98 PASS,
  10 REUSED, 0 FAIL, 0 BLOCKED; runner exit 0 và evidence verifier thành công.
- User: 63 PASS + 4 REUSED, tổng 67 case. Admin: 35 PASS + 6 REUSED, tổng 41.
- 34 case SMOKE chỉ kiểm tra route. Kết quả không chứng minh hoàn tất toàn bộ
  WEB_TEST_SCENARIOS.md hoặc GitHub Actions.
