# Sprint9.md — Business, Analytics, RBAC Full, HuAI và Feature Complete

> **Sprint Goal:** Hoàn thiện toàn bộ chức năng còn lại và kết thúc Sprint ở trạng thái **FEATURE COMPLETE / FEATURE FREEZE**.  
> Không để chức năng nghiệp vụ chính sang Sprint 10.

---

# 1. Sprint Gate

Cuối Sprint 9:

```text
Module 2.1 COMPLETE
+
Module 2.2 COMPLETE
+
Module 2.3 COMPLETE
=
FEATURE FREEZE
```

Sprint 10 chỉ:

- Fix Bug.
- Full Regression.
- Full E2E.
- Security.
- Performance.
- Release.

---

# 2. Vertical Slice S9-01 — Plan

Admin:

- List.
- Create.
- Edit.
- Clone.
- Enable/Disable.
- Soft Delete.
- Restore.
- Price.
- Billing cycle.
- Storage limit.
- Video/quality/feature limit.
- Display order.
- Subscriber count.

User:

- View Plans.
- Compare.
- Current Plan.
- Feature/limit display.

Business Rule:

- Plan đã từng có Subscription/Payment không hard delete.
- Version/change rule phải rõ để không phá subscription cũ.

---

# 3. Vertical Slice S9-02 — Subscription

State:

```text
Pending
Active
Expired
Cancelled
PastDue
```

Chức năng:

- Start.
- End.
- Auto Renew.
- Upgrade.
- Downgrade nếu scope.
- Cancel Renewal.
- History.
- Admin change/extend theo permission.

User UI:

- Current plan.
- Expiration.
- Auto renew.
- Upgrade/Downgrade.
- Cancel.

---

# 4. Vertical Slice S9-03 — Payment

Payment method theo scope:

- MoMo.
- ZaloPay.
- VNPay.
- Phương thức khác đã chốt.

State:

```text
Pending
Success
Failed
Cancelled
Refunded
```

Flow:

```text
Choose Plan
→ Create Transaction
→ Payment Gateway
→ Verify Backend
→ Activate Subscription
```

Business Rule:

- Idempotency.
- Không tạo duplicate subscription.
- Không tin Client callback.
- Gateway transaction ID.
- Retry.
- Payment History.

Admin:

- Transaction.
- Detail.
- Failure.
- Refund.
- Refund reason.
- Refund history.
- Export.
- Revenue.

---

# 5. Vertical Slice S9-04 — Creator Analytics

## Video

- Views.
- Watch Time.
- Average View Duration.
- Like.
- Dislike.
- Comment.
- Share.
- Subscriber gained/lost.
- Impression/CTR nếu dữ liệu có.
- Traffic Source.
- Retention.
- Audience nếu dữ liệu có.

## Channel

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
- Period filter.
- Compare period.

Mobile:

- KPI Carousel.
- Chart dọc.
- Bottom Sheet filter.

---

# 6. Vertical Slice S9-05 — Admin Dashboard và Analytics

Dashboard KPI:

- Total User.
- New User.
- Active User.
- Channel.
- Video.
- Moderation Queue.
- Report.
- Appeal.
- Subscription.
- Revenue.
- Restricted account.

Analytics:

- User growth.
- DAU/WAU/MAU.
- Content.
- Interaction.
- Channel.
- Moderation.
- Report validity.
- Strike.
- Appeal success.
- Processing time.
- Revenue.
- Payment success/failure.
- Refund.

Filter:

- Date/week/month/year/custom.
- Plan.
- Category.
- Segment nếu có.

Export theo Permission.

---

# 7. Vertical Slice S9-06 — RBAC Management đầy đủ

> Sprint 4 đã có RBAC Engine. Sprint 9 làm **Management UI + toàn bộ lifecycle Role/Permission/Admin**.

## Role

- View.
- Create.
- Edit.
- Clone.
- Enable/Disable.
- Soft Delete.
- Restore nếu có.
- System Role protection.

## Permission

- View grouped permission.
- Assign.
- Remove.
- Xem số Permission.
- Permission search/filter.

## Admin Account

- List Admin.
- Create Admin Access từ User.
- Assign Role.
- Remove Role.
- Enable.
- Disable.
- Force Logout.
- View last login.
- View Audit.

