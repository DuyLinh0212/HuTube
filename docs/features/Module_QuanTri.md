# 2.2. Module chức năng nhóm quản trị

> **Phạm vi:** Module dành cho Web Quản trị của hệ thống HuTube.  
> **Bản này được chuẩn hóa và mở rộng từ tài liệu gốc**, bổ sung các chức năng quản trị nhỏ, các trạng thái xử lý, cơ chế phân quyền, nhật ký, kiểm duyệt, báo cáo, khiếu nại, thanh toán và cấu hình hệ thống để có thể dùng làm cơ sở thiết kế Use Case, API và giao diện.
>
> **Nguyên tắc:** mọi thao tác có khả năng làm thay đổi dữ liệu, quyền truy cập, trạng thái nội dung, gói dịch vụ hoặc quyết định kiểm duyệt đều phải được kiểm tra quyền và ghi Audit Log.

---

## 2.2.1. Quy định chung về giao diện quản trị

### A. Layout

- Giao diện Responsive, ưu tiên Desktop/Tablet.
- Sidebar:
  - Có thể đóng/mở.
  - Hiển thị menu theo quyền của tài khoản quản trị.
  - Nhóm menu theo nghiệp vụ.
  - Highlight chức năng hiện tại.
  - Hỗ trợ submenu.
- Top bar:
  - Avatar quản trị viên.
  - Tên hiển thị.
  - Role hiện tại.
  - Thông báo hệ thống.
  - Đổi mật khẩu.
  - Đăng xuất.
- Breadcrumb để xác định vị trí hiện tại.
- Trang chi tiết có nút quay lại danh sách.
- Hỗ trợ Dark/Light Theme nếu hệ thống tổng thể có theme.

### B. Quy định chung cho màn hình danh sách

Các màn hình danh sách phải hỗ trợ khi phù hợp:

- Tìm kiếm theo từ khóa.
- Bộ lọc nâng cao.
- Sắp xếp tăng/giảm.
- Phân trang.
- Chọn số bản ghi/trang.
- Chọn nhiều bản ghi.
- Thao tác hàng loạt nếu nghiệp vụ cho phép.
- Export CSV/XLSX đối với dữ liệu được phép xuất.
- Refresh dữ liệu.
- Giữ bộ lọc khi quay lại từ trang chi tiết.
- Hiển thị:
  - Loading.
  - Empty state.
  - Error state.
  - No permission state.
- Xác nhận trước thao tác nguy hiểm.
- Yêu cầu nhập lý do đối với:
  - Ban.
  - Gỡ nội dung.
  - Đánh strike.
  - Khóa kênh.
  - Thay đổi gói thủ công.
  - Hoàn tiền.
  - Thay đổi quyền.
- Không hiển thị chức năng mà tài khoản hiện tại không có quyền sử dụng.

### C. Quy định trạng thái dữ liệu

Các đối tượng quan trọng phải ưu tiên **Soft Delete** thay vì xóa vật lý ngay lập tức, bao gồm:

- User.
- Channel.
- Video.
- Comment.
- Plan.
- Role.
- Policy.
- Category/Tag.

Dữ liệu đã xóa mềm phải có:

- `DeletedAt`.
- `DeletedBy`.
- `DeleteReason`.
- Khả năng khôi phục nếu nghiệp vụ cho phép.

---

# 2.2.2. Tổng quan - Dashboard

## A. Thẻ thống kê nhanh

Hiển thị tối thiểu:

- Tổng số người dùng.
- Người dùng mới hôm nay.
- Người dùng hoạt động.
- Tổng số kênh.
- Kênh mới.
- Tổng số video.
- Video mới.
- Video đang chờ kiểm duyệt.
- Tổng số báo cáo chưa xử lý.
- Tổng số khiếu nại chưa xử lý.
- Tổng số subscription đang hoạt động.
- Doanh thu hôm nay.
- Doanh thu tháng hiện tại.
- Số tài khoản/kênh đang bị hạn chế.

## B. Biểu đồ nhanh

- Tăng trưởng user theo thời gian.
- Tăng trưởng channel.
- Số video đăng tải.
- Lượt xem.
- Like/Dislike.
- Comment.
- Share.
- Doanh thu.
- Số report.
- Số nội dung bị xử lý.
- Số strike phát sinh.

Cho phép chọn:

- 7 ngày.
- 30 ngày.
- 90 ngày.
- Tháng hiện tại.
- Năm hiện tại.
- Khoảng thời gian tùy chọn.

## C. Hàng đợi cần xử lý

- Video chờ duyệt.
- Report mới.
- Appeal mới.
- Thanh toán lỗi cần kiểm tra.
- Tài khoản/kênh có số lượng report tăng bất thường.

