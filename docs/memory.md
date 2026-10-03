# HuTube project memory

> Cập nhật: 2026-09-27 (Asia/Bangkok)

> Cập nhật E2E 2026-10-03: Các script Playwright JavaScript trong `frontend/user-web/e2e/` đã được gỡ. Những ghi chú E2E cũ bên dưới là lịch sử, không còn là lệnh chạy hiện hành. Suite hiện hành là `frontend/e2e_testing/run_local.py`, chạy auth trên UI User/Admin và tạo screenshot/report; CI upload bằng chứng thành artifact GitHub Actions.

## Quyết định đã chốt

- Explore hub dùng một truy vấn aggregate lượt xem theo `video_id`. Kết quả top video theo danh mục lấy bằng `ROW_NUMBER`/window-equivalent trong SQL, còn top 12 toàn hệ thống được dùng chung cho bảng xếp hạng và trending.
- Lịch sử xem dùng cửa sổ 30 ngày. `GET /api/v1/library/history` giữ tham số `page` để phân trang trong cửa sổ và nhận thêm `before`; client giữ cố định `windowEnd` cho mọi trang rồi trừ đúng 30 ngày khi tải cửa sổ kế tiếp.
- Các endpoint tìm kiếm dùng `ILIKE` để PostgreSQL có thể dùng trigram index, thay cho `LOWER(column)` trên toàn bảng.
- Các danh sách video, bình luận, reaction và rating được enrich theo batch bằng aggregate/group query; không gọi một query thống kê cho từng dòng.
- Thống kê rating dùng `AVG/COUNT` trong SQL, không tải toàn bộ điểm về ứng dụng.
- Thay tag video tải các tag hiện có một lần và thêm liên kết trong cùng unit of work.
- Feed cá nhân hóa chỉ gửi tối đa 5.000 video đã xem gần nhất cho model; catalogue loại video đã xem bằng `NOT EXISTS` trên database để không tải toàn bộ lịch sử vào RAM.
- Ma trận collaborative filtering join trực tiếp với user/video hợp lệ và đọc history/reaction/rating/comment bằng async enumeration; không tạo các mệnh đề `IN` khổng lồ hay materialize từng stream đầy đủ trước khi xử lý.
- Các endpoint danh sách không có contract phân trang được giới hạn số dòng hợp lý (playlist, download, appeal và lựa chọn admin); nên bổ sung cursor/page nếu sản phẩm cần hiển thị vượt giới hạn này.

## Index đã thêm

Migration `20260927120000_QueryPerformanceIndexes` thêm index cho:

- lịch sử xem theo video và theo `(user_id, video_id, viewed_at)`;
- catalogue public theo category/thời gian;
- reaction, rating, share, comment, comment reaction và video tag;
- subscription active, report theo video, moderation case, appeal target;
- trigram search cho video title/description, channel name, tag name và user username/display name/email.

Migration có `IF NOT EXISTS` để có thể triển khai lặp lại an toàn. `Down` chỉ xóa các index do migration này tạo; extension `pg_trgm` được giữ lại vì có thể được module khác dùng.

## Hợp đồng API lịch sử xem

`before` là mốc kết thúc độc quyền của cửa sổ 30 ngày. Mặc định là thời điểm hiện tại. Client giữ cố định `windowEnd` cho mọi trang của cửa sổ rồi trừ đúng 30 ngày để tạo `before` cho cửa sổ kế tiếp; không dùng timestamp của video cuối cùng làm cursor vì dữ liệu thưa có thể gây chồng lấn. `page/pageSize` vẫn có hiệu lực trong từng cửa sổ để không làm vỡ client cũ.

## Theo dõi sau triển khai

1. Chạy migration trên staging và kiểm tra `EXPLAIN (ANALYZE, BUFFERS)` cho explore, search, history, comments và admin queues.
2. Theo dõi p95/p99 thời gian phản hồi và số query/request trong 24 giờ đầu.
3. Nếu catalogue lớn khiến aggregate lượt xem vẫn nặng, tạo bảng thống kê lượt xem theo `video_id` cập nhật bất đồng bộ rồi thay CTE aggregate bằng bảng đó.
4. Có thể thêm cache ngắn hạn cho explore hub sau khi đo p95; TTL đề xuất 30–60 giây và phải loại bỏ khi nội dung moderation thay đổi.

