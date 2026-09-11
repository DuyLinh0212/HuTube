# Sprint 5 — Gói dịch vụ, xem nội dung và đăng video

> **Sprint Goal:** Hoàn thiện lát cắt sản phẩm đầu tiên từ người dùng chưa đăng nhập xem được nội dung, người dùng đăng nhập quản lý hồ sơ/gói, Creator đăng video và người xem tương tác với video.

Sprint này được chốt theo ba nhóm phụ trách **Tú, Danh, Linh**. Nội dung dưới đây là phạm vi thực hiện của Sprint 5; các mục không được nêu trong tài liệu này không phải tiêu chí bắt buộc để đóng Sprint.

---

## 1. Tài liệu module làm căn cứ

| Phạm vi Sprint 5 | Tài liệu module | Mục liên quan |
|---|---|---|
| Guest, Trang chủ, Khám phá, Player, Upload, Profile, Settings | [Module_NguoiDung.md](./Module_NguoiDung.md) | 2.3.2–2.3.7, 2.3.14, 2.3.18, 2.3.20–2.3.22, 2.3.30–2.3.37 |
| Plan, Subscription, Policy, Moderation, cấu hình upload | [Module_QuanTri.md](./Module_QuanTri.md) | 2.2.3, 2.2.8, 2.2.10, 2.2.14–2.2.16, 2.2.19–2.2.20 |
| Video đề xuất cho Guest và fallback khi chưa có dữ liệu cá nhân | [Module_CF.md](./Module_CF.md) | 2.1.3, 2.1.21–2.1.25 |

### 1.1. Quy ước phạm vi

- **Must-have:** phải hoàn thành để đóng Sprint 5.
- **Should-have:** hoàn thành nếu không ảnh hưởng các luồng Must-have.
- **Stretch:** chỉ làm khi còn thời gian; không chặn Sprint Gate.
- Tính năng phải được kiểm tra ở **Backend và UI**. Không chỉ ẩn nút trên Web/Mobile.
- Các chức năng yêu cầu đăng nhập phải trả về trạng thái rõ ràng khi Guest truy cập.
- Video chỉ được hiển thị công khai khi thỏa mãn `Public`, xử lý upload thành công và không bị chặn bởi Policy.

---

## 2. Phân công tổng quan

| Người phụ trách | Phạm vi chốt | Mức độ |
|---|---|---|
| **Tú** | Gói dịch vụ/quota; chia sẻ gói; Guest xem đề xuất/khám phá; đăng xuất mọi thiết bị; lời mời realtime SignalR và email Gmail | Must-have |
| **Danh** | Chính sách; kiểm duyệt nội dung; hồ sơ người dùng | Chính sách/Profile Must-have; auto-ban Stretch |
| **Linh** | Theme; ngôn ngữ; tải video; Home/Explore; đăng video; Player; tương tác và bình luận | Must-have |

---

# 3. Phạm vi của Tú

## 3.1. Gói dịch vụ và quyền sử dụng

Tham chiếu: `Module_QuanTri.md` mục **2.2.8 Quản lý Plan và Subscription**, mục **2.2.19 Cấu hình hệ thống**; `Module_NguoiDung.md` mục **2.3.10 Thư viện cá nhân**, **2.3.14 Nội dung tải xuống** và **2.3.31 Cài đặt tài khoản**.

Mỗi Plan cần có tối thiểu các thuộc tính:

- Tên, mô tả, trạng thái và thứ tự hiển thị.
- Quota lưu trữ cho Channel.
- Dung lượng file tối đa cho một lần upload.
- Chất lượng tối đa được phép upload.
- Chất lượng tối đa được phép tải video xuống.
- Có/không có tải video.
- Có/không có phát trong nền.
- Có/không có Picture-in-Picture (PiP).
- Thời hạn hiệu lực của Subscription.

### Quy tắc bắt buộc

