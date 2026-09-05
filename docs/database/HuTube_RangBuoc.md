# HuTube — Thuộc tính phát sinh và ràng buộc trạng thái/default

Tài liệu này mô tả các phần được bổ sung trong script SQL Server của HuTube.
Phạm vi gồm thuộc tính phát sinh, các giá trị `DEFAULT`, ràng buộc `status` và một số
ràng buộc nghiệp vụ quan trọng được bổ sung sau khi hoàn thiện sơ đồ lớp phân tích /
sơ đồ lớp thiết kế.

Không liệt kê chi tiết khóa chính, khóa ngoại.

## Các thay đổi nghiệp vụ đã chốt

| Nội dung | Quyết định |
|---|---|
| Kết quả xử lý báo cáo | Bổ sung `resolution_types`; mỗi `report_resolution` phải chỉ ra loại xử lý đã áp dụng. |
| Khiếu nại | Một người dùng có thể khiếu nại nhiều lần cho cùng một `report_resolution`; phân biệt bằng `appeal_number`. |
| Kênh | Một `user` chỉ được sở hữu tối đa một `channel`. |
| Watch Later | Không tạo bảng riêng; dùng `playlists.playlist_type = watch_later`. Mỗi user chỉ có tối đa một Watch Later playlist. |
| Chất lượng video | Bổ sung `video_renditions` để lưu các bản encode như 360p, 720p, 1080p. |
| Chia sẻ video | Bổ sung `share_histories` để lưu lịch sử chia sẻ, phục vụ thống kê và có thể dùng làm implicit feedback cho hệ thống đề xuất. |
| Role | Giữ nguyên các role seed hiện có trong SQL (`user`, `creator`, `moderator`, `admin`). |

## Thuộc tính phát sinh

Các thuộc tính sau không có trong sơ đồ lớp ban đầu hoặc được bổ sung trong giai đoạn
thiết kế để phục vụ vận hành thực tế, bảo mật và truy vết dữ liệu:

| Bảng | Thuộc tính phát sinh | Mục đích |
|---|---|---|
| `roles` | `code`, `created_at`, `updated_at` | Định danh role ổn định và theo dõi thay đổi. |
| `permissions` | `status`, `created_at`, `updated_at` | Bật/tắt quyền mà không cần xóa dữ liệu. |
| `plans` | `code`, `created_at`, `updated_at` | Mã gói ổn định và theo dõi thay đổi. |
| `users` | `password_hash`, `email_verified_at`, `last_login_at`, `failed_login_attempts`, `locked_until` | Không lưu mật khẩu thuần, xác thực email và chống đăng nhập dò mật khẩu. |
| `refresh_tokens` | Toàn bộ bảng | Lưu **hash** refresh token JWT, thời hạn, thu hồi, thiết bị/IP và chuỗi thay thế token. Access token không được lưu. |
| `notifications` | `action_url`, `read_at` | Liên kết đến màn hình liên quan và thời điểm đã đọc. |
| `channels` | `handle` | Đường dẫn/mã kênh duy nhất, ví dụ `@hutube`. |
| `payments` | `plan_history_id`, `currency`, `created_at`, `updated_at` | Liên kết lịch sử gói, tiền tệ và theo dõi giao dịch. |
| `videos` | `published_at` | Thời điểm video được công khai. |
| `video_renditions` | Toàn bộ bảng | Lưu từng bản video đã encode theo chất lượng; ví dụ 360p/720p/1080p, URL trên object storage, kích thước, bitrate và trạng thái encode. |
| `playlists` | `playlist_type` | Phân biệt playlist thông thường và playlist hệ thống `watch_later`. |
| `share_histories` | Toàn bộ bảng | Ghi nhận mỗi lần user chia sẻ video, phương thức chia sẻ và thời điểm chia sẻ. |
| `recommendations` | `algorithm`, `expires_at` | Ghi nhận thuật toán và hạn dùng của kết quả gợi ý. |
| `recommendation_items` | `reason` | Lý do ngắn giải thích gợi ý video. |
| `user_permissions` | `is_granted` | Cho phép cấp hoặc chặn riêng một quyền, ghi đè quyền kế thừa từ role. |
| `resolution_types` | Toàn bộ bảng | Danh mục các cách xử lý báo cáo như gỡ video, xóa bình luận, khóa/cấm kênh hoặc không xử lý. |
| `report_resolutions` | `resolution_type_id` | Xác định hành động kiểm duyệt cụ thể đã áp dụng cho kết quả xử lý báo cáo. |
| `appeals` | `appeal_number`, `reviewer_id`, `review_note` | Cho phép khiếu nại nhiều lần và lưu thông tin người duyệt/kết quả duyệt. |

