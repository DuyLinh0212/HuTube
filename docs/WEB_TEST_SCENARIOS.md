# Kịch bản kiểm thử Web User và Web Admin HuTube

Ngày đối chiếu mã nguồn: 02/10/2026 (Asia/Bangkok). Phạm vi: hai ứng dụng Angular, các route, component dùng chung, thao tác biểu mẫu, API được gọi và các flow xuyên User–Admin. Chỉ bộ đăng ký/đăng nhập trong `frontend/e2e_testing/tests/auth.py` đã được triển khai và chạy. Các kịch bản còn lại bên dưới là kế hoạch, chưa có kết quả PASS. Performance cũng mới là kế hoạch.

## 1. Tài liệu và bằng chứng

- [Hướng dẫn chạy auth và xem ảnh](../frontend/e2e_testing/README.md).
- [Kết quả thực thi auth](../frontend/e2e_testing/artifacts/auth-results.md).
- [Danh mục giao diện](../frontend/e2e_testing/coverage/web-inventory.json): 69 khai báo route, 854 event bindings, 160 navigation references và 263 form controls; ghi ứng dụng, file, dòng, sự kiện/biểu thức và nhóm kịch bản. Bao gồm inline template trong TypeScript. Đây là danh mục nghĩa vụ kiểm thử, không phải báo cáo coverage đã đạt.
- [Kịch bản backend](BACKEND_TEST_SCENARIOS.md) và [danh mục endpoint](../frontend/e2e_testing/coverage/backend-endpoints.json).

Mỗi binding trong danh mục phải có một case cụ thể khi triển khai flow: mở component, tạo điều kiện để thao tác hiện ra, kích hoạt bằng UI, đối chiếu kết quả với dữ liệu thật, chụp ảnh. Hai nhánh của điều kiện, các tab/modal/drawer và toàn bộ lựa chọn của enum phải được kiểm tra. Việc trang mở được chưa chứng minh các nút trên trang hoạt động. Thư mục `studio/upload copy/` được ghi riêng là bản sao không được router sử dụng; không tính thành một màn hình sản phẩm.

## 2. Môi trường, tài khoản và dữ liệu xuyên suốt

| Thành phần | Giá trị chạy auth local |
| --- | --- |
| User | `http://127.0.0.1:53400` |
| Admin | `http://127.0.0.1:53401` |
| API | `http://127.0.0.1:53480/api/v1` |
| PostgreSQL | localhost port `55439`, database `hutube_e2e_runner` |
| Email | Pickup trong `frontend/e2e_testing/.state/mail`, không gửi SMTP |
| Tài khoản chính | `hutube.e2e.owner@example.test` |
| Username / tên hiển thị | `hutube_e2e_owner` / `HuTube — Người sáng tạo nội dung kiểm thử` |
| Mật khẩu ban đầu | `HuTubeE2e2026!` (chỉ dữ liệu test local) |

Giữ nguyên `.state`, email và scope môi trường qua mọi lần chạy. Runner dùng khóa hệ điều hành, chỉ một worker được sửa tài khoản này. Trước đăng ký, truy vấn tài khoản trong database test; nếu đã có thì lưu/reconcile `user_id` và dùng lại. Không thêm timestamp/random vào email, không xóa database để chạy lại. Checkpoint ghi nguyên tử sau từng bước có tác dụng, giữ bằng chứng PASS đầu tiên. Crash sau đăng ký nhưng trước ghi checkpoint được phục hồi bằng email cố định. Scope URL/port/database thay đổi phải dùng môi trường riêng có chủ đích, không tự ghi đè checkpoint cũ.

Flow đổi/reset mật khẩu sau này phải cập nhật mật khẩu trong checkpoint ngay sau thành công rồi dùng mật khẩu mới cho login; nếu crash giữa hai bước, xác định trạng thái thật trước retry, không đoán và thử hàng loạt. Tài khoản chính được dùng cho tất cả flow owner. Để kiểm tra người dùng khác, thành viên, phân quyền và reviewer không tự duyệt, cần tối thiểu các actor cố định sau; chỉ tạo một lần khi triển khai full suite, lưu ID/password/role trong checkpoint và tái sử dụng:

| Actor dự kiến, chưa được tạo bởi bộ auth | Email | Mật khẩu local dự kiến | Vai trò |
| --- | --- | --- | --- |
| Member | `hutube.e2e.member@example.test` | `HuTubeMember2026!` | Khách đăng nhập khác owner, thành viên kênh/gói |
| Reviewer 1 | `hutube.e2e.reviewer1@example.test` | `HuTubeReviewer12026!` | Claim và quyết định kiểm duyệt |
| Reviewer 2 | `hutube.e2e.reviewer2@example.test` | `HuTubeReviewer22026!` | Appeal và xung đột claim/SoD |
| Super admin | `hutube.e2e.superadmin@example.test` | `HuTubeSuperAdmin2026!` | RBAC/cấu hình recommendation |

Bộ auth hiện tại dùng **một tài khoản**: sau khi kiểm tra user thường bị từ chối Admin, fixture SQL chỉ trong database local tạm cấp role admin cho cùng `user_id`, thực hiện login/logout Admin thật rồi phục hồi role cũ trong `finally`. Checkpoint ghi role trước cấp để phục hồi ở lần chạy sau nếu crash. Đây là chuẩn bị fixture cho auth, không chứng minh UI quản lý vai trò đã được test. Full suite phải dùng actor riêng để kiểm tra tương tác nhiều vai trò.