- Quota được tính theo Channel, hiển thị `đã dùng / tổng quota / còn lại`.
- Upload phải bị từ chối ở Backend nếu vượt file size, chất lượng hoặc quota của Plan.
- Chất lượng video không được vượt giới hạn của Plan tại thời điểm upload.
- Download phải kiểm tra quyền của User và chất lượng được chọn trước khi cấp URL tải.
- Khi Plan hết hạn hoặc bị hủy, quyền mới phải được áp dụng ngay; dữ liệu đã upload không tự động bị xóa.
- Việc tính quota phải chống cộng trùng khi retry và phải rollback khi upload thất bại.

## 3.2. Chia sẻ gói

Phạm vi Sprint 5 là chia sẻ **thông tin gói**:

- Share từ màn hình Plan/Subscription.
- Copy URL gói.
- Native Share trên Mobile nếu hệ điều hành hỗ trợ.
- URL mở được với Guest và dẫn tới trang mô tả gói.
- Không cho phép chia sẻ access token, tài khoản hoặc quyền sử dụng ngoài Subscription của User.

Nếu sau này cần chia sẻ quyền theo nhóm/gia đình, đó là nghiệp vụ riêng và phải bổ sung giới hạn seat, thành viên, thu hồi quyền và audit log.

## 3.3. Guest xem video đề xuất và Khám phá

Tham chiếu: `Module_NguoiDung.md` mục **2.3.2 Guest**, **2.3.3 Trang chủ**, **2.3.4 Khám phá**; `Module_CF.md` mục **2.1.21 Cold-start** và **2.1.23 Online Recommendation**.

Guest được phép:

- Mở Trang chủ và xem video công khai.
- Mở Khám phá, xem video mới/phổ biến/xu hướng theo dữ liệu hệ thống.
- Tìm kiếm và mở trang xem video công khai nếu luồng Search đã sẵn sàng.
- Chia sẻ video và dùng các điều khiển Player cơ bản.

Guest không được phép:

- Like/Dislike, Rating, Comment, Reply, Report hoặc Subscribe.
- Upload, tải video nếu Plan yêu cầu đăng nhập, xem lịch sử cá nhân hoặc quản lý kênh.

### Quy tắc dữ liệu đề xuất

- Guest không có User ID để chạy recommendation cá nhân hóa.
- API dùng fallback theo thứ tự: video công khai mới/phổ biến, video theo Category/Tag, sau đó là danh sách mặc định.
- Không đưa video Private, Unlisted không có quyền hoặc video bị Moderation chặn vào kết quả.
- Khi User đăng nhập, hệ thống có thể chuyển sang feed cá nhân hóa; việc train/inference MBMF đầy đủ thuộc module và Sprint Recommendation.

## 3.4. Đăng xuất khỏi mọi thiết bị

Tham chiếu: `Module_NguoiDung.md` mục **2.3.31 Bảo mật**; `Module_QuanTri.md` mục **2.2.3 Thao tác quản trị user**.

Khi User chọn **Đăng xuất khỏi tất cả thiết bị**:

1. Backend thu hồi toàn bộ Refresh Token/Session đang hoạt động của User.
2. Phiên hiện tại cũng bị thu hồi sau khi API trả kết quả thành công.
3. Các request refresh token tiếp theo phải bị từ chối.
4. Web/Mobile xóa token cục bộ, trở về trạng thái Guest và điều hướng về màn hình đăng nhập hoặc Trang chủ.
5. Nếu có kết nối realtime, server gửi sự kiện `SessionRevoked` để client kick ngay; client phải tự đóng kết nối.
6. Ghi Audit Log với User, thời điểm và lý do thao tác.

## 3.5. Lời mời thành viên realtime và Gmail

Tham chiếu: `Module_NguoiDung.md` mục **2.3.18 Thành viên và quyền kênh**; `Module_QuanTri.md` mục **2.2.16 Thông báo và liên lạc**.