## Business Rule

- Không cho Role thấp tự nâng quyền vượt scope.
- Không sửa/xóa Super Admin trái rule.
- Không xóa System Role.
- Permission change phải Audit.

---

# 8. Vertical Slice S9-07 — Notification hoàn chỉnh

Notification type:

- New subscription video.
- Reply.
- Mention.
- Channel activity.
- Warning.
- Strike.
- Report.
- Copyright.
- Appeal.
- Plan.
- Payment.
- System.

User setting:

- In-app.
- Email.
- Per category.

Admin Template:

- Create/Edit Template.
- Warning.
- Strike.
- Removed/Restored.
- Report.
- Appeal.
- Copyright.
- Subscription.
- Payment.
- System.

Action:

- Mark Read.
- Mark All.
- Filter Unread.
- Deep Link.

---

# 9. Vertical Slice S9-08 — Privacy, Session và Account Lifecycle

## Privacy

- Mention.
- Watch History.
- Search History.
- Personalization setting.
- Subscription visibility nếu scope.
- Block List.

## Session

- Device list.
- Last activity.
- Current device.
- Logout one.
- Logout others.

## Delete Account

Flow:

```text
Open Advanced
→ Preview affected data
→ Re-authenticate
→ Confirm
→ Handle owned Channel
→ Deactivate/Delete according to rule
→ Notification/Email
```

Nếu User là Owner duy nhất:

- Chuyển Owner hoặc xử lý Channel trước theo rule.

## Delete Channel

- Impact preview.
- Re-authenticate.
- Owner-only.
- Soft Delete/Deactivate.
- Confirmation.

---

# 10. Vertical Slice S9-09 — System Settings

Admin config:

## Upload

- Max file size.
- Format.
- Thumbnail type.
- Quality.
- Upload limit.

## Moderation

- Strike expiry.
- Queue priority.
- Appeal deadline.
- SLA.
- Auto flag threshold nếu có.

## User/Channel

- Channel limit.
- Display name rule.
- Default quota.
- Default Plan.

## System

- Maintenance Mode.
- Feature Flag.
- Notification config.
- Policy links.
- Non-secret settings.

Không hiển thị secret thực.

---

# 11. Vertical Slice S9-10 — HuAI

## Scope

- FAQ.
- Hướng dẫn.
- Điều hướng.
- Open Settings.
- Open History.
- Open Upload.
- Search Video.
- Create Playlist nếu action framework hỗ trợ.

## Action flow

```text
User request
→ HuAI hiểu action
→ Preview
→ User Confirm
→ Backend action
→ Result
```

Bắt buộc Confirm trước:

- Delete Account.
- Delete Channel.
- Payment.
- Cancel Subscription.
- Permission change.
- Report.
- Delete Video.

HuAI không được bypass Permission/API Business Rule.

---

# 12. Vertical Slice S9-11 — Mobile Finishing

Kiểm tra toàn bộ màn hình Module User:

- Bottom Navigation.
- App Bar.
- Bottom Sheet.
- Full-screen Form.
- Search.
- Video Player.
- Rotation.
- Mini Player.
- Comment.
- Channel.
- Creator Studio.
- Upload.
- Analytics.
- Notification.
- Payment.
- Report.
- Copyright.
- Appeal.
- Settings.
- HuAI.

Cross-cutting:

- Safe Area.
- Keyboard.
- Pull-to-refresh.
- Infinite Scroll.
- Offline state.
- Retry.
- Runtime permission.
- Deep Link.
- Accessibility.
- Touch target.

Không để màn hình vẫn gọi Mock API.

---

# 13. Vertical Slice S9-12 — Web User/Admin Finishing

## Web User

- Responsive.
- Sidebar/Topbar.
- Search.
- Feed.
- Player.
- Creator Studio.
- Analytics.
- Settings.
- Empty/Error/Loading.
- Infinite Scroll.

## Admin

- Responsive Desktop/Tablet.
- Sidebar theo Permission.
- Dashboard.
- User/Channel/Video/Comment.
- Moderation.
- Report.
- Appeal.
- Plan.
- Payment.
- Analytics.
- Audit.
- Settings.
- Recommendation Management.

---

# 14. Cross-cutting hardening Sprint 9