## D. Điều hướng nhanh

Shortcut đến:

- User.
- Channel.
- Video Moderation.
- Report.
- Appeal.
- Plan.
- Payment.
- Analytics.
- Audit Log.

---

# 2.2.3. Quản lý người dùng

## A. Danh sách người dùng

Hiển thị:

- User ID.
- Avatar.
- Tên hiển thị.
- Email.
- Trạng thái tài khoản.
- Gói hiện tại.
- Ngày đăng ký.
- Lần hoạt động gần nhất.
- Kênh sở hữu.
- Số strike hiện tại.
- Số report liên quan.
- Role hệ thống nếu có.

Bộ lọc:

- Trạng thái.
- Gói.
- Có/không có kênh.
- Ngày đăng ký.
- Số strike.
- Role.
- Tình trạng xác thực email.
- Khoảng thời gian hoạt động gần nhất.

## B. Chi tiết người dùng

### 1. Thông tin cơ bản

- User ID.
- Avatar.
- Tên hiển thị.
- Email.
- Email đã xác thực hay chưa.
- Ngày tạo tài khoản.
- Lần đăng nhập gần nhất.
- Trạng thái tài khoản.
- Gói đang sử dụng.
- Ngày bắt đầu/hết hạn gói.
- Dung lượng đã sử dụng.
- Dung lượng còn lại.

### 2. Thông tin hoạt động

- Lịch sử đăng nhập.
- Lịch sử online.
- Thời lượng hoạt động theo ngày.
- Biểu đồ thời gian hoạt động.
- Lịch sử xem.
- Lịch sử tìm kiếm.
- Video đã like/dislike.
- Comment gần đây.
- Lịch sử report đã gửi.
- Lịch sử subscription/payment nếu được phép xem.

### 3. Thông tin xã hội

- Số người đăng ký.
- Số người đang theo dõi.
- Danh sách channel sở hữu.
- Thông tin channel chính.
- Tổng lượt xem nội dung của người dùng.

### 4. Thông tin vi phạm

- Tổng số report nhận được.
- Tổng số report hợp lệ.
- Warning.
- Strike đang hiệu lực.
- Strike đã hết hiệu lực.
- Lịch sử strike.
- Nội dung từng bị gỡ/ẩn.
- Lịch sử ban/suspend.
- Appeal liên quan.

## C. Thao tác quản trị user

- Chỉnh sửa thông tin cho phép.
- Xác minh email thủ công nếu có quy trình nội bộ.
- Thay đổi Plan.
- Gia hạn Plan.
- Hủy subscription thủ công.
- Khóa tài khoản tạm thời.
- Ban tài khoản.
- Unban.
- Đặt thời gian hết hạn ban.
- Ghi lý do ban.
- Buộc đăng xuất toàn bộ phiên.
- Thu hồi Refresh Token.
- Gửi email đến email đã xác thực.
- Gửi thông báo trong hệ thống.
- Gắn ghi chú nội bộ.
- Xem Audit History liên quan đến user.

> Không cho Admin xem mật khẩu, access token, refresh token hoặc thông tin xác thực nhạy cảm ở dạng rõ.

---

# 2.2.4. Vai trò và phân quyền

Hệ thống sử dụng **RBAC - Role Based Access Control**.

## A. Thành phần

- **User:** tài khoản hệ thống.
- **Admin Account:** user có quyền truy cập Web Quản trị.
- **Role:** nhóm quyền.
- **Permission:** quyền nhỏ nhất.
- Một Admin có thể có một hoặc nhiều Role.
- Một Role chứa nhiều Permission.
- Permission được kiểm tra ở:
  - Giao diện.
  - API.
  - Application/Service layer.

## B. Role hệ thống đề xuất

### 1. Super Admin

- Có toàn bộ quyền.
- Quản lý Admin.
- Quản lý Role/Permission.
- Cấu hình hệ thống.
- Không được xóa Role hệ thống bắt buộc.

### 2. Administrator

- Quản lý User.
- Channel.
- Plan.
- Content.
- Report.
- Không được chỉnh quyền của Super Admin.

### 3. Moderator

- Kiểm duyệt Video.
- Comment.
- Report.
- Strike.
- Appeal.
- Không được truy cập cấu hình hệ thống và tài chính nếu không được cấp thêm quyền.

### 4. Support

- Xem User.
- Xem Channel.
- Xem Subscription.
- Gửi email/thông báo hỗ trợ.
- Xem lịch sử xử lý.
- Không có quyền ban/gỡ nội dung mặc định.

### 5. Finance

