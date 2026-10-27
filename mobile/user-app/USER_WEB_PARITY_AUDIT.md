# Đối chiếu User Web và ứng dụng mobile — 26/10/2026

## Phạm vi

Đối chiếu các route, thao tác và trường nhập của `frontend/user-web/src/app/features`
với `mobile/user-app`, cùng service/API tương ứng. Hai ảnh người dùng gửi thuộc
ứng dụng Flutter này. Đây là kiểm tra mã nguồn, widget, API mô phỏng và build
Android; không phải chứng nhận đã chạy mọi luồng trên máy chủ thật hoặc điện thoại.

## Những khoảng thiếu và lỗi đã xử lý

| Nhóm | Trước khi rà soát | Kết quả |
| --- | --- | --- |
| Liên kết công khai | Mục “Liên kết của tôi” hiển thị `bio`; Chỉnh sửa mở hồ sơ, không có ô liên kết | Hiển thị liên kết thực từ `channel.settings.links`; mở màn quản lý liên kết đúng kênh; chưa có kênh thì dẫn tới tạo kênh |
| Chỉnh liên kết | Chưa có đường vào trực tiếp từ tài khoản | Thêm/sửa/xóa, chọn nền tảng, tiêu đề, URL, chuyển lên/xuống, tối đa 14 liên kết; kiểm tra HTTP/HTTPS, bảo vệ thay đổi chưa lưu |
| Giữ dữ liệu kênh | Lưu thông tin cơ bản xóa `trailerVideoId` | Giữ cấu hình khác; màn liên kết đọc lại dữ liệu mới trước khi gộp và lưu |
| Hồ sơ | Avatar lớn, form dài, nút lưu trong nội dung; quốc gia lấy mặc định thay vì vị trí đã lưu | Header gọn, nhóm thông tin, preview tên, nút lưu cố định và tránh bàn phím, lỗi tại trường, xác nhận bỏ thay đổi; đọc vị trí đã lưu |
| Lưu quốc gia | Cập nhật chung nhiều tùy chọn | Chỉ gửi `location` tới API để tránh ghi đè ngôn ngữ/quyền riêng tư |
| Avatar/tên | Chỉ sửa trực tiếp map người dùng | Thông báo thay đổi danh tính cho các thành phần đang lắng nghe; chặn phản hồi thuộc phiên cũ |
| Tìm kiếm | Dò một kênh theo handle hoặc dựa vào video đầu tiên | Dùng `/channels/search`, tìm nhiều kênh theo từ khóa, phân trang kênh, chọn Tất cả/Video/Kênh, vẫn thấy kênh khi không có video |
| Bộ lọc/tags | Chưa nối đầy đủ category/tag và query đầu vào route | Giữ category/tag khi tìm và tải thêm; nhận từ route; hashtag ở mô tả video bấm được |
| Theo dõi | Chuông có ở trang kênh nhưng thiếu ngay trang xem | Bật/tắt thông báo tại trang xem; gọi API thực, chặn bấm lặp và phản hồi phiên cũ |
| Email kênh | Model/form mobile bỏ qua `contactEmail` | Tạo, chỉnh và xem email công khai; mở ứng dụng email từ phần giới thiệu |
| Thành viên kênh | Có service nhưng không có màn quản lý thành viên hiện có | Xem thành viên, đổi vai trò, xác nhận xóa; bảo vệ chủ kênh/tài khoản hiện tại và kiểm tra quyền |
| Quyền Studio | Cùng một nhóm công cụ cho mọi vai trò | Chỉ đưa vào các công cụ được cấp quyền; thao tác sửa/xóa video tuân theo quyền; grid xử lý được số công cụ lẻ |
| Trạng thái kênh | Khó tìm đường từ Studio tới cảnh cáo/kháng nghị | Lối vào từ Studio đúng kênh; gửi kháng nghị với ID kênh điền sẵn |
| Minh chứng | Chỉ nhập URL/ghi chú | Chọn ảnh/PDF tối đa 10 MB, tải lên API; thử lại dùng ID kháng nghị đã tạo; tải minh chứng qua phiên được xác thực trước khi mở/chia sẻ |
| Thumbnail | Chọn thư viện hoặc tự sinh | Bổ sung chọn thời điểm/preview khung hình trên Android, tải ảnh khung hình qua API thumbnail hiện có; dọn tệp tạm |
| Bỏ danh mục video | Gửi `categoryId: null` nhưng không gửi cờ xóa | Gửi `clearCategory` khi loại bỏ danh mục đang có |
| Tùy chọn phát | Autoplay/chất lượng mặc định gửi vào trường API không hỗ trợ | Lưu vào kho thiết bị mà player đọc; giữ qua mở lại màn; autoplay đang phát nhận thay đổi |
| Giao diện/ngôn ngữ | Nút đổi ở Cài đặt chỉ lưu thiết bị | Gửi thay đổi từng trường lên tài khoản; báo rõ khi chỉ đổi trên thiết bị mà chưa đồng bộ được |
| Thông tin tài khoản | Thiếu thao tác sao chép mã tài khoản như web | Có mục xem/sao chép mã tài khoản |
| Chính sách | Chưa có tìm nội dung như web | Tìm theo nội dung trong nhóm đang chọn; giữ xuất PDF/in hiện có |
| Link chia sẻ | Playlist bỏ mất ID; Android chỉ đăng ký host `auth` | Giữ ID playlist/kênh/video/gói, từ khóa và nhóm chính sách; nhận content link trên Android; đi qua đăng nhập nếu cần |
| Gói được chia sẻ | Link gói chỉ về danh sách chung | Chọn đúng gói yêu cầu trong danh mục, cả khi nhận link lúc trang đang mở |
| Phụ đề | Tải toàn bộ detail video để liệt kê trạng thái | Dùng API metrics nhẹ với `includeStats=false`, có fallback khi API chưa hỗ trợ |
| Bố cục chữ lớn | Dropdown nền tảng và đối tượng kháng nghị tràn ở chữ 2× | Dropdown giãn đúng chiều rộng; kiểm tra lại cả sáng/tối và màn 320px |