Luồng gửi lời mời:

1. Owner/Manager có quyền nhập email và chọn Role.
2. Backend kiểm tra quyền, email, Role và lời mời đang chờ.
3. Tạo Invitation với trạng thái `Pending`, thời hạn và người gửi.
4. Nếu người nhận đang online, gửi realtime qua SignalR.
5. Gửi email Gmail/SMTP có link deep-link tới màn hình Invitation.
6. Người nhận có thể Accept/Decline; Owner có thể Revoke.

Trạng thái tối thiểu:

```text
Pending -> Accepted
Pending -> Declined
Pending -> Revoked
Pending -> Expired
```

Yêu cầu kỹ thuật:

- SignalR chỉ là kênh thông báo; dữ liệu chính phải đọc lại từ Backend.
- Email gửi lỗi không được làm mất Invitation đã tạo.
- Không tạo lời mời trùng đang còn hiệu lực.
- Accept phải kiểm tra lại người nhận, thời hạn và trạng thái Invitation ở Backend.

---

# 4. Phạm vi của Danh

## 4.1. Chính sách

Tham chiếu: `Module_QuanTri.md` mục **2.2.14 Quản lý điều khoản và chính sách**, **2.2.10 Kiểm duyệt video**; `Module_NguoiDung.md` mục **2.3.33 Báo cáo nội dung**.

Sprint 5 làm phiên bản chính sách tối thiểu:

- Trang hiển thị Điều khoản sử dụng, Chính sách quyền riêng tư và Chính sách nội dung.
- Policy có mã, tên, nhóm, nội dung, severity, trạng thái, version và thời gian hiệu lực.
- Admin có thể tạo Draft, Preview, Publish và Archive Policy.
- Moderation Case lưu lại Policy version được dùng tại thời điểm quyết định.
- Policy đã được dùng để quyết định không được sửa ngược lịch sử; thay đổi nội dung phải tạo version mới.
- Trang upload hiển thị tóm tắt Policy/checkbox xác nhận nếu loại nội dung yêu cầu.

## 4.2. Kiểm duyệt nội dung

### Must-have: kiểm duyệt trước khi hiển thị công khai

- Video mới có trạng thái `Checking` hoặc `PendingModeration` trước khi Public.
- Moderator xem được video, thumbnail, metadata, Channel, Category/Tag và Policy hiện hành.
- Moderator có thể `Approve`, `Reject` hoặc `Escalate`.
- Reject phải có Policy/reason và ghi Moderation History.
- Video bị Reject không xuất hiện ở Home, Explore, Search hoặc Recommendation.
- Quyết định kiểm duyệt phải kiểm tra RBAC và ghi Audit Log.

Trạng thái tối thiểu:

```text
Draft -> Uploading -> Processing -> Checking
Checking -> PendingModeration -> Approved -> Published
PendingModeration -> Rejected
PendingModeration -> Escalated
```

### Stretch: tự động ban nội dung nhạy cảm

Chỉ triển khai nếu còn thời gian và có rule/model đủ tin cậy:

- Tự động gắn cờ nội dung theo Policy.
- Nội dung chắc chắn vi phạm có thể tự động `Rejected`/`Hidden` và áp dụng hình phạt theo rule.
- Trường hợp không chắc chắn phải đưa vào Moderation Queue, không tự động ban.
- Luôn lưu lý do, Policy version, nguồn phát hiện, thời điểm và khả năng review/appeal.

Không dùng từ “AI đã kiểm duyệt” nếu hệ thống mới chỉ kiểm tra tên file, metadata hoặc keyword đơn giản.

## 4.3. Profile người dùng

Tham chiếu: `Module_NguoiDung.md` mục **2.3.9 Chi tiết kênh**, **2.3.30 Menu tài khoản**, **2.3.31 Cài đặt tài khoản**.

### Profile cá nhân