| Dữ liệu có ý nghĩa | Giá trị / quy tắc |
| --- | --- |
| Kênh | `HuTube — Lao động và sáng tạo`, handle `hutube_e2e_laodong` |
| Video nguồn | `F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\Em Làm Thì Em Mới Có Ăn_ Không Làm Mà Đòi Có Ăn Thì…_720p.mp4` |
| File đã xác nhận | 99.009.115 byte; kiểm tra tồn tại và đọc metadata trước flow upload; chưa upload trong bộ auth |
| Tiêu đề video | `Em làm thì em mới có ăn — Giá trị của lao động` |
| Mô tả | `Tư liệu kiểm thử về nỗ lực, trách nhiệm và kết quả lao động; dùng kiểm tra phát video, chương và tương tác.` |
| Category / tags | Giáo dục (dùng category tương ứng nếu tồn tại); `lao-dong`, `ky-nang-song` |
| Chapters | `Mở đầu` tại 0; `Nỗ lực và kết quả`, `Bài học thực hành` tại khoảng 1/3 và 2/3 duration thật; không dùng mốc vượt duration |
| Playlist | `Bài học về lao động và trách nhiệm` |
| Comment / reply | `Đoạn giải thích về nỗ lực và kết quả rất rõ; mình sẽ áp dụng vào lịch học.` / `Mình cũng sẽ thử lập kế hoạch học theo từng tuần.` |
| Lý do quản trị | `Tình huống kiểm thử: cần đối chiếu nội dung với chính sách đã chọn.`; không bịa lý do vi phạm thật |
| Tài nguyên checkpoint | `channel_id`, `video_id`, `playlist_id`, `comment_id`, `invitation_id`, `payment_id`, `report_id`, `case_id`, `appeal_id`, `strike_id`, `job_id`, trạng thái và hash/metadata file |

Trước tạo tài nguyên, đọc ID đã lưu và xác nhận trạng thái/owner. Retry update tài nguyên đó; chỉ tạo lại nếu đã xác nhận không tồn tại và flow yêu cầu. Khi kiểm tra xóa hoặc purge, dùng một fixture phụ có tên nêu rõ mục đích và lưu ID; giữ video chính cho các flow kế tiếp. Không upload file 99 MB hàng chục lần chỉ để tạo pagination. Dataset nhiều trang có manifest, nguồn và chủ đề rõ ràng, được seed một lần vào database test riêng; không được tính metadata seed là bằng chứng upload thành công.

## 3. Quy tắc thời gian, ghi nhận và tiêu chí hoàn tất

| Loại bước | Budget và cách chờ |
| --- | --- |
| Click/fill/assert | 15 giây, locator có tên/label ổn định; chờ element đúng trạng thái |
| Điều hướng | 45 giây; auth hữu hạn dùng `networkidle` để khảo sát ban đầu |
| API auth / email Pickup | 30 giây; bắt response đúng method/path trước click; email đúng recipient/origin |
| Full suite auth | 300 giây phần browser; vượt budget fail, giữ checkpoint và dừng process được runner tạo |
| Build/migration | Mỗi lệnh tối đa 180 giây; startup mỗi server 120 giây; lần đầu có thể lâu hơn warm run |
| Upload 99 MB | Bắt đầu với timeout 300 giây, điều chỉnh từ uplink đo được; ghi byte/giây và tiến độ. Không áp timeout 15 giây cho toàn file |
| Probe/transcode | Poll trạng thái nghiệp vụ mỗi 2–5 giây, deadline cấu hình 20 phút; thành công phải có rendition/playback thật |
| Payment | Chờ QR/pending trong 30 giây, poll status có deadline; không chờ hết hạn 30 phút trong mỗi test, dùng fixture thời gian cho backend |
| Recommendation job | Request tạo job nhanh; poll ID đã lưu tối đa 30 phút, dừng khi failed/canceled/succeeded; không POST lại khi poll timeout |
| Timer/worker/expiry | Backend dùng clock/fixture có kiểm soát; một flow tích hợp thật kiểm tra worker, không sleep hàng giờ |

Các budget upload/job là điểm khởi đầu kế hoạch, chưa được đo. Player, SSE/SignalR, polling và download không dùng `networkidle` để kết luận xong. Chờ `loadedmetadata`, response cụ thể, phần tử kết quả hoặc trạng thái DB/API. Không dùng `sleep(60)` thay assert. Retry có giới hạn cho đọc trạng thái; thao tác tạo chỉ retry khi có idempotency/reconciliation. Báo riêng timeout do môi trường và lỗi ứng dụng.

Mỗi case ghi ID, actor, tiền điều kiện, bước, dữ liệu, expected, observed, thời gian, screenshot, API status và resource ID. Trạng thái: `PLANNED`, `PASS`, `FAIL`, `BLOCKED`, `REUSED`. REUSED là tiền điều kiện đã hoàn tất có bằng chứng trước đó, không phải thực hiện lại đăng ký. Không gộp BLOCKED hoặc tính năng giả thành PASS. Full Web chỉ hoàn tất khi tất cả route/binding/nhánh quyền được đối chiếu và case liên quan có bằng chứng; không tuyên bố bao phủ toàn hệ thống từ 14 case auth.