Phải rà soát toàn hệ thống:

- Soft Delete.
- Audit.
- Pagination/Cursor.
- Search/Filter/Sort.
- Loading.
- Empty.
- Error.
- 401.
- 403.
- 404.
- Conflict.
- Validation.
- Dangerous action confirmation.
- Reason field.
- Idempotency.
- Retry.
- Rate limit nơi cần.
- Logging.
- Secret handling.
- Timezone.
- Mobile deep link.

---

# 15. Unit Test Sprint 9

## Plan/Subscription

- Create/Update Plan.
- Delete protected Plan.
- Upgrade.
- Downgrade.
- Cancel.
- Expire.
- PastDue.

## Payment

- Create transaction.
- Duplicate request/idempotency.
- Success.
- Failed.
- Cancel.
- Retry.
- Callback duplicate.
- Invalid callback.
- Activate subscription once.
- Refund.
- Refund invalid state.

## Analytics

- Aggregation.
- Date range.
- Permission.
- Empty dataset.

## RBAC Management

- Create Role.
- System Role protection.
- Assign Permission.
- Remove.
- Self escalation blocked.
- Disable Admin.
- Force Logout.

## Privacy/Delete

- Re-auth required.
- Owner-only.
- Owned Channel dependency.
- Session revoke.

## HuAI

- Read-only navigation.
- Action requires confirm.
- Action denied by permission.
- Dangerous action not auto-run.

---

# 16. Integration Test Sprint 9

## INT-S9-01 Payment success

```text
Create Transaction
→ Gateway Sandbox
→ Backend Verify
→ Payment Success
→ Subscription Active
```

## INT-S9-02 Duplicate callback

- Gửi callback success hai lần.

Expected:

- Một Payment final state.
- Một Subscription activation.

## INT-S9-03 Refund

```text
Admin Refund
→ Gateway/Service
→ Payment Refunded
→ Revenue/History update
→ Audit
```

## INT-S9-04 RBAC update

1. Super Admin tạo Role.
2. Assign Permission.
3. Assign Admin.
4. Admin Login.
5. Gọi API.

Expected:

- Permission effective.
- Audit có change.

## INT-S9-05 Delete Account

- User có session.
- Có/không có Channel.
- Re-auth.
- Delete/Deactivate.
- Session revoke.

## INT-S9-06 Notification Deep Link

- Trigger Strike/Payment/Reply.
- Notification.
- Click.

Expected:

- Mở đúng resource Web/Mobile.

---

# 17. E2E Sprint 9 — mô tả chi tiết

## E2E-S9-01 — Mua Plan thành công

### Steps

1. User Login.
2. Open Plan.
3. Compare.
4. Select paid Plan.
5. Create Payment.
6. Complete sandbox success.
7. Return app/web.
8. Open Subscription.

### Expected

- Payment Success.
- Plan Active đúng một lần.
- Limit/quota mới áp dụng.
- Notification/payment history tồn tại.

---

## E2E-S9-02 — Payment Failed → Retry

1. Tạo transaction.
2. Mô phỏng fail.
3. UI hiển thị Failed.
4. Retry/chọn payment method.
5. Success.

Expected:

- Không có duplicate subscription.
- Lịch sử transaction đúng.

---

## E2E-S9-03 — Refund Admin

1. Finance/Admin có Permission open transaction.
2. Refund.
3. Nhập reason.
4. Confirm.
5. User open Payment History.

Expected:

- Refunded state.
- Audit.
- Revenue/report phản ánh theo rule.

---

## E2E-S9-04 — Tạo Custom Role

1. Super Admin Create Role `Content Reviewer`.
2. Assign:
   - report.view
   - report.review
   - không assign report.resolve.
3. Assign Admin A.
4. Login A.
5. Open Report.
6. Thử Resolve.

Expected:

- View/Review được.
- Resolve bị Forbidden.
- Sidebar/API nhất quán.

---

## E2E-S9-05 — Disable Admin

1. Super Admin Disable Admin A.
2. A đang có session.
3. A refresh/gọi API.

Expected:

- Access bị revoke theo session policy.
- Không tiếp tục dùng Admin API.

---

## E2E-S9-06 — Delete Account có Channel