## Xác nhận thay đổi

- `dotnet build backend/src/HuTube.Infrastructure/HuTube.Infrastructure.csproj --no-restore`: 0 warning, 0 error.
- API build riêng với output tạm: 0 warning, 0 error.
- `npm run build -- --configuration development` tại `frontend/user-web`: hoàn tất.
- Migration `20260927120000_QueryPerformanceIndexes` đã apply thành công trên database local qua `.env.local` vào 2026-09-27; staging/production vẫn cần chạy riêng.
- Đã kiểm tra runtime `GET /api/v1/feed/explore-hub` sau khi restart API local: HTTP 200; SQL window category và aggregate featured creators chạy thành công.
- Sau khi log runtime phát hiện EF Core không dịch được left join với aggregate count, feed và search đã chuyển count sang kiểu nullable rồi dùng `COALESCE` khi sắp xếp/materialize; `GET /api/v1/feed/explore?page=1&pageSize=5` và `GET /api/v1/feed/home?page=1&pageSize=5` đều HTTP 200.
- Danh sách topic/tag admin không còn materialize count nullable từ left join; service tải danh sách và aggregate usage thành hai truy vấn rồi ghép bằng dictionary, tránh lỗi `Nullable object must have a value` với topic/tag chưa có video.
- Admin video/channel aggregate left join cũng dùng projection nullable và coalesce khi sort, đồng nhất với feed/search.
- API local đã được build lại không warning/error và restart trên `http://localhost:5080`.
- Kiểm tra lại bằng `dotnet ef database update --no-build` với `.env.local`: database local báo `No migrations were applied. The database is already up to date.`
- Explore tabs lấy danh mục từ `GET /api/v1/categories`, giữ `categoryId` database khi chọn tab và gửi chính ID đó vào truy vấn ranking; không còn danh sách slug/nhãn gán cứng ở frontend.

## Cài đặt tài khoản — gói và thanh toán

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Màn hình cài đặt người dùng nằm trong `frontend/user-web/src/app/features/account/`; chọn tab qua `AccountPage.setTab`. Khi vào tab thanh toán, tải gói hiện tại bằng `GET /api/v1/plans/my-plan`.
- Lịch sử thanh toán lấy từ `GET /api/v1/payments`. Lịch sử mua gói là các giao dịch có trạng thái `paid`; lịch sử thanh toán hiển thị mọi trạng thái (`paid`, `pending`, `failed`, `cancelled`). Hai panel dùng chung một lần tải và chỉ gọi API khi người dùng mở panel.
- Dữ liệu lịch sử mua/thanh toán hiện đã được backend cung cấp qua Payment API; không cần migration hoặc endpoint mới cho giao diện này. Giao dịch có `PlanName`, `Amount`, `Currency`, `TransactionCode`, `Status`, `PaidAt` và `CreatedAt`.
- Khi `MyPlan.subscription` không có, không mặc định coi gói trả phí là đang hoạt động: dùng `activePaidPlanIds` để phân biệt gói trả phí cũ đã hết hạn. Gói miễn phí không có subscription được xem là gói hiện tại.
- Các nhãn billing có cả tiếng Việt và tiếng Anh trong `frontend/user-web/src/app/core/i18n.service.ts`; số tiền định dạng qua `LocaleCurrencyPipe` và ngày qua `LocaleDatePipe`.
- Quyết định UI: hiển thị dữ liệu gói thật thay cho thẻ quảng bá Premium/phương thức thanh toán giả; liên kết `/plans` mở danh sách gói. Các lịch sử mở rộng theo yêu cầu để màn hình ban đầu gọn và tránh tải dữ liệu không cần thiết.
- Lỗi QR vừa hiện rồi đóng: `PlanDetailPage` theo dõi object `AuthService.user()`; refresh token tạo object User mới cùng `userId`, effect cũ nhầm là đổi danh tính rồi xóa `activePayment`. Chỉ reset khi `userId` thay đổi thật.
- Regression test `frontend/user-web/e2e/payment-modal.cjs` giả lập poll đầu tiên nhận 401, refresh token cùng user rồi poll lại pending; chạy được bằng `npm run test:e2e:payment`. Có thể đặt `PLAYWRIGHT_HEADLESS=false` để mở Edge nhìn thấy flow. Ảnh được xếp theo `frontend/e2e_testing/screenshots/<run-id>/user/billing/payment/PAYMENT-QR-01/`.
- Xác nhận 2026-10-02: regression E2E trên Edge qua sau 5,5 giây với hai lần refresh auth; `npm run build -- --configuration development` tại `frontend/user-web` hoàn tất thành công.