Ảnh desktop 1440×960 và mobile 390×844; thêm tablet 768×1024 cho full suite. Phân theo `screenshots/<run-id>/user|admin/<module>/<flow>/<case-id>/<step>.png`; mỗi case là một mục, tên bước phân biệt trạng thái và viewport. Flow xuyên app giữ chung case/resource ID nhưng ảnh đặt riêng User/Admin. Ảnh cũ đã được sắp xếp theo hierarchy này; baseline có cùng cấu trúc. Chụp trạng thái trước/đang lỗi/sau thành công/modal khi cần, mask password. Mỗi lỗi tự chụp ảnh và trace. Trace có thể chứa token/cookie/body: chỉ lưu local bị gitignore, không chia sẻ nguyên trace có bí mật. Kiểm tra console/pageerror, overflow ngang, focus, keyboard Enter/Space/Escape/Tab, label lỗi, loading và ngôn ngữ/theme.

## 4. Flow auth đã triển khai

Các bước thao tác bằng Chromium headless qua UI Angular production, API thật và PostgreSQL riêng. Không mock route API. Các case đánh dấu thực thi có ảnh trong báo cáo auth.

| Case | Các bước với tài khoản mục 2 | Kết quả cần đối chiếu |
| --- | --- | --- |
| AUTH-REG-01 | User `/register` → để trống → Đăng ký | `aria-invalid`, không POST register |
| AUTH-REG-02 | Điền tên/username/email/password; confirm `HuTubeE2e2026!Different` → submit | Lỗi chưa khớp, không POST |
| AUTH-REG-03 | Điền đúng, chụp desktop/mobile → kiểm tra checkpoint/database → chỉ submit nếu chưa có | Lần đầu 201, một user pending, thông báo đã tạo; lần sau REUSED đúng ID |
| AUTH-LOGIN-01 | Ngay sau đăng ký, `/login` → email/password đúng → submit | 403 chưa xác minh, không vào account; lần sau REUSED khi đã verified |
| AUTH-VERIFY-01 | Đọc liên kết email Pickup đúng recipient → mở `/verify-email?token=…` bằng browser | UI báo thành công và DB verified; lần sau giữ bằng chứng đầu |
| AUTH-REG-04 | Submit lại đúng bộ đăng ký | 409 `EMAIL_ALREADY_EXISTS`/`USERNAME_ALREADY_EXISTS`, UI lỗi, account_count vẫn 1 |
| AUTH-LOGIN-02 | `/login` → để trống → submit | Lỗi bắt buộc, không POST login |
| AUTH-LOGIN-03 | Email đúng, password `HuTubeE2e2026!Wrong` → submit một lần | 401 `INVALID_CREDENTIALS`, có alert; tránh lockout bởi spam |
| AUTH-LOGIN-04 | Email đúng, mật khẩu hiện tại → Đăng nhập | 200 đúng user_id, `/account` đúng tên; HttpOnly cookie đúng path, không lưu token/password trong storage; ảnh desktop/mobile |
| AUTH-LOGIN-05 | Reload `/account` | Phục hồi đúng session/identity, không rơi về login |
| AUTH-LOGIN-06 | Avatar → Đăng xuất → xác nhận → mở `/account` | Chuyển login; route được bảo vệ yêu cầu login |
| AUTH-ADMIN-01 | Admin `/login`, dùng user role bình thường | 403 `ADMIN_ACCESS_DENIED`, alert |
| AUTH-ADMIN-02 | Fixture cấp admin tạm → Admin login → reload | 200 isAdmin đúng ID, profile đúng email, cookie `hutube_admin_refresh` HttpOnly; ảnh desktop/mobile |
| AUTH-ADMIN-03 | Admin account → Đăng xuất → mở `/users` | Route guard về login; fixture khôi phục role user |

### AUTH-EXT — mở rộng auth, chưa triển khai

1. Dùng cùng email, forgot-password; xác nhận thông báo không tiết lộ account tồn tại; đọc email Pickup → reset mật khẩu thành `HuTubeE2e2026!Reset` → lưu checkpoint → login bằng mật khẩu mới; mật khẩu cũ thất bại. Link hết hạn, sai, dùng hai lần phải bị từ chối. Không tạo user mới.
2. Username/email hoa-thường, khoảng trắng, email sai, password quá ngắn/dài, thiếu đồng ý nếu UI có; thử biên đúng constraint backend và confirm show/hide password. Double-click không tạo hai record; network lỗi không giả thành công.
3. Verify link thiếu/sai/hết hạn/đã dùng; back/forward và return URL nội bộ; URL ngoài origin không được điều hướng tự do. Admin không mở registration dù route khai báo có điều kiện.
4. Khóa/suspend/delete user sau login, thu hồi session và đổi quyền giữa phiên: refresh/current route/API bị chặn đúng, UI hết loading, không giữ dữ liệu nhạy cảm. Hai tab, phiên User/Admin, mobile API không trộn cookie/platform.
5. Google login cần sandbox cấu hình hợp lệ: popup cancel, credential sai/expired, email unverified, account liên kết sẵn và blocked. Ghi BLOCKED nếu thiếu dependency; auth local tắt Google, không coi đã test OAuth thật.

## 5. Ma trận route