- Xem Plan.
- Subscription.
- Payment.
- Refund.
- Revenue Analytics.

### 6. Analyst

- Chỉ xem dữ liệu thống kê.
- Export dữ liệu được cho phép.
- Không thay đổi dữ liệu nghiệp vụ.

### 7. Auditor

- Chỉ xem Audit Log.
- Xem lịch sử moderation.
- Xem lịch sử thay đổi quyền.
- Không có quyền chỉnh sửa.

## C. Quy tắc Role

- Tạo Role.
- Sửa tên Role.
- Sửa mô tả.
- Bật/tắt Role.
- Xóa mềm Role.
- Clone Role.
- Gán Permission.
- Gỡ Permission.
- Thêm Admin vào Role.
- Gỡ Admin khỏi Role.
- Xem danh sách Admin thuộc Role.
- Xem số Permission của Role.
- Xem lịch sử thay đổi quyền.

Role hệ thống quan trọng có thể đặt:

```text
IsSystemRole = true
```

để chặn xóa.

---

## D. Danh mục Permission đề xuất

> **Tổng cộng: 100 Permission chi tiết.**  
> Đây là bộ quyền cơ sở đề xuất. Có thể tăng/giảm khi chốt Use Case và API.

### Nhóm 1 - Dashboard: 2 quyền

1. `dashboard.view`
2. `dashboard.export`

### Nhóm 2 - User: 11 quyền

3. `user.view`
4. `user.view_activity`
5. `user.view_history`
6. `user.edit`
7. `user.change_plan`
8. `user.suspend`
9. `user.ban`
10. `user.unban`
11. `user.force_logout`
12. `user.send_message`
13. `user.export`

### Nhóm 3 - Role & Permission: 9 quyền

14. `role.view`
15. `role.create`
16. `role.edit`
17. `role.delete`
18. `role.clone`
19. `role.assign_permission`
20. `role.remove_permission`
21. `role.assign_user`
22. `role.remove_user`

### Nhóm 4 - Channel: 9 quyền

23. `channel.view`
24. `channel.edit`
25. `channel.suspend`
26. `channel.ban`
27. `channel.unban`
28. `channel.strike`
29. `channel.remove_strike`
30. `channel.delete`
31. `channel.export`

### Nhóm 5 - Video: 9 quyền

32. `video.view`
33. `video.view_private`
34. `video.edit_metadata`
35. `video.hide`
36. `video.unhide`
37. `video.remove`
38. `video.restore`
39. `video.strike`
40. `video.export`

### Nhóm 6 - Comment: 7 quyền

41. `comment.view`
42. `comment.hide`
43. `comment.unhide`
44. `comment.remove`
45. `comment.restore`
46. `comment.strike`
47. `comment.export`

### Nhóm 7 - Moderation: 8 quyền

48. `moderation.view_queue`
49. `moderation.claim`
50. `moderation.review`
51. `moderation.approve`
52. `moderation.reject`
53. `moderation.escalate`
54. `moderation.view_history`
55. `moderation.reopen`

### Nhóm 8 - Report: 9 quyền

56. `report.view`
57. `report.claim`
58. `report.review`
59. `report.resolve`
60. `report.dismiss`
61. `report.escalate`
62. `report.reopen`
63. `report.contact_reporter`
64. `report.export`

### Nhóm 9 - Appeal: 6 quyền

65. `appeal.view`
66. `appeal.claim`
67. `appeal.review`
68. `appeal.approve`
69. `appeal.reject`
70. `appeal.escalate`

### Nhóm 10 - Plan & Subscription: 7 quyền

71. `plan.view`
72. `plan.create`
73. `plan.edit`
74. `plan.delete`
75. `subscription.view`
76. `subscription.change`
77. `subscription.cancel`

### Nhóm 11 - Payment: 6 quyền

78. `payment.view`
79. `payment.view_detail`
80. `payment.refund`
81. `payment.retry`
82. `payment.export`
83. `revenue.view`

### Nhóm 12 - Policy: 5 quyền

84. `policy.view`
85. `policy.create`
86. `policy.edit`
87. `policy.publish`
88. `policy.archive`

### Nhóm 13 - Category & Tag: 4 quyền

89. `taxonomy.view`
90. `taxonomy.create`
91. `taxonomy.edit`
92. `taxonomy.delete`

### Nhóm 14 - Notification: 3 quyền

93. `notification.view`
94. `notification.send`
95. `notification.manage_template`

### Nhóm 15 - Analytics: 2 quyền

96. `analytics.view`
97. `analytics.export`

### Nhóm 16 - Audit Log: 1 quyền

98. `audit.view`

### Nhóm 17 - System: 2 quyền

