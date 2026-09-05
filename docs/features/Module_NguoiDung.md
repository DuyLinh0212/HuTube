# 2.3. Module chức năng nhóm người dùng

> **Phạm vi:** Module dùng chung cho **Web User** và **Mobile User App** của hệ thống HuTube.  
> Nghiệp vụ, trạng thái và quyền truy cập được dùng chung; phần bố trí giao diện được mô tả riêng cho từng nền tảng để tránh việc bê nguyên layout Web sang Mobile.
>
> **Nền tảng áp dụng:**
> - **Web User:** giao diện Desktop/Laptop, tham chiếu 1920×1080 và Responsive.
> - **Mobile User App:** Android/iOS, ưu tiên bố cục dọc; hỗ trợ xoay ngang tại Player và một số màn hình phù hợp.
>
> **Nguyên tắc thiết kế:**
> - Web và Mobile dùng chung API, Business Rule, Permission và trạng thái dữ liệu.
> - Web ưu tiên Sidebar + Topbar; Mobile ưu tiên Bottom Navigation + App Bar + Bottom Sheet.
> - Không thu nhỏ nguyên giao diện Web để dùng cho Mobile.
> - Phân biệt rõ Guest, User đã đăng nhập, Chủ kênh, Thành viên kênh và Người kiểm duyệt kênh.
> - Các thao tác nhạy cảm như xóa kênh, xóa video, đổi quyền, thay đổi gói và báo cáo bản quyền phải có xác nhận.
> - Nội dung bị xóa, ẩn hoặc hạn chế phải hiển thị trạng thái phù hợp thay vì gây lỗi giao diện.
> - Mọi màn hình Mobile phải tính đến Safe Area, bàn phím ảo, thao tác một tay và trạng thái mạng yếu/mất mạng.

---

## 2.3.1. Quy định chung về giao diện đa nền tảng

### A. Bố cục Web User

#### Topbar

Hiển thị:

- Logo nền tảng.
- Tên HuTube.
- Thanh tìm kiếm.
- Nút tìm kiếm.
- Gợi ý từ khóa khi nhập.
- Lịch sử tìm kiếm gần đây.
- Nút tải video.
- Nút HuAI.
- Chuông thông báo.
- Avatar người dùng.
- Menu tài khoản.

Đối với Guest:

- Hiển thị nút Đăng nhập/Đăng ký.
- Các chức năng cần tài khoản sẽ yêu cầu xác thực khi người dùng thao tác.

#### Sidebar

- Có thể thu/phóng.
- Có trạng thái icon-only khi thu gọn.
- Highlight mục đang chọn.
- Có thể ghi nhớ trạng thái Sidebar trên thiết bị.

Menu cơ bản:

```text
Trang chủ
Khám phá
Kênh đăng ký
Thư viện
Kênh của bạn
```

### B. Bố cục Mobile User App

Mobile **không sử dụng Sidebar cố định**.

#### Bottom Navigation

Đề xuất 5 mục:

```text
Trang chủ
Khám phá
Tạo
Kênh đăng ký
Bạn
```

Quy ước:

- **Trang chủ:** Recommendation Feed.
- **Khám phá:** Topic, Trending, nội dung mới/phổ biến.
- **Tạo:** nút trung tâm mở Bottom Sheet tạo nội dung.
- **Kênh đăng ký:** Feed và danh sách kênh đã Subscribe.
- **Bạn:** Thư viện + tài khoản + kênh của bạn + cài đặt.

Nút **Tạo** mở Bottom Sheet:

```text
Tải Video lên
Tạo Playlist
```

Nếu User chưa có Channel:

```text
Tạo kênh
```

được hiển thị trước chức năng Upload.

#### Mobile App Bar

Ở màn hình cấp cao:

- Logo/Tên HuTube bên trái.
- Search.
- HuAI.
- Notification.

Ở màn hình cấp con:

- Back.
- Tên màn hình.
- Menu `...` khi cần.

Không cần hiển thị toàn bộ Logo + Search Bar + Avatar cùng lúc như Web.

#### Bottom Sheet

Ưu tiên dùng cho:

- Filter.
- Sort.
- Share.
- Menu `...`.
- Add to Playlist.
- Report.
- Chọn Quality.
- Chọn Speed.
- Chọn Visibility.
- Chọn Notification Level.
- Chọn Role.
- Các thao tác nhanh.

#### Full-screen Modal

Dùng cho:

- Search.
- Comment.
- Edit Metadata.
- Upload.
- Payment.
- Report form dài.
- Copyright Request.
- Appeal.
- Các form nhiều trường.

### C. Quy định danh sách dùng chung

Các màn hình danh sách hỗ trợ khi phù hợp:

- Infinite Scroll hoặc Pagination.
- Skeleton Loading.
- Empty State.
- Error State.
- Retry.
- Bộ lọc.
- Sắp xếp.
- Refresh.
- Lazy Loading.
- Menu thao tác nhanh.
- Responsive Card/List.
- Giữ trạng thái bộ lọc khi quay lại từ màn hình chi tiết.

Riêng Mobile:

- Hỗ trợ Pull-to-Refresh.
- Ưu tiên Infinite Scroll.
- Filter/Sort dùng Chip + Bottom Sheet.
- Menu `...` mở Bottom Sheet thay vì Dropdown lớn.
- Không đặt quá nhiều nút chữ trên một hàng.
- CTA chính có thể cố định ở cạnh dưới màn hình khi nhập Form.
- Không để Bottom Navigation che nội dung hoặc CTA.
- Danh sách dài phải giữ vị trí cuộn khi quay lại.

### D. Quy định điều hướng

```text
Web:
Sidebar / Topbar
      ↓
Trang chức năng
      ↓
Trang chi tiết / Modal

Mobile:
Bottom Navigation / App Bar
      ↓
Stack Navigation
      ↓
Full-screen Page / Bottom Sheet
```

Nút Back trên Mobile phải quay lại đúng màn hình trước và giữ trạng thái:

- Vị trí cuộn.
- Từ khóa.
- Filter.
- Tab đang chọn.
- Video đang phát nếu Mini Player còn hoạt động.

---


## 2.3.2. Phân loại người dùng và phạm vi chức năng

### A. Guest

Guest có thể:

- Xem video công khai.
- Xem kênh công khai.
- Tìm kiếm.
- Xem playlist công khai.
- Xem bình luận công khai.
- Chia sẻ nội dung.
- Sử dụng các chức năng phát video cơ bản.

Guest không thể:

- Like/Dislike.
- Comment.
- Subscribe.
- Lưu playlist.
- Xem lịch sử cá nhân.
- Báo cáo nội dung.
- Upload video.
- Quản lý kênh.

### B. User đã đăng nhập

Có thêm:

- Like/Dislike.
- Comment/Reply.
- Subscribe.
- Playlist.
- Watch History.
- Watch Later.
- Report.
- Notification.
- Account Settings.
- Plan/Subscription.

### C. Chủ kênh

Ngoài quyền User:

- Upload video.
- Quản lý video.
- Quản lý playlist.
- Xem Analytics.
- Quản lý bình luận trên nội dung của mình.
- Tùy chỉnh kênh.
- Mời thành viên.
- Quản lý quyền kênh.
- Gửi yêu cầu bản quyền.

### D. Thành viên kênh

Quyền phụ thuộc Role được Chủ kênh cấp, ví dụ:

- Manager.
- Editor.
- Moderator.
- Viewer.

---

## 2.3.3. Trang chủ

### A. Danh sách video gợi ý

- Hiển thị dạng Grid.
- Desktop tham chiếu tối thiểu 3 video/hàng tùy kích thước.
- Tablet/Mobile tự giảm số cột.
- Infinite Scroll.
- Lazy Loading thumbnail.
- Skeleton khi tải.
- Không tải toàn bộ dữ liệu một lần.

Thông tin card video:

- Thumbnail.
- Thời lượng.
- Tiêu đề.
- Avatar kênh.
- Tên kênh.
- Lượt xem.
- Thời gian đăng.
- Badge nếu có.

### B. Chủ đề gợi ý

Hiển thị dạng chip cuộn ngang:

- Tất cả.
- Âm nhạc.
- Game.
- Thể thao.
- Công nghệ.
- Giáo dục.
- Tin tức.
- Các chủ đề khác từ hệ thống.

### C. Thao tác nhanh trên video

Menu `...`:

- Thêm vào Xem sau.
- Thêm vào Playlist.
- Không quan tâm.
- Không đề xuất kênh này.
- Báo cáo.
- Chia sẻ.

### D. Tín hiệu phục vụ recommendation

Có thể ghi nhận:

- View.
- Watch Duration.
- Like.
- Dislike.
- Share.
- Comment.
- Not Interested.
- Don't Recommend Channel.

---

### E. Bố trí trên Mobile

```text
App Bar
Logo HuTube                  Search | HuAI | Chuông
---------------------------------------------------
Topic Chips  → cuộn ngang
---------------------------------------------------
Video Card
[ Thumbnail full width / 16:9 ]
Avatar | Tiêu đề
       | Tên kênh · View · Thời gian
                                   ...
---------------------------------------------------
Video Card tiếp theo
---------------------------------------------------
Bottom Navigation
Home | Khám phá | + | Đăng ký | Bạn
```