Mọi route sau phải kiểm tra điều hướng trực tiếp, link UI, reload, back/forward, guard khi guest/đủ quyền/thiếu quyền, ID không tồn tại và lỗi API. Dynamic ID dùng checkpoint, không hardcode ID ngẫu nhiên. `X-ROUTES` áp dụng cho tất cả các dòng trong inventory.

| App | Route | Nhóm flow |
| --- | --- | --- |
| User | `/login`, `/register`, `/verify-email`, `/forgot-password`, `/reset-password` | AUTH, AUTH-EXT |
| User | `/`, `/home`, `/explore`, `/search`, wildcard → home | U-DISCOVERY, X-ROUTES |
| User | `/subscriptions` | U-SUBSCRIPTION; guest thấy yêu cầu login |
| User | `/playlists`, `/playlists/:id`, `/channel/:handle/playlists`, `/channel/:handle/playlists/:id` | U-PLAYLIST |
| User | `/channel/create`, `/channel/:handle`, `/channel/:handle/customize` | U-CHANNEL |
| User | `/watch/:id` | U-WATCH |
| User | `/terms`, `/privacy`, `/guidelines`, `/policies` | U-POLICY |
| User | `/plans`, `/plans/accept-invite`, `/plans/:planId`, alias `/my-plan` | U-PLAN |
| User | `/account`, alias `/profile`, `/history`, `/liked`, alias `/library` | U-ACCOUNT, U-LIBRARY |
| User | `/channel-invitations`, `/studio/invitations` | U-CHANNEL, alias đúng |
| User | `/studio`, `/studio/setup`, `/studio/overview`, `/studio/content`, `/studio/content/:id/edit`, `/studio/upload`, `/studio/analytics`, `/studio/comments`, `/studio/subtitles`, `/studio/settings` | U-STUDIO; channel guard và từng studio permission |
| Admin | `/login`, `/verify-email`, `/forgot-password`, `/reset-password`, `/forbidden` | AUTH, AUTH-EXT, X-ACCESS |
| Admin | `/users`, `/channels`, `/videos`, `/roles`, `/plans`, `/topics`, `/policies` | A-USERS, A-CHANNELS, A-VIDEOS, A-RBAC, A-PLANS, A-TOPICS, A-POLICY |
| Admin | `/moderation/videos`, `/moderation/reports`, `/moderation/appeals`, `/moderation/strikes` | A-MODERATION |
| Admin | `/cf-seeder`, `/recommendations`, `/account`, root/wildcard → account | A-CF, A-RECOMMENDATION, A-ACCOUNT, X-ROUTES |

## 6. Flow Web User — kế hoạch chi tiết

Các dòng con `.01`, `.02` là case riêng trong nhóm được inventory tham chiếu. Sau mỗi save, reload và đọc API để kiểm tra persist; đối chiếu trước/sau với cùng resource ID. Mọi nút cancel/close/dismiss/copy/download/export và keyboard tương ứng trong inventory đều phải có assertion, không chỉ chụp ảnh.