99. `system.view_setting`
100. `system.edit_setting`

---

# 2.2.5. Quản lý kênh

## A. Danh sách kênh

Hiển thị:

- Channel ID.
- Avatar.
- Tên kênh.
- Chủ sở hữu.
- Ngày tạo.
- Trạng thái.
- Số subscriber/follower.
- Tổng video.
- Tổng lượt xem.
- Tổng report.
- Strike hiện tại.
- Dung lượng đã dùng.
- Dung lượng còn lại.

Bộ lọc:

- Ngày tạo.
- Trạng thái.
- Số follower.
- Tổng lượt xem.
- Tổng video.
- Số strike.
- Số report.
- Dung lượng sử dụng.

Sắp xếp theo:

- Ngày tạo.
- Follower.
- Lượt xem.
- Số video.
- Report.
- Strike.
- Dung lượng.

## B. Chi tiết kênh

- Channel ID.
- Tên.
- Avatar/Banner.
- Mô tả.
- Chủ sở hữu.
- Ngày tạo.
- Trạng thái.
- Subscriber/Follower.
- Tổng video.
- Tổng lượt xem.
- Tổng like.
- Like trung bình/video.
- Comment trung bình/video.
- Tần suất đăng video.
- Biểu đồ hoạt động.
- Dung lượng:
  - Tổng quota.
  - Đã dùng.
  - Còn lại.
- Report.
- Warning.
- Strike.
- Lịch sử moderation.

## C. Thao tác

- Edit metadata nếu được phép.
- Suspend.
- Ban.
- Unban.
- Đánh strike.
- Gỡ strike.
- Xóa mềm channel.
- Khôi phục channel.
- Gửi cảnh báo.
- Gửi email/thông báo cho chủ kênh.
- Ghi chú nội bộ.

## D. Xem nội dung kênh

- Danh sách video.
- Chọn video.
- Mở video trên Web User bằng URL.
- Nếu quản trị viên không có phiên User thì hiển thị theo quyền của Guest.
- Không giả mạo đăng nhập dưới danh nghĩa chủ kênh.

---

# 2.2.6. Quản lý video

Ngoài hàng đợi kiểm duyệt, Admin cần màn hình quản lý toàn bộ video.

## A. Danh sách

- Video ID.
- Thumbnail.
- Tiêu đề.
- Channel.
- Người đăng.
- Chủ đề.
- Tag.
- Visibility.
- Trạng thái moderation.
- Ngày đăng.
- Lượt xem.
- Like.
- Comment.
- Report.
- Strike liên quan.

## B. Bộ lọc

- Channel.
- User.
- Chủ đề.
- Tag.
- Visibility.
- Trạng thái.
- Ngày đăng.
- Số report.
- Số lượt xem.
- Có/không có strike.

## C. Thao tác

- Xem chi tiết.
- Phát video trong Web Admin.
- Xem metadata.
- Xem lịch sử chỉnh sửa.
- Ẩn.
- Bỏ ẩn.
- Gỡ.
- Khôi phục.
- Đánh strike.
- Gửi cảnh báo.
- Mở hồ sơ Channel/User.
- Xem report liên quan.
- Xem moderation history.

---

# 2.2.7. Quản lý bình luận

## A. Danh sách comment

- Comment ID.
- Nội dung.
- User.
- Video.
- Channel.
- Ngày tạo.
- Like.
- Reply count.
- Report count.
- Trạng thái.

## B. Bộ lọc

- User.
- Video.
- Channel.
- Thời gian.
- Có report.
- Trạng thái.
- Từ khóa.

## C. Thao tác

- Xem context của comment.
- Xem thread.
- Xem hồ sơ người comment.
- Ẩn.
- Bỏ ẩn.
- Xóa mềm.
- Khôi phục.
- Đánh cảnh cáo/strike nếu chính sách cho phép.
- Xem report liên quan.

---

# 2.2.8. Quản lý Plan và Subscription

## A. Quản lý Plan

Thông tin Plan:

- Plan ID.
- Tên Plan.
- Mô tả.
- Giá.
- Chu kỳ thanh toán.
- Dung lượng tối đa.
- Số lượng video/giới hạn nếu có.
- Chất lượng video tối đa.
- Các tính năng nâng cao.
- Trạng thái.
- Thứ tự hiển thị.
- Ngày tạo.
- Ngày cập nhật.

Thao tác:

- Thêm Plan.
- Sửa.
- Clone.
- Bật/tắt.
- Xóa mềm.
- Khôi phục.
- Xem số subscriber.
- Không cho xóa vật lý Plan đã từng được sử dụng.

## B. Subscription

