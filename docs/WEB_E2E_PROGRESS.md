# Tiến độ Web E2E issue #34

Run: `20261007T095524.751804Z`.

108 case: 98 PASS, 0 FAIL, 0 BLOCKED, 10 REUSED.

34 case SMOKE chỉ kiểm tra route. REUSED không được cộng vào PASS của thao tác tạo mới.

CF Seeder và simulation được loại khỏi phạm vi theo yêu cầu người dùng ngày 07/10/2026.

Chưa hoàn tất toàn bộ issue. Inventory là nghĩa vụ rà soát source, không phải số binding đã cover:

| Inventory | Số lượng |
| --- | ---: |
| routes | 75 |
| bindings | 1022 |
| navigation | 172 |
| form_controls | 307 |

## Phạm vi còn lại

| Phạm vi | Trạng thái | Ghi chú |
| --- | --- | --- |
| Recommendation jobs/matrix/model configuration | BLOCKED | Isolated runner disables recommendation; no dedicated service/model/R2 test configuration supplied |
| Payment webhook and download/entitlement | BLOCKED | No dedicated payment sandbox/webhook configuration supplied |
| Public policy UI current version | PLANNED | API synchronization asserted; User activeList uses static rules instead of policies signal |
| Discovery/library filters and pagination; playlist multi-item ordering | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Complete channel role matrix, branding MIME/size boundaries, channel restrictions/delete | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Large video/chunk/recovery; Studio metadata/captions/settings; watch reply/report flows | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Admin videos mutation/CSV; users role assignment/statistics; RBAC constraints | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Reports/appeals/strikes; reviewer conflict and separation of duties | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Realtime notifications/session operations; full keyboard/responsive/theme/language and performance | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |
| Binding/endpoint variant reconciliation and GitHub CI execution | PLANNED | Chưa có đủ assertion và evidence cho toàn bộ nhánh |

## Case đã chạy