- Xem và cập nhật Avatar, Display Name, Bio và thông tin hiển thị.
- Hiển thị Email và trạng thái xác thực theo quyền; không hiển thị dữ liệu nhạy cảm.
- Tách rõ Profile cá nhân với Profile của Channel.
- Guest chỉ xem được phần Profile công khai.

### Profile/Channel công khai

- Avatar, tên, handle, mô tả, ngày tham gia và số video nếu được công khai.
- Danh sách video Public của Channel.
- Không trả về Video Private, thông tin Subscription riêng tư hoặc dữ liệu quản trị.

---

# 5. Phạm vi của Linh

## 5.1. Theme và ngôn ngữ

Tham chiếu: `Module_NguoiDung.md` mục **2.3.30 Menu Avatar**, **2.3.31 Appearance/Language**.

- Theme: `Light`, `Dark`, `System`.
- Ngôn ngữ tối thiểu: Tiếng Việt và English.
- Áp dụng ngay trên Web/Mobile và lưu lựa chọn theo User; Guest dùng local storage.
- Reload/đăng nhập lại không làm mất lựa chọn.
- Không để chuỗi giao diện mới hard-code trong từng màn hình; dùng resource/localization chung.

## 5.2. Tải video

Tham chiếu: `Module_NguoiDung.md` mục **2.3.14 Nội dung tải xuống** và **2.3.20 Quản lý nội dung**.

Luồng người dùng:

- Từ trang xem video chọn `Tải xuống`.
- Hiển thị chất lượng được phép theo Plan và dung lượng ước tính.
- Có Progress, Cancel, Retry và thông báo lỗi.
- Lưu danh sách video đã tải: Video, chất lượng, dung lượng, ngày tải, trạng thái.
- Cho phép xóa một hoặc nhiều bản tải xuống.
- Mobile có tùy chọn chỉ tải bằng Wi-Fi và kiểm tra dung lượng thiết bị.

Ranh giới với phần của Tú: Linh làm UI/flow và trạng thái download; Backend/Plan của Tú quyết định User có quyền tải và chất lượng tối đa.

## 5.3. Trang chủ và Khám phá

Tham chiếu: `Module_NguoiDung.md` mục **2.3.3 Trang chủ** và **2.3.4 Khám phá**.

### Trang chủ

- Hiển thị Video Card gồm thumbnail, duration, title, Channel, views và thời gian đăng.
- Grid trên Web, Feed một cột trên Mobile.
- Topic/Category chips.
- Loading, Empty State, Error State và lazy loading/infinite scroll.
- User đăng nhập có thể nhận danh sách cá nhân hóa nếu API đã có; Guest dùng fallback công khai của Tú.

### Khám phá

- Nhóm `Mới nhất`, `Phổ biến`, `Xu hướng` hoặc theo Category.
- Lọc/sắp xếp tối thiểu theo Category và thời gian.
- Chỉ hiển thị nội dung Public và đã Approved.

## 5.4. Đăng video

Tham chiếu: `Module_NguoiDung.md` mục **2.3.16 Creator Studio**, **2.3.20 Quản lý nội dung**, **2.3.21 Upload và tạo Video**.

### Bước 1 — Chọn file

- File Picker trên Web/Mobile.
- Kiểm tra định dạng, dung lượng, chất lượng và quota trước khi upload.
- Hiển thị Progress.
- Có Cancel, Retry; Mobile giữ Draft khi mất mạng nếu hệ điều hành cho phép.

### Bước 2 — Metadata

- Title, Description, Thumbnail.
- Category, Tag, Language.
- Visibility: `Public`, `Private`, `Unlisted`.
- Không cho Public nếu video chưa qua Processing/Policy/Moderation theo rule.

### Bước 3 — Thành phần video

- Chia timeline/Chapter: tên chapter và timestamp bắt đầu.
- Kiểm tra timestamp tăng dần và không vượt duration.
- Cho phép xem Preview trước khi Publish.