| ID | Tiền điều kiện → các bước | Expected và bằng chứng |
| --- | --- | --- |
| U-ACCOUNT.01 | Login owner → account tab → sửa tên/bio `Tìm hiểu về lao động, học tập và sáng tạo.` → cancel → mở lại/save → avatar file ảnh hợp lệ | Cancel không persist; save đúng DB, reload giữ bio; ảnh lỗi type/size không thay avatar; preview/error/loading đúng |
| U-ACCOUNT.02 | Từng tab notifications/privacy/downloads/billing/advanced → đổi mỗi lựa chọn → save nếu có → reload | Preference/language/theme, subscription privacy và nhóm notification đúng trạng thái; copy user/channel ID đúng clipboard; nút chưa hỗ trợ phải báo rõ |
| U-ACCOUNT.03 | Tạo 2 browser context cùng owner → advanced → đổi password → checkpoint; revoke session khác/cancel/current; logout others | Chỉ session mục tiêu bị revoke; phiên còn lại bị chặn sau refresh; current revoke logout; không revoke ID người khác |
| U-ACCOUNT.04 | Downloads → từng chất lượng, smart download → xóa một/xóa tất cả/cancel → billing chuyển plans | Preference đúng, dữ liệu download bị xóa có chủ đích; quyền gói kiểm soát chất lượng, không tạo download giả |
| U-CHANNEL.01 | Owner chưa có channel → `/channel/create` hoặc studio/setup → tên/handle ở mục 2 → kiểm tra handle → create → lưu ID | Một channel đúng owner, route handle đúng; handle trùng/ký tự sai lỗi rõ; chạy lại mở channel đã có |
| U-CHANNEL.02 | Customize/settings → avatar/banner/watermark → tiêu đề/mô tả/links → thêm, sửa, reorder, remove → save/reload | Branding và link đúng public page, MIME/size/URL validation; hủy không thay đổi; lỗi một upload không báo mọi thứ thành công |
| U-CHANNEL.03 | Public channel → Home/Videos/Playlists → sort/page/search nếu hiện → share/copy → mở handle sai | Dữ liệu cùng channel, totals đúng; không leak nội dung private/deleted; empty/notfound/loading có UI |
| U-CHANNEL.04 | Owner invite member bằng email cố định → member `/studio/invitations` accept/decline → owner đổi role/remove/revoke | Checkpoint invitation ID; từng permission upload/edit/comments/analytics/settings có allow/deny UI và API; invitation đã xử lý không làm lại; owner không bị mất quyền bởi member |
| U-CHANNEL.05 | Member subscribe, chọn từng notification setting; owner report đối tượng khác theo fixture; mở trạng thái moderation/appeal | Subscription count chính xác không cộng lặp; report/appeal đúng target và status; khách phải login |
| U-CHANNEL.06 | Dùng channel phụ dành cho delete → delete cancel/confirm; channel chính thử blocked/suspended fixture | Không xóa tài nguyên xuyên suốt; bị chặn upload/play theo trạng thái; dữ liệu/account người khác không được sửa |
| U-DISCOVERY.01 | Guest/owner `/home` → chọn recommendation → mở watch → back; tắt/failed recommendation service theo fixture | Cards đúng video có thể xem; fallback có nguồn dữ liệu thật; không hiện hidden/private; personalized và anonymous được phân biệt |
| U-DISCOVERY.02 | Explore/search → tìm `lao động` và không dấu → từng category/sort/duration/date → reset → next/previous/pageSize | Query params và result khớp điều kiện, reset về trang đầu; empty không dùng dữ liệu mẫu; unicode/XSS hiển thị dưới dạng text |
| U-DISCOVERY.03 | Trending hub/carousel previous/next, creator cards → channel → subscribe; gõ nhanh đổi filter liên tục | Không vượt biên carousel; response cũ không ghi đè query mới; giữ scroll/focus hợp lý |
| U-SUBSCRIPTION.01 | Guest → subscriptions CTA login; member subscribe kênh → subscriptions → chọn tab, video và notification | Danh sách thuộc member, subscribe/unsubscribe cập nhật đúng; không lộ private subscription của owner |
| U-PLAYLIST.01 | Owner `/playlists` → create tên mục 2, từng visibility → lưu ID → edit/cancel/save | Trùng retry không sinh playlist mới; public/private/unlisted được kiểm soát đúng URL/API |
| U-PLAYLIST.02 | Add video search chọn video checkpoint → reorder lên/xuống → remove/cancel → add lại → reload | Không trùng item, thứ tự persist, tombstone video bị xóa được xử lý đúng; user khác không sửa |
| U-PLAYLIST.03 | Public/channel playlist → play all/shuffle → next/previous → share/copy → quay lại | Query playlist/index đúng, không phát sai nguồn khi chuyển nhanh; shuffled order hợp lệ không mất bài; ảnh empty/private/removed |
| U-PLAYLIST.04 | Playlist phụ → delete cancel/confirm; account có nhiều playlist fixture → pagination/filter | Chỉ xóa playlist phụ; video không bị xóa theo; số trang/tổng và quyền từng row đúng |
| U-LIBRARY.01 | Owner watch video → `/history` → sort/search/filter/page → mở lại → chuyển `/liked` | History lấy tương tác thật, watchSeconds hữu hạn đúng; liked xuất hiện/biến mất theo rating, không lẫn user |
| U-LIBRARY.02 | Like/dislike/clear trên video → reload liked/history; alias library/profile | Không cộng lượt lặp; video private/hidden/deleted không hiện URL nguồn trái quyền |
| U-POLICY.01 | Mở từng terms/privacy/guidelines/policies → nhóm/search/detail → print/download PDF nếu UI có | Nội dung version công bố và severity/group đúng; không dùng modal rỗng; PDF/download thực sự có dữ liệu |
| U-POLICY.02 | Privacy toggle chưa hỗ trợ và liên kết hỗ trợ/pháp lý → keyboard/mobile | Disabled/giải thích rõ, không thông báo lưu giả; link hoạt động đúng đích |
| U-PLAN.01 | Catalog → từng gói → detail → so feature/giá/duration/max member; current plan → share/copy | Giá/đơn vị/thời hạn từ API; gói inactive không mua được; free plan của account đã đăng ký đúng |
| U-PLAN.02 | Chọn gói sandbox → create payment → lưu payment ID → QR → poll → close/reopen bằng ID → webhook sandbox hợp lệ | Pending→paid cấp entitlement đúng một lần; close không được coi đã thanh toán; expired/canceled/failed không cấp gói; không chuyển tiền thật |
| U-PLAN.03 | Owner có gói hỗ trợ member → invite cố định → member accept-invite → owner allocate storage/edit/remove/revoke → renew setting | Quyền owner, tổng allocation không vượt quota, không giảm dưới usedBytes; invite sai/expired/đã dùng bị chặn; state persist |
| U-PLAN.04 | Downgrade/expiry fixture → thử upload/download/background/PiP → reload | Giới hạn áp dụng ở backend và UI, không chỉ ẩn nút; thiếu dependency thanh toán ghi BLOCKED |

### U-STUDIO — flow upload → xử lý → xuất bản → quản lý

