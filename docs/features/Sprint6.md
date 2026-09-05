# Sprint6.md — Player, Interaction, Community, Library và dữ liệu cho Recommendation

> **Sprint Goal:** Hoàn thiện trải nghiệm xem và tương tác với Video; đồng thời tạo dữ liệu `User → Video` đủ chuẩn để Sprint 7 xây Recommendation.

---

# 1. Luồng nghiệp vụ mục tiêu

```text
Published Video
      ↓
Watch
      ↓
Watch Progress / Resume
      ↓
Like / Dislike / Rating*
      ↓
Comment
      ↓
Share
      ↓
History / Library
      ↓
Interaction Event / Snapshot Source
```

> `Rating*`: Module Recommendation đang dùng `rating` 1–5. Trong Sprint 6 phải **chốt Product Decision**:  
> - nếu HuTube thực sự có Rating thì triển khai UI/API/Event;  
> - nếu không có Rating production thì phải cập nhật Module_CF để `rating` chỉ là benchmark/nullable signal, không để model phụ thuộc vào chức năng sản phẩm không tồn tại.

---

# 2. Dependency

Cần Sprint 5:

- Published Video.
- Visibility.
- Video URL/stream access.
- Channel.
- Creator.
- Private/Unlisted rule.

---

# 3. Vertical Slice S6-01 — Trang xem Video và Player

## Player Web

- Play/Pause.
- Seek.
- Volume.
- Mute.
- Fullscreen.
- Theater.
- Mini Player.
- Picture-in-Picture nếu scope có.
- Quality.
- Auto Quality.
- Speed.
- Subtitle.
- Auto Play.
- Loop.
- Sleep Timer.
- Keyboard shortcut.

## Player Mobile

- Portrait player.
- Landscape fullscreen.
- Double tap seek.
- Tap control.
- Mini Player nếu scope có.
- Quality/Speed/Subtitle bằng Bottom Sheet.
- Giữ timestamp khi rotate.

## Video info

- Title.
- Views.
- Publish time.
- Description.
- Expand/Collapse.
- Tag.
- Category.
- Channel.
- Avatar.
- Subscriber count.

---

# 4. Vertical Slice S6-02 — Watch Tracking

## Event cần ghi nhận

Tối thiểu cho Module_CF:

```text
VIEW_START
WATCH_PROGRESS
WATCH_END
LIKE
DISLIKE
COMMENT
SHARE
RATING       // nếu Product có Rating
```

Có thể ghi thêm:

```text
NOT_INTERESTED
DONT_RECOMMEND_CHANNEL
SEARCH_CLICK
```

để phục vụ Feed/Ranking về sau.

## Watch fields

Phải có đủ dữ liệu để tính:

```text
watch_seconds
video_duration_seconds
watch_ratio
```

với:

```text
watch_ratio = min(watch_seconds / duration, 1)
```

## Resume

- Last position.
- Last watched at.
- Continue watching.

## Chống dữ liệu rác

- Không spam event quá dày.
- Không tăng View vô hạn do refresh liên tục nếu Business Rule có threshold.
- WATCH_PROGRESS phải aggregate được.

---

# 5. Vertical Slice S6-03 — Like / Dislike / Rating / Share

## Like/Dislike

- Like.
- Unlike.
- Dislike.
- Undislike.
- Mutual exclusion.

## Share

- Copy URL.
- Native Share Mobile.
- Share at current timestamp nếu scope có.

## Rating

Nếu chốt có Rating:

- 1–5.
- Update rating.
- Remove rating nếu hỗ trợ.
- Event/aggregate lấy rating gần nhất.

---

# 6. Vertical Slice S6-04 — Comment và Reply

Chức năng:

- Create.
- Edit own comment.
- Delete own comment.
- Reply.
- Nested/thread theo mức đã chốt.
- Like comment.
- Mention.
- Sort.
- Infinite Scroll.
- Report entry point.
- Block/Mute entry point.

Validation:

- Length.
- Empty.
- Blocked word rule nếu Channel bật.
- Spam/rate limit nếu có.

Mobile:

- Comment Preview ở Video Page.
- Full-screen/Bottom Sheet.
- Input không bị keyboard che.

