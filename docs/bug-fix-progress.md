# Kết quả sửa BUG.md

Cập nhật 02/10/2026: đã xử lý mã nguồn cho **88/88 mục** trong báo cáo. Các điều khiển chưa có backend hỗ trợ (hẹn lịch, phụ đề tự động, công cụ privacy, filter thời gian kênh) được vô hiệu hóa và giải thích rõ, đúng phương án khắc phục của báo cáo; chưa triển khai các tính năng đó.

Cột xác minh phân biệt test tái hiện trực tiếp với rà soát mã và suite tổng thể. Không có nghĩa mỗi dòng đều có một test tự động riêng. API/DB tests chạy bằng dữ liệu tổng hợp trên PostgreSQL localhost; browser tests mock toàn bộ API. Chưa gọi webhook SePay thật, R2 thật, hoặc chạy trên thiết bị Flutter thật.

## Kiểm tra đã thực hiện

- Backend: **110/110 unit**, **83/83 integration**, gồm migration trên PostgreSQL, thanh toán đồng thời/rollback, quota upload đồng thời, kiểm định metadata, quyền đọc media, report comment, restart chunk và purge hoàn quota đúng một lần.
- Recommendation service: **31/31 tests**; FakeR2 dùng CAS/lease, job durable, restart và model publication. Có hai deprecation warning từ thư viện phụ thuộc.
- Mobile: **29 tests đạt, 1 smoke test bị skip** do không cấu hình API smoke; `dart analyze` lib và các test mới không có issue. Có test owner isolation, late transfer, pause/resume, keyboard/landscape và text scale2.
- Angular: User Web **36/36**, Admin Web **50/50**; cả hai build development và production thành công. Production còn warning về kích thước bundle/component styles (không vượt ngưỡng error).
- Browser: **19/19 ca đạt** với Chrome headless, viewport320/360 và1280×360, API giả lập. Harness được lưu trong `scripts/ui-regression/`.

Log cục bộ ở `.codex-build-verify/`; TRX backend ở thư mục `TestResults/` của từng project test. Đây là kết quả local, không xác nhận trạng thái production.

## Đối chiếu từng mục