1. **U-STUDIO.01**: owner login → tạo/dùng kênh checkpoint → `/studio/upload`. Dùng đúng file mục 2 bằng file input. Đọc duration/dimensions thật (ffprobe/browser metadata), chụp file và preview. Lần sau nếu `video_id` đã ready thì dùng lại cho downstream; test upload riêng dùng phiên upload ID đã lưu, không tự upload lại do timeout.
2. **U-STUDIO.02**: đi qua toàn bộ bước wizard, next/back/cancel: tiêu đề, mô tả, category, tags, language; thumbnail upload/chọn frame/seek; chapters hợp lệ; privacy và allowComments; playlist; trang review. Trống/biên/quá dài/chapters trùng/ngoài duration/ảnh sai loại phải lỗi đúng trường. Scheduled publish và tự tạo phụ đề đang disabled phải kiểm tra disabled/giải thích, không ghi PASS cho xử lý chưa có.
3. **U-STUDIO.03**: lưu draft → reload → restore/cancel restore; publish đúng một lần → lưu upload/video ID ngay khi có → tiến độ từng giai đoạn → poll processing tới ready → GET playback và phát thật. Không tin duration/quality client nếu server probe khác. Nguồn 720p không được giả có rendition chất lượng cao hơn nguồn. Với protocol dùng chunk, lấy `chunkSize` từ response (CF store hiện 24 MiB: file này cần 4 chunk); không hardcode số chunk cho mọi endpoint.
4. **U-STUDIO.04**: file không tồn tại/sai extension/zero byte, quá quota, không đủ role, hủy trước/trong upload, gián đoạn mạng, request lặp, server restart, lỗi probe/FFmpeg/storage, retry đúng upload ID. UI không giữ success giả; DB/storage/manifest không có bản hoàn tất trùng; thông báo riêng lỗi có thể phục hồi. Auth runner hiện tắt video processing, không dùng cấu hình này để chạy media suite.
5. **U-STUDIO.05**: content lọc mọi status/visibility/category/search/page → mở edit video checkpoint → sửa metadata/thumbnail/tags/playlist → save/reload. Response cũ khi chuyển video nhanh không được ghi vào video mới; lỗi playlist sau save metadata báo phần thành công/thất bại đúng.
6. **U-STUDIO.06**: content/detail xem pending/processing/rejected/ready/removed, retry hợp lệ, delete fixture phụ/cancel/confirm; creator moderation notice → appeal lý do/evidence → xem kết quả. Video purge không được restore bằng UI dù appeal đã accept.
7. **U-STUDIO.07**: overview/analytics → chọn mọi khoảng thời gian/tab/chart → kiểm tra totals với API ở dataset nhiều trang; views khác watchSeconds, không chỉ cộng trang đầu. Export nếu có binding phải kiểm tra file/header/row/value và spreadsheet formula escaping. Empty/loading/error không điền số mẫu.
8. **U-STUDIO.08**: comments → video/filter/status/sort/page → view replies/edit/reply/hide/delete/moderation theo permission → reload/watch phía member. Disable comments phải chặn mutation ở API; moderation visibility đúng giữa owner/member/guest.
9. **U-STUDIO.09**: subtitles → trạng thái tính năng hiện có, toàn bộ button hiện/disabled. Nếu chỉ placeholder thì kiểm tra thông báo và mở issue phần chưa thực hiện; không coi là dịch/phụ đề thành công. Settings/invitations áp dụng U-CHANNEL.02/.04 với đủ và thiếu từng studio permission.

### U-WATCH — flow xem và tương tác

1. **U-WATCH.01**: guest/member `/watch/<video_id>` ready → chờ metadata → play/pause, seek, volume/mute, speed, từng quality có thật, chapters; fullscreen, mini player/PiP theo khả năng browser và entitlement. So currentTime/duration/paused và rendition URL/status, không chỉ kiểm tra icon đổi. Không giữ browser fullscreen quá deadline.
2. **U-WATCH.02**: xem đến một mốc có ý nghĩa → pause/navigate → history/progress → resume. View count/rating/watchSeconds không tăng sai khi reload/gửi lặp hoặc out-of-range. Playlist A→B nhanh, next/previous và onEnded không phát stream A cho video B.
3. **U-WATCH.03**: member like→dislike→clear, subscribe→notification setting→unsubscribe; share/copy, add/remove playlist, download từng chất lượng được phép. Kiểm tra clipboard/download file thật, quota/plan; guest chọn mutation được dẫn login, không làm mất context.
4. **U-WATCH.04**: comment có ý nghĩa ở mục 2 → reply → edit/cancel/save/delete/cancel, reaction, sort, pagination → report comment/video/channel đúng loại → lưu report ID. Owner/member khác không edit/delete trái quyền; blocked/disabledComments/hidden state có UI và API nhất quán.
5. **U-WATCH.05**: guest/member/owner với public/private/unlisted/age-restricted/hidden/removed/deleted và channel suspended. Kiểm tra authorization, không lộ sourceURL/thumbnail nhạy cảm qua JSON. Video đang processing không có play giả; missing rendition/media 404 có retry/error; network gián đoạn không chạy vô hạn.

## 7. Flow Web Admin — kế hoạch chi tiết

Login bằng actor đã cấp quyền cố định. Chạy mỗi nhóm với đủ quyền và với permission bị thu hồi; direct URL và API đều kiểm tra. Role admin không đồng nghĩa super_admin. Restore fixture sau flow; không thao tác trên user thật.