---

# 7. Vertical Slice S6-05 — Subscribe Channel

- Subscribe.
- Unsubscribe.
- Notification Level:
  - All.
  - Personalized.
  - Off.
- Subscription list.
- Subscription feed nền.
- New video indicator.

Lưu ý Module_CF:

- Follow/Subscribe là `User → Channel`.
- Không đưa trực tiếp vào MBMF User→Video.
- Dùng làm Subscription Feed/fallback.

---

# 8. Vertical Slice S6-06 — Watch History

- Record watched Video.
- Watch progress.
- Resume.
- Search history list.
- Remove item.
- Clear history.
- Clear by period nếu scope có.
- Pause watch history.
- Resume history.

Privacy rule phải được tôn trọng.

---

# 9. Vertical Slice S6-07 — Liked Videos và Watch Later

## Liked Videos

- List.
- Unlike.
- Play.
- Save.
- Share.

## Watch Later

- Add.
- Remove.
- Play All.
- Shuffle.
- Reorder nếu chốt.
- Bulk Remove.

---

# 10. Vertical Slice S6-08 — Playlist

- Create.
- Edit.
- Delete.
- Cover.
- Description.
- Public.
- Unlisted.
- Private.
- Add Video.
- Remove Video.
- Bulk Remove.
- Drag/Reorder.
- Sort.
- Play All.
- Shuffle.
- Share.

Video unavailable:

- Video Removed/Private/Deleted không làm hỏng cả Playlist.
- Item phải hiển thị trạng thái phù hợp.

---

# 11. Vertical Slice S6-09 — Download/Offline

Theo scope Module User:

## Web

- Download nếu Business Rule cho phép.
- Progress.
- Cancel.
- Retry.
- Delete local record.

## Mobile

- Offline download.
- Wi-Fi only.
- Quality.
- Storage check.
- Pause/Resume/Retry.
- Delete.
- Offline state.

Nếu hệ thống chưa đủ thời gian cho offline thực sự, không được giả lập “download” bằng UI; cần chốt scope rõ trong Sprint Planning.

---

# 12. Vertical Slice S6-10 — Community Moderation của Creator

Creator/Channel Moderator:

- Xem Comment thuộc Video của Channel.
- Reply trực tiếp.
- Delete theo permission.
- Report.
- Hide User From Channel.
- Unhide.
- Filter.
- Mark reviewed nếu scope có.
- Bulk action.

## Blocked Words

- Add.
- Remove.
- Search.
- Enable/Disable.

## Comment moderation mode

- Allow all.
- Hold potentially inappropriate.
- Hold all.
- Disable comments.

## Link rule

- Allow.
- Hold.
- Block.

---

# 13. Interaction Data Contract cho Sprint 7

Đến cuối Sprint 6 phải đảm bảo pipeline có thể tạo snapshot dạng:

```text
user_id
item_id
rating
like
dislike
comment
share
watch_ratio
source
timestamp
```

Trong đó:

- `rating` nullable nếu không có.
- like/dislike có trạng thái quan sát rõ.
- comment = có ít nhất một comment hợp lệ.
- share = từng share.
- watch_ratio có thể aggregate/cap.
- source = REAL cho user thật.

Đây là **Sprint Gate quan trọng**.

---

# 14. Unit Test Sprint 6

## Player/Watch

- Duration > 0.
- Watch ratio cap 1.
- Resume position.
- Progress không vượt duration.
- History paused không ghi theo rule.
- Private/Removed video không playback public.

## Like/Dislike

- Like.
- Unlike.
- Dislike.
- Mutual exclusion.
- Duplicate request/idempotent theo design.

## Comment

- Create.
- Edit owner.
- Edit người khác forbidden.
- Delete owner.
- Reply.
- Blocked word.
- Hidden user.
- Moderator permission.

## Subscribe

- Subscribe.
- Duplicate subscribe.
- Unsubscribe.
- Notification level.

## Playlist

- Create.
- Visibility.
- Add duplicate theo rule.
- Reorder.
- Remove.
- Unavailable video.

## Interaction aggregation