## Watermark thương hiệu kênh và upload video

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Watermark được tải lên qua `POST /api/v1/channels/{channelId}/watermark` và lưu ngay trên kênh; trang Xây dựng thương hiệu không cần URL textfield hoặc nút Lưu riêng. Sau phản hồi upload, giữ nguyên tab đang mở khi tải lại dữ liệu kênh để preview không biến mất.
- Watermark là lớp phủ ở góc dưới bên phải của trình phát, không được encode/burn vào file video nguồn. Watch player đọc `ChannelWatermarkUrl` từ chi tiết video. Các API kênh và chi tiết video phải đổi đường dẫn lưu R2 thành read URL trước khi trả về client; không gửi signed URL ngược lại khi lưu thông tin cơ bản của kênh.
- Wizard upload lấy watermark từ kênh đang chọn trong `StudioDataService`; mục “Xem trước watermark” mặc định bật và cho phép ẩn/hiện lớp phủ ngay trên video preview.
- Regression UI: `frontend/user-web/e2e/watermark-preview.cjs`, chạy bằng `npm --prefix frontend/user-web run test:e2e:watermark`. Fixture video tổng hợp và stub media metadata/thumbnail giữ thời gian chạy ngắn, không cần codec. Screenshot phân loại ở `frontend/e2e_testing/screenshots/<run-id>/user/channel/branding/CHANNEL-WATERMARK-01/` và `.../user/studio/upload/STUDIO-WATERMARK-01/`.
- Backend integration assertion nằm trong `UploadModeratePublish_ExposesVideoInPublicFeedsAndPlayback`: kiểm tra URL đọc watermark ở API kênh và API chi tiết video. Build/test assembly đã compile bằng output tách riêng; test chạy thật cần `TEST_DATABASE_CONNECTION` có sẵn trong tiến trình test.
- Xác nhận 2026-10-02: frontend development build và E2E watermark trên Edge qua; hai screenshot thành công ở run `20261002T150944Z`. Backend API và integration-test assembly build 0 warning/0 error; integration test chưa chạy được vì test process thiếu biến môi trường database.

## Drawer tài khoản — phím tắt và liên kết kênh

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Mục “Phím tắt” nằm chung danh sách hành động của account drawer; chọn mục mở hộp thoại liệt kê K, J/L, F và M. Escape đóng hộp thoại trước, giữ drawer mở và trả focus về nút Phím tắt; Tab được giữ trong hộp thoại.
- Drawer gọi lại `GET /api/v1/channels/me` mỗi khi mở để lấy cấu hình mới sau khi trang tùy chỉnh kênh lưu. Settings có mảng `links` (kể cả mảng rỗng) là nguồn chính; nếu cấu hình cũ không có mảng này, UI đọc dự phòng `localStorage` key `hutube_channel_links_<channelId>`. Link chỉ hiển thị nếu URL dùng HTTP/HTTPS và giới hạn 5 link.
- Regression E2E `frontend/user-web/e2e/account-drawer.cjs` chạy bằng `npm run test:e2e:drawer`, giả lập settings cũ lúc khởi động, settings mới khi drawer mở, cấu hình legacy thiếu `links` và xóa hết links; kiểm tra links, popup, Escape và focus. Ảnh lưu ở `frontend/e2e_testing/screenshots/<run-id>/user/account/drawer/ACCOUNT-DRAWER-01/`.
- Xác nhận 2026-10-02: `npm run build -- --configuration development`, `npm run test:e2e:drawer` (Edge) và `node --check e2e/account-drawer.cjs` đều qua.