| ID | Các bước | Expected |
| --- | --- | --- |
| A-ACCOUNT.01 | Login → account profile/preferences/theme/language → reload; sessions → revoke/cancel/current/logout others/logout | Read-only profile phản ánh API, preference persist; session mục tiêu đúng; guard đúng sau revoke |
| A-USERS.01 | Users → search email owner → mọi role/status/filter → pageSize/page → detail → statistics từng range/custom | Tổng/trang đúng, clear filter reset; drawer đúng ID khi chọn nhanh; empty/error hiển thị |
| A-USERS.02 | Chọn fixture member → lock/unlock với reason → đổi role theo permission → xem notification User | Guard/API bị khóa giữa phiên; audit actor/target/reason, notification đúng người; không tự nâng quyền |
| A-CHANNELS.01 | Channels → các status/tab/search/sort/pageSize/page → menu/detail → export CSV | Sort/tổng/filter đúng; menu không bị cắt trên mobile; CSV Unicode/formula escaped; time filter chưa hỗ trợ disabled |
| A-CHANNELS.02 | Fixture channel phụ → ban/suspend/unban/delete có reason và cancel → User reload/watch/upload | Trạng thái và quyền xem/tải lên thống nhất, thông báo gửi đúng owner; delete không phá channel chính |
| A-VIDEOS.01 | Videos → toàn bộ status/visibility/category/date/sort/pageSize → detail/preview/statistics → export | Không dùng row stale, totals đúng, CSV có nội dung đúng trang/định nghĩa export |
| A-VIDEOS.02 | Edit metadata → thử clear description, category, title và chuyển video nhanh → cancel/save/reload | Giá trị rỗng được persist nếu hợp lệ, không ghi video trước vào video sau; permission và audit đúng |
| A-VIDEOS.03 | Video phụ → hide/unhide/remove/restore từng reason/cancel → watch/creator phía User | Luồng trạng thái hợp lệ, không restore purged; UI phản ánh hiệu lực thực tế |
| A-VIDEOS.04 | Nếu nút Add Video hiện → title/visibility → submit → truy vấn DB/list | Hiện `submitAddVideo()` chỉ đóng modal và báo notice, không gọi API. Case phải phát hiện không persist và ghi FAIL/issue nếu yêu cầu tạo thật; không chấp nhận toast là bằng chứng đã tạo video |
| A-RBAC.01 | Roles → search → create role code/name/description/reason → permissions search/toggle → save → assign member → login lại | Role và permission persist; từng API được allow/deny như ma trận; session cũ cập nhật/revoke đúng |
| A-RBAC.02 | Edit/delete role phụ; thử code trùng, role hệ thống/đang được dùng, missing permission, tự nâng quyền | Constraint và lỗi rõ; cancel không thay đổi; permission tổng và permission thành viên kênh không bị nhầm |
| A-PLANS.01 | Plans → từng tab/template → create gói test có giá/thời hạn/quota/maxMembers/features/order → edit/archive/reload | Gói chỉ tạo một lần lưu ID; giá/byte/time units đúng; inactive không hiển thị mua, gói đang dùng có ràng buộc |
| A-PLANS.02 | Mỗi feature download/background/PiP/upload, numeric 0/negative/overflow/decimal → User plans | Không parse sai/hạ quota dưới used; feature card và entitlement backend khớp |
| A-TOPICS.01 | Categories/tags → search → create tên chủ đề có ý nghĩa nếu thiếu → edit/status/archive/delete | Unique/biên/permission; category/tag đang được video dùng không mất liên kết sai; reload đúng |
| A-POLICY.01 | Groups/search/details → create code/group/severity/text → edit draft/version → publish new version → User policies | Version/code/status persist; published immutable theo contract; policy lưu trong moderation decision đúng version |
| A-CF.01 | Seeder → chọn existing account pool từ manifest → import JSON/template → file picker/folder fallback → category/quality settings → preview | Không chạy chế độ tạo account mới mỗi lần; invalid JSON/duplicate/thiếu quyền rõ; đúng account/video IDs |
| A-CF.02 | Chạy upload seed dùng file mục 2 → chunk/status/history/log → cancel/reset/download history → restart/recover | Dữ liệu persist và đúng nguồn, tiến độ không mất ID; không gọi lại job tạo dữ liệu khi chỉ cần poll; reset UI không xóa checkpoint |
| A-RECOMMENDATION.01 | Super admin → status/registry → từng model được API công bố → active average/weighted và toàn bộ weight → save/reload | Non-super admin bị chặn; weight normalize/decimal/zero/negative hợp lệ đúng constraint; cấu hình thực sự được feed sử dụng |
| A-RECOMMENDATION.02 | Matrix preview/page/export CSV → model update job → polling/history/log → error/cancel | Dữ liệu/headers/order Unicode đúng; job ID persist, không làm treo request; thiếu service ghi BLOCKED |
| A-RECOMMENDATION.03 | Simulation → fixed manifest users/videos/categories → mỗi signal/rate/cluster/comment template → start/stop/history | Tương tác có ý nghĩa, không account spam; không tạo bot mới do reload; job canceled không tiếp tục mutation |

### A-MODERATION và X-MODERATION — chuỗi User → Admin → User