- Comment event → comment=1.
- Share event → share=1.
- Like/Dislike current state.
- Rating latest.
- Watch ratio.

---

# 15. Integration Test Sprint 6

## INT-S6-01 Watch → Event

1. Play Video.
2. Gửi Progress.
3. End.
4. Đọc History/Interaction.

Expected:

- Progress persist.
- Resume đúng.
- Event có thể aggregate.

## INT-S6-02 Like/Dislike

1. Like.
2. Dislike.

Expected:

- Like bị unset nếu rule mutual exclusion.
- Interaction state đúng.

## INT-S6-03 Comment → Community

1. Viewer Comment.
2. Creator mở Community.

Expected:

- Comment xuất hiện đúng Video/thumbnail.
- Creator Reply được.

## INT-S6-04 Subscription

1. User Subscribe Channel.
2. Channel publish/seed Video.
3. Open Subscription Feed.

Expected:

- Video/Channel xuất hiện đúng rule.

## INT-S6-05 Playlist privacy

1. Tạo Private Playlist.
2. Add Video.
3. Guest truy cập.

Expected:

- Guest bị chặn.

---

# 16. E2E Sprint 6 — mô tả chi tiết

## E2E-S6-01 — Watch và Resume

### Steps

1. Login User.
2. Open Published Video.
3. Watch tới khoảng giữa Video.
4. Rời màn hình.
5. Mở History.
6. Chọn lại Video.

### Expected

- History có Video.
- Progress đúng gần vị trí cũ.
- Resume không về 0 ngoài Business Rule.

---

## E2E-S6-02 — Interaction lifecycle

1. User mở Video.
2. Like.
3. Dislike.
4. Like lại.
5. Comment.
6. Share.
7. Refresh.

Expected:

- Final state đúng.
- Không duplicate interaction sai.
- Counts/DTO cập nhật đúng theo consistency rule.

---

## E2E-S6-03 — Comment moderation

1. Viewer comment vào Video.
2. Owner mở Creator Studio > Community.
3. Reply.
4. Hide User From Channel.
5. Viewer thử comment tiếp.

Expected:

- Reply hiển thị đúng.
- Hidden User bị xử lý theo Channel rule.
- Backend enforce, không chỉ UI.

---

## E2E-S6-04 — Playlist với Video unavailable

1. User tạo Playlist.
2. Add 3 Video.
3. Một Video được Admin/seed chuyển Removed.
4. Mở Playlist.

Expected:

- Playlist còn hoạt động.
- Video Removed hiển thị unavailable/không play.
- 2 Video còn lại play được.

---

## E2E-S6-05 — Watch Later

1. Add 3 Video.
2. Reorder.
3. Play All.
4. Remove một Video.
5. Refresh.

Expected:

- Order persist.
- Removed item biến mất.
- Play All dùng order đúng.

---

## E2E-S6-06 — Mobile Player

1. Open Video portrait.
2. Play.
3. Rotate landscape.
4. Seek.
5. Rotate portrait.
6. Mở Comment.
7. Thu Player thành Mini Player nếu có.

Expected:

- Timestamp không mất.
- UI không vỡ.
- Bottom Navigation/Mini Player không che nhau.

---

## E2E-S6-07 — Interaction dataset readiness

1. Seed 2 User, nhiều Video.
2. Tạo View/Watch/Like/Comment/Share.
3. Chạy aggregation/query snapshot thử.

Expected:

- Mỗi cặp User–Video tạo được record đúng schema.
- Đây là dữ liệu đầu vào trực tiếp cho Sprint 7.

---

# 17. Sprint 6 Exit Criteria

- [ ] Player Web Done.
- [ ] Player Mobile Done.
- [ ] Watch tracking Done.
- [ ] Resume/History Done.
- [ ] Like/Dislike/Share Done.
- [ ] Rating decision chốt.
- [ ] Comment/Reply Done.
- [ ] Subscribe Done.
- [ ] Playlist/Watch Later/Liked Done.
- [ ] Community moderation Done.
- [ ] Interaction snapshot có thể build.
- [ ] Unit Test pass.
- [ ] Integration Test pass.
- [ ] E2E Smoke pass.