## Tính hợp lệ theo thời gian

- Chính sách cửa sổ lịch sử 30 ngày là quyết định sản phẩm hiện tại; nếu UX thay đổi, cập nhật đồng thời service contract, controller và client infinite scroll.
- Tên index và schema trong file này phản ánh migration hiện tại. Khi đổi tên bảng/cột, cập nhật migration mới thay vì sửa lịch sử migration đã chạy.

## Sidebar Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Điều hướng Studio dùng cùng chiều rộng với sidebar chính: 248px khi mở và 76px khi thu gọn. Nút hamburger trên topbar chuyển trạng thái ở desktop; trên màn hình rộng tối đa 960px, nút này mở drawer trượt để giữ nguyên hành vi mobile.
- Mục điều hướng được nhóm thành Quản lý kênh, Cộng đồng, Công cụ và Cài đặt. Khi thu gọn, icon và đường phân nhóm vẫn hiện; nhãn trượt/mờ dần thay vì bị xóa khỏi layout tức thì. Drawer mobile luôn khôi phục chữ kể cả khi trạng thái desktop trước đó đang thu gọn.
- Drawer mobile phải nằm phía trên scrim để nút đóng luôn nhận click. Sidebar tôn trọng `prefers-reduced-motion`; chuyển động mở/thu dùng 240ms với easing giống drawer chính.
- Regression E2E nằm ở `frontend/user-web/e2e/studio-sidebar.cjs`, chạy bằng `npm run test:e2e:studio-sidebar` từ `frontend/user-web`. API được mock, nên test không tạo dữ liệu backend. Test xác nhận bề rộng, chuyển động qua các kích thước trung gian, tên truy cập, và drawer mobile mở/đóng.
- Xác nhận 2026-10-02: development build thành công; Playwright trên Microsoft Edge qua, đo được 248px → 76px với 21–22 mẫu chuyển động. Screenshot nằm ở `frontend/e2e_testing/screenshots/<run-id>/user/studio/navigation/STUDIO-SIDEBAR-01/`.

## Danh sách video Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Trang Nội dung Studio dùng API `GET /api/v1/videos/manage` với `page`, `pageSize=20`, `search`, `visibility` và `status`. Client chỉ tải trang đầu và quan sát sentinel cuộn với vùng đệm 320px để tải tiếp; không gọi `StudioDataService.load()` tải toàn bộ video khi đang ở `/studio/content`. Các trang Studio khác vẫn giữ hành vi tải nội dung mà chúng cần.
- Danh sách lấp đầy khung nội dung, hiển thị thumbnail tỷ lệ 16:9, tiêu đề, thời lượng gọn dạng `m:ss`/`h:mm:ss`, tag, chế độ hiển thị, kiểm duyệt, ngày, lượt xem và cột Thao tác. Cột Tương tác cũ được bỏ; Sửa dùng route `/studio/content/:id/edit`; Xóa yêu cầu `video.delete`, mở xác nhận rồi gọi `DELETE /api/v1/videos/:id` (backend xóa mềm).
- Bộ lọc trạng thái/hiển thị và tìm kiếm cùng đi qua API phân trang; thay đổi bộ lọc sẽ hủy timer/response cũ, đặt lại danh sách về trang đầu. Thumbnail lỗi có fallback, lỗi tải có nút thử lại, cập nhật visibility và xóa hiển thị phản hồi ngắn.
- Regression E2E `frontend/user-web/e2e/studio-content.cjs`, chạy `npm --prefix frontend/user-web run test:e2e:studio-content`. API và SVG thumbnail mock, 45 fixture nội dung có ý nghĩa, không tạo dữ liệu backend. Ảnh theo `frontend/e2e_testing/screenshots/<run-id>/user/studio/content/STUDIO-CONTENT-01/`.
- Xác nhận 2026-10-02: lệnh npm E2E qua trên Microsoft Edge trong 11,2 giây; kiểm tra 20 video trang đầu, thumbnail, action bounds, lọc ba tiêu chí, visibility update, tải trang hai, hủy/xác nhận xóa và mobile. Build Angular development hoàn tất (không warning/error). Ảnh lần xác nhận cuối ở `frontend/e2e_testing/screenshots/20261002T155921Z/user/studio/content/STUDIO-CONTENT-01/`.