### Bước 4 — Publish

- Lưu Draft.
- Upload/Processing/Checking.
- Gửi Moderation.
- Publish sau khi được Approved.
- Copy URL và mở trang xem video sau khi thành công.

Danh sách Creator Studio cần có:

- Video, Visibility, Moderation Status, ngày đăng, Views, Like, Comment.
- Search/Filter theo trạng thái, Category, Tag và Visibility.
- Edit metadata, đổi Visibility, Copy URL, Delete/Soft Delete.

## 5.5. Player và dữ liệu xem

Tham chiếu: `Module_NguoiDung.md` mục **2.3.6 Trang xem video**, **2.3.36 Thao tác nâng cao**, **2.3.37 Phím tắt**.

Player phải hỗ trợ:

- Play/Pause, tua tới/lùi, thanh tiến trình, volume/mute.
- Playback Speed.
- Đổi chất lượng và Auto Quality theo các bản video có sẵn và giới hạn Plan.
- Fullscreen, Mini Player và PiP khi trình duyệt/hệ điều hành hỗ trợ.
- Phát trong nền khi thiết bị và quyền Plan cho phép.
- Phím tắt Web: Space/K, J, L, M, F, T, C, mũi tên âm lượng.
- Mobile: double tap để tua, xoay ngang fullscreen, giữ timestamp khi đổi hướng.

Dữ liệu cần lưu cho User đã đăng nhập:

- `watch_seconds`, `video_duration_seconds`, `watch_ratio`.
- Vị trí xem gần nhất và thời điểm cập nhật.
- Resume khi mở lại video.
- Không ghi History nếu User đã tắt lưu lịch sử.

## 5.6. Tương tác với video

Tham chiếu: `Module_NguoiDung.md` mục **2.3.6 C. Tương tác**, **2.3.7 Bình luận**, **2.3.35 Chia sẻ**; `Module_CF.md` mục **2.1.1 Unified user-video behaviors**.

### Video

- Like/Unlike.
- Dislike/Undislike; Like và Dislike loại trừ nhau.
- Share bằng Copy URL hoặc Native Share.
- Rating 1–5; User được cập nhật hoặc xóa Rating theo rule đã chốt.
- Ghi event/aggregate tương ứng cho `like`, `dislike`, `share`, `rating` và `watch_ratio`.

### Comment

- Tạo, sửa/xóa comment của mình.
- Reply.
- Lọc `Top comment`/`Mới nhất`.
- Like/Dislike comment.
- Report comment.
- Ẩn comment theo quyền của chủ Channel/Moderator.
- Thông báo khi có người reply comment của mình.
- Kiểm tra độ dài, từ bị cấm và chống spam ở mức tối thiểu.

Guest không được Like/Dislike, Rating, Comment, Reply hoặc Report.

---

# 6. File/module triển khai

Các file hiện có cần được mở rộng trước khi tạo module mới:

| Nhóm | File hiện có liên quan |
|---|---|
| Auth/Session | `backend/src/HuTube.Application/Auth/AuthService.cs`, `backend/src/HuTube.Infrastructure/Authentication/TokenService.cs`, `backend/src/HuTube.Infrastructure/Persistence/AuthStore.cs`, `backend/src/HuTube.Api/Controllers/AuthController.cs` |
| Account/Profile/Settings | `backend/src/HuTube.Application/Account/AccountDtos.cs`, `backend/src/HuTube.Infrastructure/Account/AccountService.cs`, `backend/src/HuTube.Api/Controllers/AccountController.cs`, `frontend/user-web/src/app/features/account/*`, `mobile/user-app/lib/account/*` |
| Channel/Invitation | `backend/src/HuTube.Application/Channels/*`, `backend/src/HuTube.Infrastructure/Persistence/ChannelStore.cs`, `backend/src/HuTube.Api/Controllers/ChannelController.cs`, `frontend/user-web/src/app/features/channel/*`, `mobile/user-app/lib/channel/*` |
| Email | `backend/src/HuTube.Infrastructure/Authentication/AuthEmailSender.cs` |
| Quota/Preferences | `backend/src/HuTube.Domain/Channels/ChannelQuota.cs`, `backend/src/HuTube.Domain/Users/UserPreferences.cs` |