- Danh sách subscription.
- User.
- Plan.
- Ngày bắt đầu.
- Ngày hết hạn.
- Auto-renew.
- Trạng thái.
- Payment gần nhất.
- Lịch sử đổi gói.
- Upgrade.
- Downgrade.
- Cancel.
- Gia hạn thủ công khi được phép.

---

# 2.2.9. Quản lý thanh toán và doanh thu

## A. Payment

- Transaction ID.
- User.
- Plan.
- Số tiền.
- Phương thức:
  - MoMo.
  - ZaloPay.
  - VNPay.
  - Các phương thức khác khi mở rộng.
- Thời gian.
- Trạng thái.
- Gateway Transaction ID.
- Nội dung lỗi nếu thất bại.

## B. Thao tác

- Xem chi tiết giao dịch.
- Kiểm tra trạng thái.
- Retry nghiệp vụ phù hợp.
- Refund nếu gateway hỗ trợ.
- Ghi lý do refund.
- Xem lịch sử refund.
- Export giao dịch.

## C. Doanh thu

- Tổng doanh thu.
- Doanh thu theo ngày/tháng/năm.
- Doanh thu theo Plan.
- Số subscription mới.
- Upgrade/Downgrade.
- Cancel rate.
- Payment success rate.
- Payment failure rate.
- Refund amount.

---

# 2.2.10. Kiểm duyệt video

## A. Moderation Queue

Hiển thị theo FIFO mặc định:

- Video chờ lâu nhất ở trên.
- Có thể ưu tiên:
  - Video có nhiều report.
  - Video từ channel có lịch sử vi phạm.
  - Nội dung được hệ thống đánh dấu rủi ro cao.

## B. Trạng thái

- `Pending`.
- `InReview`.
- `Escalated`.
- `Approved`.
- `Rejected`.

## C. Thông tin khi duyệt

- Video.
- Thumbnail.
- Metadata.
- Channel.
- User.
- Ngày upload.
- Chủ đề.
- Tag.
- Report liên quan.
- Vi phạm trước đó.
- Policy hiện hành.

## D. Quy trình

1. Moderator nhận case.
2. Case chuyển sang `InReview`.
3. Xem video trực tiếp.
4. Đối chiếu Policy.
5. Checkbox một hoặc nhiều điều khoản vi phạm.
6. Ghi chú nội bộ.
7. Chọn quyết định:
   - Approve.
   - Reject.
   - Hide.
   - Remove.
   - Warning.
   - Strike.
   - Escalate.
8. Gửi thông báo kết quả.
9. Ghi Moderation History.
10. Ghi Audit Log.

## E. Chức năng bổ sung

- Claim case để tránh hai Moderator xử lý cùng lúc.
- Release case.
- Chuyển case cho Moderator khác.
- Escalate cho cấp cao hơn.
- Reopen case.
- Lọc theo:
  - Thời gian.
  - Chủ đề.
  - Tag.
  - Channel.
  - Reporter count.
  - Risk level.
  - Moderator.
  - Trạng thái.

---

# 2.2.11. Quản lý báo cáo

## A. Đối tượng có thể bị report

- Video.
- Comment.
- Channel.
- User.

## B. Nhóm báo cáo

Nếu nhiều người report cùng một nội dung:

```text
1 Target = 1 Report Case
```

Trong case hiển thị danh sách:

- Người report.
- Loại vi phạm được chọn.
- Nội dung mô tả.
- Thời gian report.
- Evidence nếu có.

## C. Trạng thái

- `Pending`.
- `InReview`.
- `Resolved`.
- `Dismissed`.
- `Escalated`.

Giao diện chính có thể nhóm thành ba tab:

- Chờ xử lý.
- Đang đánh giá.
- Đã giải quyết.

`Dismissed` và `Escalated` được thể hiện bằng trạng thái/bộ lọc chi tiết.

## D. Chi tiết case

- Case ID.
- Target.
- Tổng số reporter.
- Danh sách reporter.
- Người bị report.
- Lịch sử vi phạm.
- Policy liên quan.
- Nội dung đang xét.
- Moderator phụ trách.
- Timeline xử lý.

## E. Thao tác

- Claim.
- Review.
- Dismiss.
- Resolve.
- Escalate.
- Reopen.
- Hide target.
- Remove target.
- Warning.
- Strike.
- Ban/Suspend nếu đủ điều kiện.
- Gửi phản hồi.

## F. Phản hồi sau xử lý

### Người bị report

Nếu có xử lý:

- Nội dung bị ẩn/gỡ.
- Policy vi phạm.
- Warning/Strike.
- Quyền appeal nếu có.

Nếu không vi phạm:

- Thông báo case đã kết thúc nếu nghiệp vụ yêu cầu.