Quy định:

- Feed 1 cột.
- Thumbnail chiếm toàn bộ chiều ngang vùng nội dung.
- Menu `...` mở Bottom Sheet.
- Topic dùng Horizontal Chips.
- Pull-to-Refresh để làm mới recommendation.
- Infinite Scroll tải tiếp khi gần cuối danh sách.

## 2.3.4. Khám phá

Cho phép khám phá nội dung theo:

- Chủ đề.
- Video mới.
- Video phổ biến.
- Xu hướng.
- Nội dung được quan tâm.

Bộ lọc/sắp xếp:

- Chủ đề.
- Thời gian.
- Loại nội dung.
- Ngôn ngữ nếu hỗ trợ.
- Mới nhất.
- Nhiều lượt xem.
- Tương tác cao.
- Đề xuất.

---

### Bố trí trên Mobile

- App Bar hiển thị `Khám phá` + Search.
- Chủ đề hiển thị Chip cuộn ngang.
- Các nhóm như `Xu hướng`, `Mới`, `Phổ biến` có thể dùng Section ngang hoặc Feed dọc.
- Nút Filter mở Bottom Sheet.
- Kết quả cuối cùng hiển thị Feed 1 cột giống Trang chủ.

## 2.3.5. Tìm kiếm

### A. Thanh tìm kiếm

- Nhập từ khóa.
- Xóa nhanh.
- Enter để tìm.
- Autocomplete.
- Gợi ý từ khóa.
- Lịch sử tìm kiếm.
- Xóa từng từ khóa lịch sử.
- Xóa toàn bộ lịch sử tìm kiếm.

### B. Kết quả tìm kiếm

Có thể trả về:

- Video.
- Channel.
- Playlist.

### C. Bộ lọc

- Ngày tải lên.
- Lượt xem.
- Thời lượng.
- Loại.
- Chủ đề.
- Sắp xếp theo liên quan/mới nhất/nhiều view.

### D. Kết quả Video

Mỗi dòng hiển thị:

- Thumbnail.
- Thời lượng trên thumbnail.
- Tên video.
- Tên kênh.
- Avatar kênh.
- Lượt xem.
- Thời gian đăng.
- Description rút gọn.
- Tag/Badge phù hợp.

### E. Cơ chế tải

- Infinite Scroll.
- Không tải toàn bộ kết quả ngay từ đầu.
- Giữ từ khóa và bộ lọc khi quay lại.

---

### F. Bố trí trên Mobile

Khi nhấn Search:

```text
Back | [ Nhập nội dung tìm kiếm................ ] | X
----------------------------------------------------
Lịch sử / Gợi ý tìm kiếm
```

Sau khi tìm:

```text
Back | Từ khóa tìm kiếm
----------------------------------------------------
[Video] [Kênh] [Playlist]       ← Tab ngang
[Filter] [Ngày] [Thời lượng]    ← Chip ngang
----------------------------------------------------
Kết quả dạng List
```

- Search mở màn hình Full-screen.
- Bộ lọc mở Bottom Sheet.
- Kết quả Video ưu tiên Thumbnail bên trái + Metadata bên phải nếu màn hình đủ rộng; trên máy hẹp dùng Card dọc.
- Giữ từ khóa và vị trí cuộn khi mở Video rồi quay lại.

## 2.3.6. Trang xem video

### A. Player

Player hỗ trợ:

- Play/Pause.
- Thanh tiến trình.
- Tua tới/lùi.
- Volume.
- Mute.
- Fullscreen.
- Theater Mode.
- Mini Player.
- Picture-in-Picture nếu trình duyệt hỗ trợ.
- Chọn chất lượng.
- Auto Quality.
- Playback Speed.
- Subtitle/Caption nếu có.
- Auto Play video kế tiếp.
- Loop.
- Sleep Timer.
- Phím tắt.

### B. Thông tin video

- Tiêu đề.
- Lượt xem.
- Ngày đăng.
- Description.
- Tag.
- Chủ đề.
- Kênh.
- Avatar kênh.
- Số subscriber/follower.
- Subscribe/Unsubscribe.

### C. Tương tác

- Like.
- Dislike.
- Share.
- Save.
- Add to Watch Later.
- Add to Playlist.
- Report.

### D. Description

- Expand/Collapse.
- Hiển thị link hợp lệ.
- Hashtag.
- Timestamp/Chapter nếu có.

### E. Video tiếp theo

- Danh sách đề xuất.
- Auto Play.
- Không quan tâm.
- Không đề xuất kênh.
- Thêm Xem sau.

### F. Ghi nhận lịch sử xem

- Thời gian bắt đầu xem.
- Watch Duration.
- Vị trí xem gần nhất.
- Resume từ vị trí cũ.

---

### G. Bố trí trên Mobile

#### Portrait

```text
[ Video Player 16:9 ]
-----------------------------
Tiêu đề
View · Ngày đăng          v
-----------------------------
Like | Dislike | Share | Save | ...
        ← cuộn ngang
-----------------------------
Avatar | Tên kênh     Subscribe
-----------------------------
Mô tả rút gọn
-----------------------------
Bình luận (123)         >
[ Preview comment ]
-----------------------------
Video đề xuất
[ Thumbnail ]
[ Metadata  ]
...
```

- Player nằm trên cùng.
- Khi cuộn xuống, Player có thể chuyển thành Mini Player tùy thiết kế.
- Comment mở thành Bottom Sheet cao hoặc màn hình Full-screen.
- Action Row cuộn ngang để tránh ép nút.
- Quality, Speed, Subtitle, Sleep Timer mở Bottom Sheet.
- Xoay ngang chuyển sang Fullscreen Player.
- Khi thoát Fullscreen, trả về đúng timestamp.

#### Gesture đề xuất

- Double Tap trái/phải: tua lùi/tới.
- Tap Player: hiện/ẩn Control.
- Swipe xuống Mini Player: thu nhỏ nếu hỗ trợ.
- Pinch Zoom chỉ dùng nếu Player hỗ trợ chế độ Fill/Fit.

## 2.3.7. Bình luận

### A. Danh sách

- Sort Top Comment/Mới nhất.
- Infinite Scroll.
- Hiển thị số Reply.
- Load Reply theo yêu cầu.

### B. Tạo Comment

- Nhập nội dung.
- Hủy.
- Gửi.
- Giới hạn độ dài.
- Kiểm tra từ bị cấm.
- Chống spam.

### C. Comment của mình

- Edit.
- Delete.
- Reply.
- Like.

### D. Comment người khác

- Reply.
- Like.
- Report.
- Block/Mute nếu hệ thống hỗ trợ.

### E. Mention

Hỗ trợ:

```text
@username
```

Người được Mention có thể nhận Notification.

---

### F. Bố trí trên Mobile

- Tại Video Page chỉ hiển thị số lượng + 1 Comment Preview.
- Nhấn khu vực Comment mở:
  - Bottom Sheet 70–95% chiều cao, hoặc
  - Full-screen Comments.
- Thanh nhập Comment cố định phía dưới và nằm trên bàn phím ảo.
- Reply mở inline bên dưới Comment.
- Menu `...` của Comment mở Bottom Sheet.
- Filter `Top/Mới nhất` dùng Chip hoặc Bottom Sheet.

## 2.3.8. Kênh đăng ký

### A. Sidebar

Hiển thị Top 5 kênh ưu tiên:

- Kênh thường xuyên xem.
- Kênh vừa có video mới.
- Kênh có tương tác cao với User.

Có nút `Xem tất cả`.

### B. Trang danh sách kênh đăng ký

Hiển thị:

- Avatar.
- Tên kênh.
- Subscriber/Follower.
- Trạng thái có video mới.

Bộ lọc:

- Theo tên.
- Hoạt động mới.
- Có video mới.
- A-Z.

### C. Notification Level của từng kênh

- Tất cả.
- Cá nhân hóa.
- Tắt.

---

### D. Bố trí trên Mobile

Tab `Kênh đăng ký` trong Bottom Navigation mở trực tiếp:

```text
App Bar: Kênh đăng ký
Avatar kênh → cuộn ngang
--------------------------------
Feed video mới từ các kênh
--------------------------------
Bottom Navigation
```

- Hàng Avatar phía trên hiển thị kênh vừa có Video mới.
- Nhấn `Tất cả` mở danh sách đầy đủ.
- Notification Level mở Bottom Sheet.

## 2.3.9. Chi tiết kênh

### A. Header

- Avatar.
- Banner.
- Tên kênh.
- Handle/Tag.
- Mô tả ngắn.
- Subscriber/Follower.
- Số video.
- Contact nếu công khai.
- Subscribe/Unsubscribe.
- Notification Setting.

### B. Tab Trang chủ

- Video nổi bật.
- Video mới.
- Video phổ biến.
- Playlist nổi bật.

Video phổ biến:

- Top 5 mặc định.
- Cho phép cuộn ngang/xem thêm.

### C. Tab Video

- Danh sách video.
- Mới nhất → cũ nhất mặc định.
- Filter.
- Sort mới nhất/cũ nhất/phổ biến nhất.

### D. Tab Playlist

