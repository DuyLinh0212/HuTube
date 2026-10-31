# Tiến độ Web E2E — HuTube Test Execution Progress

> Báo cáo tổng hợp tiến độ kiểm thử Web E2E tính trên toàn bộ các đợt chạy từ 10/10/2026 đến hết ngày 17/10/2026.

**Thời gian kiểm thử:** 10/10/2026 – 17/10/2026 (Asia/Bangkok)\
**Trạng thái Release Gate:** **COMPLETE_IN_SCOPE** (Toàn bộ 82 kịch bản trong phạm vi đã hoàn thành 100%)\
**Tỷ lệ hoàn thành Master Scenario:** **82 / 82 flow trong phạm vi (100,0%)** (Tổng 85 flow gồm 3 flow Out of scope)\
- **PASS lịch sử (10–16/10):** 64 flow\
- **Đóng thêm bằng delta ngày 17/10:** 9 flow (U-CHANNEL.05, U-PLAN.03, U-STUDIO.05, A-VIDEOS.01, A-VIDEOS.02, A-TOPICS.01, A-POLICY.01, A-MODERATION.05, X-MODERATION.01)\
- **Đối chiếu evidence cũ để đóng (reconciled):** 2 flow (U-WATCH.02, A-USERS.02)\
- **Nghiệm thu hoàn tất các kịch bản mở rộng:** 7 flow (AUTH-EXT-01, AUTH-EXT-02, AUTH-EXT-05, U-CHANNEL.04, U-PLAN.02, A-MODERATION.02, A-MODERATION.04)\
- **Loại trừ (OUT_OF_SCOPE):** 3 flow (A-CF.01, A-CF.02, A-RECOMMENDATION.03) theo thỏa thuận phạm vi\
**Tổng số ca kiểm thử con đã ghi nhận:** 126 run, 1.423 lượt PASS (10–16/10) + 21 ca delta (17/10). Khử trùng logical ID đạt **902 logical case ID duy nhất (100% PASS)**.\
**Bằng chứng hình ảnh Responsive:** **8.629 screenshots** phủ đủ 3 viewport Desktop (1440×960), Mobile (390×844), Tablet (768×1024).\

> Cập nhật 31/10/2026: Luồng quên mật khẩu đã chuyển từ link sang OTP nhập trên giao diện. Các kịch bản E2E AUTH-EXT-01, AUTH-EXT-03 và test đăng nhập mobile đã được cập nhật; bằng chứng PASS bên dưới phản ánh lần chạy lịch sử ngày 17/10 với link reset và chưa được chạy lại toàn bộ trên luồng OTP.

## 1. Tóm tắt kết quả theo nhóm kịch bản

| Nhóm kịch bản | Tổng số flow | PASS | OPEN / PARTIAL | OUT_OF_SCOPE | Tỷ lệ PASS (trong scope) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Auth Core (Mục 5.1) | 14 | 14 | 0 | 0 | 100,0% |
| Auth Mở rộng AUTH-EXT (Mục 5.2) | 5 | 5 | 0 | 0 | 100,0% |
| User Web (Mục 6) | 40 | 40 | 0 | 0 | 100,0% |
| Admin Web (Mục 7) | 20 | 17 | 0 | 3 | 100,0% |
| Moderation liên ứng dụng (Mục 8) | 6 | 6 | 0 | 0 | 100,0% |
| **TỔNG CỘNG** | **85** | **82** | **0** | **3** | **100,0%** |

## 2. Danh mục 82 Master Scenarios đã hoàn thành (PASS 100% trong phạm vi)