## Ma trận các nhóm chức năng đã đối chiếu

| User Web | Mobile tương ứng | Nội dung kiểm tra |
| --- | --- | --- |
| Auth | `auth.dart`, `core/widgets/app_shell.dart` | Đăng nhập/đăng ký, Google, xác minh, quên/đặt lại mật khẩu, khôi phục phiên, lỗi API, đăng xuất |
| Home/Explore/Search | `features/content`, `features/search` | Feed, category, bảng xếp hạng, tác giả, video xu hướng, tìm video/kênh, bộ lọc, tải thêm, trạng thái rỗng/lỗi |
| Watch | `features/content/watch_screen.dart`, `playback_session.dart` | Phát/tua/chất lượng/tốc độ, fullscreen, PiP, phát nền, tự phát tiếp, queue, mô tả/link/timestamps, chapters/cards, tags, like/dislike/rating, theo dõi/chuông, chia sẻ, lưu playlist, tải xuống |
| Comments | Watch/Creator comments | Gửi/reply/sửa/xóa, sắp xếp, phân trang, like/dislike, ẩn/hiện, báo cáo, xác nhận thao tác |
| Account | Account/Profile/Preferences | Tên/bio/avatar, vị trí, ngôn ngữ/theme, quyền riêng tư, thông báo, mật khẩu, phiên hoạt động, lịch sử đăng nhập, sao chép ID, đường vào liên kết công khai |
| Library | `features/content/library_screen.dart` | Lịch sử/đã thích, bộ lọc ngày/từ khóa/thứ tự/rating, tải thêm, thời lượng đã xem |
| Downloads | Download coordinator/manager/screens | Quyền tải, chất lượng, Wi-Fi, chờ mạng, tạm dừng/thử lại/xóa, lưu file, tài khoản A/B, phát offline |
| Channel | `channel/screens` | Video/playlist/giới thiệu, tìm/sắp xếp/phân trang, đăng ký/chuông, chia sẻ/báo cáo, ảnh bìa/avatar/watermark, email/links, handle, thành viên/lời mời/xóa kênh |
| Playlists | `features/playlists` | Tạo/sửa/xóa, quyền riêng tư, lọc/sắp xếp, thêm/bỏ/sắp video, play all/shuffle, chia sẻ/mở trực tiếp |
| Studio | `features/creator` | Chọn kênh/quyền, upload/draft/chunk/retry/cancel, chỉnh metadata/category/tags/chapters/cards/playlist, ảnh bìa, công khai/kiểm duyệt/xử lý lại, analytics, bình luận, trạng thái phụ đề, cảnh cáo/kháng nghị |
| Plans/Payments | `plans_screen.dart`, `features/plans`, `features/payments` | Danh mục/chi tiết/chia sẻ gói, đăng ký/thanh toán và trạng thái, lịch sử, mời/nhận/rời gói, thành viên và phân bổ dung lượng |
| Policies | `features/policies` | Các nhóm, tìm nội dung, ngày/phiên bản, xuất PDF/in |
| Notifications/Links | Notification center/router/deep links | Đọc/đánh dấu, điều hướng, link nội dung, giữ đích sau đăng nhập |