### Người report

Thông báo:

- Report đã được tiếp nhận.
- Report đã được xử lý.
- Nội dung đã bị gỡ/ẩn nếu chính sách cho phép tiết lộ.
- Không tiết lộ thông tin nội bộ hoặc thông tin riêng tư của người bị report.

---

# 2.2.12. Quản lý Warning, Strike và hình phạt

Đây là module dùng chung cho Video, Comment, Channel và User.

## A. Strike

Thông tin:

- Strike ID.
- Target Type.
- Target ID.
- Policy vi phạm.
- Severity.
- Lý do.
- Moderator.
- Ngày tạo.
- Ngày hết hiệu lực.
- Trạng thái.
- Report/Moderation Case nguồn.

## B. Severity đề xuất

- `Low`.
- `Medium`.
- `High`.
- `Critical`.

## C. Trạng thái strike

- Active.
- Expired.
- Revoked.

## D. Thao tác

- Tạo strike.
- Xem.
- Thu hồi strike.
- Xem lịch sử.
- Gắn Policy.
- Gắn evidence.
- Ghi chú nội bộ.

## E. Rule xử lý

Số strike và hình phạt **không hard-code trên UI**.

Ví dụ rule có thể được cấu hình:

```text
1 strike -> Warning
2 strike -> Hạn chế một số chức năng
3 strike -> Suspend
N strike -> Ban
```

Quy tắc thực tế phải do Policy/Business Rule của hệ thống quyết định.

---

# 2.2.13. Quản lý khiếu nại - Appeal

Người dùng phải có cơ chế khiếu nại đối với quyết định kiểm duyệt nếu hệ thống hỗ trợ.

## A. Đối tượng appeal

- Video bị gỡ.
- Comment bị gỡ.
- Strike.
- Channel bị suspend.
- User bị suspend/ban nếu chính sách cho phép.

## B. Trạng thái

- Pending.
- InReview.
- Approved.
- Rejected.
- Escalated.

## C. Thông tin

- Appeal ID.
- User.
- Quyết định bị khiếu nại.
- Lý do appeal.
- Evidence.
- Ngày gửi.
- Moderator cũ.
- Reviewer hiện tại.
- Timeline.

## D. Thao tác

- Claim.
- Review.
- Approve.
- Reject.
- Escalate.
- Ghi chú.
- Gửi kết quả.

Nếu Appeal được duyệt:

- Khôi phục nội dung nếu phù hợp.
- Gỡ strike nếu phù hợp.
- Ghi rõ quyết định đảo ngược.
- Không xóa lịch sử xử lý cũ.

---

# 2.2.14. Quản lý điều khoản và chính sách

Đây là phần cần có để chức năng Moderation có danh sách điều khoản đối chiếu.

## A. Policy

- Policy ID.
- Mã.
- Tên.
- Nhóm.
- Nội dung.
- Severity mặc định.
- Loại đối tượng áp dụng.
- Trạng thái.
- Phiên bản.
- Ngày hiệu lực.
- Ngày hết hiệu lực.

## B. Thao tác

- Tạo.
- Sửa Draft.
- Preview.
- Publish.
- Archive.
- Xem phiên bản cũ.
- Xem Moderation Case đang tham chiếu.

> Policy đã được dùng cho quyết định kiểm duyệt không được sửa lịch sử; khi thay đổi nội dung quan trọng nên tạo version mới.

---

# 2.2.15. Quản lý chủ đề, danh mục và Tag

## A. Category/Topic

- Tạo.
- Sửa.
- Xóa mềm.
- Bật/tắt.
- Sắp xếp thứ tự.
- Quản lý icon/thumbnail nếu có.
- Xem số video thuộc category.

## B. Tag

- Danh sách tag.
- Tìm kiếm.
- Merge tag trùng.
- Rename.
- Disable.
- Xóa mềm.
- Xem số video sử dụng.

---

# 2.2.16. Thông báo và liên lạc

## A. Loại thông báo

- In-app notification.
- Email.

## B. Template

Quản lý template:

- Warning.
- Strike.
- Video removed.
- Video restored.
- Report resolved.
- Appeal result.
- Subscription.
- Payment.
- System notice.

## C. Gửi thông báo

Cho phép gửi đến:

- Một user.
- Một nhóm user.
- User thuộc Plan.
- Chủ channel.
- Toàn hệ thống nếu có quyền.

Thông tin:

- Tiêu đề.
- Nội dung.
- Loại.
- Kênh gửi.
- Người gửi.
- Thời gian.
- Trạng thái gửi.

---

# 2.2.17. Thống kê và phân tích

## A. User Analytics