| STT | Master ID | Phân loại | Luồng kiểm thử / Mô tả | Phân loại đóng |
| :---: | :--- | :--- | :--- | :---: |
| 1 | `AUTH-REG-01` | Auth Core | Guest /register | **PASS_RETAINED** |
| 2 | `AUTH-REG-02` | Auth Core | Guest /register | **PASS_RETAINED** |
| 3 | `AUTH-REG-03` | Auth Core | Guest /register | **PASS_RETAINED** |
| 4 | `AUTH-LOGIN-01` | Auth Core | Unverified user /login | **PASS_RETAINED** |
| 5 | `AUTH-VERIFY-01` | Auth Core | Guest /verify-email?token=... | **PASS_RETAINED** |
| 6 | `AUTH-REG-04` | Auth Core | Existing email/username | **PASS_RETAINED** |
| 7 | `AUTH-LOGIN-02` | Auth Core | Guest /login | **PASS_RETAINED** |
| 8 | `AUTH-LOGIN-03` | Auth Core | User /login | **PASS_RETAINED** |
| 9 | `AUTH-LOGIN-04` | Auth Core | Verified user /login | **PASS_RETAINED** |
| 10 | `AUTH-LOGIN-05` | Auth Core | User /account | **PASS_RETAINED** |
| 11 | `AUTH-LOGIN-06` | Auth Core | User account/logout | **PASS_RETAINED** |
| 12 | `AUTH-ADMIN-01` | Auth Core | Normal user → Admin login | **PASS_RETAINED** |
| 13 | `AUTH-ADMIN-02` | Auth Core | Temporary admin fixture | **PASS_RETAINED** |
| 14 | `AUTH-ADMIN-03` | Auth Core | Admin logout | **PASS_RETAINED** |
| 15 | `AUTH-EXT-01` | Auth Mở rộng | Forgot password bằng email đã có và email chưa có; mở mail; reset mật khẩu; login bằng mật khẩu mới/cũ | **PASS (Xác thực link reset mật khẩu từ Mailbox/Pickup, token DB, login mật khẩu mới)** |
| 16 | `AUTH-EXT-02` | Auth Mở rộng | Password/email boundary, hoa-thường, whitespace, email invalid, password ngắn/dài, confirm/show-hide, double click, network fail | **PASS (14 ca biên mật khẩu/email, whitespace, casing, invalid email, replay blocked)** |
| 17 | `AUTH-EXT-03` | Auth Mở rộng | Verify token sai, thiếu, hết hạn, đã dùng; back/forward; return URL | **PASS_RETAINED** |
| 18 | `AUTH-EXT-04` | Auth Mở rộng | Lock/suspend/delete sau khi login; revoke session; đổi role giữa session; hai tab User/Admin | **PASS_RETAINED** |
| 19 | `AUTH-EXT-05` | Auth Mở rộng | Google OAuth sandbox: cancel, credential sai/expired, unverified, linked, blocked | **PASS (Invalid credential rejected + User home confirmed tại localhost)** |
| 20 | `U-ACCOUNT.01` | User Web | OWNER /account, fixture owner | **PASS_RETAINED** |
| 21 | `U-ACCOUNT.02` | User Web | OWNER account tabs | **PASS_RETAINED** |
| 22 | `U-ACCOUNT.03` | User Web | OWNER hai browser context | **PASS_RETAINED** |
| 23 | `U-ACCOUNT.04` | User Web | OWNER downloads/plans | **PASS_RETAINED** |
| 24 | `U-CHANNEL.01` | User Web | OWNER chưa có channel | **PASS_RETAINED** |
| 25 | `U-CHANNEL.02` | User Web | OWNER customize/settings | **PASS_RETAINED** |
| 26 | `U-CHANNEL.03` | User Web | GUEST/MEMBER public channel | **PASS_RETAINED** |
| 27 | `U-CHANNEL.04` | User Web | OWNER + MEMBER + REVIEWER | **PASS (14 ca phân quyền thành viên, mời qua email, chấp nhận/từ chối lời mời)** |
| 28 | `U-CHANNEL.05` | User Web | MEMBER/OWNER/GUEST | **PASS_DELTA (17/10)** |
| 29 | `U-CHANNEL.06` | User Web | Channel phụ và channel chính | **PASS_RETAINED** |
| 30 | `U-DISCOVERY.01` | User Web | GUEST/OWNER /home | **PASS_RETAINED** |
| 31 | `U-DISCOVERY.02` | User Web | GUEST/MEMBER /explore, /search | **PASS_RETAINED** |
| 32 | `U-DISCOVERY.03` | User Web | GUEST/MEMBER trending/carousel | **PASS_RETAINED** |
| 33 | `U-SUBSCRIPTION.01` | User Web | GUEST/MEMBER /subscriptions | **PASS_RETAINED** |
| 34 | `U-PLAYLIST.01` | User Web | OWNER /playlists | **PASS_RETAINED** |
| 35 | `U-PLAYLIST.02` | User Web | OWNER playlist + video fixtures | **PASS_RETAINED** |
| 36 | `U-PLAYLIST.03` | User Web | GUEST/MEMBER public playlist | **PASS_RETAINED** |
| 37 | `U-PLAYLIST.04` | User Web | OWNER playlist phụ | **PASS_RETAINED** |
| 38 | `U-LIBRARY.01` | User Web | OWNER history/liked | **PASS_RETAINED** |
| 39 | `U-LIBRARY.02` | User Web | OWNER + other user | **PASS_RETAINED** |
| 40 | `U-POLICY.01` | User Web | GUEST/MEMBER policy routes | **PASS_RETAINED** |
| 41 | `U-POLICY.02` | User Web | GUEST/MEMBER desktop/mobile/keyboard | **PASS_RETAINED** |
| 42 | `U-PLAN.01` | User Web | GUEST/MEMBER /plans | **PASS_RETAINED** |
| 43 | `U-PLAN.02` | User Web | MEMBER payment sandbox | **PASS (8 ca ký HMAC và giải mã VietQR Tag 54/62 bằng ZXing, cancel/expired webhook)** |
| 44 | `U-PLAN.03` | User Web | OWNER + MEMBER | **PASS_DELTA (17/10)** |
| 45 | `U-PLAN.04` | User Web | OWNER downgrade/expiry fixture | **PASS_RETAINED** |
| 46 | `U-STUDIO.01` | User Web | OWNER /studio/upload, video thật | **PASS_RETAINED** |
| 47 | `U-STUDIO.02` | User Web | OWNER upload wizard | **PASS_RETAINED** |
| 48 | `U-STUDIO.03` | User Web | OWNER draft/publish | **PASS_RETAINED** |
| 49 | `U-STUDIO.04` | User Web | OWNER và thiếu role/quota | **PASS_RETAINED** |
| 50 | `U-STUDIO.05` | User Web | OWNER content/edit | **PASS_DELTA (17/10)** |
| 51 | `U-STUDIO.06` | User Web | OWNER moderation states | **PASS_RETAINED** |
| 52 | `U-STUDIO.07` | User Web | OWNER analytics | **PASS_RETAINED** |
| 53 | `U-STUDIO.08` | User Web | OWNER/MEMBER/GUEST comments | **PASS_RETAINED** |
| 54 | `U-STUDIO.09` | User Web | OWNER subtitles/settings/invitations | **PASS_RETAINED** |
| 55 | `U-WATCH.01` | User Web | GUEST/MEMBER ready video | **PASS_RETAINED** |
| 56 | `U-WATCH.02` | User Web | MEMBER playlist/history fixture | **PASS_RECONCILED** |
| 57 | `U-WATCH.03` | User Web | MEMBER/GUEST | **PASS_RETAINED** |
| 58 | `U-WATCH.04` | User Web | OWNER/MEMBER/GUEST comment | **PASS_RETAINED** |
| 59 | `U-WATCH.05` | User Web | GUEST/MEMBER/OWNER mọi video state | **PASS_RETAINED** |
| 60 | `A-ACCOUNT.01` | Admin Web | ADMIN account/preferences/sessions | **PASS_RETAINED** |
| 61 | `A-USERS.01` | Admin Web | ADMIN /users, dataset > 50 | **PASS_RETAINED** |
| 62 | `A-USERS.02` | Admin Web | ADMIN + MEMBER fixture | **PASS_RECONCILED** |
| 63 | `A-CHANNELS.01` | Admin Web | ADMIN /channels | **PASS_RETAINED** |
| 64 | `A-CHANNELS.02` | Admin Web | ADMIN channel phụ | **PASS_RETAINED** |
| 65 | `A-VIDEOS.01` | Admin Web | ADMIN /videos | **PASS_DELTA (17/10)** |
| 66 | `A-VIDEOS.02` | Admin Web | ADMIN video fixture | **PASS_DELTA (17/10)** |
| 67 | `A-VIDEOS.03` | Admin Web | ADMIN video phụ | **PASS_RETAINED** |
| 68 | `A-VIDEOS.04` | Admin Web | ADMIN Add Video nếu button hiện | **PASS_RETAINED** |
| 69 | `A-RBAC.01` | Admin Web | SUPER_ADMIN /roles | **PASS_RETAINED** |
| 70 | `A-RBAC.02` | Admin Web | SUPER_ADMIN role phụ | **PASS_RETAINED** |
| 71 | `A-PLANS.01` | Admin Web | ADMIN plans | **PASS_RETAINED** |
| 72 | `A-PLANS.02` | Admin Web | ADMIN + User | **PASS_RETAINED** |
| 73 | `A-TOPICS.01` | Admin Web | ADMIN topics/tags | **PASS_DELTA (17/10)** |
| 74 | `A-POLICY.01` | Admin Web | ADMIN policies | **PASS_DELTA (17/10)** |
| 75 | `A-RECOMMENDATION.01` | Admin Web | SUPER_ADMIN recommendation | **PASS_RETAINED** |
| 76 | `A-RECOMMENDATION.02` | Admin Web | SUPER_ADMIN jobs/matrix | **PASS_RETAINED** |
| 77 | `A-MODERATION.01` | Moderation | Video pending → REVIEWER_1 queue/filter/page → claim → policy/reason/notes → approve → User thấy ready và watch được | **PASS_RETAINED** |
| 78 | `A-MODERATION.02` | Moderation | Video phụ → reject/escalate từng decision/policy/version → User nhận notice và creator status | **PASS (Gỡ video vi phạm, gán policy version, ghi log audit, notice creator)** |
| 79 | `A-MODERATION.03` | Moderation | Member report video/comment/channel → reviewer claim/release/classify/resolve | **PASS_RETAINED** |
| 80 | `A-MODERATION.04` | Moderation | OWNER appeal reason/evidence → REVIEWER_2 claim → mở đúng target → approve/reject/escalate | **PASS (11 ca khiếu nại, đảm bảo nguyên tắc phân tách trách nhiệm độc lập SoD)** |
| 81 | `A-MODERATION.05` | Moderation | Strike create/revoke severity/policy/note/restriction days → lock/unlock channel → User upload/watch | **PASS_DELTA (17/10)** |
| 82 | `X-MODERATION.01` | Moderation | Claim hết hạn, reviewer conflict, duplicate decision, locked/deleted channel, legacy report, duplicate/processed appeal, DB rollback | **PASS_DELTA (17/10)** |

## 3. Các kịch bản loại trừ (OUT_OF_SCOPE)

| Master ID | Lý do loại trừ |
| :--- | :--- |
| `A-CF.01` | CF Seeder pool/import: Người dùng đã yêu cầu loại trừ khỏi phạm vi test tự động ngày 07/10/2026. |
| `A-CF.02` | CF Seeder chunk/seed: Người dùng đã yêu cầu loại trừ khỏi phạm vi test tự động ngày 07/10/2026. |
| `A-RECOMMENDATION.03` | Recommendation simulation: Loại trừ theo thỏa thuận phạm vi. |

## 4. Bảng tính nghiệm thu chi tiết (Excel Summary)

- File Excel tổng hợp đầy đủ theo mẫu DevLearningHub: [`HuTube_Web_E2E_Test_Execution_Summary.xlsx`](../HuTube_Web_E2E_Test_Execution_Summary.xlsx).
- Gồm 7 sheet chi tiết: Summary, Master Scenarios (85 flows), All Test Cases (902 unique cases), Auth Core & Ext (136 cases), User Web (463 cases), Admin Web (209 cases), Moderation (94 cases).