| ID | Vấn đề | Thay đổi | Xác minh |
|---|---|---|---|
| BUG-001 | Webhook SePay bỏ xác thực khi thiếu secret | Thiếu secret/signature/timestamp bị từ chối; payment init báo cấu hình chưa sẵn sàng. | Unit HMAC + integration thanh toán |
| BUG-002 | Metadata video riêng tư vẫn xuất hiện trong playlist công khai | Playlist dùng tombstone trung tính cho video caller không được xem. | Integration PrivatePlaylist |
| BUG-003 | URL download được cấp lại dù quyền truy cập đã bị thu hồi | List/resume/retry kiểm tra lại quyền video, gói và chất lượng trước khi cấp URL. | Rà soát policy + integration downloads |
| BUG-004 | Public video detail trả URL file nguồn ngoài kiểm soát chất lượng | Video detail không trả URL source; URL media nằm trong playback có kiểm soát quyền/chất lượng. | Integration MetadataDoesNotIssueSourceUrls |
| BUG-005 | Bỏ qua thanh toán bằng endpoint subscribe trực tiếp | Subscribe trực tiếp gói có giá trả PAYMENT_REQUIRED; chỉ payment đã xác thực kích hoạt gói. | Integration plans/payment |
| BUG-006 | HMAC SePay dùng sai chuỗi ký và định dạng header | HMAC dùng timestamp.rawBody, header sha256=hex, so sánh constant-time và cửa sổ chống replay. | 110 unit tests, có verifier |
| BUG-007 | Đọc strikes và ghi chú kiểm duyệt của kênh khác bằng ID công khai | Endpoint user chỉ cho chủ kênh và loại bỏ ghi chú/actor nội bộ; endpoint admin giữ quyền riêng. | Rà soát StrikeService + suite .NET |
| BUG-008 | Quota upload bị vượt và bộ đếm bị ghi thiếu khi có hai request | Transaction khóa quota theo kênh, reload rồi reserve; request bị từ chối dọn object đã upload. | Integration ConcurrentUploads với barrier |
| BUG-009 | Creator có thể đảo ngược quyết định kiểm duyệt bằng sửa video | Tách restriction moderator khỏi metadata creator; publish/retry/submit không được bỏ qua hidden/purge. | Integration ProfileBioPersists_AndModeratorRestrictionsSurviveCreatorEdits |
| BUG-010 | Download offline không tách theo tài khoản trên mobile | Manifest và file offline tách theo user; logout/đổi user vô hiệu transfer và không lộ dữ liệu tài khoản trước. | Flutter download_security_test |
| BUG-011 | Autoplay playlist không cập nhật vị trí khi router tái sử dụng trang | Playlist phản ứng với query route; ended tìm index bằng video hiện tại. | Rà soát WatchPage + User Web build/tests |
| BUG-012 | Response video cũ ghi đè trang mới và làm sai viewing history | Đổi route hủy request cũ; các mutation/history gắn video ID và generation đã chụp. | Rà soát WatchPage + User Web build/tests |
| BUG-013 | Hai race trong manager download mobile | Transfer tìm record bằng ID, dùng generation/client identity; old request không đóng client mới. | Flutter download_security_test |
| BUG-014 | CSV export cho phép dữ liệu user trở thành công thức | CSV quote/escape và trung hòa tiền tố công thức/control character. | 8 ca CSV mới, Admin Web 50 tests |
| BUG-015 | Admin hiển thị chứng cứ và số liệu giả khi API lỗi | Bỏ dữ liệu mẫu khi API lỗi; hiển thị lỗi/unknown thay tổng, chứng cứ hay video giả. | Browser counts failure + rà soát services |
| BUG-016 | Recovery rendition có thể lấy source của video khác | Source recovery chỉ dùng workspace gắn video ID và đường dẫn hợp lệ. | Rà soát VideoRenditionProcessing + suite .NET |
| BUG-017 | Hub thông báo và state không đổi theo tài khoản web | Notification state/hub gắn user và session; hủy request/callback cũ, server ngắt phiên đã thu hồi. | Rà soát client/server + suite .NET/User Web |
| BUG-018 | Restart API làm mất resume chunk và tích lũy file orphan | Lưu manifest chunk atomic trên disk, phục hồi committed offset, truncate partial và janitor dọn orphan. | Integration ChunkUploadRecoveryTests |
| BUG-019 | Suspend/ban kênh không được áp dụng ở quyền đọc media | Policy chung yêu cầu kênh active cho detail/playback/download/discovery. | Integration MetadataDoesNotIssueSourceUrls |
| BUG-020 | Xóa video không phục hồi dung lượng và không có purge cho trạng thái deleted | Deleted/cancel upload có retention; purge dọn media và hoàn quota đúng một lần. | Integration DeletedVideoPurge |
| BUG-021 | Purge xóa media nhưng SaveChanges thất bại vì URL rỗng | Giữ object key không rỗng, persist purge intent trước delete; migration cho phép rendition deleted. | Integration DeletedVideoPurge trên PostgreSQL |
| BUG-022 | Route report comment cũ tạo hồ sơ ngoài workflow đang dùng | Route report comment gọi ReportService và liên kết report_case; bỏ implementation legacy. | Integration Comments_ReplyReactionReportAndOwnerModeration |
| BUG-023 | Metadata media do client khai được dùng làm căn cứ giới hạn upload | ffprobe đo duration/resolution và actual file size; chạy lại preflight/chapter validation. | Integration UploadProbeOverridesClientClaims |
| BUG-024 | Quyết định “hạn chế đề xuất” không được thực thi ở discovery | Cột restriction thực thi ở catalogue/discovery; giữ restriction khi creator sửa chapters. | Integration moderation restrictions + rà soát catalogue |
| BUG-025 | Report API làm lộ nội dung target mà caller không được xem | Kiểm tra quyền xem target trước khi tạo response report; kênh inactive không được đọc. | Rà soát ReportService + suite .NET |
| BUG-026 | Separation of duties bỏ sót moderation case dạng target | Separation of duties xét cả VideoId và target video trong lịch sử quyết định. | Unit moderation/appeal + integration moderation |
| BUG-027 | Simulator không duy trì tỷ lệ danh mục đã chọn | Simulator refill theo pool danh mục riêng; tỷ lệ giữ khi pool thiếu, validation danh mục đúng. | Rà soát thuật toán + integration recommendation |
| BUG-028 | Job model mất trạng thái bền vững sau restart | Job lưu CSV/hash/service ID bền vững; polling đối chiếu active manifest và cấu hình chuẩn hóa sau restart. | Python FakeR2 recovery + integration model jobs |
| BUG-029 | Replica Python không đồng bộ model/job/lock | Replica refresh model định kỳ; job dùng R2; CAS tạo job và lease ngăn training trùng. | Python test_r2_update, 31 tests |
| BUG-030 | Worker .NET claim job không atomic và recovery không xét owner | Worker .NET có advisory leader session, atomic claim, recover chỉ khi có leadership; reconnect khi mất lease. | Rà soát worker + integration recommendation |
| BUG-031 | Preview/export ma trận dùng average khi model active dùng weighted | Preview/export dùng cấu hình aggregation active; worker verify cả mode và weights của manifest. | Integration recommendation + rà soát đối chiếu |
| BUG-032 | Trọng số lớn được nhận nhưng làm tính điểm overflow | Chuẩn hóa weights theo maximum trước tính score để tránh decimal overflow; đối chiếu có tolerance float. | Rà soát normalize + suite .NET/Python |
| BUG-033 | CF không tự phục hồi khi R2 lỗi thoáng qua ở startup | Refresh nền có backoff sau startup lỗi; load lỗi giữ model đang phục vụ. | Python tests + rà soát lifespan/registry |
| BUG-034 | CF pagination và phần bù không tạo một danh sách ổn định | CF prefix có kích thước cố định và thứ tự fallback ổn định theo ID, phân trang trên cùng danh sách. | Integration search/recommendation + rà soát feed |
| BUG-035 | Thanh toán và kích hoạt gói không được commit nguyên tử | Activate plan, history, quota và paid status cùng transaction/context; rollback khi save payment lỗi. | Integration PaymentFinalSaveFailure với trigger lỗi |
| BUG-036 | Idempotency payment không khớp phạm vi unique của database | Unique index và lookup cùng phạm vi user/key; replay cả trạng thái kết thúc, conflict nếu payload đổi. | Integration PaymentIdempotency với requests đồng thời |
| BUG-037 | Race đổi mật khẩu và refresh có thể giữ lại phiên ngoài danh sách thu hồi | Đổi mật khẩu dùng cùng user transaction lock với refresh trước khi thu hồi phiên. | Rà soát Account/AuthStore + integration auth |
| BUG-038 | Các lỗi nghiệp vụ plan/payment bị trả thành500 | Middleware map PlanException/PaymentException theo HTTP status và code nghiệp vụ. | Integration plans/payment |
| BUG-039 | Cập nhật tiểu sử thành công nhưng nội dung không được lưu | Map Bio vào users.bio và migration; profile round-trip giữ dữ liệu. | Integration ProfileBioPersists |
| BUG-040 | Topbar che nút đóng drawer User Web trên mobile/tablet | Nâng stacking context drawer và scrim mobile để nút đóng nằm trên topbar. | Browser mobile drawer |
| BUG-041 | Route công khai của kênh nằm trong nhóm yêu cầu đăng nhập | Routes public channel/playlist/watch ra ngoài auth guard; giữ guard cho thao tác riêng. | Browser anonymous channel + rà soát routes |
| BUG-042 | Drawer Admin Web không nhận pointer khi mở trên màn hình nhỏ | Drawer Admin mở có pointer-events và stacking context trên topbar. | Browser mobile Admin drawer |
| BUG-043 | Dropdown bộ lọc Admin Web không chọn được bằng bàn phím | Custom select dùng button/combobox, focus và keyboard navigation/selection/Escape. | Browser keyboard select |
| BUG-044 | Modal thanh toán, appeal và action không có đường cuộn trên viewport thấp | Modal có max-height theo viewport và overflow cuộn; error nằm trong vùng modal. | Browser modal thấp + rà soát payment/appeal CSS |
| BUG-045 | Picker upload, thumbnail và avatar không có cách dùng bằng bàn phím | Video picker dùng button; thumbnail/avatar có keyboard Enter/Space và focus-visible. | Browser upload picker + rà soát call sites |
| BUG-046 | Hẹn giờ phát hành trên wizard chỉ thay giao diện, không thay request | Vô hiệu hẹn lịch chưa có backend support và ghi rõ trạng thái; không cho chọn rồi bỏ dữ liệu. | Rà soát wizard + User Web build |
| BUG-047 | Nút Lưu nháp trên upload wizard không lưu dữ liệu | Lưu metadata/tags/chapters theo user/channel, restore sau reload; chọn lại file không ghi đè title draft. | Browser save/reload/reselect draft |
| BUG-048 | Sheet tạo nội dung mobile không cuộn theo chiều cao khả dụng | Sheet dùng primitive SafeArea, keyboard inset, giới hạn chiều cao và scroll. | Flutter responsive_bugfix_test |
| BUG-049 | Search mobile không giữ định danh bộ query khi tải tiếp hoặc xóa | Search chụp query/sort committed và generation; clear vô hiệu mọi response cũ. | Rà soát async + Flutter tests/analyzer |
| BUG-050 | Feed mobile bỏ qua trang bị lỗi khi tải tiếp | Chỉ cập nhật page sau response thành công; retry đúng trang lỗi và chặn auto retry loop. | Rà soát feed + Flutter tests/analyzer |
| BUG-051 | Response feed cũ ghi vào bộ lọc mới trên mobile | Refresh/filter tăng generation; success và error cũ không ghi state mới. | Rà soát feed + Flutter tests/analyzer |
| BUG-052 | Filter thời gian và trạng thái kênh Admin không khớp query | Reset tab khi đổi status; filter thời gian chưa được hỗ trợ bị disabled. | Browser disabled filter + rà soát query |
| BUG-053 | Trang quản lý gói có chữ gần trắng trên nền trắng khi dark mode | Trang plans dùng surface/text/border tokens thay màu cố định. | Browser Admin dark plans |
| BUG-054 | Breakpoint viewport không tính sidebar khiến thumbnail editor tràn cột | Thumbnail dùng container query theo chiều rộng editor card, xếp một cột khi vùng chứa hẹp. | Browser editor với sidebar ở 1200px |
| BUG-055 | Studio chỉ tải 50 video đầu nhưng trình bày như toàn bộ nội dung kênh | Studio thu thập đủ các trang rồi tính tổng/tìm kiếm, hủy khi đổi kênh. | Rà soát Rx expand/reduce + User Web tests/build |
| BUG-056 | Thời gian xem Studio giả định mỗi view xem hết video | API tổng WatchDuration thực; Studio dùng watchSeconds thay views nhân duration. | Rà soát DTO/query + suite .NET/User Web |
| BUG-057 | Mọi kênh đều có badge đã xác minh | Bỏ badge verified mặc định khi API không có chứng cứ xác minh. | Rà soát template + User Web build |
| BUG-058 | Công cụ privacy báo thành công nhưng không thực hiện hành động | Privacy controls chưa có endpoint bị disabled kèm giải thích; bỏ thông báo thành công giả. | Browser privacy controls + rà soát handlers |
| BUG-059 | Reload trang gói không nạp gói hiện tại sau restore đăng nhập | Restore auth thực sự được subscribe; identity effect nạp lại current plan và reset state. | Browser reload current plan |
| BUG-060 | Hero chi tiết gói có min-width vượt card ở viewport 320px | Hero plan min-width 0 và bố cục mobile không vượt card. | Browser 320px |
| BUG-061 | PlanEnabled bị bỏ qua khi gửi thông báo lời mời dùng chung gói | Mapping plan_invitation đọc PlanEnabled trước khi publish notification. | Rà soát NotificationService + suite .NET |
| BUG-062 | Home giữ bốn cột đề xuất trên điện thoại do specificity | Rule mobile cùng specificity với feed recommendations; một cột ở điện thoại. | Browser Home 320px |
| BUG-063 | Thêm playlist thất bại nhưng sửa video vẫn báo lưu thành công | Playlist failure giữ lỗi/lưu một phần, chỉ ignore duplicate409; chặn playlist không đủ điều kiện. | Rà soát save flow + User Web tests/build |
| BUG-064 | Tùy chọn phụ đề tự động và cho bình luận bị bỏ khỏi request | AllowComments được gửi/lưu/enforce; auto subtitles chưa hỗ trợ bị disabled. | Integration DisabledComments + rà soát wizard |
| BUG-065 | Drawer Channels và dialog Topics nằm dưới topbar | Channels drawer/Topics dialog nâng overlay stacking context và giới hạn viewport. | Rà soát CSS/template + Admin Web build |
| BUG-066 | Các trang kiểm duyệt chỉ tải trang đầu của backlog | Moderation/reports/appeals/strikes lấy đủ trang bằng expand/reduce. | Rà soát pagination + Admin Web tests/build |
| BUG-067 | Open target của report nối cứng localhost:4200 | Open target dùng USER_WEB_BASE_URL được validate; cấu hình/target không hợp lệ không có link. | Rà soát runtime config/href + Admin Web build |
| BUG-068 | Response video cũ ghi đè form và có thể lưu nhầm sang video khác | Hydration form có generation; save bị chặn khi detail chưa nạp và close vô hiệu response cũ. | Rà soát async + browser editor/save |
| BUG-069 | Rule base ghi đè breakpoint một cột của form RBAC | Rule một cột RBAC đặt sau base và đúng selector. | Browser RBAC 360px |
| BUG-070 | Lỗi form/modal chỉ hiện ở trang nền dưới backdrop | Hiển thị role=alert trong các form/dialog để lỗi không nằm dưới backdrop. | Browser409 trong edit modal + rà soát các dialog |
| BUG-071 | Xóa description bị serialize thành không thay đổi nhưng vẫn báo thành công | Description gửi chuỗi rỗng khi clear; không serialize thành undefined. | Browser capture request + suite .NET |
| BUG-072 | Sheet playlist, report và sửa video không cuộn khi bàn phím chiếm chiều cao | Playlist/report/editor sheet dùng scrollable primitive xử lý bàn phím. | Flutter responsive test + rà soát call sites |
| BUG-073 | Offline player lấy chiều cao theo chiều rộng và tràn ở landscape | Offline player Flexible + AspectRatio trong vùng chứa, account change đóng player. | Rà soát widget + Flutter analyzer/tests |
| BUG-074 | Reaction trả muộn của video A ghi đè metadata video B | Reaction/rating chụp video/generation; response muộn không update video khác. | Rà soát Watch async + Flutter analyzer/tests |
| BUG-075 | Profile giữ snapshot danh sách phiên nên refresh không cập nhật UI | Profile lắng nghe AccountController/Auth và đọc sessions/loading hiện tại thay snapshot. | Rà soát listeners/render + Flutter analyzer/tests |
| BUG-076 | Đóng thanh toán chưa paid vẫn báo đăng ký gói thành công | Flow payment chưa paid thoát mà không chạy snackbar đăng ký thành công. | Rà soát payment flow + Flutter tests |
| BUG-077 | Download menu không khớp trạng thái server nên thiếu Resume/Pause | Map chính xác ready/pending/processing/cancelled/failed/revoked; Pause dừng transfer, Resume/Retry enqueue response được xác thực. | Flutter download_actions_test + pause/resume test |
| BUG-078 | Form auth giữ nền trắng nhưng dùng chữ gần trắng của dark theme | Auth surfaces dùng màu theme thay nền trắng cố định. | Flutter dark/auth tests + rà soát theme |
| BUG-079 | Empty/error view chung vượt chiều cao landscape và khuất nút phục hồi | State view chung cuộn theo constraints, action phục hồi vẫn trong viewport. | Flutter responsive test landscape/text scale2 |
| BUG-080 | Library, comments, channel và creator bỏ metadata phân trang | Library/history/liked/comments/channel/creator dùng helper lấy đủ trang. | Rà soát pagination + Flutter analyzer/tests |
| BUG-081 | Comment mới bị mất khỏi giao diện do State cũ được tái sử dụng theo vị trí | Comment widget dùng ValueKey ID và didUpdateWidget cập nhật khi thay record. | Rà soát widget identity + Flutter tests |
| BUG-082 | Thu nhỏ Watch sau go/deep link không rời trang và dựng thêm mini-player | Minimize pop nếu có stack, go home nếu deep link; giữ player state. | Rà soát navigation + Flutter analyzer/tests |
| BUG-083 | Chất lượng mặc định đã lưu nhưng Watch luôn chọn rendition cao nhất | Chọn rendition theo preference quality và cap, fallback hợp lệ; giữ danh sách mọi source. | Rà soát selection + Flutter analyzer/tests |
| BUG-084 | Upload cho nhập tiêu đề 150 ký tự nhưng API chỉ nhận tối đa 100 | Giới hạn title mobile100 thống nhất API. | Rà soát validation + Flutter analyzer/tests |
| BUG-085 | Menu thao tác bị clip khi filter chỉ còn ít dòng và mở lên trong bảng | Action menu fixed theo viewport, hit-test được; đóng khi anchor scroll/resize/click ngoài. | Browser single-row menu 1280×360 |
| BUG-086 | Bảng Policies cắt cột bên phải trên mobile và không có đường cuộn ngang | Policies dùng min-width bảng và overflow-x auto trên wrapper. | Browser mobile horizontal scroll |
| BUG-087 | Controls Channels/Videos mời thao tác mà role chỉ xem không thể hoàn tất | Mutation controls/handlers xét permission; detail chỉ xem vẫn được mở. | Browser role view-only Channels/Videos |
| BUG-088 | Màn thiết bị mở từ AccountHub không có vùng cuộn cho nội dung dài | AccountHub Profile có Scaffold/AppBar/SingleChildScrollView, nội dung thiết bị cuộn được. | Rà soát route/widget + Flutter analyzer/tests |