- Playlist công khai.
- Số video.
- Thumbnail.
- Ngày cập nhật.

### E. Tab Giới thiệu

- Description.
- Ngày tham gia.
- Tổng view.
- Liên kết công khai.
- Contact công khai.

---

### F. Bố trí trên Mobile

```text
[ Banner ]
      (Avatar)
Tên kênh
@handle · Subscriber · Video
[ Subscribe ] [ Chuông ]
Mô tả rút gọn
--------------------------------
Home | Video | Playlist | Giới thiệu
           ← Tab cuộn ngang
--------------------------------
Nội dung Tab
```

- Header co lại khi cuộn.
- Tab có thể Sticky dưới App Bar.
- Video/Playlist hiển thị 1 cột hoặc 2 cột tùy kích thước màn hình.
- Contact/Link đặt trong Tab Giới thiệu thay vì chen quá nhiều vào Header.

## 2.3.10. Thư viện cá nhân

Thư viện gồm:

```text
Lịch sử xem
Video đã thích
Xem sau
Video của bạn
Tải xuống
Playlist
```

---

### Bố trí trên Mobile

Toàn bộ Thư viện được gom vào tab **Bạn**:

```text
App Bar: Bạn
--------------------------------
Avatar | Tên User
Xem kênh của bạn
--------------------------------
Lịch sử xem        >
Video đã thích     >
Xem sau            >
Tải xuống          >
Playlist           >
Video của bạn      >
--------------------------------
Plan hiện tại
Cài đặt
```

- Các nhóm dùng Card/Section.
- Hiển thị Preview ngang cho History/Playlist trước khi nhấn `Xem tất cả`.

## 2.3.11. Lịch sử xem

Hiển thị:

- Video.
- Channel.
- Ngày xem.
- Watch Progress.

Chức năng:

- Tiếp tục xem.
- Xóa từng Video.
- Xóa theo ngày.
- Xóa toàn bộ History.
- Tìm kiếm trong History.
- Tạm dừng lưu History.
- Bật lại History.

---

### Bố trí trên Mobile

- Danh sách 1 cột.
- App Bar có Search + Menu.
- `Xóa lịch sử`, `Tạm dừng lịch sử` đặt trong Menu/Bottom Sheet.
- Swipe item có thể hỗ trợ `Xóa khỏi lịch sử`, nhưng phải có Undo.
- Progress xem hiển thị ngay trên Thumbnail.

## 2.3.12. Video đã thích

- Danh sách Video đã Like.
- Phát.
- Bỏ Like.
- Add Playlist.
- Add Watch Later.
- Share.
- Search.
- Sort.

Nếu Video không còn khả dụng, hiển thị trạng thái phù hợp.

---

### Bố trí trên Mobile

- List 1 cột.
- Action nhanh mở Bottom Sheet.
- Có `Play All` nếu nghiệp vụ cho phép.
- Video không khả dụng hiển thị Placeholder + trạng thái rõ ràng.

## 2.3.13. Xem sau

- Add Video.
- Remove.
- Remove hàng loạt.
- Play All.
- Shuffle.
- Reorder nếu hỗ trợ.
- Sort.

Menu card Video có thao tác nhanh `Add to Watch Later`.

---

### Bố trí trên Mobile

- App Bar: `Xem sau`.
- Header nhỏ hiển thị số Video.
- CTA `Phát tất cả` và `Phát ngẫu nhiên`.
- Reorder bằng nhấn giữ và kéo.
- Bulk Action bật bằng Long Press/Select Mode.

## 2.3.14. Nội dung tải xuống

### A. Web

Nếu tải file thực sự:

- Download theo quyền/gói.
- Chọn chất lượng nếu cho phép.
- Hiển thị Progress.
- Cancel.
- Retry.

Nếu là Offline Download trong ứng dụng, phải phân biệt rõ với tải file về máy.

### B. Quản lý

- Danh sách Video đã tải.
- Dung lượng.
- Ngày tải.
- Chất lượng.
- Xóa.
- Xóa nhiều Video.

### C. Mobile

- Lưu Offline.
- Xóa Offline.
- Kiểm tra dung lượng thiết bị.
- Chỉ tải bằng Wi-Fi nếu bật tùy chọn.

---

### D. Bố trí trên Mobile

- Đây là màn hình Offline quan trọng.
- Hiển thị:
  - Tổng dung lượng Download.
  - Dung lượng còn lại thiết bị.
  - Danh sách Video Offline.
- Có trạng thái:
  - Đang chờ.
  - Đang tải.
  - Tạm dừng.
  - Hoàn tất.
  - Lỗi.
- Cho phép Pause/Resume/Retry.
- Setting Download đặt trong Menu:
  - Chỉ Wi-Fi.
  - Chất lượng mặc định.
  - Xóa tất cả.

## 2.3.15. Quản lý Playlist

### A. Danh sách Playlist

- Cover.
- Tên.
- Số Video.
- Visibility.
- Ngày cập nhật.

### B. Tạo Playlist

- Tên.
- Description.
- Visibility:
  - Public.
  - Unlisted.
  - Private.
- Cover nếu cho phép.

### C. Chi tiết Playlist

- Cover.
- Tên.
- Description.
- Số Video.
- Tổng thời lượng.
- Visibility.
- Share.
- Play All.
- Shuffle.
- Filter/Search Video.

### D. Quản lý Video trong Playlist

- Add.
- Remove.
- Remove hàng loạt.
- Drag & Drop.
- Move to Top.
- Move to Bottom.
- Sort Manual/Mới nhất/Cũ nhất/Phổ biến.

### E. Video không còn khả dụng

Nếu Video:

- Bị chủ kênh xóa.
- Bị Admin gỡ.
- Chuyển Private.
- Bị hạn chế.

thì Playlist:

- Không phát Video đó.
- Hiển thị cảnh báo.
- Cho phép Remove item.
- Không làm hỏng thứ tự các Video còn lại.

---

### F. Bố trí trên Mobile

#### Danh sách Playlist

- Grid 2 cột hoặc List tùy kích thước.
- FAB/Nút `+` để tạo Playlist.

#### Chi tiết Playlist

```text
[ Cover ]
Tên Playlist
Visibility · Số Video · Tổng thời lượng
[ Play ] [ Shuffle ] [ Share ] [...]
--------------------------------------
Video 1
Video 2
Video 3
```

- Edit mở màn hình riêng.
- Reorder dùng Drag Handle.
- Multi-select dùng Long Press.

## 2.3.16. Kênh của bạn - Creator Studio

Menu đề xuất:

```text
Tổng quan
Nội dung
Playlist
Phân tích
Cộng đồng
Bản quyền
Tùy chỉnh kênh
Thành viên & Quyền
Cài đặt
```

---

### Bố trí Creator Studio trên Mobile

Creator Studio không dùng Sidebar cố định.

Điểm vào:

```text
Tab Bạn
  ↓
Kênh của bạn
  ↓
Creator Studio
```

Navigation trong Studio:

```text
Tổng quan | Nội dung | Phân tích | Cộng đồng
            ← Tab ngang
```

Các mục ít dùng hơn đặt trong Menu:

```text
Playlist
Bản quyền
Thành viên & Quyền
Tùy chỉnh kênh
Cài đặt
```

Nút `+ Tạo` luôn dễ truy cập để Upload Video/Create Playlist.

## 2.3.17. Tổng quan Creator

Hiển thị:

- Subscriber.
- Tổng View.
- Watch Time.
- Video mới nhất.
- Comment mới.
- Video hoạt động tốt.
- Notification/Cảnh báo.
- Strike.
- Dung lượng đã sử dụng.
- Dung lượng còn lại.

Quick Action:

- Upload Video.
- Create Playlist.
- Edit Channel.
- View Analytics.

---

### Bố trí trên Mobile

- KPI Card dùng Carousel ngang:
  - Subscriber.
  - View.
  - Watch Time.
  - Storage.
- `Video mới nhất` hiển thị Card.
- `Comment mới`, `Cảnh báo`, `Strike` là các Section riêng.
- Quick Action dạng 2×2 hoặc Horizontal Actions.

## 2.3.18. Thành viên và quyền kênh

> Cần phân biệt **Moderator bình luận** và **người được mời quản trị kênh**. Đây là hai phạm vi quyền khác nhau.

### A. Owner

Có toàn quyền:

- Edit Channel.
- Upload.
- Edit/Delete Video.
- Manage Playlist.
- Manage Comment.
- Analytics.
- Copyright.
- Settings.
- Manage Member.
- Delete Channel.

Không thể bị thành viên khác xóa quyền Owner.

### B. Manager

Có thể:

- Xem Dashboard.
- Upload.
- Edit Video.
- Manage Playlist.
- Manage Comment.
- Analytics.
- Edit Channel theo quyền.

Không mặc định được:

- Xóa Channel.
- Chuyển Owner.
- Quản lý thanh toán cá nhân Owner.

### C. Editor

- Upload.
- Edit Video được phép.
- Manage Playlist.
- Xem dữ liệu nội dung.

Không mặc định được:

- Quản lý thành viên.
- Xóa Channel.
- Ban User.

### D. Moderator

Tập trung Community:

- Xem Comment.
- Reply.
- Hide Comment.
- Delete Comment nếu Owner cấp.
- Hide User From Channel.
- Report Comment.

Không có quyền mặc định:

- Edit Video.
- Upload.
- Channel Settings.
- Analytics nhạy cảm.

### E. Viewer

- Xem Dashboard.
- Xem Analytics được cấp.
- Không chỉnh sửa.

### F. Permission nhỏ đề xuất

```text
channel.view_dashboard
channel.edit_profile
channel.edit_branding

video.view
video.upload
video.edit
video.delete
video.publish

playlist.view
playlist.create
playlist.edit
playlist.delete

comment.view
comment.reply
comment.delete
comment.hide_user
comment.report

analytics.view

copyright.view
copyright.submit

member.view
member.invite
member.change_role
member.remove

channel.setting.view
channel.setting.edit
channel.delete
```

### G. Mời thành viên

- Nhập Email/User.
- Chọn Role.
- Gửi Invitation.
- Pending.
- Accept.
- Decline.
- Expire.
- Revoke Invitation.

### H. Quản lý thành viên

- Danh sách.
- Role.
- Ngày tham gia.
- Đổi Role.
- Remove.
- Xem Invitation đang chờ.
- Owner xác nhận khi cấp quyền nguy hiểm.

---

### I. Bố trí trên Mobile

- Danh sách thành viên là List.
- Mỗi item: Avatar + Tên + Role + trạng thái.
- Nhấn item mở Bottom Sheet chi tiết.
- `Mời thành viên` mở Full-screen Form.
- `Chọn Role` mở Bottom Sheet và mô tả quyền trước khi xác nhận.
- Permission chi tiết không hiển thị thành bảng rộng; dùng Accordion theo nhóm.

## 2.3.19. Tùy chỉnh kênh

### A. Thông tin kênh

- Tên.
- Handle/Tag.
- Description.
- Avatar.
- Banner.
- Contact.
- Social Link nếu hỗ trợ.

### B. Branding

- Avatar.
- Banner.
- Watermark/Logo trên Video.
- Preview.

Watermark:

- Upload ảnh.
- Chọn vị trí.
- Chọn thời điểm hiển thị:
  - Toàn Video.
  - Cuối Video.
  - Khoảng thời gian tùy chọn.

### C. Trang chủ kênh

Cho phép cấu hình:

- Featured Video.
- Video mới.
- Popular Uploads.
- Playlist Section.

---

### D. Bố trí trên Mobile

- Tùy chỉnh kênh dùng Form theo Section:
  - Hồ sơ.
  - Branding.
  - Trang chủ.
- Avatar/Banner cho phép Crop ngay sau khi chọn ảnh.
- Watermark Preview hiển thị trên Mock Player.
- CTA `Lưu` cố định phía dưới khi có thay đổi chưa lưu.

## 2.3.20. Quản lý nội dung của kênh

### A. Danh sách Video

- Thumbnail.
- Tên.
- Visibility.
- Restriction.
- Ngày đăng.
- View.
- Comment.
- Like.
- Trạng thái Moderation.

### B. Bộ lọc

- Visibility.
- Ngày.
- Trạng thái.
- Playlist.
- Chủ đề.
- Tag.
- Có cảnh báo/Strike.

### C. Bulk Action

- Add to Playlist.
- Change Visibility.
- Delete.
- Add Tag nếu hỗ trợ.
- Remove Playlist.

### D. Thao tác từng Video

- View.
- Edit.
- Analytics.
- Comment.
- Copy URL.
- Change Visibility.
- Delete.
- Download bản gốc nếu được phép.

---

### E. Bố trí trên Mobile

- Danh sách Video dùng List 1 cột.
- Mỗi Video:
  - Thumbnail nhỏ.
  - Tên.
  - Visibility.
  - Ngày.
  - View/Comment.
  - Menu `...`.
- Long Press bật Select Mode để Bulk Action.
- Filter mở Bottom Sheet.

## 2.3.21. Upload và tạo Video

### Bước 1 - Chọn file

- Drag & Drop.
- File Picker.
- Kiểm tra định dạng.
- Kiểm tra dung lượng.
- Kiểm tra Quota còn lại.
- Upload Progress.
- Pause/Resume nếu Storage hỗ trợ.
- Cancel.

### Bước 2 - Chi tiết

- Tên Video.
- Description.
- Thumbnail:
  - Auto-generated.
  - Custom Thumbnail.
- Playlist.
- Topic/Category.
- Tag.
- Ngôn ngữ.
- Audience nếu có.
- Age Restriction nếu cần.

### Bước 3 - Thành phần Video

Có thể hỗ trợ:

- Video Card.
- End Screen.
- Poll/Quiz.
- Subtitle.
- Chapter.

#### Video Card

- Link Video.
- Playlist.
- Channel nếu chính sách cho phép.
- Thời điểm xuất hiện.

#### Quiz/Poll

- Câu hỏi.
- Danh sách lựa chọn.
- Đáp án nếu là Quiz.
- Thời điểm xuất hiện.

### Bước 4 - Kiểm tra ban đầu

Kiểm tra:

- File đã xử lý chưa.
- Metadata.
- Policy.
- Copyright nếu hệ thống hỗ trợ.
- Cảnh báo.

Trạng thái:

```text
Uploading
Processing
Checking
Ready
Failed
```

### Bước 5 - Visibility

- Public.
- Private.
- Unlisted.
- Schedule Publish nếu hỗ trợ.

### Bước 6 - Publish

- Preview.
- Xác nhận.
- Publish.
- Copy URL.
- View Video.
- Open Analytics.

---

### Bố trí Upload trên Mobile

Upload chạy theo **Full-screen Wizard**, không dùng Modal nhỏ.

```text
Bước 1/5
Chọn Video
[ Preview ]
---------------------------
Hủy              Tiếp tục
```

Các bước:

1. Chọn file từ Gallery/File/Camera nếu hỗ trợ.
2. Chi tiết Video.
3. Thumbnail + Playlist + Category/Tag.
4. Policy Check/Visibility.
5. Preview + Publish.

Quy định:

- CTA `Tiếp tục/Đăng` cố định phía dưới.
- Upload Progress phải còn hoạt động khi User tạm chuyển màn hình nếu hệ điều hành cho phép.
- Khi mạng mất:
  - Pause.
  - Giữ Draft.
  - Retry khi có mạng.
- Không bắt User nhập tất cả metadata trên cùng một màn hình.

## 2.3.22. Chỉnh sửa Video

Cho phép chỉnh:

- Title.
- Description.
- Thumbnail.
- Playlist.
- Tag.
- Category.
- Subtitle.
- Visibility.
- Schedule.
- Cards.
- Quiz/Poll.
- End Screen.

Không nên tùy tiện thay file Video gốc nếu nghiệp vụ xác định upload mới là một Video khác.

---

### Bố trí trên Mobile

- Edit Video là Full-screen Form.
- Chia thành Accordion/Section:
  - Thông tin.
  - Thumbnail.
  - Playlist/Category.
  - Visibility.
  - Thành phần Video.
- Có cảnh báo `Chưa lưu thay đổi` khi Back.

## 2.3.23. Phân tích Video

### A. Tổng quan

- View.
- Watch Time.
- Average View Duration.
- Like.
- Dislike.
- Comment.
- Share.
- Subscriber Gained.
- Subscriber Lost.

### B. Reach

- Impression.
- CTR nếu có.
- Traffic Source.
- Search.
- Recommendation.
- External.

### C. Engagement

- Watch Time.
- Average Percentage Viewed.
- Audience Retention.

### D. Audience

- New/Returning Viewer.
- Subscriber/Non-subscriber.
- Device.
- Country/Region nếu được phép thu thập.

### E. Khoảng thời gian

- 7 ngày.
- 30 ngày.
- 90 ngày.
- Từ lúc Publish.
- Custom.

---

### F. Bố trí Analytics Video trên Mobile

```text
Video Thumbnail + Tên
--------------------------------
[Overview] [Reach] [Engagement] [Audience]
            ← Tab ngang
--------------------------------
KPI Cards → cuộn ngang
--------------------------------
Biểu đồ
--------------------------------
Top dữ liệu / bảng rút gọn
```

- Chart phải có Tooltip khi Tap.
- Bảng nhiều cột chuyển thành Card/List.
- Filter thời gian mở Bottom Sheet.

## 2.3.24. Phân tích kênh

- Subscriber Growth.
- Total View.
- Watch Time.
- Upload Count.
- Average View.
- Average Like.
- Average Comment.
- Top Video.
- Top Playlist.
- Traffic Source.
- Audience.
- Revenue nếu tương lai có Monetization.

Cho phép:

- Filter thời gian.
- So sánh kỳ trước.
- Export nếu gói/quyền cho phép.

---

### Bố trí Analytics kênh trên Mobile

- KPI Card dạng Carousel.
- Chart xếp dọc từng khối.
- Khoảng thời gian ở Chip phía trên.
- `So sánh kỳ trước` là Toggle/Option.
- Top Video/Top Playlist dùng Horizontal List.
- Export đặt trong Menu `...`.

## 2.3.25. Cộng đồng - Quản lý bình luận trên kênh