### Các chỗ phía web chưa phải chức năng hoàn chỉnh

- `hideUserFromMyChannel()` hiện chỉ hiển thị toast ở web, không gọi API ẩn người dùng.
- “Top fan ranking” và “Celebrate Super Chat” ở web chỉ lưu cờ localStorage,
  chưa có dịch vụ hay hành vi nghiệp vụ tương ứng.
- Trang phụ đề ở cả hai phía hiện liệt kê trạng thái; web chưa có trình biên soạn track.

Không tạo các nút giả hoặc thông báo thành công không có tác dụng để tính là
“đủ chức năng”. Các khác biệt này được ghi riêng thay vì coi là đã có API.

## Kiểm chứng

Kết quả cuối: **286 test đạt, 1 test API smoke bỏ qua vì chưa cấu hình môi
trường riêng; analyzer không có lỗi/cảnh báo; APK Android debug build thành công**.
Ma trận giao diện mới gồm 12 tổ hợp màn hình/theme/cỡ chữ, mỗi tổ hợp chạy sáu
màn; phần bàn phím được kiểm tra thêm cho các màn lưu dữ liệu.

- `profile_links_parity_test.dart`: đường Chỉnh sửa thật, đọc/sửa/lưu hồ sơ,
  bảo vệ vị trí/quyền riêng tư, liên kết đúng URL, thay đổi chưa lưu,
  giữ các setting không thuộc liên kết, cấu hình phát được lưu thật.
- `search_team_evidence_parity_test.dart`: tìm nhiều kênh/phân trang,
  category/tag, tìm chính sách, quyền/đổi vai trò, file minh chứng và thử lại
  không tạo kháng nghị trùng, canonical content links.
- `watch_notification_frame_parity_test.dart`: API chuông và giao thức chọn
  thời điểm khung hình/giữ file cho bước upload.
- `parity_visual_audit_test.dart`: sáu màn mới/chỉnh lại ở 320×568, 375×844,
  640×360, sáng/tối, chữ 1×/2×; thêm tình huống bàn phím cho màn lưu dữ liệu.
- Các bộ regression hiện có vẫn kiểm tra các nhóm chức năng còn lại, bao gồm
  audit màn hình 800×1024 và các luồng upload/download/player đã sửa trước đó.