Các vertical slice mới của Sprint 5 được đặt theo convention hiện tại:

```text
backend/src/HuTube.Domain/
  Plans/
  Videos/
  Moderation/
  Comments/
  Notifications/

backend/src/HuTube.Application/
  Plans/
  Videos/
  Moderation/
  Comments/
  Notifications/

backend/src/HuTube.Infrastructure/
  Persistence/
  Storage/
  Realtime/
  Notifications/

frontend/user-web/src/app/features/
  home/
  explore/
  video/
  creator/
  plans/

mobile/user-app/lib/
  home/
  explore/
  video/
  creator/
  plans/
```

Không bắt buộc phải dùng đúng tên thư mục trên, nhưng mỗi vertical slice phải tách được Model/Contract/Service/Screen và không dồn toàn bộ logic vào Controller hoặc Widget.

---

# 7. Dữ liệu và API tối thiểu

## 7.1. Bảng/aggregate tối thiểu

- `Plan`, `Subscription`, `PlanEntitlement`.
- `ChannelQuota` và lịch sử cập nhật quota.
- `Video`, `VideoVariant`, `VideoUpload`.
- `VideoCategory`, `Tag`, `VideoTag`.
- `VideoVisibility`, `VideoModerationCase`, `Policy`, `PolicyVersion`.
- `WatchProgress`, `WatchHistory`.
- `VideoReaction`, `VideoRating`, `VideoShare`.
- `Comment`, `CommentReaction`, `CommentReport`.
- `DownloadRecord`.
- `Notification` và trạng thái gửi Email.

## 7.2. Nguyên tắc API

- DTO không trả secret, token, nội dung Policy nội bộ hoặc dữ liệu Private trái quyền.
- Các thao tác Like/Dislike, Comment, Download, Publish, Accept Invitation phải idempotent hoặc chống double-submit.
- API phải trả lỗi nghiệp vụ có mã ổn định để Web/Mobile hiển thị đúng.
- URL Storage phải có thời hạn và kiểm tra quyền trước khi cấp.
- Endpoint Guest chỉ trả nội dung Public/Approved.

---

# 8. Kiểm thử bắt buộc

## 8.1. Unit test

- Plan: quota, file size, upload quality, download quality, entitlement hết hạn.
- Guest: chỉ xem Public/Approved; không dùng API tương tác.
- Logout all: thu hồi toàn bộ session và refresh token.
- Invitation: quyền gửi, Role, duplicate, accept/decline/revoke/expire.
- Profile: validation Display Name/Bio và dữ liệu công khai.
- Upload: file invalid, vượt quota, retry, cancel, visibility.
- Player: seek, speed, quality, watch ratio cap, resume.
- Like/Dislike: mutual exclusion và idempotency.
- Comment: reply, filter, report, hide, notification.
- Policy/Moderation: version, approve/reject, video rejected không xuất hiện Public.

## 8.2. Integration/E2E

### E2E-S5-01 — Guest xem Home/Explore

1. Mở Home không đăng nhập.
2. Xem danh sách video đề xuất/fallback.
3. Mở Explore và lọc theo Category.
4. Mở một video Public.
5. Thử Like/Comment/Download.

Kết quả: xem được nội dung hợp lệ; thao tác yêu cầu login bị chặn rõ ràng.

### E2E-S5-02 — Plan giới hạn upload/download

1. User có Plan với quota và chất lượng giới hạn.
2. Upload file vượt file size hoặc quality.
3. Upload file hợp lệ.
4. Thử download ở chất lượng cao hơn giới hạn.