## Áp dụng khi triển khai

1. Áp dụng EF migration `202610020001_BugFixAccountPayment` trước khi dùng binary mới. Migration bổ sung Bio, AutoRenew, moderation flags, AllowComments, purge intent, model job metadata, unique payment key theo user và trạng thái rendition deleted. Migration Down cố ý không xóa dữ liệu; rollback binary cần giữ schema này.
2. Cấu hình SePay secret/account/bank đầy đủ và kiểm tra định dạng HMAC theo [tài liệu SePay](https://developer.sepay.vn/vi/sepay-webhooks/xac-thuc). Thiếu cấu hình sẽ chặn khởi tạo payment/xác thực webhook, thay vì chấp nhận tùy ý.
3. Máy chủ cần FFprobe/FFmpeg; `VideoProcessing:FfprobePath` và `VideoProcessing:FfmpegPath` trỏ tới binary phù hợp. FFprobe được dùng cả khi không tạo rendition thấp để kiểm định file upload.
4. Admin Web cần `USER_WEB_BASE_URL` là origin User Web thực (không có path). Nếu thiếu trên production thì Open target không tạo link; localhost fallback chỉ dành cho local.
5. Đặt `CfSeedUpload__Directory` trên volume tồn tại qua restart. Upload chunk hiện phục hồi cùng thư mục trên một API instance; cần sticky routing nếu chạy nhiều instance. Không dùng nhiều process ghi cùng root chunk: chưa triển khai distributed locking cho chunk sessions. Janitor xóa sessions/orphan hết hạn24h; giữ disk capacity cho upload đang hoạt động.
6. Model replicas phải dùng chung R2 bucket/prefix với conditional writes hỗ trợ If-Match/If-None-Match; worker .NET phải dùng chung PostgreSQL để advisory leader lock có tác dụng. FakeR2 xác minh protocol; cần kiểm tra quyền bucket/config thực khi triển khai.
7. Deleted/cancel video giữ media30 ngày rồi purge. Purge lưu intent trước xóa và giữ object key để retry; hoàn quota khi DB commit thành công. Dữ liệu quota lịch sử đã sai trước bản sửa không thể được suy ra đầy đủ từ test, cần đối chiếu media hiện có trước khi sửa bộ đếm trên production.
8. Resume tải mobile hiện khởi động lại transfer sau tái xác thực URL; không tiếp tục byte Range của file partial. File offline hoàn tất của chủ tài khoản vẫn dùng được offline; legacy file không có owner không tự gán cho tài khoản khác.

## Chạy lại

```powershell
# Chỉ dùng PostgreSQL thử riêng, không dùng database thật.
$env:TEST_DATABASE_CONNECTION = 'Host=127.0.0.1;Port=55432;Username=bugfix_test;Database=postgres;Pooling=false'
dotnet test backend/tests/HuTube.UnitTests
dotnet test backend/tests/HuTube.IntegrationTests

# Trong recommendation-service
.venv/Scripts/python.exe -m pytest -q

# Trong mobile/user-app
flutter test
dart analyze lib test/download_actions_test.dart test/download_security_test.dart test/responsive_bugfix_test.dart

# Trong từng frontend/user-web và frontend/admin-web
npm test -- --watch=false --browsers=ChromeHeadless
npm run build -- --configuration development

# Từ root repository; Python có playwright, FFmpeg có trong PATH
$env:CHROME_BIN = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
recommendation-service/.venv/Scripts/python.exe scripts/ui-regression/run.py
```

`run.py` phục vụ hai build local và đóng server khi kết thúc. Harness tạo video tổng hợp1s, dùng fake users/API, ghi JSON kết quả và screenshot vào `.codex-build-verify/` (có thể đổi `BUGFIX_OUTPUT_DIR`). Có thể chọn FFmpeg bằng `FFMPEG_BIN`; bỏ `CHROME_BIN` để dùng Chromium của Playwright.