- User mới.
- User active.
- DAU.
- WAU.
- MAU.
- Retention.
- Churn nếu xác định được.
- Tăng trưởng.

## B. Content Analytics

- Video upload.
- Lượt xem.
- Watch time.
- Like.
- Dislike.
- Comment.
- Share.
- Search.
- Chủ đề phổ biến.
- Tag phổ biến.

## C. Channel Analytics

- Channel tăng trưởng nhanh.
- Subscriber.
- View.
- Engagement.
- Tần suất đăng.
- Channel bị report nhiều.

## D. Moderation Analytics

- Report count.
- Report hợp lệ.
- Nội dung bị gỡ.
- Warning.
- Strike.
- Ban.
- Appeal.
- Tỷ lệ Appeal thành công.
- Thời gian xử lý trung bình.
- Số case mỗi Moderator.

## E. Business Analytics

- Revenue.
- Revenue by Plan.
- Subscription.
- Upgrade.
- Downgrade.
- Cancel.
- Refund.
- Payment failure.

## F. Bộ lọc chung

- Ngày.
- Tuần.
- Tháng.
- Quý.
- Năm.
- Khoảng tùy chọn.
- Plan.
- Channel.
- User segment.
- Category.

## G. Hiển thị

- Line chart.
- Bar chart.
- Pie/Donut khi phù hợp.
- KPI Card.
- Table.
- Export.

---

# 2.2.18. Nhật ký hệ thống - Audit Log

Audit Log ghi lại mọi thao tác quan trọng.

## A. Dữ liệu tối thiểu

- Audit ID.
- Admin ID.
- Admin name.
- Role.
- Permission được sử dụng.
- Action.
- Resource Type.
- Resource ID.
- Old Value.
- New Value.
- Reason.
- IP.
- User Agent.
- Timestamp.
- Request/Correlation ID nếu có.

## B. Bắt buộc ghi log

- Login Admin.
- Logout Admin.
- Login thất bại.
- Tạo/sửa/xóa.
- Ban/Unban.
- Suspend.
- Strike.
- Gỡ strike.
- Hide/Remove/Restore.
- Moderation decision.
- Report decision.
- Appeal decision.
- Thay đổi Plan.
- Refund.
- Thay đổi Role.
- Gán/gỡ Permission.
- Gán/gỡ Admin khỏi Role.
- Thay đổi System Setting.
- Publish Policy.

## C. Tra cứu

- Theo Admin.
- Theo action.
- Theo resource.
- Theo khoảng thời gian.
- Theo IP.
- Theo Permission.

Audit Log không cho Admin thông thường sửa hoặc xóa.

---

# 2.2.19. Cấu hình hệ thống

Chỉ tài khoản có quyền cao được truy cập.

## A. Cấu hình upload

- Dung lượng file tối đa.
- Định dạng video.
- Định dạng thumbnail.
- Chất lượng cho phép.
- Giới hạn upload.

## B. Cấu hình moderation

- Thời hạn strike.
- Ngưỡng tự động flag.
- Quy tắc ưu tiên queue.
- Appeal deadline.
- Thời gian SLA xử lý.

## C. Cấu hình user/channel

- Giới hạn channel/user.
- Username/display name rules.
- Default storage quota.
- Default Plan.

## D. Cấu hình hệ thống khác

- Maintenance mode.
- Feature flag.
- Email sender.
- Notification config.
- Link điều khoản/chính sách.
- Cấu hình các thông số nghiệp vụ không nhạy cảm.

> Secret, private key, payment key, JWT secret và credential không hiển thị giá trị thực trên giao diện quản trị.

---

# 2.2.20. Quản lý tài khoản quản trị

## A. Danh sách Admin

- Admin ID.
- Avatar.
- Tên.
- Email.
- Role.
- Trạng thái.
- Lần đăng nhập cuối.
- Ngày tạo.

## B. Thao tác

- Tạo quyền truy cập Admin từ user hiện có.
- Gán Role.
- Gỡ Role.
- Disable Admin access.
- Enable Admin access.
- Force logout.
- Xem Audit Log.
- Không cho tự nâng quyền vượt quyền hiện tại.

## C. Bảo mật tài khoản Admin

- Đổi mật khẩu.
- Bắt buộc xác thực email.
- Khuyến nghị/áp dụng MFA khi triển khai thực tế.
- Quản lý session.
- Thu hồi session.
- Hiển thị lần đăng nhập gần nhất.
- Cảnh báo đăng nhập bất thường nếu có.

---

# 2.2.21. Ma trận phạm vi module