### A. Danh sách

Hiển thị:

- Avatar.
- User.
- Nội dung Comment.
- Video.
- Thumbnail Video.
- Ngày Comment.
- Like.
- Reply.
- Report nếu có.

### B. Filter

- Video.
- Ngày.
- Chưa trả lời.
- Có Report.
- Có từ bị chặn.
- User.

### C. Thao tác

- Reply trực tiếp.
- Like/Heart nếu hỗ trợ.
- Delete.
- Report.
- Hide User From Channel.
- Unhide User.
- View Video.
- View User.

### D. Bulk Action

- Delete.
- Hide User.
- Mark Reviewed.

---

### E. Bố trí Community trên Mobile

- Comment Card 1 cột.
- Thumbnail Video nhỏ ở góc/card header để biết Comment thuộc Video nào.
- Reply inline hoặc Full-screen thread.
- Swipe/Long Press mở thao tác moderation.
- Bulk Action dùng Select Mode.
- Filter mở Bottom Sheet.

## 2.3.26. Kiểm soát nội dung của kênh

### A. Từ bị chặn

Owner có thể:

- Add Keyword.
- Remove Keyword.
- Import danh sách.
- Search.
- Bật/tắt Filter.

Comment chứa từ bị chặn có thể:

- Giữ lại để duyệt.
- Ẩn.
- Từ chối.

### B. Link trong Comment

- Cho phép.
- Giữ để duyệt.
- Chặn.

### C. Comment Moderation

- Allow All.
- Hold Potentially Inappropriate.
- Hold All.
- Disable Comments.

### D. Hidden Users

- Danh sách.
- Search.
- Hide.
- Unhide.

### E. Moderator

- Add.
- Remove.
- Xem trạng thái.

---

### F. Bố trí trên Mobile

- Setting theo dạng Native List.
- Blocked Words mở màn hình riêng có Search + Add.
- Hidden Users mở List riêng.
- Comment Moderation dùng Radio/Select.
- Các thay đổi quan trọng có nút Save cố định.

## 2.3.27. Bản quyền

### A. Yêu cầu gỡ bỏ

- URL Video vi phạm.
- Nội dung bị sử dụng.
- Lý do.
- Mô tả.
- Thông tin liên hệ.
- Evidence/Attachment nếu hỗ trợ.
- Cam kết thông tin đúng.

### B. Trạng thái

```text
Draft
Submitted
InReview
NeedMoreInfo
Approved
Rejected
Withdrawn
```

### C. Theo dõi yêu cầu

- Xem trạng thái.
- Xem Timeline.
- Bổ sung thông tin.
- Rút yêu cầu nếu phù hợp.
- Nhận Notification/Email.

### D. Lịch sử

- Danh sách Copyright Request đã gửi.
- Kết quả xử lý.
- Ngày gửi.

---

### E. Bố trí Copyright trên Mobile

- Màn hình đầu là danh sách Request + trạng thái.
- Nút `Tạo yêu cầu` mở Full-screen Wizard.
- Evidence dùng File Picker/Photo Picker.
- Timeline hiển thị dạng dọc.
- `Bổ sung thông tin` chỉ hiện khi trạng thái `NeedMoreInfo`.

## 2.3.28. Cài đặt kênh

### A. Tổng quan

- Channel ID.
- Handle.
- Owner.
- Created At.

### B. Upload Default

- Visibility mặc định.
- Category mặc định.
- Tag mặc định.
- Description Template.

### C. Nội dung

- Comment Setting.
- Blocked Words.
- Hidden Users.
- Moderator.

### D. Quyền

- Member.
- Role.
- Invitation.

### E. Branding

- Avatar.
- Banner.
- Watermark.

### F. Cài đặt nâng cao

- Channel ID.
- Default Channel nếu User có nhiều kênh.
- Delete Channel.

---

### G. Bố trí Cài đặt kênh trên Mobile

Hiển thị dạng danh sách phân cấp:

```text
Cài đặt kênh
├── Thông tin chung
├── Upload mặc định
├── Nội dung & Bình luận
├── Thành viên & Quyền
├── Branding
└── Nâng cao
```

Không đặt toàn bộ Setting trên một màn hình dài.

## 2.3.29. Xóa kênh

Quy trình:

1. Chọn Delete Channel.
2. Hiển thị dữ liệu bị ảnh hưởng:
   - Video.
   - Playlist.
   - Comment.
   - Analytics.
3. Yêu cầu xác thực lại.
4. Yêu cầu nhập tên kênh/mã xác nhận.
5. Xác nhận.
6. Soft Delete/Deactivate theo Business Rule.
7. Gửi Email xác nhận.

Không cho thành viên thường xóa Channel.

---

### Bố trí xác nhận trên Mobile

- Dùng Full-screen Confirmation hoặc Bottom Sheet không thể bấm nhầm.
- Hiển thị rõ:
  - Tên kênh.
  - Số Video.
  - Playlist.
  - Hậu quả.
- Yêu cầu xác thực lại.
- Nút nguy hiểm đặt tách xa nút Cancel.

## 2.3.30. Menu Avatar / tài khoản

Click Avatar hiển thị:

- Tên.
- Email.
- Channel.
- View Channel.
- Account Settings.
- Đổi ngôn ngữ.
- Đổi giao diện.
- Phím tắt.
- HuAI.
- Đăng xuất.

---

### Bố trí trên Mobile

Mobile không cần Dropdown Avatar giống Web.

Tab **Bạn** đóng vai trò Account Hub.

App Bar hoặc trang Bạn có:

- Avatar.
- Tên.
- Email.
- Xem kênh.
- Chuyển kênh nếu User có nhiều kênh.
- Settings.
- Theme.
- Language.
- Shortcut/Help.
- Logout.

Các thao tác phụ mở Bottom Sheet.

## 2.3.31. Cài đặt tài khoản

### A. Hồ sơ

- Avatar.
- Tên hiển thị.
- Email.
- Email Verification.
- Ngôn ngữ.
- Theme.

### B. Bảo mật

- Đổi mật khẩu.
- Quên mật khẩu.
- Session đang đăng nhập.
- Đăng xuất thiết bị khác.
- Login History nếu hỗ trợ.
- Liên kết Google/Facebook nếu có.

### C. Notification

Tùy chọn:

- Kênh đăng ký.
- Video đề xuất.
- Mention.
- Hoạt động trên kênh.
- Reply Comment.
- Hoạt động với Comment của mình.
- Warning/Strike.
- Report Status.
- Copyright.
- Plan sắp hết hạn.
- Payment.
- System Announcement.

Mỗi nhóm có thể bật/tắt:

- In-App.
- Email.

### D. Privacy

- Cho phép Mention.
- Hiển thị Subscription công khai/riêng tư nếu hỗ trợ.
- Lưu Watch History.
- Lưu Search History.
- Personalization nếu hỗ trợ.
- Block List.

### E. Appearance

- Light.
- Dark.
- System.

### F. Language

- Đổi ngôn ngữ.
- Áp dụng ngay.
- Ghi nhớ lựa chọn.

### G. Advanced

- User ID.
- Channel ID.
- Download Data nếu tương lai hỗ trợ.
- Delete Account.

---

### H. Bố trí Settings trên Mobile

```text
Cài đặt
├── Tài khoản
├── Bảo mật
├── Thông báo
├── Quyền riêng tư
├── Giao diện
├── Ngôn ngữ
├── Tải xuống
└── Nâng cao
```

- Dùng Native-style List.
- Toggle cho thiết lập bật/tắt.
- Radio/Bottom Sheet cho lựa chọn một giá trị.
- Màn hình con có App Bar + Back.
- Không dùng Form Desktop nhiều cột.

## 2.3.32. Thông báo

### A. Notification Center

- Avatar/Thumbnail.
- Nội dung.
- Thời gian.
- Đã đọc/Chưa đọc.
- Deep Link.

### B. Loại Notification

- Video mới từ kênh đăng ký.
- Reply.
- Mention.
- Hoạt động trên kênh.
- Warning/Strike.
- Report.
- Copyright.
- Plan.
- Payment.
- System.

### C. Thao tác

- Mark As Read.
- Mark All As Read.
- Delete nếu cho phép.
- Filter Unread.
- Click mở đúng nội dung.

---

### D. Bố trí Notification trên Mobile

- Mở từ biểu tượng Chuông trên App Bar.
- List 1 cột.
- Unread có Indicator rõ.
- Swipe có thể `Đánh dấu đã đọc`.
- Filter `Tất cả/Chưa đọc` bằng Tab hoặc Chip.
- Tap Notification dùng Deep Link đến đúng màn hình.

## 2.3.33. Báo cáo nội dung

Đối tượng:

- Video.
- Comment.
- Channel.
- User nếu hệ thống hỗ trợ.

### A. Quy trình

1. Chọn Report.
2. Chọn loại vi phạm.
3. Chọn lý do chi tiết.
4. Nhập mô tả thêm nếu cần.
5. Submit.
6. Hiển thị xác nhận.

### B. Loại vi phạm ví dụ

- Spam.
- Lừa đảo.
- Quấy rối.
- Nội dung nguy hiểm.
- Nội dung tình dục.
- Bạo lực.
- Vi phạm bản quyền.
- Khác.