Ngoài ra, các bảng nghiệp vụ có dữ liệu thay đổi (`roles`, `users`, `videos`,
`video_renditions`, `comments`, `payments`, `resolution_types`, …) dùng
`created_at`/`updated_at` để truy vết. Trigger của SQL Server tự cập nhật
`updated_at` mỗi khi bản ghi được sửa.

## Ràng buộc nghiệp vụ quan trọng

### Một User chỉ sở hữu tối đa một Channel

`channels.owner_user_id` được áp dụng unique index.

```text
User 1 -------- 0..1 Channel
```

Một user không thể tạo hai channel khác nhau.

### Watch Later dùng Playlist

Không tạo bảng `watch_later` riêng. `playlists` có:

```text
playlist_type = normal | watch_later
```

Mỗi user chỉ được có tối đa một playlist có `playlist_type = watch_later`.

### Video và các bản chất lượng

```text
Video 1 -------- 0..* VideoRendition
```

Một video có thể chưa có rendition khi đang xử lý, sau đó có một hoặc nhiều bản như
360p, 720p, 1080p. Cặp `(video_id, quality_label)` là duy nhất.

### Lịch sử chia sẻ

```text
User  1 -------- 0..* ShareHistory
Video 1 -------- 0..* ShareHistory
```

Không đặt unique `(user_id, video_id)` vì một user có thể chia sẻ cùng một video nhiều lần.

### ReportResolution và ResolutionType

```text
ResolutionType 1 -------- 0..* ReportResolution
```

`ViolationType` mô tả **vi phạm gì**, còn `ResolutionType` mô tả **xử lý như thế nào**.

### Khiếu nại nhiều lần

Một user có thể tạo nhiều `appeals` cho cùng một `report_resolution`. Mỗi lần được
phân biệt bằng:

```text
(user_id, resolution_id, appeal_number)
```

`appeal_number` phải lớn hơn `0`.

## Ràng buộc `status`

| Bảng | Giá trị hợp lệ | Giá trị mặc định |
|---|---|---|
| `roles` | `active`, `inactive` | `active` |
| `permissions` | `active`, `inactive` | `active` |
| `plans` | `active`, `inactive`, `archived` | `active` |
| `users` | `pending`, `active`, `suspended`, `banned`, `deleted` | `pending` |
| `channels` | `active`, `suspended`, `banned`, `deleted` | `active` |
| `channel_actions` | `active`, `expired`, `revoked` | `active` |
| `subscriptions` | `active`, `paused` | `active` |
| `plan_histories` | `pending`, `active`, `expired`, `cancelled` | `active` |
| `payments` | `pending`, `processing`, `paid`, `failed`, `cancelled`, `refunded` | `pending` |
| `categories` | `active`, `inactive` | `active` |
| `videos` | `uploading`, `processing`, `published`, `blocked`, `deleted`, `failed` | `processing` |
| `video_renditions` | `processing`, `ready`, `failed` | `processing` |
| `comments` | `visible`, `hidden`, `held`, `deleted` | `visible` |
| `recommendations` | `generating`, `active`, `expired`, `failed` | `active` |
| `violation_types` | `active`, `inactive` | `active` |
| `resolution_types` | `active`, `inactive` | `active` |
| `reports` | `pending`, `reviewing`, `resolved`, `rejected`, `cancelled` | `pending` |
| `report_resolutions` | `approved`, `rejected`, `no_violation` | Không có |
| `appeals` | `pending`, `reviewing`, `approved`, `rejected`, `cancelled` | `pending` |