1. **A-MODERATION.01**: video checkpoint pending → reviewer1 queue video, filter/page → claim → detail chính sách/reason/notes → approve. User content thấy ready đúng và watch phát được; request release/claim lặp, claim reviewer2 đồng thời không ghi đè ownership. Các action bulk nếu hiển thị phải kiểm tra tất cả row được chọn, partial failure và role.
2. **A-MODERATION.02**: video fixture phụ → reject/escalate với từng decision hiện trong UI và policy/version hợp lệ → User nhận notice/creator status. Quyết định không có reason/policy khi bắt buộc phải bị chặn; release/claim lại giữ lịch sử.
3. **A-MODERATION.03**: member tạo report video/comment/channel → reviewer1 reports filter/group → claim/release/classify → xử lý. Kiểm tra từng decision hiện có: dismiss, warn, age_restrict, recommendation_restricted, hide, remove, upload_restriction, strike, lock_channel, escalate; đúng target, đúng hiệu lực, idempotent và audit. Không chọn action không phù hợp target.
4. **A-MODERATION.04**: owner tạo appeal bằng lý do và evidence (ảnh/video hợp lệ) → reviewer2 appeals claim → xem evidence/open target về đúng User origin → approve/reject/escalate. Reviewer đã quyết định không tự duyệt appeal trái SoD; evidence hết quyền/broken có error; video purge không khôi phục; effective state và thông báo đúng.
5. **A-MODERATION.05**: strikes → create/revoke với severity/policy/note/restriction days → channel lock/unlock → User upload/watch. Đối chiếu số strike active/expired/revoked và ràng buộc không âm; thời gian hết hạn kiểm tra bằng backend clock, không đợi hàng ngày trong browser.
6. **X-MODERATION.01**: claim hết hạn, hai reviewer conflict, quyết định lặp, channel đã bị lock/deleted, report legacy, appeal trùng/đã xử lý, action rollback khi lưu DB lỗi. UI không success giả; bằng chứng cả trang Admin và User sau quyết định cùng resource ID.

## 8. Các kiểm tra chung không được bỏ qua

| Nhóm | Kịch bản áp dụng mọi màn hình/thao tác liên quan |
| --- | --- |
| X-SHELL | Header/sidebar/menu/drawer/search/notification/avatar, open/close/cancel/dismiss, active route, backdrop/Escape, notification read/read-all và link target đúng; realtime reconnect không nhân đôi item |
| X-ACCESS | Guest, owner, member, reviewer1/2, admin thiếu permission, super_admin; direct URL/ID, không dựa chỉ vào nút ẩn; 401/403/404 không leak dữ liệu |
| X-FORM | Mọi input/select/checkbox/upload: required, min/max, Unicode/space, enum sai, negative/overflow, URL, double click, cancel, Enter, stale response; XSS dạng text, CSV công thức bị escape |
| X-ERROR | API timeout/offline/400/401/403/404/409/422/429/500 theo contract; loading kết thúc, thông báo cụ thể, retry có giới hạn, không mutation trùng. Fault injection riêng phải gắn nhãn không phải backend happy path thật |
| X-UI | Desktop/mobile/tablet, light/dark, vi/en nếu hỗ trợ; keyboard/focus/label, dài tên/tiêu đề, zoom, không overflow, modal không bị che/cắt, empty và disabled rõ |
| X-DATA | Pagination > 1 trang và >50 rows với dataset riêng, mọi enum/order/filter/reset, query params và counts; cross-user/cross-channel không lẫn |
| X-STATE | Reload/back/forward/tab mới, storage/auth restore, crash/restart sau bước tạo, checkpoint reuse không làm mất bằng chứng đầu; không test destructive song song trên account chính |

## 9. Performance frontend — kế hoạch, chưa chạy

Production build như runner; cold cache rồi warm cache trên home/search/watch/account và Admin users/videos/moderation/recommendations. Ghi cấu hình máy, browser, build, mạng, số rows, API latency và kích thước asset. Đo navigation, LCP/CLS, long task, phản hồi click/filter/scroll, heap trước/sau 20 lần chuyển route; video đo time-to-first-frame, seek/buffering riêng, không gộp tải cả file vào page latency.

Ngưỡng nội bộ đề xuất để bắt đầu: LCP ≤2,5 giây, CLS ≤0,1, phản hồi interaction p95 ≤200 ms với mạng/máy baseline đã ghi; không có pageerror; heap không tăng liên tục sau các vòng route. Đây là mục tiêu cần hiệu chỉnh, không phải kết quả đo hay cam kết hiện đạt. Chạy thêm profile mạng chậm với deadline riêng; ảnh screenshot không dùng làm thước đo performance. Danh sách lớn kiểm tra render/filter không block UI; realtime nhiều event không nhân đôi listener; export/job không khóa trang. Backend load và profile xem tài liệu backend.

## 10. Thứ tự triển khai và cổng kiểm tra bao phủ

1. Auth hiện đã triển khai → account/preferences/sessions → channel/membership → upload một nguồn → ready/watch.
2. Discovery/library/subscriptions → playlist/comments/download → plan/payment sandbox/membership.
3. Admin RBAC/users/channels/videos/topics/policies → moderation/report/appeal/strike xuyên hai ứng dụng.
4. Seeder/recommendation/simulation → toàn bộ negative/role matrix/responsive → performance.

Regenerate inventory khi code đổi. Đối chiếu mọi route và binding với case chi tiết và status, thêm case cho thao tác mới; rà thủ công dynamic templates, href/routerLink, service side effect và feature flag mà regex không biểu diễn đủ. Endpoint mới đối chiếu backend inventory. Chưa triển khai các flow trên thì giữ PLANNED; dependency thiếu ghi BLOCKED kèm lý do. Chỉ công bố không bỏ sót khi inventory được reconcile, tất cả case yêu cầu đã có assertion và evidence, không có nhánh placeholder được nhận thành công giả.