| Module | Xem | Tạo | Sửa | Xóa/Ẩn | Xử lý nghiệp vụ | Export |
|---|---:|---:|---:|---:|---:|---:|
| Dashboard | ✓ | - | - | - | - | ✓ |
| User | ✓ | - | ✓ | Ban/Suspend | Change Plan/Force Logout | ✓ |
| Role | ✓ | ✓ | ✓ | ✓ | Assign Permission/User | - |
| Channel | ✓ | - | ✓ | Ban/Delete | Strike | ✓ |
| Video | ✓ | - | Metadata | Hide/Remove | Strike/Restore | ✓ |
| Comment | ✓ | - | - | Hide/Remove | Strike/Restore | ✓ |
| Moderation | ✓ | - | - | - | Approve/Reject/Escalate | - |
| Report | ✓ | - | - | - | Resolve/Dismiss/Escalate | ✓ |
| Appeal | ✓ | - | - | - | Approve/Reject/Escalate | - |
| Plan | ✓ | ✓ | ✓ | Soft Delete | Subscription Change | - |
| Payment | ✓ | - | - | - | Refund/Retry | ✓ |
| Policy | ✓ | ✓ | Draft | Archive | Publish | - |
| Category/Tag | ✓ | ✓ | ✓ | Soft Delete | Merge Tag | - |
| Notification | ✓ | Template | Template | - | Send | - |
| Analytics | ✓ | - | - | - | - | ✓ |
| Audit | ✓ | - | - | - | - | Theo quyền |
| System | ✓ | - | ✓ | - | Config | - |

---

# 2.2.22. Luồng kiểm tra quyền chuẩn

Mỗi request quản trị nên đi qua luồng:

```text
Admin
  ↓
Authentication
  ↓
Kiểm tra Admin Access
  ↓
Kiểm tra Role
  ↓
Kiểm tra Permission
  ↓
Kiểm tra Business Rule
  ↓
Thực hiện nghiệp vụ
  ↓
Audit Log
  ↓
Response
```

Ví dụ:

```text
Moderator muốn gỡ Video
        ↓
Có video.remove?
        ↓
Không -> 403 Forbidden
        ↓ Có
Video có tồn tại?
        ↓
Có đang ở trạng thái cho phép gỡ?
        ↓
Nhập lý do
        ↓
Remove Video
        ↓
Thông báo chủ Video
        ↓
Ghi Moderation History
        ↓
Ghi Audit Log
```

---

# 2.2.23. Các nguyên tắc nghiệp vụ bắt buộc

1. **Không hard-delete dữ liệu quan trọng nếu chưa có quy trình rõ ràng.**
2. **Mọi quyết định moderation phải xác định được ai thực hiện, lúc nào và dựa trên Policy nào.**
3. **Mọi thao tác nhạy cảm phải yêu cầu lý do.**
4. **Không cho Admin thao tác vượt Permission.**
5. **Không cho Admin tự nâng quyền cho chính mình nếu không có quyền tương ứng.**
6. **Không cho Role thấp chỉnh sửa/xóa Role cao hơn nếu không được phép.**
7. **Không hiển thị secret hoặc credential ở dạng rõ.**
8. **Không xóa Audit Log qua Web Admin thông thường.**
9. **Report, Moderation và Appeal phải có Timeline.**
10. **Strike phải có trạng thái và thời hạn, không chỉ lưu một con số tổng.**
11. **Plan đã phát sinh subscription/payment không được xóa vật lý.**
12. **Policy đã được dùng để ra quyết định phải giữ được version lịch sử.**
13. **Các thao tác hàng loạt phải hiển thị preview số đối tượng bị ảnh hưởng trước khi xác nhận.**
14. **Các thao tác nguy hiểm phải chống double-submit và được xử lý idempotent nếu API yêu cầu.**
15. **Màn hình quản trị phải phân biệt dữ liệu công khai, dữ liệu nội bộ và dữ liệu nhạy cảm.**

---

# 2.2.24. Danh sách menu Sidebar đề xuất

```text
Tổng quan

Người dùng
├── Danh sách người dùng
├── Tài khoản quản trị
└── Vai trò & phân quyền

Nội dung
├── Kênh
├── Video
├── Bình luận
├── Chủ đề
└── Tag

Kiểm duyệt
├── Hàng đợi video
├── Báo cáo
├── Khiếu nại
├── Warning & Strike
├── Lịch sử kiểm duyệt
└── Điều khoản & chính sách

Kinh doanh
├── Plan
├── Subscription
├── Payment
└── Doanh thu

Hệ thống
├── Thông báo
├── Thống kê
├── Nhật ký hệ thống
└── Cấu hình
```

Menu thực tế được render dựa trên Permission của tài khoản đang đăng nhập.