## Phân tích Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- `/studio/analytics` dùng cùng vùng nội dung toàn chiều rộng Studio. Bộ chọn có chế độ toàn kênh và mọi video đã tải của kênh; khi chọn toàn kênh, chỉ render Top 5 xếp lượt xem giảm dần và cho phép bấm từng video để mở thống kê riêng.
- KPI toàn kênh: lượt xem, thích và bình luận chia cho tổng số video; thời lượng xem trung bình là tổng `watchSeconds / tổng views` (có trọng số theo lượt xem); điểm đánh giá là trung bình `averageRating` có trọng số `ratingCount`. Khi chọn video, lượt xem/thích/bình luận/rating là giá trị video đó; thời lượng vẫn là `watchSeconds / views`. Thiếu rating hiển thị dấu gạch ngang.
- Radar dùng 5 trục lượt xem, thích, bình luận, thời lượng xem trung bình và rating. Lượt xem/thích/bình luận/thời lượng chuẩn hóa theo giá trị cao nhất tương ứng trong kênh; rating chuẩn hóa theo thang 5. KPI vẫn hiển thị số tuyệt đối/trung bình nên radar chỉ bổ sung so sánh tương đối. Nhãn trục ngắn để không bị cắt ở màn hình hẹp.
- Regression Playwright `frontend/user-web/e2e/studio-analytics.cjs`, chạy `npm run test:e2e:studio-analytics` khi User Web đang chạy; dùng 12 fixture API giả lập, không ghi vào database. Xác nhận trung bình, Top 5, chọn video từ bộ lọc và Top 5, radar, độ rộng desktop, mobile không tràn và nhãn radar nằm trong SVG. Ảnh được nhóm tại `frontend/e2e_testing/screenshots/<run-id>/user/studio/analytics/STUDIO-ANALYTICS-01/`.
- Hướng dẫn chạy nằm trong mục Creator Studio Analytics ở `frontend/user-web/README.md`. Xác nhận 2026-10-02: development build thành công; Playwright Edge qua trong 7,6 giây, navigation khoảng 4,1 giây, mobile overflow 0px. Ảnh lần kiểm tra cuối: `frontend/e2e_testing/screenshots/20261002T161318Z/user/studio/analytics/STUDIO-ANALYTICS-01/`.