### C. Theo dõi

- Report History nếu hỗ trợ.
- Trạng thái cơ bản.
- Notification khi có kết quả phù hợp.

---

### D. Bố trí Report trên Mobile

- `Report` mở Bottom Sheet chọn nhóm lý do.
- Nếu cần mô tả/evidence thì chuyển sang Full-screen Form.
- CTA `Gửi báo cáo` cố định dưới cùng.
- Sau khi gửi hiển thị Success State, không đóng im lặng.

## 2.3.34. Chặn và ẩn người dùng

### A. Block cá nhân

User có thể Block User khác nếu hệ thống hỗ trợ.

Ảnh hưởng có thể gồm:

- Hạn chế tương tác.
- Hạn chế Mention.
- Hạn chế nhắn tin nếu tương lai có Messaging.

### B. Hide User From Channel

Chủ kênh/Moderator có thể:

- Hide User.
- Comment của User không hiển thị công khai theo Rule.
- Unhide.

`Block User` và `Hide User From Channel` là hai nghiệp vụ khác nhau.

---

### C. Bố trí trên Mobile

- Block/Hide nằm trong Bottom Sheet menu của User/Comment.
- Sau thao tác hiển thị Snackbar có `Hoàn tác` nếu nghiệp vụ cho phép.
- Danh sách Blocked/Hidden User nằm trong Settings hoặc Channel Moderation.

## 2.3.35. Chia sẻ

Cho phép chia sẻ:

- Video.
- Playlist.
- Channel.

Hình thức:

- Copy URL.
- Share qua ứng dụng nếu Browser/Mobile hỗ trợ.
- QR Code nếu muốn mở rộng.
- Start At đối với Video nếu hỗ trợ.

---

### Bố trí trên Mobile

- Ưu tiên Native Share Sheet của Android/iOS.
- Trước Share Sheet có thể hiển thị:
  - Copy Link.
  - Start At.
  - QR.
- Không tự xây danh sách hàng chục mạng xã hội nếu hệ điều hành đã hỗ trợ.

## 2.3.36. Thao tác nâng cao với Video

Menu Video:

- Add Watch Later.
- Add Playlist.
- Not Interested.
- Don't Recommend Channel.
- Report.
- Share.
- Copy URL.
- Copy URL At Current Time nếu hỗ trợ.

Trong Player:

- Quality.
- Speed.
- Subtitle.
- Auto Play.
- Loop.
- Sleep Timer.
- Theater.
- Mini Player.
- Full Screen.

---

### Bố trí trên Mobile

- Menu `...` của Video mở Bottom Sheet.
- Player Setting dùng Bottom Sheet nhiều cấp:
  - Quality.
  - Speed.
  - Caption.
  - Sleep Timer.
- Action phổ biến Like/Share/Save nằm trực tiếp dưới Video; Action ít dùng đưa vào `...`.

## 2.3.37. Phím tắt

Ví dụ:

```text
Space / K  -> Play/Pause
J          -> Tua lùi
L          -> Tua tới
M          -> Mute
F          -> Fullscreen
T          -> Theater Mode
C          -> Caption
↑ / ↓      -> Volume
```

Có Modal `Phím tắt` mở từ Avatar Menu hoặc Player.

---

### Mobile

Phím tắt vật lý không phải chức năng chính trên Mobile.

Thay bằng Gesture/Touch:

- Double Tap tua.
- Tap Play/Pause.
- Rotate Fullscreen.
- Swipe/Picture-in-Picture nếu hỗ trợ.
- Keyboard Shortcut vẫn có thể hoạt động khi dùng bàn phím ngoài nhưng không bắt buộc.

## 2.3.38. HuAI - Chatbot hỗ trợ nền tảng

### A. Hỏi đáp

Ví dụ:

- Cách tạo Channel?
- Làm sao đổi Plan?
- Tại sao Video bị ẩn?
- Cách tạo Playlist?
- Strike là gì?

### B. Điều hướng

Ví dụ:

```text
"Mở lịch sử xem"
→ /history
```

### C. Thao tác hỗ trợ

HuAI có thể hỗ trợ:

- Mở Settings.
- Tạo Playlist.
- Mở Upload.
- Tìm Video.
- Mở Channel.

### D. Xác nhận thao tác

Đối với thao tác thay đổi dữ liệu:

```text
User
 ↓
HuAI đề xuất hành động
 ↓
Preview
 ↓
User xác nhận
 ↓
Thực hiện
```

HuAI không được tự thực hiện các thao tác nhạy cảm như:

- Delete Channel.
- Delete Account.
- Delete Video.
- Purchase Plan.
- Cancel Subscription.
- Report.
- Change Permission.

nếu chưa có xác nhận rõ ràng.

---

### E. Bố trí HuAI trên Mobile

Điểm truy cập đề xuất:

- Icon HuAI trên App Bar.
- Mục HuAI trong tab `Bạn`.

Giao diện:

```text
HuAI
--------------------------------
Lịch sử hội thoại
--------------------------------
Tin nhắn
Tin nhắn
...
--------------------------------
[ Nhập câu hỏi........ ] [Gửi]
```

Khi HuAI đề xuất thao tác:

- Hiển thị Action Card.
- Có nút `Xem trước`.
- Có nút `Xác nhận`.
- Không tự điều hướng nhiều lần hoặc tự thao tác nhạy cảm.

## 2.3.39. Plan và Subscription phía người dùng

### A. Xem Plan

- Tên.
- Giá.
- Dung lượng.
- Chức năng.
- Giới hạn.
- Chu kỳ.

### B. Compare Plan

So sánh:

- Free.
- Các gói trả phí.

### C. Mua/Nâng cấp

1. Chọn Plan.
2. Xem chi tiết.
3. Chọn phương thức thanh toán.
4. Thanh toán.
5. Nhận kết quả.
6. Activate Subscription.

### D. Subscription

User có thể:

- Xem gói hiện tại.
- Ngày bắt đầu.
- Ngày hết hạn.
- Auto Renew.
- Upgrade.
- Downgrade nếu hỗ trợ.
- Cancel Renewal.
- Xem Payment History.

---

### E. Bố trí Plan trên Mobile

- Plan Card xếp dọc hoặc Carousel.
- Gói hiện tại có Badge rõ.
- So sánh tính năng dùng Accordion, không dùng bảng quá rộng.
- CTA `Nâng cấp` cố định hoặc đặt cuối Card.
- Subscription Management nằm trong `Bạn > Gói của bạn`.

## 2.3.40. Thanh toán phía người dùng

### A. Phương thức

- MoMo.
- ZaloPay.
- VNPay.
- Các phương thức mở rộng.

### B. Trạng thái

```text
Pending
Success
Failed
Cancelled
Refunded
```

### C. Lịch sử

- Transaction ID.
- Plan.
- Amount.
- Date.
- Status.
- Payment Method.

### D. Retry

Payment Failed có thể:

- Retry.
- Chọn phương thức khác.

Không tự động tạo nhiều Subscription cho cùng một giao dịch.

---

### E. Bố trí Payment trên Mobile

- Payment là Full-screen Flow.
- Chọn phương thức bằng List/Radio.
- Khi chuyển sang App thanh toán:
  - Lưu Transaction trạng thái `Pending`.
  - Khi quay lại App phải kiểm tra trạng thái từ Backend.
- Không tin hoàn toàn vào callback phía Client.
- Màn hình kết quả có:
  - Thành công.
  - Thất bại.
  - Đang xử lý.

## 2.3.41. Warning, Strike và vi phạm

User có thể xem:

- Warning.
- Strike.
- Nội dung liên quan.
- Policy vi phạm.
- Ngày nhận.
- Ngày hết hiệu lực.
- Hình phạt.
- Quyền Appeal.

Strike Center:

- Active.
- Expired.
- Revoked.

Khi có Strike:

- In-App Notification.
- Email nếu bật.
- Link đến chi tiết.

---

### Bố trí Strike Center trên Mobile

- Truy cập từ Notification hoặc `Bạn > Kênh của bạn > Vi phạm`.
- Card Strike hiển thị:
  - Trạng thái.
  - Policy.
  - Ngày.
  - Nội dung liên quan.
- CTA `Khiếu nại` chỉ hiển thị khi được phép.

## 2.3.42. Khiếu nại - Appeal

Cho phép Appeal nếu Policy cho phép đối với:

- Video bị gỡ.
- Comment bị gỡ.
- Strike.
- Channel bị hạn chế.
- Account bị hạn chế.

### A. Form

- Case/Decision.
- Reason.
- Description.
- Evidence.

### B. Trạng thái

- Pending.
- In Review.
- Approved.
- Rejected.
- Escalated.

### C. Kết quả

- Notification.
- Email.
- Timeline.

---

### D. Bố trí Appeal trên Mobile

- Danh sách Appeal theo trạng thái.
- Form Appeal Full-screen.
- Evidence dùng File Picker.
- Timeline dọc.
- Notification Deep Link về Appeal Detail.

## 2.3.43. Privacy và quản lý dữ liệu cá nhân

User có thể quản lý:

- Watch History.
- Search History.
- Mention.
- Subscription Visibility.
- Personalization.
- Block List.
- Session.

Các thao tác xóa dữ liệu phải có xác nhận:

- Clear Search History.
- Clear Watch History.
- Delete Account.

---

### Bố trí Privacy trên Mobile

- Mỗi nhóm Privacy là một Section riêng.
- Toggle cho:
  - Lưu History.
  - Lưu Search History.
  - Personalization.
  - Mention.
- Các thao tác xóa dữ liệu mở Confirmation riêng.

## 2.3.44. Quản lý Session

Hiển thị:

- Thiết bị.
- Browser.
- Thời gian đăng nhập.
- Hoạt động gần nhất.
- Trạng thái hiện tại.

Cho phép:

- Logout Session.
- Logout All Other Devices.

Không hiển thị:

- Access Token.
- Refresh Token.
- Password.

---

### Bố trí Session trên Mobile

- Mỗi thiết bị là một Card:
  - Tên thiết bị.
  - OS/App.
  - Lần hoạt động gần nhất.
  - Thiết bị hiện tại.
- `Đăng xuất` đặt trên từng Card.
- `Đăng xuất khỏi tất cả thiết bị khác` là Action riêng có Confirmation.

## 2.3.45. Xóa tài khoản

Quy trình:

1. Mở Advanced Settings.
2. Chọn Delete Account.
3. Hiển thị dữ liệu bị ảnh hưởng.
4. Xác thực lại.
5. Nhập xác nhận.
6. Delete/Deactivate theo Business Rule.
7. Gửi Email.

Nếu User là Owner duy nhất của Channel:

- Yêu cầu xử lý Channel trước.
- Chuyển Owner hoặc xóa Channel theo Business Rule.

---

### Bố trí trên Mobile

- Delete Account đặt sâu trong `Bạn > Cài đặt > Nâng cao`.
- Không đặt cạnh Logout.
- Dùng Full-screen Confirmation nhiều bước.
- Hỗ trợ Password/Re-authentication/Biometric nếu kiến trúc xác thực cho phép.

## 2.3.46. Trạng thái nội dung cần chuẩn hóa

### A. Video

```text
Draft
Uploading
Processing
Checking
Ready
Scheduled
Published
Private
Unlisted
Hidden
Removed
Failed
```

### B. Playlist

```text
Public
Unlisted
Private
Deleted
```

### C. Channel

```text
Active
Suspended
Banned
Deleted
```

### D. Subscription

```text
Pending
Active
Expired
Cancelled
PastDue
```

### E. Upload

```text
Pending
Uploading
Processing
Checking
Ready
Failed
Cancelled
```

---

## 2.3.47. Quy tắc quyền truy cập nội dung

### Public

- Guest xem được.
- Search có thể Index.
- Recommendation có thể sử dụng.

### Unlisted

- Không xuất hiện bình thường trong Search/Recommendation.
- Người có URL có thể xem.

### Private

- Chỉ chủ sở hữu hoặc người được cấp quyền.

### Hidden

- Nội dung tạm ẩn.
- Không truy cập công khai.

### Removed

- Nội dung đã bị gỡ.
- Hiển thị thông báo phù hợp.

---

## 2.3.48. Các trạng thái UI bắt buộc

Mọi chức năng chính cần có:

- Loading.
- Success.
- Empty.
- Error.
- Unauthorized.
- Forbidden.
- Not Found.
- Content Removed.
- Network Offline nếu Mobile.
- Retry.

Ví dụ:

```text
Playlist này chưa có video.
```

```text
Video này không còn khả dụng.
```

---

## 2.3.49. Quy tắc Responsive và Adaptive Layout

### A. Desktop Web

- Sidebar đầy đủ.
- Topbar đầy đủ.
- Grid nhiều cột.
- Video Page có Recommendation bên phải.
- Creator Studio có Navigation dọc/trái.
- Form có thể dùng 2 cột khi hợp lý.
- Modal dùng cho thao tác ngắn.

### B. Tablet Web/Mobile

- Sidebar chuyển Compact/Drawer.
- Grid giảm số cột.
- Recommendation chuyển xuống dưới Player nếu thiếu chiều rộng.
- Creator Studio dùng Tab + Drawer.
- Form ưu tiên 1 cột.

### C. Mobile Phone

#### Navigation

- Bottom Navigation cho màn hình cấp cao.
- App Bar + Back cho màn hình cấp con.
- Bottom Sheet cho thao tác ngắn.
- Full-screen Page cho nghiệp vụ dài.

#### Nội dung

- Feed 1 cột.
- Horizontal Scroll cho Chip, KPI Card và Action Row.
- Không dùng bảng rộng; chuyển thành Card/List.
- Không đặt quá 3–4 Action quan trọng trực tiếp trên một hàng.
- Nội dung phụ đưa vào `...`.

#### Form

- 1 cột.
- Label rõ.
- Input đủ lớn cho Touch.
- CTA chính cố định phía dưới nếu Form dài.
- Không để bàn phím che Input/CTA.

#### Player

- Portrait: Player phía trên.
- Landscape: Fullscreen.
- Gesture hỗ trợ tua/phát.
- Comment và Setting dùng Bottom Sheet/Full-screen.

#### Safe Area

Phải chừa khoảng cho:

- Notch/Dynamic Island.
- Status Bar.
- Navigation Gesture Area.
- Bottom Navigation.

### D. Adaptive Breakpoint tham khảo

Không bắt buộc khóa cứng theo px, nhưng có thể tham chiếu:

```text
Mobile nhỏ:       < 480px
Mobile lớn:       480–767px
Tablet:           768–1023px
Desktop:          >= 1024px
Desktop lớn:      >= 1440px
```

UI phải dựa trên không gian thực tế thay vì chỉ dựa vào loại thiết bị.

### E. Orientation

- App mặc định Portrait.
- Video Player hỗ trợ Landscape Fullscreen.
- Các màn hình khác không bắt buộc Landscape nhưng không được vỡ layout.
- Khi xoay màn hình phải giữ:
  - Timestamp Video.
  - Form state.
  - Tab.
  - Vị trí hợp lý.

---


## 2.3.50. Luồng nghiệp vụ tổng quát

### A. Xem Video

```text
Trang chủ/Search
      ↓
Chọn Video
      ↓
Load Metadata + Player
      ↓
Play
      ↓
Ghi View/Watch Duration
      ↓
Like/Comment/Share/Save
      ↓
Cập nhật Recommendation Signal
```

### B. Subscribe Channel

```text
User
 ↓
Subscribe
 ↓
Kiểm tra đăng nhập
 ↓
Tạo Subscription
 ↓
Cập nhật Subscriber Count
 ↓
Chọn Notification Level
```

### C. Upload Video

```text
Creator
 ↓
Chọn File
 ↓
Kiểm tra Quota/File
 ↓
Upload
 ↓
Processing
 ↓
Metadata
 ↓
Policy Check
 ↓
Visibility
 ↓
Publish
```

### D. Report

```text
User
 ↓
Report
 ↓
Chọn vi phạm
 ↓
Mô tả
 ↓
Submit
 ↓
Tạo Report Case
 ↓
Moderator xử lý
 ↓
Notification kết quả
```

---

## 2.3.51. Cấu trúc điều hướng đề xuất cuối cùng

### A. Web User - Sidebar

```text
Trang chủ

Khám phá

Kênh đăng ký
├── Top kênh
└── Xem tất cả

Thư viện
├── Lịch sử xem
├── Video đã thích
├── Xem sau
├── Video của bạn
├── Tải xuống
└── Playlist

Kênh của bạn
├── Tổng quan
├── Nội dung
├── Playlist
├── Phân tích
├── Cộng đồng
├── Bản quyền
├── Thành viên & Quyền
└── Cài đặt

Khác
├── Plan
├── HuAI
├── Cài đặt tài khoản
└── Trợ giúp
```

### B. Mobile User - Bottom Navigation

```text
[Trang chủ] [Khám phá] [+ Tạo] [Đăng ký] [Bạn]
```

#### Trang chủ

- Recommendation Feed.
- Topic Chips.
- Video Feed.

#### Khám phá

- Trending.
- Topic.
- Popular.
- New Content.

#### + Tạo

Mở Bottom Sheet:

```text
Tải Video lên
Tạo Playlist
Tạo kênh              // nếu chưa có
```

#### Kênh đăng ký

- Feed Video mới.
- Danh sách Channel Subscribe.
- Notification Level.

#### Bạn

```text
Bạn
├── Hồ sơ
├── Kênh của bạn
│   └── Creator Studio
├── Lịch sử xem
├── Video đã thích
├── Xem sau
├── Tải xuống
├── Playlist
├── Video của bạn
├── Plan & Subscription
├── HuAI
├── Cài đặt
└── Trợ giúp
```

### C. Mobile Creator Studio

Trong `Bạn > Kênh của bạn > Creator Studio`:

```text
Tabs chính:
Tổng quan | Nội dung | Phân tích | Cộng đồng

Menu phụ:
Playlist
Bản quyền
Thành viên & Quyền
Tùy chỉnh kênh
Cài đặt kênh
Vi phạm/Strike
```

### D. Quy tắc hiển thị menu