Kết quả: request vượt quyền bị từ chối ở API; quota và chất lượng hợp lệ được lưu đúng.

### E2E-S5-03 — Logout all devices

1. Đăng nhập cùng User trên Web và Mobile.
2. Chọn Logout all trên một thiết bị.
3. Gửi request bằng thiết bị còn lại.
4. Thử refresh session.

Kết quả: thiết bị còn lại bị kick ngay hoặc ở request kế tiếp; refresh token cũ không dùng được.

### E2E-S5-04 — Invitation realtime + Gmail

1. Owner gửi lời mời cho User đã đăng ký.
2. User nhận SignalR event nếu đang online.
3. Kiểm tra email có deep-link.
4. Accept Invitation.

Kết quả: Invitation chỉ tạo một lần, thành viên/Role đúng, audit và notification tồn tại.

### E2E-S5-05 — Upload → Moderation → Publish

1. Creator upload file hợp lệ.
2. Nhập metadata, Category/Tag, Chapter và Visibility.
3. Processing/Policy hoàn tất.
4. Moderator Approve.
5. Mở URL bằng Guest.

Kết quả: Video không Public trước khi Approve; sau Approve Guest xem được, metadata và timeline đúng.

### E2E-S5-06 — Player và tương tác

1. User mở video Public.
2. Đổi Speed/Quality, tua và rời video giữa chừng.
3. Mở lại để Resume.
4. Like, Dislike, Share và Rating.
5. Comment, Reply, Like/Dislike, Report và kiểm tra notification.

Kết quả: trạng thái cuối đúng, watch progress không vượt duration, không tạo interaction trùng.

---

# 9. Sprint Gate và tiêu chí đóng Sprint

## Sprint Gate

Luồng sau phải chạy được trên môi trường Staging:

```text
Guest mở Home/Explore
        ↓
Mở Video Public
        ↓
Creator upload + metadata + timeline
        ↓
Policy/Moderation
        ↓
Approve và Publish
        ↓
Guest xem được Video
        ↓
User đăng nhập tương tác và Resume
```

## Definition of Done

- [ ] Plan và quyền quota/file size/upload quality/download quality hoạt động ở Backend.
- [ ] Guest xem được Home/Explore/video Public; không thực hiện được thao tác yêu cầu login.
- [ ] Logout all devices thu hồi session và kick phiên còn lại.
- [ ] Invitation có trạng thái, SignalR realtime và gửi Gmail/SMTP.
- [ ] Policy có version và được tham chiếu trong Moderation.
- [ ] Profile cá nhân và Profile/Channel công khai hoạt động.
- [ ] Theme và Language hoạt động trên Web/Mobile.
- [ ] Upload, metadata, Category/Tag, timeline, Visibility và Creator Content hoạt động.
- [ ] Player có tua, tốc độ, chất lượng, Resume, PiP/background theo entitlement và khả năng thiết bị.
- [ ] Like/Share, Comment/Reply/filter/like-dislike/report/hide/notification hoạt động theo quyền.
- [ ] Download có kiểm tra Plan, quality, progress, retry/cancel và xóa bản tải.
- [ ] Unit, Integration và E2E bắt buộc pass.
- [ ] Stretch auto-ban chỉ được ghi là hoàn thành khi có test, Policy reference và cơ chế review; nếu chưa đạt thì ghi rõ `Deferred`, không chặn Sprint.

## Không thuộc phạm vi bắt buộc Sprint 5

- Payment gateway và đối soát doanh thu.
- Huấn luyện/inference MBMF đầy đủ cho recommendation cá nhân hóa.
- Moderation AI tự động ban ở mức production nếu chưa đủ độ tin cậy.
- Appeal, Copyright và hệ thống Strike đầy đủ nhiều cấp.
- Analytics chuyên sâu.