Lưu ý:

- `visibility` của `videos` và `playlists` không phải `status`, nhưng cũng bị giới hạn giá trị để kiểm soát quyền xem.
- `playlist_type` cũng không phải `status`; chỉ nhận `normal` hoặc `watch_later`.
- `resolution_types.target_type` chỉ nhận `video`, `comment`, `channel` hoặc `any`.

## Các giá trị `DEFAULT`

Quy ước: `UTC now` là `SYSUTCDATETIME()`; giá trị GUID tự sinh cho cột mã định danh
không được liệt kê ở đây.

| Bảng | Cột và giá trị mặc định |
|---|---|
| `roles` | `is_default = 0`; `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `permissions` | `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `plans` | `price = 0`; `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `users` | `status = pending`; `failed_login_attempts = 0`; `created_at = UTC now`; `updated_at = UTC now` |
| `role_permissions` | `assigned_at = UTC now` |
| `user_permissions` | `is_granted = 1`; `granted_at = UTC now` |
| `refresh_tokens` | `jti = NEWID()`; `issued_at = UTC now` |
| `notification_settings` | Tất cả cờ thông báo = `1`; `updated_at = UTC now` |
| `notifications` | `is_read = 0`; `created_at = UTC now` |
| `search_histories` | `search_type = all`; `searched_at = UTC now` |
| `channels` | `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `channel_quotas` | `storage_used = 0`; `updated_at = UTC now` |
| `channel_actions` | `created_at = UTC now`; `status = active` |
| `subscriptions` | `subscribed_at = UTC now`; `notifications_enabled = 1`; `status = active` |
| `plan_histories` | `status = active`; `created_at = UTC now` |
| `payments` | `currency = VND`; `status = pending`; `created_at = UTC now`; `updated_at = UTC now` |
| `categories` | `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `videos` | `visibility = public`; `status = processing`; `created_at = UTC now`; `updated_at = UTC now` |
| `video_renditions` | `status = processing`; `created_at = UTC now`; `updated_at = UTC now` |
| `tags` | `created_at = UTC now` |
| `video_tags` | `created_at = UTC now` |
| `playlists` | `visibility = private`; `playlist_type = normal`; `created_at = UTC now`; `updated_at = UTC now` |
| `playlist_videos` | `added_at = UTC now` |
| `viewing_histories` | `viewed_at = UTC now`; `watch_duration = 0`; `progress = 0` |
| `share_histories` | `share_method = copy_link`; `shared_at = UTC now` |
| `video_reactions` | `created_at = UTC now`; `updated_at = UTC now` |
| `comments` | `status = visible`; `created_at = UTC now`; `updated_at = UTC now` |
| `comment_reactions` | `created_at = UTC now`; `updated_at = UTC now` |
| `recommendations` | `algorithm = collaborative_filtering`; `generated_at = UTC now`; `status = active` |
| `violation_types` | `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `resolution_types` | `status = active`; `created_at = UTC now`; `updated_at = UTC now` |
| `reports` | `status = pending`; `created_at = UTC now`; `updated_at = UTC now` |
| `report_resolutions` | `resolved_at = UTC now` |
| `appeals` | `appeal_number = 1`; `status = pending`; `created_at = UTC now` |

## Gợi ý dữ liệu `ResolutionType`

SQL seed các loại xử lý cơ bản:

| `code` | Đối tượng |
|---|---|
| `no_action` | `any` |
| `hide_video` | `video` |
| `remove_video` | `video` |
| `hide_comment` | `comment` |
| `delete_comment` | `comment` |
| `warning_channel` | `channel` |
| `suspend_channel` | `channel` |
| `ban_channel` | `channel` |
| `restore_content` | `any` |

`legacy_unspecified` chỉ được tạo khi nâng cấp một database cũ đã có
`report_resolutions` nhưng chưa có `resolution_type_id`; đây là giá trị migration,
không phải lựa chọn nghiệp vụ cho dữ liệu mới.