- Menu phụ thuộc trạng thái đăng nhập.
- User chưa có Channel không hiển thị Creator Studio.
- Member chỉ thấy chức năng được Permission cho phép.
- Moderator không mặc định thấy Analytics/Settings.
- Guest chỉ thấy các chức năng công khai.

---



## 2.3.52. Ma trận bố trí màn hình Web và Mobile

| Chức năng | Web User | Mobile User App |
|---|---|---|
| Trang chủ | Sidebar + Topbar + Grid nhiều cột | App Bar + Feed 1 cột + Bottom Nav |
| Khám phá | Grid/List + Filter | Chip ngang + Feed + Bottom Sheet Filter |
| Search | Search Bar trên Topbar + Result Page | Full-screen Search + Tab + Filter Chip |
| Xem Video | Player trái, Recommendation phải | Player trên, Action/Channel/Comment/Recommend xếp dọc |
| Comment | Khu vực dưới Video | Bottom Sheet/Full-screen |
| Channel | Banner + Tab + Grid | Header co giãn + Tab ngang + Feed |
| Subscription | Sidebar + trang riêng | Bottom Nav riêng |
| Thư viện | Sidebar + nhiều trang | Gom vào Tab Bạn |
| History | List | List + Pull-to-Refresh/Swipe |
| Playlist | Trang danh sách/chi tiết | Grid/List + Full-screen Detail |
| Creator Studio | Sidebar Studio | Tab ngang + Menu phụ |
| Upload Video | Modal/Wizard hoặc Page | Full-screen Wizard |
| Manage Video | Table/List | List + Long Press Select |
| Analytics | Dashboard nhiều cột | KPI Carousel + Chart xếp dọc |
| Community | Table/List | Comment Card + Bottom Sheet |
| Channel Settings | Sidebar Setting | List phân cấp |
| Account Settings | Trang nhiều Section | Native List + màn hình con |
| Notification | Dropdown + Page | Full-screen List |
| Report | Modal | Bottom Sheet → Full-screen nếu dài |
| Share | Modal | Native Share Sheet |
| Plan | Card/Table | Card dọc/Carousel |
| Payment | Page/Redirect | Full-screen Flow + App Deep Link |
| HuAI | Side Panel/Popup/Page | Full-screen Chat |
| Copyright | Page + Form | List + Full-screen Wizard |
| Appeal | Page + Timeline | List + Full-screen Form/Timeline |
| Session | Table/Card | Device Card List |

---

## 2.3.53. Quy tắc thiết kế riêng cho Mobile

### A. Touch Target

- Nút/Icon phải đủ lớn để thao tác bằng ngón tay.
- Không đặt hai thao tác nguy hiểm quá sát nhau.
- Không phụ thuộc Hover.

### B. Bottom Navigation

- Chỉ hiển thị màn hình cấp cao.
- Không hiển thị trên:
  - Fullscreen Player.
  - Upload Wizard.
  - Payment.
  - Một số Form Full-screen.
- Khi ẩn Bottom Nav phải có Back rõ ràng.

### C. Bottom Sheet

Bottom Sheet phải có:

- Drag Handle.
- Title nếu có nhiều lựa chọn.
- Scroll khi nội dung dài.
- Safe Area phía dưới.
- Close/Swipe Down khi không làm mất dữ liệu quan trọng.

### D. Keyboard

- Tự cuộn Input đang nhập lên trên bàn phím.
- Enter/Done thực hiện hành động phù hợp.
- Không để CTA bị Keyboard che.
- Search Keyboard có nút Search.

### E. Offline và mạng yếu

Mobile cần xử lý:

- Mất mạng.
- Timeout.
- Retry.
- Upload bị gián đoạn.
- Download bị gián đoạn.
- Nội dung Cached.
- Draft chưa đồng bộ.

### F. Deep Link

Notification/Share Link phải mở đúng:

- Video.
- Channel.
- Playlist.
- Comment Thread nếu có.
- Report.
- Appeal.
- Strike.
- Payment Result.

Nếu chưa đăng nhập:

```text
Deep Link
   ↓
Login
   ↓
Quay lại đúng màn hình đích
```

### G. Permission hệ điều hành

App có thể yêu cầu:

- Photo/Video Library.
- Camera.
- Microphone nếu tương lai có Record.
- Notification.
- Storage tùy nền tảng.

Chỉ yêu cầu Permission khi User bắt đầu chức năng cần dùng, không xin toàn bộ ngay lần đầu mở App.

### H. Mini Player

Nếu hỗ trợ:

```text
Video Page
   ↓ Back/Swipe
Mini Player phía trên Bottom Nav
   ↓ Tap
Quay lại Video Page
```

Mini Player:

- Play/Pause.
- Close.
- Thumbnail.
- Tên Video.
- Không che Bottom Navigation.

### I. Accessibility

- Hỗ trợ Dynamic Text/Font Scale.
- Có Label cho Icon.
- Contrast đủ rõ.
- Không chỉ dùng màu để biểu thị trạng thái.
- Caption/Subtitles dễ bật.

---

## 2.3.54. Danh sách chức năng nhỏ cần kiểm thử riêng

- Subscribe/Unsubscribe.
- Notification Level của từng kênh.
- Like/Unlike.
- Dislike/Undislike.
- Comment/Edit/Delete.
- Reply Comment.
- Mention.
- Share.
- Copy URL.
- Add Playlist.
- Remove Playlist.
- Watch Later.
- Remove Watch Later.
- Clear History.
- Pause History.
- Search History.
- Clear Search History.
- Not Interested.
- Don't Recommend Channel.
- Report.
- Block User.
- Hide User From Channel.
- Resume Video.
- Auto Play.
- Quality.
- Speed.
- Subtitle.
- Full Screen.
- Theater.
- Mini Player.
- Sleep Timer.
- Shuffle Playlist.
- Reorder Playlist.
- Bulk Remove.
- Upload Cancel.
- Upload Retry.
- Processing Failed.
- Change Visibility.
- Schedule Publish.
- Edit Metadata.
- Delete Video.
- Invite Member.
- Revoke Invitation.
- Change Member Role.
- Remove Member.
- Blocked Words.
- Hidden Users.
- Moderator.
- Copyright Request.
- Appeal.
- Notification Read/Unread.
- Change Theme.
- Change Language.
- Logout.
- Logout Other Sessions.
- Upgrade Plan.
- Cancel Renewal.
- Payment Retry.
- Delete Channel.
- Delete Account.

---

## 2.3.55. Nguyên tắc nghiệp vụ bắt buộc

1. Guest chỉ truy cập chức năng công khai.
2. Các thao tác cá nhân yêu cầu đăng nhập.
3. Owner là người có quyền cao nhất trong Channel.
4. Channel Moderator không mặc định có quyền chỉnh sửa Video.
5. Member Role và Permission phải được kiểm tra ở API, không chỉ ẩn nút trên giao diện.
6. Video Private không xuất hiện trong Search/Recommendation công khai.
7. Video Unlisted chỉ truy cập qua URL hoặc khu vực được phép.
8. Nội dung Removed/Hidden không được phát công khai.
9. Playlist không được lỗi toàn bộ chỉ vì một Video không còn khả dụng.
10. Delete Channel/Delete Account phải yêu cầu xác thực lại.
11. Payment phải chống tạo giao dịch trùng.
12. Upload phải kiểm tra Quota trước khi ghi Storage và xử lý trường hợp vượt Quota.
13. User không được xem Analytics của Channel khác nếu không có quyền.
14. Không hiển thị Password, Token hoặc Credential ở UI.
15. Mọi thay đổi quyền Channel phải ghi lịch sử.
16. Report và Appeal phải có trạng thái để User theo dõi nếu nghiệp vụ cho phép.
17. Warning/Strike phải hiển thị Policy liên quan.
18. History, Search History và dữ liệu cá nhân phải tuân theo Privacy Setting.
19. HuAI phải yêu cầu xác nhận trước thao tác nhạy cảm.
20. Responsive không được làm mất chức năng; chỉ thay đổi cách bố trí.

21. Web và Mobile phải cho cùng một kết quả nghiệp vụ đối với cùng một hành động.
22. Mobile không được bỏ chức năng nghiệp vụ chỉ vì không đủ không gian; chức năng phụ phải chuyển vào Menu/Bottom Sheet.
23. Deep Link sau Login phải quay lại đúng tài nguyên mà User đang muốn mở.
24. Upload/Download trên Mobile phải có khả năng phục hồi hợp lý khi mạng gián đoạn.
25. Bottom Navigation không được hiển thị đè lên CTA, bàn phím hoặc Mini Player.
26. Player khi đổi Portrait/Landscape phải giữ nguyên timestamp và trạng thái phát.
27. Mobile phải phân biệt dữ liệu đã Cache với dữ liệu mới từ Server khi có nguy cơ gây hiểu nhầm.
28. Permission hệ điều hành chỉ được xin tại thời điểm cần sử dụng chức năng tương ứng.
29. Các hành động bằng Gesture phải luôn có cách thực hiện thay thế bằng nút/menu.
30. Mọi màn hình quan trọng phải kiểm thử trên ít nhất một màn hình nhỏ và một màn hình lớn.