1. User là Owner duy nhất.
2. Chọn Delete Account.
3. Hệ thống phát hiện Channel.
4. Thực hiện flow yêu cầu xử lý Channel/chuyển Owner.
5. Hoàn tất điều kiện.
6. Re-auth.
7. Confirm Delete.

Expected:

- Không tạo orphan Channel.
- Session revoke.
- Không login lại ngoài recovery policy.

---

## E2E-S9-07 — Notification Deep Link trên Mobile

1. User nhận Reply notification.
2. Tap.
3. Nếu app đang logout, Login.
4. Sau Login quay lại đúng Comment/Video.

Expected:

- Deep Link không mất.
- Back navigation hợp lý.

---

## E2E-S9-08 — HuAI navigation

1. User hỏi “mở lịch sử xem”.
2. HuAI đề xuất action.
3. User chọn.
4. App điều hướng History.

Expected:

- Không cần dangerous confirmation cho navigation.
- Route đúng.

---

## E2E-S9-09 — HuAI dangerous action

1. User yêu cầu “xóa kênh”.
2. HuAI phân tích action.
3. Hiển thị Preview/Confirmation.
4. User Cancel.

Expected:

- Channel không bị xóa.
- Không gọi mutation trước confirm.

---

## E2E-S9-10 — Creator Analytics

1. Seed/perform watch/interactions.
2. Creator open Analytics.
3. Chọn date range.
4. Open Video Analytics.
5. So sánh số liệu cơ bản với source test.

Expected:

- KPI đúng.
- User khác không xem được analytics Channel này.

---

## E2E-S9-11 — Admin Dashboard

1. Seed User/Video/Report/Payment.
2. Admin open Dashboard.
3. Filter date.
4. Open drill-down.

Expected:

- KPI/graph đúng dữ liệu.
- Permission export đúng.

---

## E2E-S9-12 — Feature Freeze Regression Smoke

Chạy tối thiểu:

```text
Register/Login
→ Create Channel
→ Upload
→ Moderate
→ Publish
→ Search
→ Watch
→ Like/Comment/Share
→ Recommendation
→ Report
→ Strike
→ Appeal
→ Plan/Payment
→ Analytics
```

Expected:

- Không có Blocker/Critical.
- Các dependency lớn nối được trên Staging.

---

# 18. Feature Freeze Checklist

## Module 2.1

- [ ] Benchmark.
- [ ] Snapshot.
- [ ] MBMF.
- [ ] Metrics.
- [ ] Model Version.
- [ ] Python Service.
- [ ] .NET integration.
- [ ] Admin Recommendation.
- [ ] Fallback.

## Module 2.2

- [ ] Admin User.
- [ ] Channel.
- [ ] Video.
- [ ] Comment.
- [ ] Moderation.
- [ ] Report.
- [ ] Appeal.
- [ ] Strike.
- [ ] Policy.
- [ ] Plan.
- [ ] Payment.
- [ ] Analytics.
- [ ] Audit.
- [ ] RBAC full.
- [ ] System Settings.
- [ ] Notification.

## Module 2.3

- [ ] Web User.
- [ ] Mobile User.
- [ ] Creator.
- [ ] Upload.
- [ ] Player.
- [ ] Interaction.
- [ ] Search.
- [ ] Feed.
- [ ] Library.
- [ ] Community.
- [ ] Report.
- [ ] Copyright.
- [ ] Appeal.
- [ ] Plan/Payment.
- [ ] Analytics.
- [ ] Privacy.
- [ ] HuAI.

---

# 19. Sprint 9 Exit Criteria

- [ ] Không còn nghiệp vụ chính chưa implement.
- [ ] Không còn Mock API bắt buộc ở Web.
- [ ] Không còn Mock API bắt buộc ở Mobile.
- [ ] Không còn Mock API bắt buộc ở Admin.
- [ ] Unit Test toàn Sprint pass.
- [ ] Integration Test pass.
- [ ] Sprint E2E pass.
- [ ] Staging smoke pass.
- [ ] Recommendation staging healthy.
- [ ] Payment sandbox pass.
- [ ] Không còn Blocker/Critical.
- [ ] Tag release candidate/pre-freeze theo quy trình nhóm.
- [ ] Chính thức chuyển sang Feature Freeze cho Sprint 10.