## Bình luận Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Trang `/studio/comments` chỉ tải danh sách kênh/quyền, không tải toàn bộ video. Danh sách bình luận gọi `GET /api/v1/channels/{channelId}/comments/manage` theo trang 20 mục; backend trả `videoTitle` theo batch cùng các thống kê bình luận. Tránh N+1: không gọi API chi tiết video riêng cho từng bình luận.
- Tham số `status` lọc bình luận hiển thị/đã ẩn; `sort=newest|oldest|mostLiked` sắp xếp tại backend trước khi phân trang. Chỉ số tổng và lượt thích được query bằng phép đếm/aggregate; các index `ix_comments_video_status_time`, `ix_comments_parent_status_time`, `ix_comment_reactions_comment_type` có trong migration `20260927120000_QueryPerformanceIndexes`.
- Giao diện dùng chiều rộng Studio, card dễ quét với tên/video/ngày/nội dung/lượt thích/số trả lời, responsive mobile; IntersectionObserver tải trang kế tiếp và có nút dự phòng. Sentinel chỉ xuất hiện sau khi request trang đầu kết thúc, nên dùng setter `@ViewChild` để đăng ký observer theo vòng đời sentinel (khởi tạo trong `ngAfterViewInit` sẽ không bắt được cuộn). Studio layout đã tải danh sách kênh/quyền, vì vậy trang bình luận không gọi load kênh lần thứ hai. Các thao tác trả lời, ẩn/hiện và xóa báo lỗi/đang xử lý.
- Regression E2E `frontend/user-web/e2e/studio-comments.cjs`, lệnh `npm run test:e2e:studio-comments`. API mock 45 bình luận nội dung bóng đá có ý nghĩa, kiểm tra ba cách sắp xếp, filter trạng thái, phân trang, không có truy vấn chi tiết video, thao tác kiểm duyệt và mobile. Ảnh được phân loại ở `frontend/e2e_testing/screenshots/<run-id>/user/studio/comments/STUDIO-COMMENTS-01/`; hướng dẫn ở `frontend/user-web/README.md`.
- Backend test `Comments_ReplyReactionReportAndOwnerModeration_WorkEndToEnd` bổ sung kiểm tra tên video và thứ tự newest/oldest/mostLiked. Xác nhận 2026-10-02: development build frontend và backend IntegrationTests assembly build qua, không warning/error; Playwright Edge qua trong 7,8 giây (navigation 1,6 giây), tải 20 mục đầu, kiểm tra infinite scroll và 3 cách sắp xếp, filter, reply/hide/delete, 0 request chi tiết video, mobile overflow 0px. Ảnh cuối ở `frontend/e2e_testing/screenshots/20261002T164347Z/user/studio/comments/STUDIO-COMMENTS-01/`. Chưa chạy integration test với PostgreSQL vì tiến trình hiện thiếu `TEST_DATABASE_CONNECTION`.

## Không gian cộng tác Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Trang `/studio/invitations` dùng toàn bộ chiều rộng Studio; desktop bố cục ba thẻ tổng quan, hai panel lời mời và kênh có quyền. Kênh sở hữu và kênh thành viên cùng hiển thị dưới tên “Kênh bạn quản lý và cộng tác”, tránh gắn nhãn nhầm kênh sở hữu là kênh cộng tác.
- Lời mời thể hiện tên/handle, vai trò, mô tả phạm vi và thời điểm hết hạn; chấp nhận/từ chối gọi API hiện hữu, khóa thao tác khi đang gửi và làm mới số liệu/danh sách sau phản hồi. Kênh hiển thị vai trò, phần tóm tắt quyền, nhóm quyền dễ đọc, số video/người đăng ký và nút mở Studio.
- E2E `frontend/user-web/e2e/studio-collaboration.cjs`, lệnh `npm run test:e2e:studio-collaboration`, dùng API mock với dữ liệu kênh có ý nghĩa; kiểm tra chiều rộng, vai trò/quyền, accept/decline và mobile. Ảnh chia thư mục ở `frontend/e2e_testing/screenshots/<run-id>/user/studio/collaboration/STUDIO-COLLABORATION-01/`; hướng dẫn ở `frontend/user-web/README.md`.
- Xác nhận 2026-10-02: Angular development build thành công; Playwright Edge qua trong 4,5 giây, kiểm tra tải lời mời/kênh, quyền và vai trò, chấp nhận/từ chối, làm mới danh sách, desktop đầy chiều rộng và mobile không tràn. Ảnh cuối ở `frontend/e2e_testing/screenshots/20261002T165514Z/user/studio/collaboration/STUDIO-COLLABORATION-01/`.

## Điều hướng Creator Studio

> Cập nhật: 2026-10-02 (Asia/Bangkok)

- Đã gỡ tab Phụ đề và nhóm Công cụ chỉ chứa tab này khỏi sidebar Creator Studio theo yêu cầu; route và nội dung phụ đề trong luồng upload được giữ lại.
- Regression `frontend/user-web/e2e/studio-sidebar.cjs` xác nhận tab Phụ đề không xuất hiện, các nhóm còn lại hiển thị, sidebar thu/phóng và drawer mobile hoạt động. Build development thành công; Playwright Edge qua. Ảnh cuối ở `frontend/e2e_testing/screenshots/20261002T165848Z/user/studio/navigation/STUDIO-SIDEBAR-01/`.