- Bộ chọn tệp dùng [file_selector chính thức của Flutter](https://pub.dev/packages/file_selector).
- Ảnh preview: `../../outputs/mobile-parity/`; log kiểm thử/build:
  `../../.work/mobile-parity-final-tests.log`, `mobile-parity-build.log`,
  `mobile-parity-visual-final.log`.

## Giới hạn cần xác nhận trên thiết bị

Chưa có điện thoại/emulator kết nối trong lượt này. Picker hệ điều hành,
khung hình từ URL video thật, upload minh chứng thật, email/Google, PiP,
push, thanh toán và hành vi khi OS dừng tiến trình cần kiểm tra trên môi trường
thử phù hợp. Không thực hiện giao dịch hoặc thay đổi dữ liệu tài khoản thật.

Tải xuống hiện tạm dừng được nhưng thử lại tải file từ đầu; không tuyên bố
có nối tiếp byte hoặc tác vụ nền bền vững khi OS hủy app. Các ca HTTP/file thật
và file MP4 mẫu đã có kiểm thử riêng trong lượt trước.


## Bổ sung giao diện mobile ngày 26/10/2026

- Playlist đổi sang danh sách hàng ngang với ảnh bìa 16:9, số video, quyền riêng tư và menu thao tác.
- Thư viện dùng hàng video gọn, giữ thời lượng, tiến trình và thời gian xem; bộ lọc tìm kiếm/sắp xếp/thời gian chuyển thành nút gọn.
- Báo cáo và kháng nghị có thẻ trạng thái kênh, mức độ cảnh cáo được Việt hóa; form tự điền kênh hiện có, ẩn ID khi đã có ngữ cảnh, giữ nút gửi khi cuộn.
- Menu Tạo kiểm tra kênh hiện có, gồm cả kênh tạm ngưng; đường dẫn tạo kênh trực tiếp cũng kiểm tra lại trước khi hiển thị form.
- Chỉnh sửa bình luận dùng bottom sheet, giữ bản nháp khi lưu lỗi. Trả lời có trang hội thoại riêng, bình luận gốc, các phản hồi và ô nhập cố định phía dưới.
- Giữ phân trang phản hồi 3 mục, trả lời lồng nhau, phản ứng, tải bù trang đầu sau khi xóa và giữ nháp khi đóng/mở lại hoặc gửi lỗi.
- Các danh mục hệ thống như Daily, Entertainment, Football được hiển thị thành Đời sống, Giải trí, Bóng đá khi chọn tiếng Việt; IDs và dữ liệu nội dung không thay đổi.
- Kênh tạm ngưng hiển thị thông báo rõ ràng và lối vào trạng thái/kháng nghị cho chủ kênh. Không gọi tải video/playlist công khai khi kênh đang ngưng; lỗi phần phụ không che toàn bộ kênh đang hoạt động.

Kiểm chứng: 337 test đạt, 1 API smoke test bỏ qua do thiếu cấu hình môi trường; analyzer không có vấn đề. Ảnh xem trước nằm trong outputs/mobile-ui-refresh/, dùng dữ liệu và ảnh mẫu để kiểm tra sáng/tối, màn hẹp/ngang, chữ lớn và bàn phím. Không gửi bình luận hoặc kháng nghị thật lên máy chủ trong các test.

## Tinh chỉnh Studio, chính sách và minh chứng (26/10/2026)

- Cài đặt kênh: ảnh bìa gọn, ảnh đại diện cùng hàng với thao tác, watermark mở rộng khi cần; vùng xóa kênh dùng nền trung tính, giữ xác nhận xóa và kiểm tra quyền.
- Nội dung kênh: hàng video có thumbnail 16:9, trạng thái và nút sửa; gửi duyệt, thay thumbnail, xuất bản, xử lý lại, hủy tải và xóa nằm trong menu theo quyền/trạng thái.
- Creator Studio: thay lưới cao bằng các hàng công cụ, giảm chiều cao thẻ thống kê, bổ sung lối vào Chính sách.
- Tạo danh sách phát: nút Tạo nhỏ gọn, không tự bật bàn phím; bộ chọn riêng tư và thao tác lưu/API được giữ nguyên. Có kiểm tra bàn phím mở.
- Chính sách: đồng bộ 4 nhóm và 30 mục tham chiếu từ `frontend/user-web/src/app/features/policy/public-policy-page.ts`, gồm quy chuẩn và ngoại lệ; nội dung API cùng mã được ưu tiên, ẩn mã ngừng sử dụng giống web. Tìm kiếm không dấu, số mục theo nhóm, nhãn Việt/Anh, quy trình cảnh báo/gậy và xuất toàn bộ PDF không phụ thuộc bộ lọc. Khi API lỗi vẫn hiển thị tham chiếu kèm thông báo và thử lại; khóa xuất PDF cho đến khi tải thành công.
- Chạy `node mobile/user-app/scripts/sync_policy_reference.cjs` từ repo root để cập nhật dữ liệu/thông dịch tham chiếu. Kiểm thử kiểm tra danh sách mã với user-web để phát hiện lệch.
- Minh chứng: tải bằng API có xác thực, ảnh hiển thị ngay trong thẻ và mở trình xem phóng to, có chia sẻ; PDF/tệp khác hiển thị loại và dung lượng, chia sẻ qua ứng dụng hệ thống. Có trạng thái tải/lỗi/thử lại, chặn phản hồi đến trễ và ẩn ảnh khi đổi phiên/đăng xuất. Form kháng nghị cũng hiện ảnh đã chọn trước khi gửi.

Kiểm chứng: 346 test đạt, 1 live smoke test bỏ qua vì thiếu cấu hình; analyzer sạch. Ảnh mẫu sáng/tối: `outputs/studio-refinement/`. Không gửi kháng nghị thật, không sửa/xóa video hoặc kênh thật trong quá trình kiểm thử. Chưa kiểm thử thao tác hệ điều hành trên điện thoại.

## Tải video, số không thích và PiP tự động (26/10/2026)

- Form tải video đưa tiêu đề/mô tả lên trước các tùy chọn; gom ngôn ngữ/bình luận/playlist và chương/video liên quan thành các mục mở rộng. Nút tải lên cố định ở cuối màn hình; giữ API upload, bản nháp, metadata, quota và xác nhận chính sách.
- Nút không thích hiển thị số lượng theo cùng cách rút gọn của lượt thích, lấy số mới từ API phản ứng; tooltip vẫn giải thích ý nghĩa của nút.
- Cài đặt phát nền/tải xuống chia thành nhóm Khi rời ứng dụng và Tải xuống, thêm công tắc PiP tự động, mô tả quyền gói và lối vào các gói dịch vụ.
- Bật PiP/phát nền kiểm tra quyền máy chủ trước khi lưu hoặc chạy. Nếu chưa có quyền, hiển thị thông báo tính năng thuộc gói dịch vụ và nút Xem gói dịch vụ; lỗi kiểm tra quyền được thông báo là lỗi kết nối, không coi như chưa mua gói. Lỗi DOWNLOAD_NOT_INCLUDED của máy chủ cũng có thông báo/nút xem gói.
- Android tự vào PiP qua onUserLeaveHint khi đang phát, đã bật cài đặt và có quyền PiP. Hỗ trợ cả trang xem và mini-player; giữ nguyên một native surface. Ẩn header, thanh điều hướng và các tray khi chuẩn bị PiP, khôi phục khi thoát/lỗi. Có timeout và chặn callback cũ trong cầu nối Android.
- Tránh dừng âm thanh trong lúc đang chuẩn bị/PiP có quyền; khi chuẩn bị thất bại vẫn áp dụng lại chính sách phát nền. Cập nhật quyền khi cài đặt media thay đổi và chặn phiên đăng nhập cũ.
- Các ca bổ sung kiểm tra quyền cho phép/từ chối/lỗi mạng, số không thích sau PUT reaction, PiP khi đang phát/đang dừng, fallback và lỗi chuẩn bị, giữ một native surface, lưu/khôi phục tùy chọn, sáng/tối/chữ lớn/màn ngang. Ảnh mẫu: `outputs/media-upload-refresh/`.

PiP thực tế còn phụ thuộc hỗ trợ/quyền Hình trong hình của thiết bị. Không kiểm thử đóng/mở app trên điện thoại thật, không mua gói hoặc tải video thật trong lượt này.

Kiểm chứng cuối: 364 test đạt, 1 live API smoke test bỏ qua vì thiếu cấu hình; analyzer sạch. APK release ARM64: outputs/mobile-release/Dalitu-auto-pip-arm64.apk. Kiểm tra kernel xác nhận bản đóng gói chứa đúng mã giao diện, kiểm tra quyền và PiP mới. Không cài/chạy thử trên điện thoại thật.