| App | ID | Kết quả | Scenario |
| --- | --- | --- | --- |
| user | U-ACCOUNT-READ-01 | PASSED | Đọc hồ sơ và mở form sửa |
| user | U-ACCOUNT-CANCEL-01 | PASSED | Hủy sửa hồ sơ rồi reload |
| user | U-ACCOUNT-MOBILE-01 | PASSED | Form hồ sơ ở viewport mobile |
| user | U-ACCOUNT-VALIDATION-01 | PASSED | Tên chỉ có khoảng trắng |
| user | U-ACCOUNT-VALIDATION-02 | PASSED | Tên quá giới hạn 120 ký tự |
| user | U-ACCOUNT-BIO-LIMIT-01 | PASSED | Nhập bio 161 ký tự |
| user | U-ACCOUNT-SAVE-01 | PASSED | Lưu tên/bio có khoảng trắng đầu cuối |
| user | U-ACCOUNT-RESTORE-01 | PASSED | Phục hồi hồ sơ fixture |
| admin | A-ACCOUNT-READ-01 | PASSED | Đọc hồ sơ Admin |
| admin | A-ACCOUNT-RELOAD-01 | PASSED | Reload hồ sơ Admin |
| admin | A-ACCOUNT-MOBILE-01 | PASSED | Hồ sơ Admin trên mobile |
| user | U-CHANNEL-CREATE-01 | REUSED | Tạo hoặc mở lại kênh fixture |
| user | U-CHANNEL-PUBLIC-01 | PASSED | Member đọc kênh public của owner |
| user | U-CHANNEL-SUBSCRIBE-01 | PASSED | Subscribe/unsubscribe qua UI và đối chiếu API |
| user | U-PLAYLIST-CREATE-01 | REUSED | Tạo playlist private; tên trống không submit |
| user | U-PLAYLIST-EDIT-01 | PASSED | Sửa mô tả playlist và reload |
| user | U-PLAYLIST-ACCESS-01 | PASSED | Member không đọc playlist private của owner |
| user | U-HOME-SMOKE-01 | PASSED | Smoke route /home |
| user | U-EXPLORE-SMOKE-01 | PASSED | Smoke route /explore |
| user | U-SUBSCRIPTIONS-SMOKE-01 | PASSED | Smoke route /subscriptions |
| user | U-HISTORY-SMOKE-01 | PASSED | Smoke route /history |
| user | U-LIKED-SMOKE-01 | PASSED | Smoke route /liked |
| user | U-PLANS-SMOKE-01 | PASSED | Smoke route /plans |
| user | U-TERMS-SMOKE-01 | PASSED | Smoke route /terms |
| user | U-PRIVACY-SMOKE-01 | PASSED | Smoke route /privacy |
| user | U-GUIDELINES-SMOKE-01 | PASSED | Smoke route /guidelines |
| user | U-POLICIES-SMOKE-01 | PASSED | Smoke route /policies |
| user | U-DISCOVERY-EMPTY-01 | PASSED | Tìm kiếm từ khóa không tồn tại |
| user | U-STUDIO-OVERVIEW-SMOKE-01 | PASSED | Smoke route /studio/overview |
| user | U-STUDIO-CONTENT-SMOKE-01 | PASSED | Smoke route /studio/content |
| user | U-STUDIO-ANALYTICS-SMOKE-01 | PASSED | Smoke route /studio/analytics |
| user | U-STUDIO-COMMENTS-SMOKE-01 | PASSED | Smoke route /studio/comments |
| user | U-STUDIO-SUBTITLES-SMOKE-01 | PASSED | Smoke route /studio/subtitles |
| user | U-STUDIO-SETTINGS-SMOKE-01 | PASSED | Smoke route /studio/settings |
| user | U-STUDIO-INVITATIONS-SMOKE-01 | PASSED | Smoke route /studio/invitations |
| user | U-ACCOUNT-NOTIFICATIONS-01 | PASSED | Đổi sáu lựa chọn thông báo, reload và phục hồi |
| user | U-ACCOUNT-PRIVACY-01 | PASSED | Đổi quyền riêng tư subscription và phục hồi |
| user | U-STUDIO-UPLOAD-01 | REUSED | Upload video thật qua wizard; required và schedule disabled |
| user | U-WATCH-PLAYBACK-01 | PASSED | Transcode và phát video có frame/âm thanh thật |
| user | U-WATCH-PRIVATE-01 | PASSED | Member không lấy được playback video private |
| user | U-WATCH-REACTION-01 | PASSED | Like → dislike → clear qua UI; reload |
| user | U-WATCH-COMMENT-01 | PASSED | Tạo bình luận Unicode/XSS dạng text và reload |
| user | X-COMMENT-ACCESS-01 | PASSED | Member không xóa bình luận của owner |
| user | U-WATCH-COMMENT-DELETE-01 | PASSED | Hủy rồi xóa bình luận đúng ID |
| user | U-CHANNEL-INVITE-01 | PASSED | Owner gửi lời mời Editor cho member fixture |
| user | U-CHANNEL-ACCEPT-01 | PASSED | Member accept, thấy channel cộng tác |
| user | U-CHANNEL-ROLE-01 | PASSED | Đổi Editor → Viewer; chặn sửa và tự nâng quyền |
| user | U-CHANNEL-REMOVE-01 | PASSED | Cancel rồi remove member; giữ quyền owner |
| user | X-ERROR-SEARCH-01 | PASSED | Fault injection 500 → retry API thật |
| admin | A-USERS-SMOKE-01 | PASSED | Smoke route /users |
| admin | A-CHANNELS-SMOKE-01 | PASSED | Smoke route /channels |
| admin | A-VIDEOS-SMOKE-01 | PASSED | Smoke route /videos |
| admin | A-RBAC-SMOKE-01 | PASSED | Smoke route /roles |
| admin | A-PLANS-SMOKE-01 | PASSED | Smoke route /plans |
| admin | A-SUBSCRIPTIONS-SMOKE-01 | PASSED | Smoke route /subscriptions |
| admin | A-PAYMENTS-SMOKE-01 | PASSED | Smoke route /payments |
| admin | A-TOPICS-SMOKE-01 | PASSED | Smoke route /topics |
| admin | A-POLICY-SMOKE-01 | PASSED | Smoke route /policies |
| admin | A-MODERATION-SMOKE-01 | PASSED | Smoke route /moderation/videos |
| admin | A-REPORTS-SMOKE-01 | PASSED | Smoke route /moderation/reports |
| admin | A-APPEALS-SMOKE-01 | PASSED | Smoke route /moderation/appeals |
| admin | A-STRIKES-SMOKE-01 | PASSED | Smoke route /moderation/strikes |
| admin | A-NOTIFICATIONS-SMOKE-01 | PASSED | Smoke route /system/notifications |
| admin | A-SYSTEM-REPORTS-SMOKE-01 | PASSED | Smoke route /system/reports |
| admin | A-LOGS-SMOKE-01 | PASSED | Smoke route /system/logs |
| admin | A-RECOMMENDATION-SMOKE-01 | PASSED | Smoke route /recommendations |
| admin | A-USERS-SEARCH-01 | PASSED | Tìm owner và mở đúng detail |
| admin | A-USERS-FILTER-01 | PASSED | Chạy từng lựa chọn status và role |
| admin | A-TOPICS-CREATE-01 | REUSED | Tạo danh mục qua UI và lưu checkpoint |
| admin | A-TOPICS-EDIT-01 | PASSED | Sửa danh mục, reload và đối chiếu API |
| admin | A-TOPICS-CANCEL-01 | PASSED | Hủy lưu trữ danh mục |
| admin | A-TOPICS-ARCHIVE-01 | PASSED | Lưu trữ danh mục và kiểm tra filter |
| user | X-TOPICS-ACCESS-01 | PASSED | User không sửa được danh mục Admin |
| admin | A-TAGS-CREATE-01 | PASSED | Tạo tag qua UI |
| admin | A-TAGS-DELETE-01 | PASSED | Hủy rồi xác nhận xóa tag chưa được sử dụng |
| admin | A-PLANS-CREATE-01 | REUSED | Tạo gói và kiểm tra chuyển đổi đơn vị |
| admin | A-PLANS-EDIT-01 | PASSED | Sửa gói, reload giữ quota và duration |
| user | X-PLANS-CATALOG-01 | PASSED | Gói active Admin xuất hiện ở User |
| admin | A-PLANS-ARCHIVE-01 | PASSED | Cancel rồi archive; đối chiếu catalog User |
| admin | A-RBAC-CREATE-01 | REUSED | Tạo nhóm quyền; bắt buộc lý do |
| admin | A-RBAC-EDIT-01 | PASSED | Cancel rồi lưu thu hồi permission, reload |
| user | X-RBAC-ACCESS-01 | PASSED | User không cấp permission Admin qua API |
| user | X-MODERATION-PUBLISH-01 | REUSED | User đổi public; Admin thấy đúng moderation case |
| admin | A-MODERATION-APPROVE-01 | REUSED | Claim và approve video User qua UI |
| user | X-MODERATION-WATCH-01 | PASSED | User khác lấy playback sau khi Admin approve |
| user | U-PLAYLIST-ITEM-01 | PASSED | Thêm video qua Watch picker, reload playlist |
| user | X-PLAYLIST-EDIT-01 | PASSED | Member không thêm video vào playlist owner |
| user | U-PLAYLIST-REMOVE-01 | PASSED | Cancel rồi remove item; giữ video nguồn |
| user | X-MODERATION-RESTORE-01 | PASSED | Khôi phục video fixture về private |
| admin | A-USERS-LOCK-01 | PASSED | Cancel rồi khóa member; User mất quyền truy cập |
| admin | A-USERS-UNLOCK-01 | PASSED | Unlock fixture và User đăng nhập lại |
| admin | A-POLICY-CREATE-01 | REUSED | Tạo policy published v1 qua UI |
| admin | A-POLICY-PUBLISH-01 | REUSED | Publish v2 và reload Admin |
| user | X-POLICY-API-01 | PASSED | API public đọc v2; User không publish Admin policy |
| admin | A-USERS-PAGINATION-01 | PASSED | 55 users: sáu trang, không trùng/thiếu; tìm kiếm reset trang |
| admin | A-CHANNELS-LIST-01 | PASSED | Search/pageSize/detail đúng owner; time filter disabled |
| admin | A-CHANNELS-CSV-01 | PASSED | Tải CSV đúng trang, Unicode và escape @handle |
| user | U-CHANNEL-VALIDATION-01 | PASSED | Tên trắng và URL javascript không persist |
| user | U-CHANNEL-BASIC-01 | PASSED | Lưu mô tả/contact/link; reload; chặn non-member |
| user | U-CHANNEL-CONTACT-CLEAR-01 | PASSED | Xóa email liên hệ qua UI và reload |
| user | U-CHANNEL-BASIC-RESTORE-01 | PASSED | Phục hồi metadata/link fixture sau test |
| user | U-CHANNEL-AVATAR-01 | PASSED | Upload PNG avatar và reload preview |
| user | U-CHANNEL-BANNER-01 | PASSED | Upload PNG banner và reload preview |
| user | U-CHANNEL-WATERMARK-01 | PASSED | Upload PNG watermark và reload preview |
| user | U-PLAYLIST-VISIBILITY-01 | PASSED | Unlisted/public/private: quyền xem và sửa đúng actor |
| user | U-PLAYLIST-CANCEL-01 | PASSED | Đóng modal không persist tên chưa lưu |
| user | U-PLAYLIST-DELETE-01 | PASSED | Playlist phụ: cancel rồi delete; giữ playlist/video chính |
| user | U-WATCH-RATING-01 | PASSED | Score 0/6 bị chặn; 5→2→clear persist sau reload |
