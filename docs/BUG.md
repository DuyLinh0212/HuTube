# Báo cáo lỗi HuTube

> Cập nhật sửa lỗi 02/10/2026: đã xử lý mã nguồn cho 88 mục. Xem [kết quả, kiểm thử và yêu cầu triển khai](docs/bug-fix-progress.md). Nội dung bên dưới giữ nguyên bằng chứng của đợt rà soát trước khi sửa.

Ngày rà soát: 30/09–01/10/2026 (Asia/Bangkok). Trạng thái: **Hoàn tất đợt rà soát mã nguồn mở rộng toàn dự án và giao diện/responsive; đã cập nhật tuần tự**.

Đã ghi nhận **88 phát hiện: 19 P1 / Cao, 67 P2 / Trung bình, 2 P3 / Thấp**. Mức độ dựa trên ảnh hưởng và điều kiện nêu trong từng mục; không khẳng định tất cả điều kiện đều đang tồn tại trên production.

## Phạm vi và cách xác minh

- Bản mã nguồn: thư mục `HuTube`, nhánh `develop`, commit bắt đầu `018ebc9`.
- Kiểm tra bảo mật, truy vấn/dữ liệu, lỗi logic và tích hợp trong API .NET, PostgreSQL, User Web, Admin Web, mobile Flutter, recommendation service và cấu hình triển khai liên quan.
- Mỗi lỗi ghi điều kiện, cách xảy ra/tái hiện, bằng chứng file:dòng, ảnh hưởng, phương án khắc phục và kiểm thử hồi quy đề xuất.
- Phân biệt **xác minh bằng mã nguồn**, **tái hiện cục bộ** và **cần xác minh môi trường**. Không suy diễn kết quả local thành sự cố đã xảy ra trên production.
- Báo cáo không chứa giá trị secret, token, mật khẩu hay dữ liệu người dùng thực. Các bản dump/database thật không dùng để chạy thử phá huỷ.
- Chỉ lập báo cáo; mã ứng dụng chưa được chỉnh sửa để khắc phục trong lần rà soát này.
- Theo yêu cầu “xem code thôi”, phần còn lại của đợt rà soát chỉ đọc mã và ghi báo cáo. Các kết quả thử nghiệm được ghi bên dưới đã hoàn thành trước yêu cầu này; mục **kiểm thử hồi quy đề xuất** là hướng dẫn cho lần sửa sau, không phải kết quả đã chạy.
- Đợt mở rộng 01/10 kiểm tra User Web, Admin Web, Flutter, routing/API contract, responsive, theme, bàn phím và các điều khiển chưa hoàn thiện. Điều kiện viewport là kịch bản suy từ CSS/widget constraints; chưa chạy trình duyệt hoặc Flutter để đo/chụp giao diện. Không coi sở thích màu sắc, bo góc hay phong cách là lỗi chức năng.

## Mức độ ưu tiên

- **P0 / Nghiêm trọng**: nguy cơ chiếm quyền hoặc lộ dữ liệu diện rộng, cần xử lý ngay nếu điều kiện triển khai tồn tại.
- **P1 / Cao**: phá vỡ phân quyền, lộ dữ liệu, mất dữ liệu hoặc làm gián đoạn chức năng chính.
- **P2 / Trung bình**: lỗi có điều kiện, dữ liệu sai, truy vấn gây tải hoặc luồng người dùng thất bại.
- **P3 / Thấp**: ảnh hưởng giới hạn, cần sửa để tăng độ ổn định.

## Danh sách lỗi

| ID | Mức độ | Nhóm | Vấn đề | Xác minh |
|---|---|---|---|---|
| BUG-001 | P1 / Cao | Bảo mật / thanh toán | Thiếu secret khiến webhook SePay chấp nhận chữ ký tùy ý | Proof verifier thật, key giả |
| BUG-002 | P2 / Trung bình | Bảo mật / quyền riêng tư | Playlist công khai làm lộ metadata video đã riêng tư hoặc bị gỡ | Proof service có mock |
| BUG-003 | P1 / Cao | Bảo mật / tải xuống | Cấp lại URL download sau khi mất quyền xem hoặc hết gói | Proof service có mock |
| BUG-004 | P1 / Cao | Bảo mật / quyền lợi gói | API chi tiết video trả URL file nguồn, vượt giới hạn chất lượng | Proof service có mock |
| BUG-005 | P1 / Cao | Bảo mật / thanh toán | Đăng ký trực tiếp gói trả phí mà không cần thanh toán | Mã nguồn |
| BUG-006 | P1 / Cao | Tích hợp / thanh toán | Xác minh HMAC sai định dạng SePay, từ chối webhook hợp lệ | Proof verifier + tài liệu hãng |
| BUG-007 | P1 / Cao | Bảo mật / phân quyền | User bất kỳ đọc strikes và ghi chú nội bộ của kênh khác | Proof service có mock |
| BUG-008 | P1 / Cao | Truy vấn / đồng thời | Upload đồng thời vượt quota vì sử dụng dữ liệu đọc trước transaction | Mã nguồn |
| BUG-009 | P1 / Cao | Bảo mật / kiểm duyệt | Creator tự gỡ các hạn chế do moderator áp dụng | Proof service có mock |
| BUG-010 | P1 / Cao | Mobile / riêng tư | Tài khoản B xem và xóa video offline của tài khoản A | Mã nguồn |
| BUG-011 | P2 / Trung bình | Web / playlist | Autoplay playlist mắc ở video thứ hai | Proof TypeScript có mock |
| BUG-012 | P2 / Trung bình | Web / dữ liệu | Response cũ ghi đè video mới và ghi sai lịch sử xem | Proof TypeScript có mock |
| BUG-013 | P2 / Trung bình | Mobile / đồng thời | Download ghi đè phần tử khác và request cũ đóng client mới | Mã nguồn + mô hình lịch chạy |
| BUG-014 | P2 / Trung bình | Bảo mật / export | CSV không trung hòa công thức trong dữ liệu user | Proof exporter; chưa mở Excel |
| BUG-015 | P2 / Trung bình | Admin / dữ liệu | API lỗi bị thay bằng video, hồ sơ kiểm duyệt và số liệu giả | Proof TypeScript có mock |
| BUG-016 | P1 / Cao | Bảo mật / xử lý video | Recovery dùng nhầm file của video khác chỉ vì bằng dung lượng | Mã nguồn + proof helper |
| BUG-017 | P1 / Cao | Web / riêng tư | Hub thông báo của A tiếp tục dùng sau khi đăng nhập B | Proof TypeScript có mock |
| BUG-018 | P2 / Trung bình | Upload / vận hành | Restart làm mất session chunk, để lại file tạm không được dọn | Proof cục bộ |
| BUG-019 | P1 / Cao | Bảo mật / kiểm duyệt | Kênh bị suspended/banned vẫn cấp URL và xuất hiện ở discovery | Proof service có mock |
| BUG-020 | P2 / Trung bình | Dữ liệu / storage | Xóa video không có vòng đời purge và hoàn quota | Proof service có mock |
| BUG-021 | P1 / Cao | Truy vấn / mất dữ liệu | Purge xóa file rồi ghi URL rỗng trái CHECK của database | Mã nguồn + schema |
| BUG-022 | P2 / Trung bình | Kiểm duyệt / dữ liệu | Endpoint report comment cũ tạo hồ sơ không xử lý được | Proof service có mock |
| BUG-023 | P1 / Cao | Bảo mật / quyền lợi gói | Upload tin duration/quality do client tự khai | Mã nguồn |
| BUG-024 | P2 / Trung bình | Kiểm duyệt / feed | Flag hạn chế đề xuất được ghi nhưng không được đọc để lọc | Mã nguồn |
| BUG-025 | P2 / Trung bình | Bảo mật / riêng tư | Report target không được xem vẫn làm lộ title/content | Proof service có mock |
| BUG-026 | P1 / Cao | Phân quyền / khiếu nại | Moderator được duyệt appeal cho quyết định remove của chính mình | Proof service có mock |
| BUG-027 | P2 / Trung bình | Gợi ý / dữ liệu | Simulator làm sai tỷ lệ danh mục khi một pool hết video | Proof helper |
| BUG-028 | P2 / Trung bình | Gợi ý / trạng thái | Model đã active nhưng job báo failed sau Python restart | Proof FakeR2 + mã .NET |
| BUG-029 | P2 / Trung bình | Gợi ý / nhiều instance | Replica Python giữ model cũ và không chia sẻ trạng thái job | Proof hai registry giả |
| BUG-030 | P2 / Trung bình | Truy vấn / nhiều instance | Worker claim cùng job và startup vô hiệu hóa job của instance khác | Mã nguồn |
| BUG-031 | P2 / Trung bình | Gợi ý / dữ liệu | Preview/export CSV không khớp cấu hình weighted đang active | Proof helper + mã nguồn |
| BUG-032 | P3 / Thấp | Gợi ý / validation | Trọng số decimal hợp lệ gây overflow và job failed | Proof helper |
| BUG-033 | P2 / Trung bình | Gợi ý / vận hành | Lỗi R2 thoáng qua khi startup làm CF không tự phục hồi | Proof FakeR2 |
| BUG-034 | P2 / Trung bình | Truy vấn / feed | Phân trang CF + fallback làm mất và trùng video | Mã nguồn + lịch dữ liệu |
| BUG-035 | P1 / Cao | Thanh toán / đồng thời | Kích hoạt gói và ghi nhận paid không trong cùng transaction | Mã nguồn |
| BUG-036 | P2 / Trung bình | Truy vấn / thanh toán | Idempotency lookup không tương thích unique index | Mã nguồn + schema |
| BUG-037 | P1 / Cao | Auth / đồng thời | Đổi mật khẩu có thể bỏ sót phiên vừa refresh | Mã nguồn |
| BUG-038 | P2 / Trung bình | API / xử lý lỗi | PlanException và PaymentException bị biến thành lỗi 500 | Mã nguồn |
| BUG-039 | P2 / Trung bình | Tài khoản / lưu dữ liệu | Tiểu sử được nhận nhưng không lưu vì EF bỏ qua Bio | Mã nguồn + EF mapping |
| BUG-040 | P2 / Trung bình | User Web / responsive | Topbar phủ đầu drawer và nút đóng ở màn hình nhỏ | CSS + DOM |
| BUG-041 | P2 / Trung bình | User Web / routing | Trang kênh/playlist công khai buộc khách đăng nhập | Router + guard + API |
| BUG-042 | P1 / Cao | Admin Web / responsive | Drawer hiện ra nhưng không nhận click/touch trên mobile/tablet | CSS + component scope |
| BUG-043 | P2 / Trung bình | Admin Web / bàn phím | Custom select không thể chọn option bằng bàn phím | Template + event handlers |
| BUG-044 | P2 / Trung bình | User/Admin Web / responsive | Modal thanh toán, appeal và action không cuộn trên màn hình thấp | CSS + cấu trúc nội dung |
| BUG-045 | P2 / Trung bình | User Web / bàn phím | Picker upload, thumbnail và avatar thiếu thao tác bàn phím | Template + event handlers |
| BUG-046 | P2 / Trung bình | Studio / xuất bản | Chọn lịch phát hành nhưng request bỏ qua toàn bộ lịch | Form + API contract |
| BUG-047 | P2 / Trung bình | Studio / mất dữ liệu form | Nút Lưu nháp không thực hiện lưu | Binding + state ownership |
| BUG-048 | P2 / Trung bình | Mobile / responsive | Sheet tạo nội dung không cuộn, tràn ở landscape/chữ lớn | Widget constraints |
| BUG-049 | P2 / Trung bình | Mobile / tìm kiếm | Load-more trộn query cũ/mới và response ghi lại sau clear | State + async flow |
| BUG-050 | P2 / Trung bình | Mobile / phân trang | Feed bỏ qua trang lỗi vì tăng page trước thành công | State transitions |
| BUG-051 | P2 / Trung bình | Mobile / filter | Response load-more cũ ghép vào feed sau đổi filter | Async interleaving |
| BUG-052 | P2 / Trung bình | Admin Web / filter | Filter thời gian/trạng thái kênh không khớp query hiển thị | UI → query builder → API |
| BUG-053 | P2 / Trung bình | Admin Web / dark mode | Trang gói giữ nền trắng nhưng dùng chữ gần trắng | CSS cascade + theme tokens |
| BUG-054 | P2 / Trung bình | Studio / responsive | Lưới thumbnail tràn cột sửa video khi sidebar mở ở tablet | CSS geometry |
| BUG-055 | P2 / Trung bình | Studio / truy vấn UI | Content/search và tổng kênh chỉ dùng 50 video đầu | Pagination contract + UI |
| BUG-056 | P2 / Trung bình | Studio / số liệu | Watch time tính bằng views × duration thay thời gian xem thực | Công thức + nhãn UI |
| BUG-057 | P3 / Thấp | User Web / thông tin | Mọi kênh đều có badge đã xác minh | Template + DTO |
| BUG-058 | P2 / Trung bình | User Web / trạng thái giả | Công cụ privacy báo thành công nhưng không thực hiện hành động | Handlers + nội dung UI |
| BUG-059 | P2 / Trung bình | User Web / khôi phục phiên | Reload trang gói không nạp gói hiện tại sau restore đăng nhập | Bootstrap + lifecycle |
| BUG-060 | P2 / Trung bình | User Web / responsive | Hero chi tiết gói có min-width vượt card ở viewport 320px | CSS geometry |
| BUG-061 | P2 / Trung bình | Backend / cài đặt thông báo | PlanEnabled bị bỏ qua khi gửi thông báo lời mời dùng chung gói | Preference → producer → filter |
| BUG-062 | P2 / Trung bình | User Web / responsive | Home giữ bốn cột đề xuất trên điện thoại do specificity | CSS cascade / kích thước track |
| BUG-063 | P2 / Trung bình | User Web / lưu video | Thêm playlist thất bại nhưng sửa video vẫn báo lưu thành công | Observable error → success / API policy |
| BUG-064 | P2 / Trung bình | User Web / upload | Tùy chọn phụ đề tự động và cho bình luận bị bỏ khỏi request | Binding → FormData → server contract |
| BUG-065 | P2 / Trung bình | Admin Web / overlay | Drawer Channels và dialog Topics nằm dưới topbar | DOM layers / CSS z-index |
| BUG-066 | P2 / Trung bình | Admin Web / phân trang | Các trang kiểm duyệt chỉ tải trang đầu của backlog | UI calls → API Skip/Take |
| BUG-067 | P2 / Trung bình | Admin Web / liên kết | Open target của report nối cứng localhost:4200 | Href builder / relative targetUrl |
| BUG-068 | P1 / Cao | Admin Web / race ghi metadata | Response video cũ ghi đè form và có thể lưu nhầm sang video khác | Async interleaving → persisted update |
| BUG-069 | P2 / Trung bình | Admin Web / responsive | Rule base ghi đè breakpoint một cột của form RBAC | Stylesheet order / CSS cascade |
| BUG-070 | P2 / Trung bình | Admin Web / lỗi trong modal | Lỗi form/modal chỉ hiện ở trang nền dưới backdrop | Error signal → template placement |
| BUG-071 | P2 / Trung bình | Admin Web / sửa video | Xóa description bị serialize thành không thay đổi nhưng vẫn báo thành công | Payload undefined → server update predicate |
| BUG-072 | P2 / Trung bình | Flutter / form sheet | Sheet playlist, report và sửa video không cuộn khi bàn phím chiếm chiều cao | Keyboard insets / widget constraints |
| BUG-073 | P2 / Trung bình | Flutter / responsive player | Offline player lấy chiều cao theo chiều rộng và tràn ở landscape | AspectRatio / body height |
| BUG-074 | P2 / Trung bình | Flutter / watch race | Reaction trả muộn của video A ghi đè metadata video B | Router State reuse / async commit |
| BUG-075 | P2 / Trung bình | Flutter / quản lý phiên | Profile giữ snapshot danh sách phiên nên refresh không cập nhật UI | Controller notify / missing listener |
| BUG-076 | P2 / Trung bình | Flutter / thanh toán | Đóng thanh toán chưa paid vẫn báo đăng ký gói thành công | Dialog result / control flow |
| BUG-077 | P2 / Trung bình | Flutter / download flow | Download menu không khớp trạng thái server nên thiếu Resume/Pause | Status vocabulary / API transitions |
| BUG-078 | P2 / Trung bình | Flutter / dark theme | Form auth giữ nền trắng nhưng dùng chữ gần trắng của dark theme | Theme tokens / fixed background |
| BUG-079 | P2 / Trung bình | Flutter / responsive state view | Empty/error view chung vượt chiều cao landscape và khuất nút phục hồi | Fixed child heights / shell constraints |
| BUG-080 | P2 / Trung bình | Flutter / collection pagination | Library, comments, channel và creator bỏ metadata phân trang | PageResult consumer / fixed page1 |
| BUG-081 | P2 / Trung bình | Flutter / comment identity | Comment mới bị mất khỏi giao diện do State cũ được tái sử dụng theo vị trí | Unkeyed list / cached widget state |
| BUG-082 | P2 / Trung bình | Flutter / mini-player navigation | Thu nhỏ Watch sau go/deep link không rời trang và dựng thêm mini-player | Route stack / minimized flag |
| BUG-083 | P2 / Trung bình | Flutter / playback preference | Chất lượng mặc định đã lưu nhưng Watch luôn chọn rendition cao nhất | Preference write / source selection |
| BUG-084 | P2 / Trung bình | Flutter / upload validation | Upload cho nhập tiêu đề 150 ký tự nhưng API chỉ nhận tối đa 100 | Client field rule / backend validation |
| BUG-085 | P2 / Trung bình | Admin Web / menu bố cục | Menu thao tác bị clip khi filter chỉ còn ít dòng và mở lên trong bảng | Flip heuristic / overflow scrollport |
| BUG-086 | P2 / Trung bình | Admin Web / responsive table | Bảng Policies cắt cột bên phải trên mobile và không có đường cuộn ngang | Table markup / clipping / width constraints |
| BUG-087 | P2 / Trung bình | Admin Web / permission UX | Controls Channels/Videos mời thao tác mà role chỉ xem không thể hoàn tất | Permission computed → template → API gate |
| BUG-088 | P2 / Trung bình | Flutter / profile responsive | Màn thiết bị mở từ AccountHub không có vùng cuộn cho nội dung dài | Route wrapper / Column / viewport |

### BUG-001 — Webhook SePay bỏ xác thực khi thiếu secret

- **Bằng chứng:** [SepaySignatureVerifier.cs:23](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/SepaySignatureVerifier.cs:23)–28; [SepayOptions.cs:12](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/SepayOptions.cs:12); [Program.cs:48](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Program.cs:48), [Program.cs:78](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Program.cs:78); [PaymentsController.cs:65](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/PaymentsController.cs:65)–84; [PaymentService.cs:80](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:80)–141.
- **Điều kiện:** môi trường có gói trả phí và chưa cấu hình `SePay:SecretKey` (mặc định rỗng). API vẫn khởi động vì không kiểm tra cấu hình SePay bắt buộc. Chưa xác minh giá trị secret trên production.
- **Cách xảy ra:** `Verify()` chỉ yêu cầu header chữ ký không rỗng, sau đó trả `true` khi secret trống. Không có kiểm tra môi trường Development cho nhánh bỏ xác thực. Endpoint webhook cho phép anonymous; payload được tin để kích hoạt gói.
- **Tái hiện trong môi trường thử nghiệm:** tạo đơn pending bằng tài khoản thử; gửi `POST /api/v1/payments/webhook/sepay` với header `X-SePay-Signature: invalid`, body có `id` thử nghiệm mới, `transferType: "in"`, `code` của đơn và `transferAmount` đủ giá. Với secret rỗng, verifier chấp nhận dù không có giao dịch ngân hàng.
- **Ảnh hưởng:** người có tài khoản có thể tự tạo đơn và giả mạo xác nhận tiền vào để nhận gói trả phí, gây gian lận doanh thu.
- **Khắc phục:** bắt buộc cấu hình secret hợp lệ khi bật thanh toán; nếu thiếu thì từ chối webhook và không cho tạo đơn. Bỏ nhánh `return true` khi thiếu key. Chế độ giả lập local phải tách rõ, không dùng endpoint thanh toán thật. Đối chiếu tài khoản nhận và giao dịch trước khi kích hoạt.
- **Kiểm thử hồi quy đề xuất:** secret rỗng/whitespace và chữ ký tùy ý đều bị từ chối; cấu hình Production thiếu key phải fail startup hoặc vô hiệu hóa thanh toán; chỉ webhook hợp lệ mới chuyển pending → paid.
- **Trạng thái:** verifier thật liên kết từ mã nguồn đã trả `True` với key rỗng và chữ ký tùy ý trên fixture local. Không gửi webhook để kích hoạt gói thật. Test hiện có [SepaySignatureVerifierTests.cs:11](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/tests/HuTube.UnitTests/SepaySignatureVerifierTests.cs:11) đang kỳ vọng secret rỗng trả `true`, cần sửa kỳ vọng này.
- **Cập nhật 02/10/2026:** `.env.local` hiện khai báo `SePay__SecretKey`. API được chạy bằng [run-local.ps1:8](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/scripts/run-local.ps1:8)–11 (nạp biến qua [common.ps1:5](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/scripts/common.ps1:5)–27) hoặc Docker Compose ([docker-compose.yml:30](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docker-compose.yml:30)–39) sẽ nhận cấu hình này; trong hai cách chạy đó, nhánh bỏ xác thực do secret rỗng sẽ không áp dụng nếu key này đúng với webhook SePay. Launch profile trực tiếp của API chỉ khai báo ASPNETCORE tại [launchSettings.json:7](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Properties/launchSettings.json:7)–10; `dotnet run` không qua script và không có biến môi trường được nạp riêng vẫn có thể gặp điều kiện cũ. Chưa kiểm chứng key với SePay hoặc trạng thái production. BUG-006 là lỗi định dạng chữ ký riêng, không được giải quyết chỉ bằng cách thêm key.

### BUG-002 — Metadata video riêng tư vẫn xuất hiện trong playlist công khai

- **Bằng chứng:** [PlaylistService.cs:50](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Playlists/PlaylistService.cs:50)–79, [PlaylistService.cs:127](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Playlists/PlaylistService.cs:127)–130; [PlaylistController.cs:26](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/PlaylistController.cs:26); luồng đổi visibility tại [ContentService.cs:876](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:876)–882.
- **Điều kiện:** video từng được thêm vào playlist public khi còn public, rồi chủ video chuyển private hoặc nội dung bị gỡ/xóa mềm.
- **Cách xảy ra:** service tính `available = false` nhưng vẫn đưa `Title`, thumbnail URL được cấp lại, duration, visibility và moderation status vào response. Quyền đọc playlist không đồng nghĩa với quyền đọc mọi video trong playlist.
- **Tái hiện:** tài khoản A thêm video public của B vào playlist public; B chuyển video private; gọi anonymous `GET /api/v1/playlists/{playlistId}`. Item bị đánh dấu unavailable nhưng tiêu đề và URL ảnh vẫn có trong JSON.
- **Ảnh hưởng:** lộ metadata và ảnh của nội dung riêng tư hoặc đã gỡ. Phát hiện này không khẳng định endpoint playlist làm lộ toàn bộ file video.
- **Khắc phục:** áp dụng cùng policy xem video cho từng item trước khi enrich; với viewer không đủ quyền chỉ trả tombstone tối thiểu (ID item, vị trí và trạng thái unavailable), không trả title, ảnh hoặc metadata nhạy cảm. Chủ video được xem metadata nếu policy cho phép.
- **Kiểm thử hồi quy đề xuất:** public → private/removed/deleted phải ẩn metadata với anonymous và người không sở hữu; viewer được phép vẫn thấy đúng dữ liệu.
- **Trạng thái:** service thật với EF InMemory và storage giả đã trả title/thumbnail cho item private dù available=false; controller cho phép anonymous được đối chiếu bằng mã. Chưa gọi API production.

### BUG-003 — URL download được cấp lại dù quyền truy cập đã bị thu hồi

- **Bằng chứng:** [ContentService.cs:1383](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1383)–1409, [ContentService.cs:1420](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1420)–1433, [ContentService.cs:1787](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1787); [ContentControllers.cs:280](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:280)–288; [R2ObjectStorageService.cs:91](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Storage/R2ObjectStorageService.cs:91)–101.
- **Điều kiện:** user đã tạo download hợp lệ; sau đó video chuyển private/bị gỡ hoặc user hết gói cho phép tải. Object trên storage vẫn còn, chưa bị dọn.
- **Cách xảy ra:** tạo download có kiểm tra quyền xem, DownloadEnabled và chất lượng, nhưng đọc danh sách hoặc đổi trạng thái chỉ kiểm tra bản ghi thuộc user. Service gọi lại storage để sinh URL có thời hạn mới mà không kiểm tra quyền hiện tại.
- **Tái hiện:** A tạo download của video public; chủ video chuyển private; A gọi `GET /api/v1/downloads` hoặc cancel/retry download. Response vẫn có URL R2 mới dùng để lấy file. Có thể lặp lại sau khi URL trước hết hạn.
- **Ảnh hưởng:** tiếp tục truy cập nội dung đã thu hồi và quyền lợi tải/chất lượng đã hết hạn. Khác với vấn đề URL cũ còn hiệu lực: endpoint chủ động cấp thêm URL mới.
- **Khắc phục:** kiểm tra video, moderation, quyền xem, gói hiện tại và chất lượng trước mọi lần cấp URL; đánh dấu bản download revoked/unavailable khi mất quyền; thu hồi bản ghi/link liên quan khi private/remove nếu chính sách yêu cầu.
- **Kiểm thử hồi quy đề xuất:** kiểm tra GET và retry sau public → private, moderation removed, gói hết hạn và hạ chất lượng; response không còn URL truy cập được.
- **Trạng thái:** service thật với dữ liệu/storage giả đã cấp lại URL cho download sau khi video private. Nhánh hết gói được xác minh bằng mã; chưa tải nội dung thật.

### BUG-004 — Public video detail trả URL file nguồn ngoài kiểm soát chất lượng

- **Bằng chứng:** [ContentControllers.cs:127](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:127)–131; [ContentService.cs:599](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:599)–616, [ContentService.cs:1465](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1465)–1466, [ContentService.cs:1374](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1374)–1386.
- **Điều kiện:** video public được duyệt có file nguồn cao hơn giới hạn của viewer, ví dụ 1080p/2160p với viewer anonymous giới hạn 720p.
- **Cách xảy ra:** playback chỉ cấp rendition dưới `maxHeight`, download kiểm tra gói, nhưng `GET /api/v1/videos/{id}` gọi `ToResponseAsync()` và cấp URL đọc của `video.VideoUrl` (source) cho mọi viewer được xem video.
- **Tái hiện:** gọi anonymous detail của video nguồn 2160p; lấy trường `videoUrl` và truy cập. So sánh playback chỉ có rendition ≤720p và download yêu cầu gói: source URL vẫn cho lấy file gốc.
- **Ảnh hưởng:** bỏ qua giới hạn chất lượng và cổng cấp quyền download của sản phẩm, tăng chi phí băng thông source. Không có cơ chế web nào ngăn tuyệt đối việc lưu luồng đã cho xem; lỗi cụ thể ở đây là cấp riêng file nguồn ngoài policy rendition.
- **Khắc phục:** public DTO chỉ trả metadata và các URL playback đã áp dụng entitlement; source URL chỉ cấp trong luồng quản lý có quyền rõ ràng. Client phát video qua playback và xử lý không có rendition thay vì dùng source tự do.
- **Kiểm thử hồi quy đề xuất:** anonymous/free không nhận source URL; chất lượng được cấp luôn ≤ giới hạn; quản lý/owner chỉ lấy source khi có permission phù hợp.
- **Trạng thái:** service thật với dữ liệu/storage giả đã trả source 2160p trong detail của anonymous trong khi playback giới hạn 720p; không tải file thật.

### BUG-005 — Bỏ qua thanh toán bằng endpoint subscribe trực tiếp

- **Bằng chứng:** [PlansController.cs:47](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/PlansController.cs:47)–53; [PlanService.cs:239](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Plans/PlanService.cs:239)–303; luồng thanh toán riêng tại [PaymentService.cs:20](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:20)–75, [PaymentService.cs:125](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:125)–140.
- **Điều kiện:** tài khoản thường đang dùng gói free hoặc chưa có gói, và tồn tại gói active có `Price > 0`. Không phụ thuộc cấu hình secret webhook.
- **Cách xảy ra:** `SubscribeAsync()` chỉ kiểm tra quy tắc đổi/hạ gói. Nếu gói hiện tại là free hoặc gói đích đắt hơn, service tạo ngay PlanHistory active, cập nhật `User.PlanId` và quota. Không có điều kiện bắt buộc payment paid hay purchase entitlement cho nhánh này.
- **Tái hiện:** lấy ID gói trả phí từ `GET /api/v1/plans`; đăng nhập tài khoản free; gọi `POST /api/v1/plans/{paidPlanId}/subscribe` với `{ "autoRenew": false }`. Service kích hoạt gói dù chưa tạo đơn và chưa chuyển tiền.
- **Ảnh hưởng:** mọi tài khoản free có thể nhận quota/download/quyền lợi gói trả phí, và nâng tiếp lên gói đắt hơn miễn phí.
- **Khắc phục:** endpoint subscribe trực tiếp chỉ áp dụng gói free hoặc chuyển sang quyền lợi đã mua còn hạn. Kích hoạt gói trả phí phải qua payment đã đối soát, ràng buộc user/plan/amount; tập trung thay đổi entitlement vào một service giao dịch có kiểm tra nguồn cấp quyền.
- **Kiểm thử hồi quy đề xuất:** free → paid và paid → gói đắt hơn qua subscribe phải bị từ chối khi chưa paid; webhook hợp lệ kích hoạt đúng một lần; free subscription vẫn hoạt động theo contract.
- **Trạng thái:** xác minh controller và toàn bộ hàm subscribe, chưa gọi endpoint trên database thật.

### BUG-006 — HMAC SePay dùng sai chuỗi ký và định dạng header

- **Bằng chứng:** [SepaySignatureVerifier.cs:31](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/SepaySignatureVerifier.cs:31)–45; [PaymentsController.cs:70](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/PaymentsController.cs:70)–87; test [SepaySignatureVerifierTests.cs:35](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/tests/HuTube.UnitTests/SepaySignatureVerifierTests.cs:35)–46 tạo chữ ký theo cùng thuật toán sai.
- **Nguồn đối chiếu:** [Tài liệu xác thực webhook SePay](https://developer.sepay.vn/vi/sepay-webhooks/xac-thuc), đọc ngày 30/09/2026. Hãng quy định ký `timestamp + "." + raw_body` và header `sha256={hex_hash}`.
- **Điều kiện:** cấu hình webhook SePay dùng HMAC-SHA256 và secret không rỗng.
- **Cách xảy ra:** HuTube chỉ HMAC body, so sánh với hex không prefix. Timestamp được kiểm tra riêng và còn cho phép thiếu/không parse được, không nằm trong dữ liệu ký.
- **Tái hiện cục bộ:** dùng key thử nghiệm, timestamp hiện tại và body JSON; tính chữ ký đúng tài liệu có prefix `sha256=`; truyền vào `Verify()`. Kết quả sẽ false, dù chữ ký hợp lệ với giao thức SePay. Chữ ký body-only mà test hiện tại dùng lại được chấp nhận.
- **Ảnh hưởng:** giao dịch thật bị webhook trả 401, đơn không được kích hoạt tự động. Bộ test hiện có có thể xanh vì dùng fixture cùng sai lệch giao thức.
- **Khắc phục:** đọc raw bytes nguyên vẹn; yêu cầu timestamp hợp lệ trong cửa sổ cho phép; ký đúng bytes `timestamp.raw_body`; parse prefix/hex và so sánh constant-time. Dùng fixture từ hợp đồng hãng, không lấy thuật toán implementation làm oracle test.
- **Kiểm thử hồi quy đề xuất:** request đúng format được chấp nhận; đổi body/timestamp bị từ chối; timestamp thiếu, sai định dạng, ngoài range và quá cũ đều từ chối có kiểm soát.
- **Trạng thái:** verifier thật trên fixture local từ chối chữ ký theo tài liệu SePay, chấp nhận body-only signature thiếu timestamp hoặc timestamp invalid. Dùng key giả; không gửi giao dịch thật.

### BUG-007 — Đọc strikes và ghi chú kiểm duyệt của kênh khác bằng ID công khai

- **Bằng chứng:** [UserModerationController.cs:13](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/UserModerationController.cs:13), [UserModerationController.cs:79](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/UserModerationController.cs:79)–81; [StrikeService.cs:16](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/StrikeService.cs:16)–25, [StrikeService.cs:63](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/StrikeService.cs:63)–80.
- **Điều kiện:** bất kỳ tài khoản đã đăng nhập biết channelId của kênh khác (ID có trong API công khai).
- **Cách xảy ra:** endpoint chỉ yêu cầu đăng nhập, không truyền viewerId vào service và không kiểm tra quyền trên kênh. DTO trả cả `InternalNote`, lý do, policy, người thu hồi và ghi chú thu hồi.
- **Tái hiện:** A không sở hữu/tham gia kênh B; gọi `GET /api/v1/channels/{B}/strikes` bằng token A. Service truy vấn strikes của B và trả các trường nội bộ.
- **Ảnh hưởng:** lộ lịch sử vi phạm, nhận xét nội bộ và thông tin xử lý của moderator trên kênh không thuộc quyền của caller.
- **Khắc phục:** kiểm tra owner/member và permission cụ thể trước query; DTO dành cho chủ kênh loại bỏ `InternalNote` và dữ liệu chỉ dành cho quản trị. Admin dùng endpoint/DTO riêng có RBAC.
- **Kiểm thử hồi quy đề xuất:** unrelated user bị 403/404; owner/member được phép chỉ nhận các trường public-to-owner; anonymous vẫn bị từ chối.
- **Trạng thái:** service thật với dữ liệu InMemory đã trả InternalNote của strike; controller thiếu kiểm tra quan hệ caller/kênh được đối chiếu bằng mã. Chưa đọc kênh của người dùng thật.

### BUG-008 — Quota upload bị vượt và bộ đếm bị ghi thiếu khi có hai request

- **Bằng chứng:** [ContentService.cs:637](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:637)–646, [ContentService.cs:660](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:660)–726, [ContentService.cs:728](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:728)–739.
- **Điều kiện:** hai upload cùng kênh đọc cùng quota trước khi một request hoàn tất; upload/transcoding làm khoảng chờ này dài.
- **Cách xảy ra:** quota là entity được đọc/tracked trước transaction. Transaction Serializable được mở sau bước xử lý file nhưng lần kiểm tra thứ hai vẫn dùng entity cũ, rồi ghi `StorageUsed` từ giá trị cũ. Isolation không bảo vệ dữ liệu đã đọc ngoài transaction.
- **Tái hiện theo lịch chạy:** quota used=0, limit=10; T1 và T2 cùng đọc 0, mỗi file size=6. T1 commit used=6. T2 bắt đầu transaction sau commit của T1, vẫn dùng cached 0 và commit used=6. Tổng file là 12 nhưng bộ đếm là 6. Không cần hai transaction chồng lấn để xảy ra lỗi.
- **Ảnh hưởng:** vượt dung lượng được cấp, tính sai storage và tăng chi phí lưu trữ; preflight không bảo đảm reservation.
- **Khắc phục:** reserve bằng atomic conditional UPDATE `used = used + size` với điều kiện `used + size <= limit`, kiểm tra affected rows trong transaction; hoặc đọc lại và khóa quota trong transaction. Có cơ chế hoàn reservation/dọn object nếu upload thất bại.
- **Kiểm thử hồi quy đề xuất:** dùng barrier cho hai upload trên database PostgreSQL thử riêng; chỉ một upload vượt tổng limit được nhận; tổng quota phải khớp các object đã lưu.
- **Trạng thái:** xác minh lịch đọc/ghi của EF; chưa stress database thật.

### BUG-009 — Creator có thể đảo ngược quyết định kiểm duyệt bằng sửa video

- **Bằng chứng:** [ReportService.cs:698](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:698)–715; [ContentService.cs:866](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:866)–918.
- **Điều kiện:** moderator hide một video đã approved/published, hoặc áp dụng age/recommendation restriction; creator vẫn có VideoEdit.
- **Cách xảy ra:** hide chỉ đặt visibility private, không tạo enforcement state riêng. Creator đổi lại public và vì ModerationStatus vẫn approved nên không vào review mới. Creator cũng sửa `AgeRestricted=false`; cập nhật chapters thay toàn bộ Metadata, xóa flag `recommendation_restricted` của moderator.
- **Tái hiện:** moderator xử lý `hide`, creator PATCH `{ "visibility": "public" }` → video trở lại public. Tương tự age restriction bị bỏ bằng `{ "ageRestricted": false }`; recommendation restriction mất khi PATCH chapters hợp lệ.
- **Ảnh hưởng:** nội dung đã hạn chế tự công khai/được đề xuất lại mà không có quyết định moderator hoặc appeal được chấp nhận.
- **Khắc phục:** tách sở thích creator khỏi enforcement của moderator; tính policy hiệu lực bằng cả hai. Chỉ moderator/appeal service được gỡ enforcement. Khi sửa metadata phải merge trường chapters, giữ các trường do hệ thống quản lý.
- **Kiểm thử hồi quy đề xuất:** thực hiện từng quyết định moderator rồi PATCH từ creator; hạn chế phải còn hiệu lực. Moderator có quyền vẫn gỡ được qua luồng có audit.
- **Trạng thái:** service thật với dữ liệu/dependencies giả đã cho creator đổi lại public, gỡ age restriction và ghi đè metadata chứa recommendation restriction. Không sửa video thật.

### BUG-010 — Download offline không tách theo tài khoản trên mobile

- **Bằng chứng:** [local_download_manager.dart:87](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:87)–108, [local_download_manager.dart:120](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:120)–135, [local_download_manager.dart:160](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:160)–187; [downloads_screen.dart:126](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/downloads_screen.dart:126), [downloads_screen.dart:234](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/downloads_screen.dart:234)–239; [offline_player_screen.dart:37](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/offline_player_screen.dart:37)–45, [offline_player_screen.dart:70](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/offline_player_screen.dart:70)–76; [auth.dart:466](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/auth.dart:466)–476.
- **Điều kiện:** A tải xong video trên thiết bị; logout và đăng nhập B trên cùng app. Video có thể là nội dung private mà A có quyền xem.
- **Cách xảy ra:** singleton manager dùng chung danh sách và `downloads/manifest.json`, không có ownerUserId. Logout chỉ xóa phiên auth; màn downloads hiển thị tất cả item local và offline player mở file trực tiếp mà không xác minh owner.
- **Tái hiện:** A tải video thử, logout, login B, mở Downloads rồi chọn item của A. B thấy tiêu đề, có thể phát và xóa file đã tải của A.
- **Ảnh hưởng:** lộ nội dung và lịch sử tải giữa các tài khoản dùng chung thiết bị; B can thiệp file của A. Backend đã scope remote downloads theo user nhưng local client không giữ ranh giới này.
- **Khắc phục:** manifest/path và job gắn userId; lọc theo phiên hiện tại và kiểm tra owner trước phát/xóa/retry. Dừng job, xóa state trong RAM khi chuyển phiên; xử lý migration các item cũ không có owner theo chính sách rõ ràng.
- **Kiểm thử hồi quy đề xuất:** A → logout → B không thấy/phát/xóa item A; login lại A phục hồi đúng item của A; job đang chạy không ghi vào state B.
- **Trạng thái:** xác minh mã Flutter và contract backend; chưa chạy app trên thiết bị.

### BUG-011 — Autoplay playlist không cập nhật vị trí khi router tái sử dụng trang

- **Bằng chứng:** [watch-page.ts:94](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:94)–110, [watch-page.ts:317](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:317)–332; route `watch/:id` tại [app.routes.ts](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/app.routes.ts).
- **Điều kiện:** playlist có ít nhất ba video khả dụng, bật autoplay, mở từ index=0.
- **Cách xảy ra:** playlistIndex chỉ được đọc trong constructor. Khi router chuyển A → B bằng cùng route/component, subscription paramMap đổi videoId nhưng không đổi index từ queryParamMap.
- **Tái hiện:** playlist [A,B,C], mở `/watch/A?playlist=P&index=0`; A hết chuyển B với index=1; B hết vẫn tính next từ index=0 nên lại chọn B. C không được phát tự động.
- **Ảnh hưởng:** luồng phát liên tục bị mắc và chuyển playlist trong cùng trang dùng queue/index cũ.
- **Khắc phục:** phản ứng đồng thời với paramMap và queryParamMap; cập nhật playlist/index mỗi navigation, nạp queue khi playlist đổi; ưu tiên xác định vị trí từ videoId thực tế.
- **Kiểm thử hồi quy đề xuất:** autoplay A → B → C; chuyển playlist khi vẫn trên watch; bỏ qua item unavailable và kết thúc đúng cuối danh sách.
- **Trạng thái:** class TypeScript thật với router/HTTP mock đã cho chuỗi A → B → B; playlistIndex vẫn 0 khi route index là 1. Chưa chạy trình duyệt thật.

### BUG-012 — Response video cũ ghi đè trang mới và làm sai viewing history

- **Bằng chứng:** [watch-page.ts:105](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:105)–110, [watch-page.ts:149](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:149)–163, [watch-page.ts:183](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:183)–204, [watch-page.ts:409](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.ts:409)–415; endpoint progress tại [ContentControllers.cs:197](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:197)–199.
- **Điều kiện:** mạng chậm hoặc response trả đảo thứ tự khi chuyển A → B nhanh.
- **Cách xảy ra:** các GET detail/playback/comments subscribe độc lập, không cancel và không có guard theo videoId/generation. Callback của A vẫn thay video/player/comments sau khi mutable videoId đã là B; progress dùng videoId hiện tại thay vì identity của media đang phát.
- **Tái hiện:** trì hoãn response A, chuyển B; cho B trả trước rồi A trả sau. URL là B nhưng trang/player hiển thị A; timeupdate gửi progress vào `/videos/B/watch-progress` với thời gian của A.
- **Ảnh hưởng:** xem nhầm nội dung, sai trạng thái bình luận/download và ghi sai lịch sử video B.
- **Khắc phục:** dùng switchMap từ route để hủy flow GET cũ, hoặc guard generation + ID ở mọi callback; reset state phụ thuộc video khi đổi route và buộc progress gắn đúng video của player.
- **Kiểm thử hồi quy đề xuất:** mock response A trả sau B, cả success/error; chỉ B được cập nhật UI/history; response cũ không thay download options.
- **Trạng thái:** class TypeScript thật với response/router mock đã cho URL B nhưng state/player A và progress B=42 giây từ A; endpoint nhận progress được đối chiếu bằng mã. Chưa chạy trình duyệt thật.

### BUG-013 — Hai race trong manager download mobile

- **Bằng chứng:** [local_download_manager.dart:183](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:183), [local_download_manager.dart:195](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:195)–220, [local_download_manager.dart:260](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/local_download_manager.dart:260)–272.
- **Điều kiện:** enqueue nhiều download nhanh, hoặc khởi động lại/cấp lại download cùng video+quality trong khi transfer cũ còn hoạt động; hai lượt có cùng ID. Không giả định nút retry trên UI luôn khả dụng lúc đang tải.
- **Cách xảy ra:** `_start()` giữ index trước await filesystem; enqueue khác insert đầu list làm index trỏ sang item khác. Lượt start mới cùng ID thay `_clients[id]`, nhưng finally của request cũ remove/close client hiện tại, và catch cũ vẫn đánh failed item mới.
- **Tái hiện theo lịch mã:** A giữ index=0 rồi chờ `_directory()`; B insert index=0; A resume `_replace(0, A)` làm mất B/trùng A. Hoặc start lại A cùng ID, để catch/finally request cũ chạy sau khi client mới được gán → client mới bị đóng.
- **Ảnh hưởng:** mất job, sai manifest, retry thất bại và state bị ghi đè không xác định.
- **Khắc phục:** quản lý bằng map keyed theo ID hoặc lookup lại ngay trước mutation; generation/client identity guard cho success/catch/finally. Serialize ghi manifest và dùng atomic rename; cleanup chỉ client/file thuộc generation hiện tại.
- **Kiểm thử hồi quy đề xuất:** fake filesystem/network có barrier; enqueue A/B bảo toàn hai ID; finally cũ không đóng client retry mới.
- **Trạng thái:** mã Dart được đối chiếu với mô hình lịch chạy bằng JavaScript đã cho list [A,A] và client mới bị đóng. Đây mô hình interleaving, không phải chạy code Dart/Flutter; chưa xác minh trên thiết bị.

### BUG-014 — CSV export cho phép dữ liệu user trở thành công thức

- **Bằng chứng:** [admin-videos.service.ts:259](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos.service.ts:259)–272; [admin-channels.service.ts:193](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels.service.ts:193)–206; title hợp lệ tại [ContentService.cs:629](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:629)–630.
- **Điều kiện:** admin xuất CSV có title/tên kênh/tên user do người dùng kiểm soát, rồi mở bằng spreadsheet có đánh giá công thức.
- **Cách xảy ra:** escape dấu nháy và bọc CSV không trung hòa các prefix công thức `=`, `+`, `-`, `@`. Một title `=1+1` hợp lệ được xuất thành ô `"=1+1"`.
- **Tái hiện an toàn:** tạo title `=1+1` trên dữ liệu thử, export CSV, mở bằng Excel/Calc; tùy phần mềm/cấu hình ô được coi là công thức thay vì title.
- **Ảnh hưởng:** giả mạo dữ liệu báo cáo; công thức độc hại có thể tạo link/lời mời hoặc ngoại gửi dữ liệu tùy phần mềm và thiết lập. Chưa chứng minh thực thi mã hoặc exfiltration trong môi trường người dùng.
- **Khắc phục:** ưu tiên XLSX với cell type string; nếu giữ CSV, trung hòa prefix nguy hiểm và control character trước khi quote theo chính sách spreadsheet mục tiêu. Kiểm tra cả title, channelName, ownerName và các cột text khác.
- **Kiểm thử hồi quy đề xuất:** `=1+1`, `+1+1`, `@...`, newline/tab và dấu nháy phải còn là text khi mở và lưu/mở lại.
- **Trạng thái:** exporter TypeScript thật với Blob/download mock đã giữ nguyên ô `"=1+1"`; chưa mở Excel/Calc và chưa chứng minh tác động ngoại gửi dữ liệu.

### BUG-015 — Admin hiển thị chứng cứ và số liệu giả khi API lỗi

- **Bằng chứng:** [admin-videos-page.ts:274](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.ts:274)–319; [admin-videos-page.html:523](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:523)–527, [admin-videos-page.html:575](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:575)–585, [admin-videos-page.html:612](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:612)–620; [admin-channels.service.ts:114](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels.service.ts:114)–148.
- **Điều kiện:** GET chi tiết video/count kênh lỗi mạng, 403 hoặc 500.
- **Cách xảy ra:** callback error tạo detail gắn với video thật nhưng URL BigBuckBunny, duration/filesize mẫu, audit “AI Moderation Bot” và báo cáo user mẫu. Count lỗi trả các số cố định 12568/10432/856/1280. UI dùng các dữ liệu đó như dữ liệu thực, không có nhãn lỗi/demo.
- **Tái hiện:** mock GET `/api/v1/admin/videos/{id}` trả 500 trong dev; mở Preview. Video và bằng chứng mẫu vẫn hiện dưới video đã chọn. Mock count trả lỗi sẽ hiện số cố định.
- **Ảnh hưởng:** quản trị viên có thể quyết định kiểm duyệt dựa trên video/chứng cứ không liên quan; outage hoặc thiếu quyền bị che giấu bằng số liệu sai.
- **Khắc phục:** giữ detail null, hiện unavailable + retry và vô hiệu hóa quyết định cần evidence; count hiển thị không có dữ liệu khi lỗi. Fixture/demo nằm trong chế độ riêng có nhãn rõ ràng.
- **Kiểm thử hồi quy đề xuất:** 403/500/network không tạo detail/audit/report giả, không phát video mẫu và không hiện count mẫu.
- **Trạng thái:** class TypeScript thật với HTTP mock trả lỗi đã tạo URL/duration/audit/report mẫu; template được đối chiếu bằng mã. Không mở URL video mẫu hoặc kết nối dịch vụ thật.

### BUG-016 — Recovery rendition có thể lấy source của video khác

- **Bằng chứng:** [VideoRenditionProcessing.cs:139](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoRenditionProcessing.cs:139)–159, [VideoRenditionProcessing.cs:204](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoRenditionProcessing.cs:204)–209, [VideoRenditionProcessing.cs:254](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoRenditionProcessing.cs:254)–291.
- **Điều kiện:** job phục hồi thiếu workingDirectory/sourcePath; thư mục temp của video A có source cùng byte size với video B đang cần phục hồi. Có thể A vẫn đang xử lý.
- **Cách xảy ra:** discovery quét các workspace và chọn theo File.Length; helper cũng coi cùng size là source hợp lệ, không xác minh videoId/hash. Rendition được lưu theo ID B và finally xóa toàn workspace đã chọn.
- **Tái hiện đã thực hiện trước yêu cầu chỉ xem code:** fixture riêng chứa `VIDEO-A-PRIVATE`; helper nhận metadata B cùng fileSize và trả đúng bytes A, không gọi network. Đường discovery/xóa workspace được xác minh qua mã, không chạy trên thư mục temp thật.
- **Ảnh hưởng:** gán nội dung A cho video B, có thể lộ media của chủ khác; xóa workspace A và làm hỏng job A.
- **Khắc phục:** workspace keyed theo videoId/jobId, manifest source có identity/checksum; recovery chỉ sử dụng workspace thuộc chính job. Không tìm file theo kích thước. Chỉ xóa thư mục có ownership xác nhận và không còn job sử dụng.
- **Kiểm thử hồi quy đề xuất:** hai source khác nhau cùng kích thước phải không dùng lẫn; restart/retry giữ đúng identity; cleanup B không đụng A.
- **Trạng thái:** proof chạy helper thật trên fixture riêng; ảnh hưởng end-to-end được suy ra từ đường mã, chưa chạy encoder thật.

### BUG-017 — Hub thông báo và state không đổi theo tài khoản web

- **Bằng chứng:** [notification.service.ts:12](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/notification.service.ts:12)–55, [notification.service.ts:74](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/notification.service.ts:74)–98; [auth.service.ts:139](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/auth.service.ts:139); [AuthController.cs:80](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/AuthController.cs:80)–100; [NotificationHub.cs:12](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Notifications/NotificationHub.cs:12)–18; [Program.cs:233](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Program.cs:233).
- **Điều kiện:** A đăng nhập và mở hub; logout rồi B đăng nhập trong cùng SPA, connection chưa disconnect.
- **Cách xảy ra:** service singleton không có teardown khi clear auth; `connect()` return nếu connection đã tồn tại. Hub cũ vẫn gắn sub của A, callbacks đưa thông báo vào chung items. Poll cũng merge mà không guard phiên. DB revoke không tự đóng connection đã xác thực; event SessionRevoked chỉ yêu cầu client tự clear.
- **Tái hiện đã có:** harness chạy class TypeScript thật với hub/router/http mock: sau A → B chỉ có một hub bound A; push A xuất hiện khi user là B; event revoke A còn clear phiên B. Đây là proof state/lifecycle, chưa là thử transport SignalR thật.
- **Ảnh hưởng:** lộ thông báo/nội dung riêng của A cho B; phiên B có thể bị đăng xuất do sự kiện dành cho A. Connection bị đánh cắp cũng chưa có cơ chế server thu hồi tức thì.
- **Khắc phục:** theo dõi identity/session; stop connection, clear timers/items/cache và hủy request khi logout/đổi user; callbacks guard generation. Backend quản lý connection theo session để disconnect khi revoke và cấu hình đóng khi authentication hết hạn phù hợp.
- **Kiểm thử hồi quy đề xuất:** A → logout → B tạo hub B; callback/poll/event A đến muộn bị bỏ; revoke session phải chặn tiếp nhận trên connection của session đó.
- **Trạng thái:** tái hiện logic TypeScript với mock; server lifecycle xác minh qua mã và [tài liệu authentication SignalR của Microsoft](https://learn.microsoft.com/en-us/aspnet/core/signalr/authn-and-authz?view=aspnetcore-10.0), đã đối chiếu trước yêu cầu chỉ xem code. Chưa thử transport/revocation thật.

### BUG-018 — Restart API làm mất resume chunk và tích lũy file orphan

- **Bằng chứng:** [CfSeedChunkUploadStore.cs:14](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Services/CfSeedChunkUploadStore.cs:14)–23, [CfSeedChunkUploadStore.cs:25](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Services/CfSeedChunkUploadStore.cs:25)–53, [CfSeedChunkUploadStore.cs:149](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Services/CfSeedChunkUploadStore.cs:149)–160.
- **Điều kiện:** người có quyền CF seed upload một phần video rồi API restart/deploy trước complete.
- **Cách xảy ra:** session/offset chỉ ở ConcurrentDictionary RAM. Instance mới không đọc metadata từ disk; Require trả 404. CleanupExpired chỉ duyệt dictionary hiện tại nên file `.upload` cũ không được xét TTL hoặc dọn.
- **Tái hiện đã có:** upload chunk 1 byte trong TEMP riêng; tạo instance mới → session cũ 404, file vẫn còn; Start mới không dọn orphan. Limit 256 GiB từng file không tạo budget tổng cho temp disk.
- **Ảnh hưởng:** phải upload lại, file dang dở tồn tại qua các lần restart và có thể làm đầy volume. Endpoint có quyền quản trị nên đây không phải tấn công anonymous.
- **Khắc phục:** persist/reconcile session và offset hoặc cleanup rõ lúc startup; janitor định kỳ quét orphan phối hợp lock, endpoint cancel, giới hạn disk/user/tổng. Khi scale phải chia sẻ store hoặc định tuyến phiên có chủ đích.
- **Kiểm thử hồi quy đề xuất:** restart giữa chunk có resume hoặc hủy/dọn đúng contract; orphan quá TTL được dọn; không xóa file đang xử lý; budget tổng được áp dụng.
- **Trạng thái:** proof chạy source thật với file nhỏ trong thư mục riêng, không DB/R2.

### BUG-019 — Suspend/ban kênh không được áp dụng ở quyền đọc media

- **Bằng chứng:** [ContentService.cs:1644](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1644)–1649, [ContentService.cs:215](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:215)–223 và các public feed/search predicates; thay channel status tại [AdminContentService.cs:434](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AdminContentService.cs:434) và [StrikeService.cs:350](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/StrikeService.cs:350).
- **Điều kiện:** kênh bị suspended/banned nhưng có video còn published, approved, public.
- **Cách xảy ra:** public access xét trạng thái video và trả trước khi xét channel. Feed/search join channel nhưng không yêu cầu channel active. Thay channel status không tự thay mọi video.
- **Tái hiện đã có:** harness đặt channel.Status=suspended, gọi GetVideo anonymous vẫn thành công và được cấp URL source mới. Ban có cùng thiếu predicate channel ở đường đọc.
- **Ảnh hưởng:** quyết định đình chỉ/khóa kênh không chặn nội dung công khai như trạng thái thể hiện; video vẫn có thể được tìm và phát.
- **Khắc phục:** dùng một policy public catalogue/media yêu cầu channel active trên detail/playback/feed/search/download. Tách ngoại lệ quản lý của owner/admin khỏi quyền public.
- **Kiểm thử hồi quy đề xuất:** suspended/banned không xuất hiện ở discovery và không cấp URL mới cho viewer công khai; luồng quản lý được phép vẫn hoạt động.
- **Trạng thái:** suspended detail tái hiện service có fake storage; các nhánh discovery/ban xác minh qua mã.

### BUG-020 — Xóa video không phục hồi dung lượng và không có purge cho trạng thái deleted

- **Bằng chứng:** [ContentService.cs:1001](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1001)–1006; [VideoMediaRetentionCleanupService.cs:61](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoMediaRetentionCleanupService.cs:61)–71, [VideoMediaRetentionCleanupService.cs:95](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoMediaRetentionCleanupService.cs:95)–107.
- **Điều kiện:** owner xóa video đã chiếm quota, hoặc media bị purge sau moderation.
- **Cách xảy ra:** delete chỉ soft-delete, không đặt retention/purge schedule. Worker chỉ chọn blocked+rejected nên video deleted không có đường dọn. Ngay cả nhánh purge của worker cũng không hoàn ChannelQuota.StorageUsed.
- **Tái hiện đã có:** video size=100, quota used=100; DeleteVideo → status deleted nhưng used vẫn100 và fake storage ghi nhận 0 delete. Rà soát worker xác nhận deleted không thuộc tập cleanup.
- **Ảnh hưởng:** người dùng xóa video nhưng quota có thể đầy mãi; media deleted tích lũy chi phí. Soft-delete có retention là hợp lý, nhưng cần vòng đời kết thúc và hoàn quota đúng thời điểm.
- **Khắc phục:** định nghĩa retained/deleted/purged rõ; xếp lịch dọn tất cả assets cho deleted theo retention; release quota đúng một lần khi chính sách cho phép, có transaction/marker và job idempotent. Không giảm quota rồi vẫn cho lưu object vô hạn.
- **Kiểm thử hồi quy đề xuất:** delete → retention → purge → quota giảm đúng; retry purge không giảm lần hai; appeal/restore trong retention bảo toàn tài nguyên cần thiết.
- **Trạng thái:** hành vi delete tái hiện với fake storage; vòng đời cleanup xác minh mã.

### BUG-021 — Purge xóa media nhưng SaveChanges thất bại vì URL rỗng

- **Bằng chứng:** [VideoMediaRetentionCleanupService.cs:95](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoMediaRetentionCleanupService.cs:95)–105, [VideoMediaRetentionCleanupService.cs:121](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/VideoMediaRetentionCleanupService.cs:121); SQL dùng bởi EF bootstrap [Bootstrap.sql:410](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/Migrations/Bootstrap.sql:410) và bản SQL [up.sql:371](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/database/migrations/20260905_bootstrap/up.sql:371) có CHECK `char_length(btrim(video_url)) > 0`; migration [20260925150000_VideoMediaRetention.cs](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/Migrations/20260925150000_VideoMediaRetention.cs) chỉ thêm retention/purge columns.
- **Điều kiện:** database có CHECK từ bootstrap/migration hiện hành, worker xử lý media hết hạn.
- **Cách xảy ra:** worker xóa object vật lý trước, đặt VideoUrl="", rồi SaveChanges. Giá trị rỗng vi phạm CHECK; MediaPurgedAt không commit dù object đã mất. Một hàng lỗi còn làm SaveChanges của batch thất bại.
- **Tái hiện qua mã/schema:** đối chiếu giá trị ghi ở worker với CHECK. Không chạy purge hoặc thử CHECK trên database thật; InMemory test không mô phỏng CHECK PostgreSQL.
- **Ảnh hưởng:** mất nguồn nhưng database vẫn ghi chưa purge, retry định kỳ và audit/log sai; các video trong cùng batch có thể bị ảnh hưởng commit trạng thái.
- **Khắc phục:** migration cho trạng thái media_purged dùng URL nullable hoặc CHECK có điều kiện hợp lệ; dùng state machine/outbox cho thao tác storage ngoài transaction; lưu tiến độ purge và retry idempotent, chỉ báo thành công khi DB xác nhận.
- **Kiểm thử hồi quy đề xuất:** PostgreSQL thử riêng giữ đúng CHECK hiện hành; purge phải commit MediaPurgedAt và URL đúng schema; lỗi DB/storage không làm mất dấu tiến độ.
- **Trạng thái:** xác minh mã và schema, chưa chạy trên PostgreSQL.

### BUG-022 — Route report comment cũ tạo hồ sơ ngoài workflow đang dùng

- **Bằng chứng:** [ContentService.cs:1342](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1342)–1360; [ReportService.cs:379](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:379), [ReportService.cs:688](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:688)–690, [ReportService.cs:779](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:779); fallback tại [content.service.ts:171](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/content.service.ts:171)–173.
- **Điều kiện:** client dùng route report comment legacy, hoặc route `/reports` lỗi và frontend fallback.
- **Cách xảy ra:** tạo Report và caseType=`report_review` nhưng không gán ModerationCaseId/TargetType/TargetId theo grouped report workflow. Queue hiện tại chỉ dùng `report_case`; legacy resolve yêu cầu workflow mới và trả 409. Migration backfill chỉ sửa dữ liệu trước thời điểm chạy.
- **Tái hiện đã có:** gọi service legacy với comment thử; Report.ModerationCaseId=null và case mới là report_review. Đối chiếu query queue và resolve cho thấy hồ sơ không đi qua luồng xử lý hiện hành.
- **Ảnh hưởng:** client nhận thành công nhưng báo cáo không được xử lý đúng queue; người dùng tưởng đã gửi báo cáo hợp lệ.
- **Khắc phục:** route legacy delegate service CreateReportAsync(target=comment) cùng idempotency; bỏ logic tạo case cũ và backfill các hàng lỗi mới sinh. Fallback client chỉ dùng khi contract thật sự tương thích.
- **Kiểm thử hồi quy đề xuất:** cả hai route tạo đúng grouped case, vào queue và resolve được; retry không nhân đôi report.
- **Trạng thái:** tạo record tái hiện bằng service/InMemory; query workflow xác minh mã.

### BUG-023 — Metadata media do client khai được dùng làm căn cứ giới hạn upload

- **Bằng chứng:** [ContentControllers.cs:90](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:90)–93, [ContentControllers.cs:145](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:145)–146; [ContentService.cs:830](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:830)–835, [ContentService.cs:702](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:702), [ContentService.cs:744](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:744)–746.
- **Điều kiện:** bật PlanEnforcement; client gửi file chất lượng/thời lượng vượt gói nhưng khai SourceQuality/Duration thấp hơn.
- **Cách xảy ra:** preflight kiểm tra các giá trị form, không lấy metadata authoritative từ file. Source rendition được đánh Height từ SourceQuality đã khai; Duration lưu trực tiếp. Encoder tạo rendition thấp hơn nhưng không sửa/kiểm định lại metadata source trước cấp URL.
- **Tái hiện bằng đường mã:** file 2160p dài vượt hạn, khai 360p/duration=1. Nếu size vẫn hợp lệ, điều kiện quality/duration vượt gói không thấy media thật; record source Height=360 lọt filter playback ≤720 dù bytes thực là 2160p.
- **Ảnh hưởng:** vượt giới hạn thời lượng/chất lượng, lệch chapters/progress/thống kê; độc lập với lỗi BUG-004 vì metadata sai còn làm rendition filter mất tác dụng.
- **Khắc phục:** ffprobe/decoder worker đo duration, dimensions, MIME authoritative; chỉ ready/publish sau khi validate metadata thật với quyền lợi gói. Preflight là ước lượng UX, không phải bằng chứng media hợp lệ.
- **Kiểm thử hồi quy đề xuất:** metadata form sai phải bị từ chối hoặc sửa theo file; sourceHeight/duration lưu bằng giá trị được kiểm định.
- **Trạng thái:** xác minh argument/data flow; chưa encode file thật.

### BUG-024 — Quyết định “hạn chế đề xuất” không được thực thi ở discovery

- **Bằng chứng:** ghi flag tại [ModerationService.cs:210](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ModerationService.cs:210)–224, [ReportService.cs:701](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:701)–711; public predicates tại [ContentService.cs:82](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:82)–86, [ContentService.cs:215](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:215)–223, [ContentService.cs:307](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:307), [ContentService.cs:403](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:403).
- **Điều kiện:** video approved/public bị gắn `Metadata.recommendation_restricted=true`.
- **Cách xảy ra:** repository search trong backend/recommendation app tìm thấy các nơi ghi flag, không có nơi đọc flag để loại ứng viên. Video vẫn thỏa published/approved/public ở Home/Explore/fallback.
- **Tái hiện theo query:** áp dụng decision rồi xét các predicates public/feed: không predicate nào loại video vì flag; notification lại thông báo đã hạn chế đề xuất.
- **Ảnh hưởng:** quyết định moderator có tên/notification nhưng video vẫn được đưa vào discovery; không chỉ creator xóa flag như BUG-009, ngay cả flag còn nguyên cũng chưa được thực thi.
- **Khắc phục:** dùng trường policy riêng có index nếu cần; áp dụng trên training catalogue, inference candidates và mọi live fallback/Home/Explore. Cho phép direct link theo policy nếu sản phẩm muốn, nhưng discovery phải tuân quyết định.
- **Kiểm thử hồi quy đề xuất:** flag vẫn true, detail đúng policy nhưng Home/Explore/trending/fallback không trả video; gỡ restriction hợp lệ mới xuất hiện lại.
- **Trạng thái:** xác minh bằng tìm kiếm toàn bộ đường đọc/ghi và predicates hiện hành.

### BUG-025 — Report API làm lộ nội dung target mà caller không được xem

- **Bằng chứng:** [ReportService.cs:69](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:69)–80, [ReportService.cs:191](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:191)–197.
- **Điều kiện:** user biết ID video private/không khả dụng hoặc comment thuộc nội dung không được xem.
- **Cách xảy ra:** report service chỉ kiểm tra target tồn tại, không kiểm tra viewer; trả TargetTitle hoặc 50 ký tự đầu comment trong DTO thành công.
- **Tái hiện đã có:** GetVideo của reader bị 403; CreateReport với cùng private ID vẫn thành công và trả tiêu đề private từ fake dataset.
- **Ảnh hưởng:** lộ tiêu đề/nội dung qua endpoint khác và tạo report không đủ ngữ cảnh/quyền đọc.
- **Khắc phục:** dùng visibility/access policy trước đọc/copy metadata, hoặc nhận report opaque không trả nội dung target khi policy cho phép báo cáo chỉ qua ID. Idempotency/rate limit không thay thế resource authorization.
- **Kiểm thử hồi quy đề xuất:** user không được xem không nhận title/content từ create/list report; user được phép report vẫn hoạt động.
- **Trạng thái:** tái hiện service với dữ liệu giả; không đọc nội dung người dùng thật.

### BUG-026 — Separation of duties bỏ sót moderation case dạng target

- **Bằng chứng:** [AppealService.cs:53](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AppealService.cs:53)–59, [AppealService.cs:570](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AppealService.cs:570)–587; report case dùng TargetType/TargetId tại [ReportService.cs:146](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:146)–148.
- **Điều kiện:** moderator M remove video thông qua report_case có VideoId=null, TargetType=video, TargetId=V; appeal không gửi linked case ID.
- **Cách xảy ra:** tự tìm case và original reviewer bằng `m.VideoId == V`, bỏ qua case dùng TargetId. Guard linked case cũng không hoạt động khi lookup không tìm được case; M được duyệt appeal cho quyết định của chính mình.
- **Tái hiện đã có:** seed case report remove của M, owner tạo appeal theo contract mặc định, M resolve approved → video published/approved; guard `CANNOT_RESOLVE_OWN_CASE` không kích hoạt.
- **Ảnh hưởng:** phá vỡ kiểm soát người xử lý độc lập của quy trình appeal, cho phép tự đảo quyết định mà hệ thống dự định cấm.
- **Khắc phục:** appeal gắn enforcement/case chuẩn do server suy ra, kiểm tra cả target và legacy VideoId; verify supplied case ID đúng target/quyết định. Dùng cùng lookup cho create/claim/resolve.
- **Kiểm thử hồi quy đề xuất:** original reviewer luôn bị cấm với upload_case/report_case, có/không linked ID; moderator độc lập được xử lý.
- **Trạng thái:** tái hiện service với InMemory/fake dependencies; chưa gọi API thật.

### BUG-027 — Simulator không duy trì tỷ lệ danh mục đã chọn

- **Bằng chứng:** [RecommendationAdminService.cs:597](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:597)–610, [RecommendationAdminService.cs:738](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:738)–760.
- **Điều kiện:** cấu hình categoryRates có tỷ lệ không đồng đều, số video mỗi danh mục nhỏ so với actionsPerUser.
- **Cách xảy ra:** weighted draw chỉ đưa danh mục còn video vào danh sách. Pool chỉ reset khi tất cả danh mục hết, nên danh mục vừa cạn bị loại khỏi tỷ lệ trong các lượt tiếp theo.
- **Tái hiện đã có:** A=80%, B=20%, mỗi danh mục một video, 100 lượt → 50A/50B tất định. Inventory 1A/9B, 10 lượt → 1A/9B dù yêu cầu 80/20. Đây không phải sai số ngẫu nhiên thông thường.
- **Ảnh hưởng:** dữ liệu bot không thể hiện persona/tỷ lệ cấu hình, làm lệch ma trận và kết quả đánh giá CF.
- **Khắc phục:** bốc category trên toàn weights mỗi lượt rồi refill riêng category được chọn; nếu cần tỷ lệ chính xác trên hữu hạn lượt, phân bổ số lượt theo largest-remainder rồi shuffle.
- **Kiểm thử hồi quy đề xuất:** các inventory 1/1 và 1/9 với cấu hình 80/20; kiểm tra phân phối sau nhiều chu kỳ và điều kiện refill.
- **Trạng thái:** helper nguyên logic nguồn chạy bằng dữ liệu giả trước yêu cầu code-only; không chạy simulator trên tài khoản thật.

### BUG-028 — Job model mất trạng thái bền vững sau restart

- **Bằng chứng:** [model_registry.py:137](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/model_registry.py:137)–138; [api.py:157](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/api.py:157)–183; [RecommendationAdminService.cs:474](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:474)–477, [RecommendationAdminService.cs:515](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:515)–539.
- **Điều kiện:** Python đã ghi model mới vào active manifest nhưng restart trước lần .NET poll tiếp theo.
- **Cách xảy ra:** update_jobs chỉ nằm trong RAM. Python restart vẫn nạp model mới từ R2 nhưng không tìm thấy jobId cũ; .NET coi polling 404 là lỗi và đánh failed trước bước verify manifest.
- **Tái hiện đã có:** FakeR2 và registry/API thật: trước restart job completed; registry mới load đúng version active; cùng jobId trả404. Luồng .NET đối chiếu xác nhận kết luận failed trước reconcile.
- **Ảnh hưởng:** trạng thái/audit admin sai với model đang phục vụ, cleanup CSV bị bỏ và người vận hành có thể chạy cập nhật lặp không cần thiết.
- **Khắc phục:** lưu job/outcome bền vững với CSV hash/key/config/modelVersion; lưu serviceJobId trong DB .NET để resume. Khi poll mất job hoặc disconnect, reconcile manifest đúng hash/config trước kết luận thất bại.
- **Kiểm thử hồi quy đề xuất:** restart trước/sau publish; chỉ completed nếu đúng manifest; job failed thật giữ đủ nguyên nhân và có retry an toàn.
- **Trạng thái:** Python/FakeR2 tái hiện; .NET outcome xác minh mã, không restart dịch vụ thật.

### BUG-029 — Replica Python không đồng bộ model/job/lock

- **Bằng chứng:** [main.py:20](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/main.py:20)–23; [model_registry.py:133](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/model_registry.py:133)–138, [model_registry.py:251](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/model_registry.py:251)–253; [api.py:110](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/api.py:110)–120, [api.py:180](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/api.py:180)–183.
- **Điều kiện bắt buộc:** ít nhất hai Python worker/replica hoặc khoảng chồng lấn khi rolling deploy. Docker hiện dùng một worker; không khẳng định cấu hình đang chạy có nhiều replica.
- **Cách xảy ra:** mỗi process chỉ load manifest lúc startup; train trên A chỉ thay registry A. B giữ model trước đó không có poll/invalidation. Jobs và threading.Lock cũng riêng từng process; poll đến B không thấy job A.
- **Tái hiện đã có:** hai registry cùng FakeR2 load V1, A publish V2; A khớp active, B vẫn V1. Đây mô phỏng hai registry, chưa là test load balancer thật.
- **Ảnh hưởng:** recommendation tùy instance, poll lỗi ngẫu nhiên; train trên hai process có thể tranh publication vì lock không dùng chung.
- **Khắc phục:** distributed trainer lease, shared durable jobs; inference atomically reload khi manifest version đổi bằng polling/pubsub. Nếu chưa hỗ trợ scale thì enforce một instance/worker và ghi rõ giới hạn vận hành.
- **Kiểm thử hồi quy đề xuất:** hai replicas đồng bộ version sau publish, polling không phụ thuộc routing, chỉ một trainer giữ quyền publish.
- **Trạng thái:** proof registry có fake storage; điều kiện triển khai cần xác minh riêng.

### BUG-030 — Worker .NET claim job không atomic và recovery không xét owner

- **Bằng chứng:** [RecommendationJobWorker.cs:17](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationJobWorker.cs:17)–24, [RecommendationJobWorker.cs:35](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationJobWorker.cs:35)–42; EF model tại [HuTubeDbContext.cs:86](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/HuTubeDbContext.cs:86)–100; simulator check tại [RecommendationAdminService.cs:606](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:606)–607.
- **Điều kiện bắt buộc:** hai API instances/workers hoặc chồng lấn deploy; một worker tuần tự đơn lẻ không tự gây double claim.
- **Cách xảy ra:** SELECT queued và UPDATE running là hai bước, UPDATE không yêu cầu status vẫn queued hoặc rowversion. Hai worker cùng chọn một hàng sẽ cùng ProcessAsync. Startup còn đánh failed mọi running, không xét owner/lease của worker khác đang sống.
- **Tái hiện theo lịch mã:** W1 và W2 đọc cùng J queued; W1 save running; W2 save running theo PK; cả hai chạy J. Hoặc W2 startup khi W1 đang chạy và đổi J failed; W1 vẫn tiếp tục vì chỉ dừng trạng thái cancelling.
- **Ảnh hưởng:** nhân đôi side effects mô phỏng, progress ghi đè, trạng thái/audit sai; active job unique index bị nhả khi công việc cũ chưa thực sự dừng. Index chống hai hàng model_update không ngăn hai worker xử lý cùng một hàng.
- **Khắc phục:** conditional UPDATE queued→running RETURNING hoặc FOR UPDATE SKIP LOCKED; owner/lease/heartbeat; chỉ recovery lease hết hạn. Side effects idempotent theo job/action, progress có concurrency guard.
- **Kiểm thử hồi quy đề xuất:** hai worker chỉ một người claim J; khởi động instance mới không fail job có lease sống; recover được worker đã chết.
- **Trạng thái:** static schedule và schema; chưa chạy nhiều instance hoặc database thật.

### BUG-031 — Preview/export ma trận dùng average khi model active dùng weighted

- **Bằng chứng:** [RecommendationAdminService.cs:224](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:224)–229, [RecommendationAdminService.cs:257](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:257)–258, [RecommendationAdminService.cs:291](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:291)–296, [RecommendationAdminService.cs:485](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:485)–490; contract vận hành tại [RECOMMENDATIONS.md:5](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/operations/RECOMMENDATIONS.md:5)–9.
- **Điều kiện:** active model được huấn luyện với weighted, trọng số không bằng nhau.
- **Cách xảy ra:** Diff dùng active.ScoreAggregation và training dùng payload, nhưng preview/export luôn gọi DefaultScoreAggregation (average), không nêu chế độ riêng trong CSV/preview contract.
- **Tái hiện đã có:** tín hiệu rating5, like, watch20%; weights rating10/like1/watch1 → score0.9333. Cùng dữ liệu export/preview average →0.7333.
- **Ảnh hưởng:** ma trận tải/xem không tương ứng cấu hình đang kiểm chứng; tái lập model local bằng CSV export có thể ra kết quả khác dù dữ liệu nguồn không đổi.
- **Khắc phục:** preview/export dùng cùng score config với Diff/training hoặc cho chọn config và trả metadata rõ. Nếu chủ đích export average tham chiếu, UI/contract phải nói rõ và cung cấp export theo active config để tái lập.
- **Kiểm thử hồi quy đề xuất:** weighted active cho cùng score ở preview, export, diff và snapshot; xác nhận metadata cấu hình đi kèm.
- **Trạng thái:** helper score đã chạy với dữ liệu giả và call sites được đối chiếu; không retrain model thật.

### BUG-032 — Trọng số lớn được nhận nhưng làm tính điểm overflow

- **Bằng chứng:** [RecommendationAdminService.cs:68](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:68)–79, [RecommendationAdminService.cs:114](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Recommendations/RecommendationAdminService.cs:114)–123.
- **Điều kiện:** Super Admin gửi ít nhất hai trọng số lớn gần decimal.MaxValue; dữ liệu có tín hiệu tương ứng. Đây cấu hình quản trị bất thường, mức P3.
- **Cách xảy ra:** validation chỉ kiểm tra nonnegative/nonzero; cộng total và totalWeight vượt range decimal. Job đã được nhận mới failed thay vì bị validation từ chối.
- **Tái hiện đã có:** rating và like cùng decimal.MaxValue qua guard, row rating5+like ném OverflowException. Cùng tỷ lệ 1:1 với trọng số1/1 hợp lệ.
- **Ảnh hưởng:** cấu hình API coi hợp lệ không train được, lỗi xảy ra muộn và mất công đợi job; không phải đường truy cập anonymous.
- **Khắc phục:** chuẩn hóa từng weight theo max trước khi cộng (score bất biến theo scale), hoặc đặt giới hạn an toàn và trả400 sớm. Không cộng tổng chưa chuẩn hóa để kiểm tra chính overflow đó.
- **Kiểm thử hồi quy đề xuất:** input cực lớn được normalize đúng hoặc reject400; input tỷ lệ tương đương cho cùng score.
- **Trạng thái:** proof helper nguyên logic trước yêu cầu code-only.

### BUG-033 — CF không tự phục hồi khi R2 lỗi thoáng qua ở startup

- **Bằng chứng:** [main.py:20](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/main.py:20)–23; [model_registry.py:149](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/model_registry.py:149)–177; [api.py:46](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/api.py:46)–68, [api.py:110](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/recommendation-service/app/api.py:110)–117; [render.yaml:95](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/render.yaml:95).
- **Điều kiện:** request R2 active manifest/artifact lỗi tạm thời khi service khởi động; storage sau đó hoạt động lại.
- **Cách xảy ra:** load chỉ một lần; lỗi bị catch với loaded vẫn None. Health liveness vẫn200; ready/inference trả503 nhưng không kích hoạt retry/load. Deployment dùng `/health` nên không phản ánh trạng thái CF chưa sẵn sàng.
- **Tái hiện đã có:** FakeR2 lỗi đúng một lần, rồi khôi phục; health200, ready503, inference503 và registry vẫn chưa initialized. Gọi load thủ công mới phục hồi.
- **Ảnh hưởng:** lỗi hạ tầng ngắn biến thành mất CF kéo dài cho đến restart/retrain; .NET dùng fallback mà model tốt trên R2 chưa được nạp lại.
- **Khắc phục:** bounded startup retry/backoff và background retry khi chưa có model; giữ last-known-good khi reload thất bại; readiness/alert theo khả năng phục vụ CF, thêm recovery được xác thực nếu cần.
- **Kiểm thử hồi quy đề xuất:** transient fail→storage recovered tự trở lại ready, không cần retrain; lỗi kéo dài có backoff giới hạn và trạng thái rõ.
- **Trạng thái:** FakeR2/API thật đã mô phỏng trước yêu cầu code-only, không thao tác R2 thật.

### BUG-034 — CF pagination và phần bù không tạo một danh sách ổn định

- **Bằng chứng:** [ContentService.cs:207](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:207), [ContentService.cs:219](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:219)–223, [ContentService.cs:238](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:238)–252 và fallback query sau đó.
- **Điều kiện:** ranking model có một số video không còn public/eligible; người dùng tải nhiều trang. Ranking không cần thay đổi giữa hai request.
- **Cách xảy ra:** mỗi page xin prefix lớn dần, lọc invalid rồi Skip theo offset của danh sách sau lọc. Fallback excludes và fallbackSkip cũng tính theo prefix mới, không theo toàn danh sách đã trả trước đó.
- **Tái hiện theo dữ liệu:** pageSize20, top20 có5 invalid → page1 trả15 recommendation + F0..F4. Page2 xin top40, còn35 valid rồi Skip20 → bỏ qua5 recommendation chưa từng hiện ở page1, trả15 recommendation tiếp + fallback có thể lại F0..F4. Nếu filler trước thuộc phần model prefix mới, sự thay đổi excludes còn làm tính offset lệch theo cách khác.
- **Ảnh hưởng:** mất video giữa các trang và trùng video bù, làm infinite scroll/recommendation không ổn định ngay với snapshot cố định.
- **Khắc phục:** cursor/snapshot của một ordered eligible catalogue cố định; hoặc overfetch để đủ eligible offset+size trước paging, với tập fallback cố định và offset dựa số filler đã trả. Tách candidate policy khỏi pagination nhưng dùng cùng snapshot.
- **Kiểm thử hồi quy đề xuất:** ranking cố định có invalid ở đầu, nhiều page không trùng/mất; fallback ít/nhiều hơn pageSize; đủ điều kiện catalogue thay đổi được xử lý theo contract cursor.
- **Trạng thái:** worked example từ query hiện hành, không chạy feed thật.

### BUG-035 — Thanh toán và kích hoạt gói không được commit nguyên tử

- **Bằng chứng:** [PaymentService.cs:83](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:83)–125; [PlanService.cs:307](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Plans/PlanService.cs:307)–344.
- **Điều kiện:** process/DB lỗi sau ActivatePaidPlanAsync commit nhưng trước payment SaveChanges, hoặc hai webhook hợp lệ trùng đến đồng thời.
- **Cách xảy ra:** dedupe/pending là read-check riêng, không khóa payment. PlanService có transaction riêng và commit entitlement trước; payment paid/transactionId/historyId được save sau bằng giao dịch khác. Unique gateway ID không ngăn hai request cùng cập nhật một payment row đã cùng đọc pending.
- **Tái hiện theo lịch mã:** request1 commit PlanHistory/User/quota, ngắt trước payment save → DB có gói active nhưng payment vẫn pending. Retry không thấy paid và kích hoạt lại. Hai request đồng thời cũng có thể cùng qua checks và tạo nhiều histories.
- **Ảnh hưởng:** ledger/payment lệch entitlement, kích hoạt lặp, hết hạn/histories/audit không nhất quán; khó đối soát sau crash.
- **Khắc phục:** một transaction tại orchestration thanh toán bao gồm claim giao dịch, trạng thái payment và cấp entitlement; row lock/conditional transition pending→paid, unique payment reference cho activation. Service con không tự commit giao dịch độc lập; notification qua outbox sau commit.
- **Kiểm thử hồi quy đề xuất:** lỗi ở mọi điểm không tạo partial state; webhook cùng ID/song song chỉ kích hoạt một lần; retry sau crash trả trạng thái đúng.
- **Trạng thái:** static transaction/interleaving trace; unit test PaymentService đang mock PlanService nên không kiểm tra ranh giới commit thật.

### BUG-036 — Idempotency payment không khớp phạm vi unique của database

- **Bằng chứng:** [PaymentService.cs:34](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:34)–70; [HuTubeDbContext.cs:184](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/HuTubeDbContext.cs:184); [up.sql:849](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/database/migrations/20260905_bootstrap/up.sql:849).
- **Điều kiện:** retry cùng key khi đơn đã paid/expired, hai request cùng key đến đồng thời, hoặc hai user/plan dùng cùng key.
- **Cách xảy ra:** lookup chỉ tìm cùng user+plan+pending+chưa hết hạn; unique index lại áp trên IdempotencyKey toàn bảng không xét status/user. Khi lookup bỏ qua hàng cũ, insert bị DB từ chối. Concurrent first request cùng key cũng cùng không tìm thấy rồi một request bị unique violation.
- **Tái hiện theo schema:** key K đã có ở payment expired/paid; gọi initiate với K → lookup trả null, insert vi phạm ux_payments_idempotency; middleware hiện biến DbUpdateException thành500.
- **Ảnh hưởng:** retry không idempotent, lỗi500 thay vì trả đơn cũ hoặc conflict có chủ đích; phạm vi key giữa user không đúng điều kiện lookup.
- **Khắc phục:** định nghĩa key theo user và request fingerprint; lookup mọi trạng thái để replay response, key khác fingerprint trả409. Unique index cùng phạm vi (user,key), xử lý insert race bằng đọc lại hàng thắng; key rỗng chuẩn hóa null và giới hạn chiều dài.
- **Kiểm thử hồi quy đề xuất:** retry pending/paid/expired, request đổi plan, hai user cùng key và hai request song song; không trả500 cho conflict dự kiến.
- **Trạng thái:** đối chiếu query, index và middleware; chưa thử insert trên DB thật.

### BUG-037 — Race đổi mật khẩu và refresh có thể giữ lại phiên ngoài danh sách thu hồi

- **Bằng chứng:** [AccountService.cs:61](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Account/AccountService.cs:61)–91; lock chung tại [AuthStore.cs:11](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/AuthStore.cs:11)–24; refresh tại [AuthService.cs:124](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Auth/AuthService.cs:124)–155.
- **Điều kiện:** refresh/login đồng thời với change-password; request đổi mật khẩu đã tải danh sách active sessions trước khi phiên mới được tạo.
- **Cách xảy ra:** auth flows serialize bằng advisory lock user, nhưng ChangePasswordAsync không tham gia lock đó. Nó sửa password và revoke snapshot các session đã materialize; một phiên được thêm sau snapshot không bị thu hồi, không có password/security version để ValidateSession loại phiên ấy.
- **Tái hiện theo lịch mã:** change-password xác minh mật khẩu cũ và tải sessions; refresh bằng token cũ tạo child session và commit; change-password save mật khẩu mới, chỉ revoke các session trong danh sách cũ. Child còn active và được ValidateSession chấp nhận.
- **Ảnh hưởng:** token refresh đã bị lộ có thể tạo phiên tồn tại sau đổi mật khẩu, trái mục đích “revoke all” của flow này.
- **Khắc phục:** dùng cùng per-user transaction/lock cho đổi mật khẩu, login/refresh/revoke; thu hồi phiên trong vùng khóa và thêm security/password version ràng buộc mọi access/refresh session. Xác định rõ có giữ phiên hiện tại hay yêu cầu login lại.
- **Kiểm thử hồi quy đề xuất:** barrier change-password/refresh/login trên PostgreSQL thử riêng; sau commit không phiên dùng credential cũ còn hợp lệ.
- **Trạng thái:** static schedule; chưa chạy concurrency test sau yêu cầu chỉ đọc code.

### BUG-038 — Các lỗi nghiệp vụ plan/payment bị trả thành500

- **Bằng chứng:** [ApiErrors.cs:27](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Middleware/ApiErrors.cs:27)–49; định nghĩa exception tại [PaymentContracts.cs:59](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Payments/PaymentContracts.cs:59) và [PlanContracts.cs:119](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Plans/PlanContracts.cs:119); [PaymentService.cs:25](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Payments/PaymentService.cs:25)–30; [PlanService.cs:260](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Plans/PlanService.cs:260)–283.
- **Điều kiện:** request hợp lệ về JSON nhưng gặp lỗi nghiệp vụ dự kiến (gói không tồn tại, free không cần payment, đăng ký lại gói active, downgrade bị cấm).
- **Cách xảy ra:** middleware map nhiều exception domain nhưng thiếu PlanException và PaymentException, nên generic catch trả INTERNAL_ERROR500 thay vì Status/Code của exception.
- **Tái hiện theo mã:** initiate plan không tồn tại ném PaymentException404; free plan ném400; middleware nhận đều ở catch Exception và trả500. Các guard PlanException cũng mất code/thông báo hữu ích ở production.
- **Ảnh hưởng:** client không phân biệt validation/conflict và outage, có thể retry sai, người dùng chỉ thấy lỗi chung, telemetry đếm500 cho lỗi4xx.
- **Khắc phục:** exception mapper tập trung cho mọi domain exception có Status/Code, gồm plan/payment; chỉ lỗi không dự kiến mới500. Khớp OpenAPI và client error handling.
- **Kiểm thử hồi quy đề xuất:** các tình huống400/403/404/409 giữ status/code; lỗi DB không dự kiến vẫn500 và không lộ nội dung nhạy cảm.
- **Trạng thái:** đối chiếu throw sites và toàn middleware; không gọi API thật.

### BUG-039 — Cập nhật tiểu sử thành công nhưng nội dung không được lưu

- **Bằng chứng:** [HuTubeDbContext.cs:62](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Persistence/HuTubeDbContext.cs:62) gọi `b.Ignore(x => x.Bio)`; [User.cs:12](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Domain/Users/User.cs:12); [AccountService.cs:15](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Account/AccountService.cs:15), [AccountService.cs:26](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Account/AccountService.cs:26), [AccountService.cs:50](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Account/AccountService.cs:50)–58; contract [AccountDtos.cs:9](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Account/AccountDtos.cs:9), [AccountDtos.cs:16](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Account/AccountDtos.cs:16); UI [account-page.ts:130](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/account/account-page.ts:130), [account-page.ts:240](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/account/account-page.ts:240) và [account-page.html:116](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/account/account-page.html:116)–117.
- **Điều kiện:** người dùng nhập tiểu sử ở trang tài khoản và lưu. Những trường khác như DisplayName có thể vẫn được lưu bình thường.
- **Cách xảy ra:** service gán request.Bio vào entity rồi SaveChanges, nhưng EF đã bỏ Bio khỏi mapping nên không phát sinh ghi dữ liệu cho trường này. Response cập nhật gọi lại GetProfile dùng AsNoTracking; entity mới được đọc không có Bio đã gán trong RAM, nên trả null hoặc chuỗi rỗng theo nhánh preferences.
- **Tái hiện theo mã:** nhập một tiểu sử khác rỗng, lưu, rồi GET profile/tải lại trang/đăng nhập lại. Giá trị Bio không tồn tại trong dữ liệu được đọc; ngay response cập nhật cũng mất giá trị vì đọc lại entity không tracking.
- **Ảnh hưởng:** mất nội dung người dùng vừa nhập, UI báo lưu thành công nhưng không lưu được tiểu sử; gọi lại nhiều lần không khắc phục.
- **Khắc phục:** chọn một nơi lưu bền vững cho Bio: map cột thực trong users bằng migration, hoặc lưu trong preferences và dùng cùng nơi cho đọc/ghi. Bổ sung giới hạn chiều dài ở backend, thống nhất với maxlength 160 của UI; không chỉ trả lại giá trị trong RAM để che lỗi persistence.
- **Kiểm thử hồi quy đề xuất:** PATCH Bio rồi GET bằng DbContext/request mới, reload và đăng nhập lại phải giữ đúng nội dung; sửa/xóa tiểu sử hoạt động và không thay đổi profile khác.
- **Trạng thái:** xác minh mapping, contract và toàn đường đọc/ghi bằng mã nguồn; không chạy thêm thử nghiệm sau yêu cầu chỉ xem code.

### BUG-040 — Topbar che nút đóng drawer User Web trên mobile/tablet

- **Bằng chứng:** [shell-layout.component.scss:11](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/layouts/shell-layout/shell-layout.component.scss:11)–21, [shell-layout.component.scss:49](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/layouts/shell-layout/shell-layout.component.scss:49)–65; [user-sidebar.component.scss:116](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/shared/sidebar/user-sidebar.component.scss:116)–154; [user-sidebar.component.html:1](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/shared/sidebar/user-sidebar.component.html:1)–4; [user-topbar.component.scss:12](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/shared/topbar/user-topbar.component.scss:12).
- **Điều kiện:** viewport rộng ≤960px, ví dụ 390px hoặc 768px, mở menu trong shell.
- **Cách xảy ra:** topbar sticky nằm ở y=0, z-index=120; drawer fixed cũng bắt đầu y=0 nhưng z-index=100, scrim=90. Nút × ở phần đầu drawer nằm dưới nền opaque của topbar. Header mobile cao ít nhất 64px, trong khi head/nút đóng sidebar đặt ngay sau padding trên 14px, nên vùng nút bị topbar phủ.
- **Tái hiện theo CSS/DOM:** mở menu ở viewport nhỏ rồi chạm vị trí × phía trên drawer. Topbar là lớp nhận pointer, không phải nút đóng sidebar. Scrim ngoài sidebar và chọn link khác vẫn là lối thoát, nên không khẳng định toàn bộ menu bị khóa.
- **Ảnh hưởng:** nút đóng được dựng nhưng bị che, phần đầu menu thiếu/đè lên header và người dùng phải tìm cách đóng khác. Đây là lỗi lớp/bố cục, không phải nhận xét thẩm mỹ.
- **Khắc phục:** đặt drawer và scrim trên topbar bằng cùng thang overlay z-index; hoặc cho drawer bắt đầu dưới topbar với top/height phù hợp. Thống nhất chiều cao header theo breakpoint và bảo đảm close control nhìn thấy/nhận pointer.
- **Kiểm thử hồi quy đề xuất:** 320/390/768/960px, mở/đóng bằng ×, scrim và menu; scroll trang và đổi orientation; close luôn nhìn thấy và hoạt động.
- **Trạng thái:** xác minh CSS cascade và DOM; chưa render hoặc đo pixel trong trình duyệt.

### BUG-041 — Route công khai của kênh nằm trong nhóm yêu cầu đăng nhập

- **Bằng chứng:** [app.routes.ts:32](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/app.routes.ts:32)–47; [auth.guard.ts:6](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/auth.guard.ts:6)–8; [watch-page.html:170](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/video/watch-page.html:170); API cho phép khách tại [ChannelController.cs:57](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ChannelController.cs:57)–59 và [PlaylistController.cs:18](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/PlaylistController.cs:18)–20.
- **Điều kiện:** khách chưa có phiên đăng nhập mở trang kênh public, hoặc bấm tên kênh khi đang xem video public.
- **Cách xảy ra:** `/channel/:handle`, danh sách và chi tiết playlist của kênh đều là children của route `canActivate: [authGuard]`. Guard không có ngoại lệ cho trang công khai và redirect khách tới login, trong khi API channel/public playlists nhận anonymous và trang watch public vẫn đưa link này.
- **Tái hiện theo router:** phiên khách sạch → `/watch/{publicVideo}` → bấm tên kênh, hoặc mở trực tiếp `/channel/{handle}`. Nhánh authGuard trả UrlTree `/login?returnUrl=...` trước khi trang kênh được tải.
- **Ảnh hưởng:** không khám phá được kênh/playlist public từ video, link chia sẻ kênh bắt đăng nhập không cần thiết; hành vi web không khớp khả năng công khai của API.
- **Khắc phục:** đưa route chỉ đọc channel/public playlists ra nhóm auth; giữ customize, tạo kênh, studio và hành động cần tài khoản trong nhóm bảo vệ. Các nút subscribe/manage tự kiểm tra auth/permission mà không chặn toàn trang đọc.
- **Kiểm thử hồi quy đề xuất:** khách xem được kênh và playlist public nhưng không customize/upload/subscribe khi chưa đăng nhập; kênh/nội dung hạn chế vẫn tuân policy API.
- **Trạng thái:** đối chiếu route, guard, link UI và authorization API; chưa điều hướng trình duyệt thật.

### BUG-042 — Drawer Admin Web không nhận pointer khi mở trên màn hình nhỏ

- **Bằng chứng:** [admin-sidebar.component.scss:120](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/shared/sidebar/admin-sidebar.component.scss:120)–149; [admin-sidebar.component.ts:7](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/shared/sidebar/admin-sidebar.component.ts:7)–12; [admin-shell-layout.component.html:1](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/layouts/shell-layout/admin-shell-layout.component.html:1)–5.
- **Điều kiện:** viewport ≤1040px, mở navigation drawer trong Admin Web.
- **Cách xảy ra:** host và `.side-nav` bị đặt pointer-events:none. `.side-nav.is-open` chỉ thay transform; rule bật pointer là `.nav-open .side-nav` trong stylesheet sidebar. Class nav-open nằm ở div của component Shell, nhưng sidebar dùng encapsulation mặc định: selector ancestor bị scope theo sidebar, không khớp ancestor Shell. Không có global rule bù lại.
- **Tái hiện theo component/CSS:** menu mở → class is-open làm drawer trượt vào nhưng pointer-events vẫn none. Chạm link hoặc × xuyên qua drawer đến scrim/nội dung dưới, thay vì điều hướng hoặc đóng bằng nút trong menu.
- **Ảnh hưởng:** đường navigation chính của admin trên mobile/tablet hỏng; có thể phải nhập URL hoặc đổi sang màn hình lớn để truy cập chức năng. Không áp dụng kết luận này cho desktop ngoài breakpoint.
- **Khắc phục:** bật pointer-events:auto ngay trên `.side-nav.is-open` trong cùng component, hoặc gắn class trạng thái trên host/ dùng cơ chế host-context đúng. Đóng drawer phải đưa lại none/inert và quản lý focus.
- **Kiểm thử hồi quy đề xuất:** viewport 390/768/1024/1040px, mở menu rồi chọn từng link/×; link nhận pointer và điều hướng đúng, scrim chỉ đóng khi chạm ngoài drawer.
- **Trạng thái:** xác minh selector, class binding, component encapsulation và thiếu global override; chưa chạy Angular/browser để quan sát.

### BUG-043 — Dropdown bộ lọc Admin Web không chọn được bằng bàn phím

- **Bằng chứng:** [custom-select.component.ts:24](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/shared/components/custom-select/custom-select.component.ts:24)–64, [custom-select.component.ts:99](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/shared/components/custom-select/custom-select.component.ts:99)–125; [custom-select.component.scss:28](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/shared/components/custom-select/custom-select.component.scss:28); điểm dùng [admin-channels-page.html:83](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:83)–95, [admin-videos-page.html:38](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:38)–64.
- **Điều kiện:** người dùng điều khiển bằng Tab/Enter/Space/Arrow thay chuột, ở bất kỳ kích thước màn hình.
- **Cách xảy ra:** button có thể mở menu, nhưng options là li chỉ có click handler, không focusable/tabindex; không có active-descendant/roving focus hoặc key handler chọn option. Handler bàn phím duy nhất là Escape. Gán role=listbox/option không tự thêm hành vi keyboard; outline:none ở trigger còn làm mất chỉ báo focus mặc định.
- **Tái hiện theo template/events:** Tab tới trigger, Enter mở; Arrow/Enter không đổi value, Tab chuyển sang control ngoài menu. Không có đường keyboard gọi onSelect để áp dụng bộ lọc.
- **Ảnh hưởng:** người dùng bàn phím/thiết bị hỗ trợ không đổi được filter ở videos/channels và các màn dùng chung component; giao diện có dropdown nhưng thiếu cách điều khiển tương ứng.
- **Khắc phục:** dùng select native nếu phù hợp, hoặc thực hiện đầy đủ focus, Arrow/Home/End, Enter/Space, Escape, aria-controls/active-descendant và trả focus về trigger. Bổ sung focus-visible rõ; không coi ARIA là thay thế event logic.
- **Kiểm thử hồi quy đề xuất:** toàn flow chọn filter chỉ bằng keyboard; mở/chọn/đóng/trả focus, không tạo keyboard trap; kiểm tra tên/state với screen reader.
- **Trạng thái:** xác minh template, các handlers và CSS; chưa chạy screen reader/trình duyệt.

### BUG-044 — Modal thanh toán, appeal và action không có đường cuộn trên viewport thấp

- **Bằng chứng:** [payment-modal.component.ts:15](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/payment-modal.component.ts:15)–65, [payment-modal.component.ts:92](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/payment-modal.component.ts:92)–103, [payment-modal.component.ts:122](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/payment-modal.component.ts:122)–149.
- **Điều kiện:** đơn pending có QR, mở thanh toán ở điện thoại landscape như 844×390 CSS px, cửa sổ thấp hoặc zoom làm giảm chiều cao viewport.
- **Cách xảy ra:** backdrop fixed inset=0, flex center; card chỉ giới hạn chiều rộng, không max-height/overflow. QR cao 220px cộng padding wrapper/card, header, ba dòng chuyển khoản, khoảng cách và waiting indicator vượt chiều cao viewport thấp. Card được căn giữa nên phần vượt nằm cả trên/dưới; body ngoài không đưa được nội dung fixed này trở lại vùng nhìn.
- **Tái hiện theo CSS:** mở đơn pending có QR rồi xoay ngang. Header/close hoặc thông tin cuối nằm ngoài vùng nhìn, không có modal body scroll để tiếp cận đầy đủ.
- **Ảnh hưởng:** khó đọc thông tin chuyển khoản/hạn thanh toán, nút đóng có thể nằm ngoài viewport và checkout không thích ứng với màn hình thấp.
- **Khắc phục:** backdrop có padding/overflow phù hợp, card max-height theo 100dvh và modal-body overflow-y:auto; giữ header/close truy cập được. QR dùng kích thước giới hạn bởi vùng chứa; chọn top alignment khi viewport rất thấp.
- **Kiểm thử hồi quy đề xuất:** pending/paid/expired ở 320×568, 844×390, zoom 200%; nội dung/close đều có thể tới bằng touch và keyboard, không có đoạn bị cắt ngoài vùng cuộn.
- **Trạng thái:** xác minh CSS và cấu trúc nội dung; không đo tổng chiều cao pixel hoặc mở giao dịch thật.
- **Phạm vi cùng nguyên nhân:** Creator appeal tại [studio-overview-page.scss:134](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-overview-page.scss:134)–151 / [studio-overview-page.html:218](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-overview-page.html:218)–270 và [channel-settings-page.scss:450](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/channel/channel-settings-page.scss:450)–466 / [channel-settings-page.html:319](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/channel/channel-settings-page.html:319)–350; Admin Appeals tại [admin-appeals-page.scss:628](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-appeals-page.scss:628)–648, [admin-appeals-page.scss:678](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-appeals-page.scss:678)–753 / [admin-appeals-page.html:220](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-appeals-page.html:220)–264; Strikes tại [admin-strikes-page.scss:708](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.scss:708)–728, [admin-strikes-page.scss:760](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.scss:760)–835 / [admin-strikes-page.html:252](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.html:252)–300; Users action-modal tại [admin-users-page.scss:112](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/users/admin-users-page.scss:112). Các form fixed/căn giữa không có card/body height-scroll theo viewport. Cửa sổ640×360, lý do dài hoặc kéo cao textarea có thể đưa footer/close ngoài vùng nhìn; sửa cùng primitive modal và kiểm tra từng form. Không gộp Overview appeal-detail đã max-height/overflow tại dòng661 hoặc Users statistics có đường cuộn riêng.

### BUG-045 — Picker upload, thumbnail và avatar không có cách dùng bằng bàn phím

- **Bằng chứng:** [video-upload-wizard.component.html:65](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.html:65)–76; [video-upload-wizard.component.ts:403](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:403).
- **Điều kiện:** creator dùng bàn phím hoặc thiết bị hỗ trợ, ở bất kỳ viewport, bắt đầu upload tại Step 1.
- **Cách xảy ra:** CTA chọn file là label thường, input file có hidden nên không nằm trong focus order; dropzone chỉ có drag events. Không button/tabindex/key handler nào mở picker. nextStep yêu cầu selectedFile nên không thể vượt bước này nếu chưa dùng pointer/drag.
- **Tái hiện theo DOM:** Tab qua Step 1, thử Enter/Space để chọn file. Label không nhận focus/action bàn phím; nút Continue chỉ trả lỗi chưa chọn video.
- **Ảnh hưởng:** luồng upload chính không thực hiện được bằng bàn phím, dù phần còn lại dùng các button có thể focus.
- **Khắc phục:** button thật mở input file hoặc input visually-hidden vẫn focusable với label và focus styling; cung cấp tên điều khiển, trạng thái chọn file và lỗi kiểm định có thể đọc bằng thiết bị hỗ trợ.
- **Kiểm thử hồi quy đề xuất:** dùng Tab/Enter/Space chọn file, hủy/chọn lại và qua bước; keyboard focus không bị mất khi hiện progress/error.
- **Trạng thái:** xác minh DOM, hidden attribute và handlers; chưa chạy screen reader/browser.
- **Phạm vi cùng nguyên nhân:** Chọn ảnh thumbnail là label chứa input display:none tại [video-edit-page.html:51](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.html:51) / [video-edit-page.scss:49](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.scss:49)–50; avatar Account là div chỉ (click) và input hidden tại [account-page.html:61](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/account/account-page.html:61)–70. Tab không tới trigger và Enter/Space không mở picker; dùng button hoặc input vẫn focusable, kiểm tra chọn/hủy/đổi ảnh. Branding dùng button thật nên không thuộc kết luận.

### BUG-046 — Hẹn giờ phát hành trên wizard chỉ thay giao diện, không thay request

- **Bằng chứng:** [video-upload-wizard.component.html:468](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.html:468)–493; [video-upload-wizard.component.ts:97](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:97)–99, [video-upload-wizard.component.ts:425](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:425)–440; [ContentControllers.cs:84](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:84)–99.
- **Điều kiện:** Step 5 chọn schedule và ngày/giờ tương lai cho video public/unlisted, rồi gửi upload.
- **Cách xảy ra:** publishMode/scheduleDate/scheduleTime chỉ bind vào controls; submitUpload không đọc, kiểm tra hoặc đưa chúng vào FormData. Upload contract không nhận lịch. Request giống phát hành ngay theo visibility; giá trị date mặc định còn cố định 15/09/2026 thay vì ngày hiện tại.
- **Tái hiện theo form → contract:** điền lịch tương lai, so sánh các trường request với chế độ now: hoàn toàn không có timestamp lịch. Khi pipeline phê duyệt/xử lý xong, không có điều kiện từ lịch người dùng chọn giữ video đến thời điểm hẹn.
- **Ảnh hưởng:** lịch phát hành bị bỏ qua, nội dung có thể khả dụng trước thời điểm dự định sau khi được duyệt; người dùng tin một tính năng chưa được thực hiện.
- **Khắc phục:** thực hiện scheduled timestamp/timezone và validation từ UI đến API/persistence/publication worker, giữ trạng thái scheduled trước thời hạn. Nếu chưa hỗ trợ, vô hiệu hóa/bỏ controls và thông báo rõ trước gửi.
- **Kiểm thử hồi quy đề xuất:** ngày quá khứ/invalid bị từ chối; lịch tương lai lưu và chỉ publish sau hạn, kể cả xử lý/duyệt kết thúc sớm; kiểm tra timezone và restart worker.
- **Trạng thái:** đối chiếu toàn request builder và contract bằng mã; không upload hoặc thao tác thời gian thật.

### BUG-047 — Nút Lưu nháp trên upload wizard không lưu dữ liệu

- **Bằng chứng:** [video-upload-wizard.component.html:703](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.html:703)–705; state và submit flow tại [video-upload-wizard.component.ts:96](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:96)–101, [video-upload-wizard.component.ts:417](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:417)–441.
- **Điều kiện:** creator nhập tiêu đề/mô tả/chapters, bấm Lưu nháp rồi rời trang hoặc reload trước upload.
- **Cách xảy ra:** button type=button không click handler, không submit và không draft persistence. Dữ liệu form ở instance component, nên click không bảo toàn state khi instance bị hủy.
- **Tái hiện theo binding:** bấm nút không gọi method/save nào; vào lại wizard khởi tạo các field mặc định, không đọc bản nháp đã lưu.
- **Ảnh hưởng:** mất công nhập metadata/chapters; nhãn Lưu nháp khiến người dùng tưởng đã bảo toàn nội dung dù không có thao tác lưu.
- **Khắc phục:** nối action save/recover draft với phản hồi thành công/lỗi và cơ chế lưu phù hợp; nhắc khi rời form chưa lưu. File local cần yêu cầu chọn lại nếu không thể persist an toàn; bỏ action chưa hỗ trợ nếu chưa thực hiện.
- **Kiểm thử hồi quy đề xuất:** lưu nháp, rời/reload/quay lại giữ metadata; lỗi lưu có thông báo; bản nháp gắn đúng tài khoản/kênh và không ghi lẫn upload khác.
- **Trạng thái:** xác minh button binding và nơi sở hữu state; chưa thao tác UI thật.

### BUG-048 — Sheet tạo nội dung mobile không cuộn theo chiều cao khả dụng

- **Bằng chứng:** [mobile_scaffold.dart:56](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:56)–111; ba action hai dòng tại [mobile_scaffold.dart:292](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:292)–306.
- **Điều kiện:** Đăng nhập, bấm + khi landscape640×360 logical px (width<720), hoặc mở sheet ở portrait rồi xoay844×390; width≥720 ẩn nút+ nên không dùng thao tác bấm trực tiếp ở844px làm kịch bản. Text scale lớn cũng làm giảm khả năng vừa sheet.
- **Cách xảy ra:** showModalBottomSheet giữ chế độ mặc định không scroll-controlled, giới hạn chiều cao sheet theo một phần viewport. Bên trong là SafeArea/Padding/Column(mainAxisSize:min) với tiêu đề, mô tả và ba ListTile hai dòng, không có scrollable. Tổng chiều cao nội dung vượt vùng sheet trên viewport thấp/chữ lớn; SafeArea chỉ thêm padding, không tạo cuộn.
- **Tái hiện theo widget constraints:** mở sheet ở landscape/text lớn; Column vẫn yêu cầu toàn bộ chiều cao các con nhưng bị ràng buộc bởi sheet, nên phần cuối overflow/cắt và không có đường cuộn tới các action cuối.
- **Ảnh hưởng:** các lựa chọn tạo playlist/kênh ở cuối khó hoặc không thể tiếp cận; layout không thích ứng với orientation/text scale.
- **Khắc phục:** dùng scroll-controlled sheet với chiều cao giới hạn theo viewport và SingleChildScrollView/ListView; giữ SafeArea, kiểm tra text scale và landscape thay vì tăng một height cố định.
- **Kiểm thử hồi quy đề xuất:** portrait/landscape, logical height 390px, text scale 1/1.5/2; đủ ba action nhìn thấy hoặc cuộn tới được, không overflow.
- **Trạng thái:** phân tích widget constraints và cấu trúc mặc định; chưa render Flutter hoặc đo chiều cao tile trên thiết bị.

### BUG-049 — Search mobile không giữ định danh bộ query khi tải tiếp hoặc xóa

- **Bằng chứng:** [search_screen.dart:36](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/search/search_screen.dart:36)–56, [search_screen.dart:94](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/search/search_screen.dart:94)–100, [search_screen.dart:135](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/search/search_screen.dart:135)–137, [search_screen.dart:176](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/search/search_screen.dart:176)–179.
- **Điều kiện:** đã tìm A trang 1, sửa ô nhập thành B rồi bấm Tải thêm chưa tìm B; hoặc clear/đổi sort khi request còn chạy.
- **Cách xảy ra:** mỗi _search đọc text/sort đang sửa, nhưng more dùng page của bộ kết quả cũ rồi append vào results cũ. Không snapshot query/sort/generation. Clear không invalidate request; đổi sort đổi chip rồi _search bị guard loading bỏ qua, nên response trước vẫn commit dưới trạng thái mới.
- **Tái hiện theo state:** A trang 1 → gõ B → more gửi B trang 2 → list chứa A trang 1 + B trang 2, thiếu B trang 1. Clear trong lúc A pending rồi A trả về vẫn ghi lại results đã xóa.
- **Ảnh hưởng:** kết quả trộn từ khóa, bộ lọc không khớp dữ liệu và thao tác xóa bị response cũ đảo ngược.
- **Khắc phục:** tách draft input khỏi snapshot query/sort đã commit; more chỉ dùng snapshot, đổi/clear phải reset và invalidate generation. Chỉ commit response thuộc bộ query hiện tại; thông báo/khóa thao tác rõ khi cần.
- **Kiểm thử hồi quy đề xuất:** sửa query trước more, clear pending, sort pending, response đảo thứ tự; không trộn bộ kết quả và không bỏ trang đầu query mới.
- **Trạng thái:** xác minh state và async flow bằng mã; chưa gửi request/app thật.

### BUG-050 — Feed mobile bỏ qua trang bị lỗi khi tải tiếp

- **Bằng chứng:** [feed_screen.dart:57](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:57)–93; [feed_screen.dart:97](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:97)–105; [feed_screen.dart:141](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:141)–142.
- **Điều kiện:** feed có trang 1 và còn total, tải trang 2 thất bại do lỗi tạm thời rồi tiếp tục scroll.
- **Cách xảy ra:** _maybeLoadMore tăng _page trước request; catch chỉ tắt loading/ghi error, không rollback page. Retry inline hiện có tải lại từ trang1; nếu tiếp tục scroll thay vì retry/refresh, lần load tiếp tăng page thay vì retry cùng trang lỗi.
- **Tái hiện theo state:** page=1 → tăng2 → request2 lỗi → page vẫn2 → scroll → tăng3/request3; item trang2 chưa từng được append.
- **Ảnh hưởng:** Feed thiếu một đoạn video sau lỗi mạng, có thể tải trang ngoài phạm vi vì số item chưa đạt total. Reset từ trang1 qua retry inline/refresh/đổi filter có thể khôi phục, nhưng không giữ tiến trình để retry đúng trang lỗi. Retry hiện có: [feed_screen.dart:171](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:171)–172.
- **Khắc phục:** giữ committed page; tính nextPage riêng và chỉ cập nhật page sau success; thêm retry đúng failed page với trạng thái lỗi ở cuối list.
- **Kiểm thử hồi quy đề xuất:** trang2 lỗi một lần rồi retry phải vẫn trang2; không mất/trùng item, không gửi trang3 trước khi trang2 được xử lý theo contract.
- **Trạng thái:** xác minh state transitions; không mô phỏng mạng/test/app mới.

### BUG-051 — Response feed cũ ghi vào bộ lọc mới trên mobile

- **Bằng chứng:** [feed_screen.dart:57](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:57)–77; [feed_screen.dart:107](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:107)–117; refresh tại [feed_screen.dart:146](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/feed_screen.dart:146).
- **Điều kiện:** Explore đang tải trang2 filter A; đổi category/sort sang B hoặc pull-to-refresh; B trang1 trả trước A trang2. Home không hiện sort và category chỉ gửi server khi explore=true, nhưng nhánh refresh race vẫn có thể xảy ra.
- **Cách xảy ra:** filter/refresh không invalidation request more. Commit chỉ kiểm tra mounted; nextPage cũ quyết định append nhưng dùng _videos hiện tại và ghi page/total từ response cũ. _moreLoading không ngăn chọn filter.
- **Tái hiện theo lịch:** A2 pending → chọn B → B1 thay list/page=1 → A2 hoàn thành, append A2 vào B1 và đổi page/total theo A. Bộ lọc hiển thị B nhưng data chứa A.
- **Ảnh hưởng:** video ngoài filter/sort đã chọn, phân trang và loading sai; không trùng BUG-034 vì nguyên nhân nằm ở lifecycle client, ranking backend không cần thay đổi.
- **Khắc phục:** generation/query snapshot cho mỗi bộ feed, bỏ response generation cũ; hủy/invalidate more trước refresh/filter; cập nhật page/total/loading chỉ cho generation hiện hành.
- **Kiểm thử hồi quy đề xuất:** filter/refresh khi more pending với cả hai thứ tự response; chỉ bộ query hiện hành xuất hiện và more tiếp tục từ page đúng.
- **Trạng thái:** xác minh async interleaving bằng mã; chưa chạy Flutter/harness hoặc request thật.

### BUG-052 — Filter thời gian và trạng thái kênh Admin không khớp query

- **Bằng chứng:** [admin-channels-page.html:90](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:90)–95; [admin-channels-page.ts:152](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.ts:152)–171, [admin-channels-page.ts:200](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.ts:200)–203; [admin-channels.service.ts:81](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels.service.ts:81)–106; [AdminController.cs:261](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/AdminController.cs:261)–265.
- **Điều kiện:** ở Channels chọn 7 ngày/30 ngày/năm nay thay All time, mọi viewport.
- **Cách xảy ra:** setTime cập nhật timeFilter rồi load; request chỉ có search/status/sort/page/pageSize. API không nhận timeRange/fromDate và component không lọc client theo ngày, nên timeFilter không tham gia đường đọc dữ liệu.
- **Tái hiện theo state/query:** đổi thời gian với các filter khác giữ nguyên; nhãn selected thay đổi nhưng request vẫn cùng điều kiện và không loại các kênh ngoài thời gian đã chọn.
- **Ảnh hưởng:** bộ lọc không hoạt động, người quản trị hiểu sai phạm vi bảng và số liệu; tải lại dữ liệu không khắc phục vì tham số vẫn thiếu.
- **Khắc phục:** định nghĩa rõ lọc theo CreatedAt hay activity, gửi from/to/timeRange và áp dụng server query/count; nếu chưa hỗ trợ thì bỏ/vô hiệu hóa control. Tổng và export cần cùng điều kiện lọc.
- **Kiểm thử hồi quy đề xuất:** dataset có kênh trong/ngoài 7/30 ngày và năm; bảng/total/export khớp filter, page reset đúng khi đổi khoảng thời gian.
- **Trạng thái:** đối chiếu toàn query builder và endpoint; không gửi request thật.
- **Dropdown trạng thái cùng trang:** [admin-channels-page.ts:158](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.ts:158)–161, [admin-channels-page.ts:195](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.ts:195)–212: chọn tab Active rồi dropdown Banned chỉ đổi statusFilter, không đổi activeTab; load ghi đè effectiveStatus='active'. Nhãn Banned nhưng query Active. Dùng một nguồn trạng thái chung hoặc đưa tab về All khi đổi dropdown; kiểm tra mọi tổ hợp tab/dropdown.

### BUG-053 — Trang quản lý gói có chữ gần trắng trên nền trắng khi dark mode

- **Bằng chứng:** [admin-plans-page.scss:1](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/plans/admin-plans-page.scss:1); bảng/editor tại [admin-plans-page.html:5](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/plans/admin-plans-page.html:5); dark tokens và global table rules tại [styles.scss:35](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/styles.scss:35)–79.
- **Điều kiện:** Admin Web ở dark mode, mở Plans, xem bảng hoặc editor.
- **Cách xảy ra:** .editor/.plan-table hardcode background:#fff; trang kế thừa --text-dark đổi thành #f8fafc. Global dark td ép color:var(--ink)!important nhưng không đổi nền của hai container này. Các selector đổi nền .card/.admin-panel/.modal/.dialog-box không match chúng.
- **Tái hiện theo cascade:** bật dark theme → giá, thời hạn, storage/maxMembers trong td và heading editor trở thành chữ gần trắng trên nền trắng; một số label/action màu riêng vẫn đọc được nên không khẳng định mọi phần đều biến mất.
- **Ảnh hưởng:** thông tin gói khó đọc ngay ở độ phóng đại bình thường, dễ nhập/chọn/sửa nhầm; theme hỗ trợ toàn app nhưng trang này mất tương phản.
- **Khắc phục:** dùng surface/line/ink/muted tokens đồng bộ cho container/table/editor, kiểm tra cả text kế thừa và important overrides; tránh vá bằng ép toàn bộ chữ đen trong dark theme.
- **Kiểm thử hồi quy đề xuất:** light/dark/system, bảng có dữ liệu và create/edit; đo contrast thực từ computed colors của text/body/labels và kiểm tra trạng thái disabled/error.
- **Trạng thái:** xác minh màu và CSS cascade; chưa đo ảnh chụp hoặc kết luận chứng nhận WCAG toàn app.

### BUG-054 — Breakpoint viewport không tính sidebar khiến thumbnail editor tràn cột

- **Bằng chứng:** [studio-layout.component.scss:3](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/layouts/studio-layout/studio-layout.component.scss:3), [studio-layout.component.scss:57](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/layouts/studio-layout/studio-layout.component.scss:57)–59; [video-edit-page.scss:2](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.scss:2), [video-edit-page.scss:19](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.scss:19)–22, [video-edit-page.scss:37](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.scss:37), [video-edit-page.scss:79](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.scss:79)–80.
- **Điều kiện:** viewport khoảng 1024 CSS px, sidebar Studio mặc định mở, vào `/studio/content/{id}/edit`, xem phần thumbnail.
- **Cách xảy ra:** sidebar chiếm 260px tới breakpoint 960; editor vẫn hai cột tới 920 và thumbnail vẫn hai cột tới 680. Ở 1024, stage≈764px; padding 4vw hai bên còn≈682px; trừ aside330/gap22, cột chính≈330px; padding card60/border còn≈268px. Thumbnail tracks bắt buộc tối thiểu 230+220+20=470px, không thể chứa trong vùng đó.
- **Tái hiện theo kích thước CSS:** giữ sidebar mở tại 1024px, grid thumbnail vượt content box của card/cột chính. Tùy ancestor overflow sẽ tràn sang vùng lân cận hoặc bị cắt/scroll; chưa chọn một biểu hiện pixel cụ thể khi chưa render.
- **Ảnh hưởng:** Bố cục edit tràn tại tablet, lựa chọn thumbnail khó đọc/chọn dù viewport qua breakpoint mobile. Collapse sidebar giảm mức tràn nhưng chưa hết tại1024px: content card khoảng452px vẫn nhỏ hơn thumbnail tracks470px; không coi collapse là cách khắc phục đầy đủ.
- **Khắc phục:** container query theo chiều rộng editor, hoặc breakpoint tính cả sidebar; stack thumbnail khi container nhỏ hơn minimum tracks và chuyển editor một cột sớm hơn. min-width:0 riêng cho parent không giải quyết minimum của các track con.
- **Kiểm thử hồi quy đề xuất:** 960/1024/1180px với sidebar mở/đóng, nội dung dài và zoom; thumbnail/aside không tràn hoặc chồng controls.
- **Trạng thái:** tính geometry từ CSS và layout hiện hành; chưa đo/chụp browser.

### BUG-055 — Studio chỉ tải 50 video đầu nhưng trình bày như toàn bộ nội dung kênh

- **Bằng chứng:** [studio-data.service.ts:20](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/studio-data.service.ts:20)–22, [studio-data.service.ts:69](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/studio-data.service.ts:69)–70; local search tại [studio-content-page.ts:30](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-content-page.ts:30)–32 và list [studio-content-page.html:35](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-content-page.html:35)–95; [studio-analytics-page.html:3](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-analytics-page.html:3)–6; query [ContentService.cs:845](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:845)–862.
- **Điều kiện:** kênh có ít nhất 51 video phù hợp quyền quản lý, mọi viewport.
- **Cách xảy ra:** shared service luôn gọi managed(channelId,1,50), bỏ page.total. Content page không pager/load-more; search lọc array đang có. Overview/Analytics reduce cùng array và trình bày các tổng như số liệu kênh. Server đã Skip/Take theo CreatedAt nên không trả toàn bộ.
- **Tái hiện theo query:** kênh51 video, tìm đúng tiêu đề video cũ nhất trong Content → không thấy vì item51 chưa từng được nạp; không có control chuyển trang để đến edit từ list. Views/likes/comments của video đó không được cộng vào tổng.
- **Ảnh hưởng:** video cũ bị mất khỏi đường quản lý UI, tìm kiếm không đầy đủ và thống kê hụt khi kênh phát triển; không phải API mất/xóa video.
- **Khắc phục:** server pagination/search và total hiển thị rõ; tách endpoint aggregate toàn kênh khỏi trang video. Nếu chỉ là recent50, ghi nhãn/phạm vi đó và cung cấp đường tới toàn bộ nội dung.
- **Kiểm thử hồi quy đề xuất:** kênh0/50/51/150 video; tìm/điều hướng video cuối, tổng kênh không phụ thuộc page đang nạp.
- **Trạng thái:** đối chiếu request/page contract và mọi consumer dataset; chưa tạo dữ liệu hoặc gọi API.

### BUG-056 — Thời gian xem Studio giả định mỗi view xem hết video

- **Bằng chứng:** [studio-data.service.ts:23](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/studio-data.service.ts:23); nhãn/tổng tại [studio-analytics-page.html:6](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-analytics-page.html:6), [studio-overview-page.html:51](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/studio-overview-page.html:51), [i18n.service.ts:625](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/i18n.service.ts:625); lịch sử có duration được ghi tại [ContentService.cs:1121](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1121)–1132.
- **Điều kiện:** lượt xem không hoàn thành 100% hoặc nhiều phiên xem/replay, mọi viewport.
- **Cách xảy ra:** watchSeconds=sum(stats.views*duration), rồi chia3600 hiển thị “Thời gian xem (giờ)”. Công thức không dùng thời lượng thực của từng lượt/phiên, nên mỗi view bị tính như hoàn thành toàn video; việc chỉ có50 video là lỗi độc lập BUG-055.
- **Tái hiện theo công thức:** video dài1giờ có10 view được ghi nhận thì UI báo10giờ dù mỗi lượt thực tế có thể chỉ xem một đoạn ngắn. Input xem30giây hay xemhết không tham gia công thức này.
- **Ảnh hưởng:** creator đánh giá sai mức tương tác/thời gian xem, số liệu thiếu cơ sở để so sánh hiệu quả nội dung.
- **Khắc phục:** aggregate watch events/duration thực theo định nghĩa session/replay rõ ràng từ server. Nếu chỉ muốn ước lượng lý thuyết, đổi nhãn và giải thích giả định; không gọi views×duration là thời gian xem thực.
- **Kiểm thử hồi quy đề xuất:** cùng view count nhưng completion khác nhau phải có watch time khác; replay/session/duration cap có contract rõ và aggregate không phụ thuộc page.
- **Trạng thái:** kiểm tra công thức và nhãn UI bằng mã; không đo hành vi người dùng thật.

### BUG-057 — Mọi kênh đều có badge đã xác minh

- **Bằng chứng:** [channel-page.html:49](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/channel/channel-page.html:49)–51; [channel.service.ts:21](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/channel.service.ts:21)–40; [ChannelContracts.cs:23](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Application/Channels/ChannelContracts.cs:23)–41.
- **Điều kiện:** Mở bất kỳ kênh, kể cả kênh mới tạo, mọi viewport.
- **Cách xảy ra:** Badge tick và tooltip ui.verifiedChannel được render vô điều kiện; DTO không có trạng thái verified để quyết định hiển thị. Không có bằng chứng quy trình xác minh cho từng kênh trong đường render này.
- **Tái hiện theo mã:** Kênh mới hoặc chưa có trạng thái xác minh từ server vẫn có tick/tooltip “Kênh đã xác minh” như các kênh khác.
- **Ảnh hưởng:** Giao diện gán tín hiệu tín nhiệm sai, gây hiểu nhầm khi đánh giá danh tính kênh. Mức P3 vì là thông tin UI, không khẳng định kênh được thêm quyền backend.
- **Khắc phục:** Bỏ badge cho đến khi có trạng thái authoritative hoặc thêm quy trình/field server verified và chỉ render khi được xác minh; không suy từ tên/avatar hoặc việc tồn tại tài khoản.
- **Kiểm thử hồi quy đề xuất:** Kênh thường/mới không có tick; kênh đã xác minh có badge đúng trạng thái; thu hồi xác minh cập nhật UI.
- **Trạng thái:** Đối chiếu template/contract; chưa kiểm tra quy trình xác minh hay dữ liệu production.

### BUG-058 — Công cụ privacy báo thành công nhưng không thực hiện hành động

- **Bằng chứng:** [public-policy-page.ts:724](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/policy/public-policy-page.ts:724)–739; controls [public-policy-page.html:188](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/policy/public-policy-page.html:188)–211; nội dung [i18n.service.ts:286](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/i18n.service.ts:286)–301.
- **Điều kiện:** Mở /privacy hoặc /policies?tab=privacy; chọn xuất dữ liệu, reset thuật toán hoặc đổi cá nhân hóa quảng cáo.
- **Cách xảy ra:** requestDataExport chỉ showToast; resetAlgorithm chỉ confirm rồi showToast; personalization chỉ đổi signal trong component. Không có API/job/persistence/authenticated action thực hiện yêu cầu, dù UI hứa ZIP/email và thông báo đã hoàn thành.
- **Tái hiện theo mã:** Bấm xuất dữ liệu → hiện thông báo sẽ có link ZIP/email nhưng không enqueue request; reset → thông báo thành công mà dữ liệu lịch sử/đề xuất không đổi. Reload làm tùy chọn quảng cáo quay về state khởi tạo.
- **Ảnh hưởng:** Người dùng tin dữ liệu/cài đặt đã được xử lý nhưng không có tác dụng thực; yêu cầu xuất dữ liệu bị thất lạc. Đây là lỗi implementation/thông tin, không đưa ra kết luận pháp lý.
- **Khắc phục:** Hành động phải gọi service được xác thực, lưu preference/job và chỉ phản hồi sau khi server nhận/thực hiện đúng. Hiển thị pending/failure khi cần; bỏ hoặc vô hiệu hóa tính năng chưa triển khai.
- **Kiểm thử hồi quy đề xuất:** Yêu cầu tạo job/state thực, lỗi API không báo success; reload/đổi thiết bị giữ preference đúng; reset chỉ tác động theo phạm vi đã mô tả.
- **Trạng thái:** Xác minh toàn handlers và chuỗi hiển thị bằng mã; không gọi dịch vụ hoặc gửi email.

### BUG-059 — Reload trang gói không nạp gói hiện tại sau restore đăng nhập

- **Bằng chứng:** [plan-detail-page.ts:40](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/plan-detail-page.ts:40)–56; [plan-detail-page.html:36](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/plan-detail-page.html:36)–56; [auth.service.ts:37](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/core/auth.service.ts:37); [app.config.ts:21](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/app.config.ts:21); [user-topbar.component.ts:121](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/shared/topbar/user-topbar.component.ts:121)–128.
- **Điều kiện:** Có refresh cookie hợp lệ, mở trực tiếp/reload /plans/{planId} khi AuthService chưa restore xong.
- **Cách xảy ra:** Constructor chỉ getMyPlan khi auth.user đã tồn tại ngay lúc đó. Bootstrap chỉ đợi RuntimeConfig; topbar restore auth bất đồng bộ. Sau restore HTML đổi theo auth.user nhưng không có effect/subscription tải myPlan, nên myPlan vẫn null.
- **Tái hiện theo mã:** Đang dùng gói P, F5/deep-link /plans/P → auth khôi phục sau constructor; isCurrentActivePlan=false/canSwitch=true vì thiếu snapshot gói, CTA hiển thị mua thay Đang dùng.
- **Ảnh hưởng:** Trạng thái gói và hướng dẫn mua/chuyển/nâng cấp sai sau reload; có thể tạo hành động mua không cần thiết. Không khẳng định đã phát sinh thanh toán trùng.
- **Khắc phục:** Đợi restore trước nạp trạng thái hoặc theo dõi identity bằng effect/switchMap; phân biệt unknown/loading với chưa có gói, clear/reload khi đổi user và xử lý lỗi eligibility rõ ràng.
- **Kiểm thử hồi quy đề xuất:** F5/deep-link với cookie active/expired/guest và restore chậm; CTA chỉ thể hiện trạng thái đủ dữ liệu, không giữ myPlan tài khoản trước.
- **Trạng thái:** Phân tích lifecycle bootstrap/constructor/template; chưa chạy browser hoặc payment API.

### BUG-060 — Hero chi tiết gói có min-width vượt card ở viewport 320px

- **Bằng chứng:** [plan-detail-page.scss:4](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/plan-detail-page.scss:4), [plan-detail-page.scss:45](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/plan-detail-page.scss:45), [plan-detail-page.scss:404](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/plans/plan-detail-page.scss:404)–409; outer clip [shell-layout.component.scss:6](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/layouts/shell-layout/shell-layout.component.scss:6).
- **Điều kiện:** Trang /plans/{id} ở 320 CSS px; tại 360px vùng copy cũng lấn vào padding card.
- **Cách xảy ra:** Page vẫn padding24 mỗi bên; mobile hero padding24 mỗi bên và border1; hero-left vẫn min-width280. Ở320, inner hero chỉ320−48−48−2=222px, thiếu58px so với minimum. Mobile media đổi flex-direction nhưng không reset min-width.
- **Tái hiện theo mã:** Giữ viewport320px: hộp copy rộng tối thiểu280px bắt đầu sau page/hero padding, vượt card và có thể vượt viewport khoảng9px. Shell overflow-x:clip có thể cắt phần vượt, không bảo đảm có scrollbar cứu layout.
- **Ảnh hưởng:** Bố cục copy không vừa card trên điện thoại nhỏ; tên gói/mô tả dài trong hero-left có nguy cơ bị cắt hoặc lấn mép. CTA thuộc sibling hero-pricing nên không suy ra CTA bị cắt từ min-width của hero-left.
- **Khắc phục:** Reset min-width:0/width:100% cho hero-left ở mobile, padding theo vùng chứa; kiểm tra các con intrinsic width và nội dung dài.
- **Kiểm thử hồi quy đề xuất:** 320/360/390px, ngôn ngữ vi/en, tên gói dài và zoom; hộp copy nằm trong card và không có nội dung ngoài viewport.
- **Trạng thái:** Tính từ CSS constraints; chưa render hoặc xác nhận một đoạn chữ cụ thể bị cắt.

### BUG-061 — PlanEnabled bị bỏ qua khi gửi thông báo lời mời dùng chung gói

- **Bằng chứng:** [AccountController.cs:34](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/AccountController.cs:34)–40; [AccountService.cs:144](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Account/AccountService.cs:144); [NotificationHub.cs:72](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Notifications/NotificationHub.cs:72)–96; [PlanService.cs:456](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Plans/PlanService.cs:456)–458.
- **Điều kiện:** User lưu PlanEnabled=false qua API cài đặt thông báo, InAppEnabled=true; sau đó được mời dùng chung gói.
- **Cách xảy ra:** Preference được nhận/lưu/trả lại, nhưng categoryEnabled switch không đọc PlanEnabled hoặc match plan_invitation. Producer phát đúng type plan_invitation; nhánh mặc định true nên vẫn ghi Notification/gửi hub. Ngoại lệ mandatory chỉ được viết riêng cho channel_invitation.
- **Tái hiện theo mã:** Theo đường mã: settings.PlanEnabled=false → plan_invitation đi vào _=>true → InAppEnabled=true nên vẫn ghi/gửi thông báo nhóm gói.
- **Ảnh hưởng:** Cài đặt báo đã tắt nhóm gói nhưng không ảnh hưởng thông báo này; người dùng không kiểm soát đúng preference mà API cung cấp.
- **Khắc phục:** Mapping notification type/category dùng một schema chung và kiểm tra PlanEnabled. Nếu invitation phải bắt buộc theo chủ đích sản phẩm, tách/ghi rõ ngoại lệ trong contract/UI; không lưu một switch với ý nghĩa không được thực thi.
- **Kiểm thử hồi quy đề xuất:** Bật/tắt PlanEnabled kết hợp InAppEnabled và từng type plan hiện có; loại thông báo bắt buộc có contract riêng và không bỏ qua các preference khác.
- **Trạng thái:** Đối chiếu write/read preference, producer và filter nguồn; không gửi notification/email thật.

### BUG-062 — Home giữ bốn cột đề xuất trên điện thoại do specificity

- **Bằng chứng:** [home-page.scss:15](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/home/home-page.scss:15)–16, [home-page.scss:62](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/home/home-page.scss:62)–65, [home-page.scss:140](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/home/home-page.scss:140)–151; [home-page.html:8](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/home/home-page.html:8)–14.
- **Điều kiện:** Home có đề xuất, chiều rộng ≤600 CSS px.
- **Cách xảy ra:** Selector .feed-section--for-you .grid có hai class, thắng selector .grid trong media mobile chỉ có một class. Bốn cột minmax(0,1fr) vẫn áp dụng dù quy tắc mobile xuất hiện sau.
- **Tái hiện theo mã:** Tại390px, trừ28px padding và3 gap18px còn308px, mỗi card77px; tại320px mỗi card59,5px. Thumbnail16:9 chỉ cao khoảng43/33px. Tính từ source, chưa đo render.
- **Ảnh hưởng:** Khu vực đề xuất chính co thành bốn card rất hẹp; tên video/kênh và badge khó đọc, responsive một cột không hoạt động.
- **Khắc phục:** Override bằng selector đủ specificity trong media hoặc dùng grid tracks thích nghi theo vùng chứa; kiểm tra tên dài và padding ở điện thoại nhỏ.
- **Kiểm thử hồi quy đề xuất:** 320/360/390/600/601px với đề xuất có/không có và title dài; mobile áp dụng số cột dự kiến.
- **Trạng thái:** Xác định từ selector và template; chưa chạy browser/screenshot.

### BUG-063 — Thêm playlist thất bại nhưng sửa video vẫn báo lưu thành công

- **Bằng chứng:** [video-edit-page.ts:121](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.ts:121)–159; [video-edit-page.html:66](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/pages/video-edit-page.html:66)–75; [PlaylistService.cs:124](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Playlists/PlaylistService.cs:124)–132.
- **Điều kiện:** Sửa video private/unlisted hoặc đổi sang trạng thái đó, chọn playlist rồi lưu; cũng xảy ra với lỗi addVideo khác.
- **Cách xảy ra:** Sau update/thumbnail, addToPlaylists catch mọi lỗi thành of(null). forkJoin kết thúc bình thường và subscriber đặt thông báo saved. API chỉ cho thêm video published+approved+public;403 VIDEO_NOT_SAVABLE bị nuốt cùng lỗi409 trùng vốn có thể bỏ qua.
- **Tái hiện theo mã:** Update metadata thành công, addVideo trả403 vì video private → catchError chuyển thành success → trang báo đã lưu nhưng playlist không chứa video.
- **Ảnh hưởng:** Người dùng tin playlist đã cập nhật; lỗi403/404/500 không được thông báo, không biết cần sửa hoặc thử lại.
- **Khắc phục:** Chỉ bỏ qua mã409 PLAYLIST_VIDEO_EXISTS đã biết; hiện trạng thái lưu một phần và lỗi từng playlist, giữ lựa chọn để retry. Đồng bộ điều kiện chọn playlist với chính sách server.
- **Kiểm thử hồi quy đề xuất:** 403/404/500, playlist trùng và nhiều playlist với thành công một phần; thông báo phản ánh đúng từng thay đổi.
- **Trạng thái:** Đối chiếu pipeline Observable với backend; chưa gọi API.

### BUG-064 — Tùy chọn phụ đề tự động và cho bình luận bị bỏ khỏi request

- **Bằng chứng:** [video-upload-wizard.component.ts:93](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:93)–100, [video-upload-wizard.component.ts:425](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.ts:425)–440; [video-upload-wizard.component.html:297](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.html:297)–306, [video-upload-wizard.component.html:504](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/user-web/src/app/features/studio/upload/video-upload-wizard.component.html:504)–508; [ContentControllers.cs:84](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/ContentControllers.cs:84)–99; [ContentService.cs:1270](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1270)–1284.
- **Điều kiện:** Bật/tắt phụ đề tự động ở bước3 hoặc tắt Allow comments, hoàn tất upload và công bố video đủ điều kiện.
- **Cách xảy ra:** autoSubtitles/allowComments chỉ được bind vào UI, không được đọc/serialize trong submitUpload. UploadVideoForm không nhận hai lựa chọn; CreateComment không có kiểm tra lựa chọn tắt bình luận của wizard.
- **Tái hiện theo mã:** ON/OFF tạo cùng FormData; tắt Allow comments không tạo một trạng thái server cấm bình luận, nên viewer vẫn có thể bình luận video đủ quyền xem. Lựa chọn phụ đề không điều khiển tạo/hủy phụ đề theo đường upload này.
- **Ảnh hưởng:** Creator được cho lựa chọn không có hiệu lực; tắt bình luận không được thực thi, tùy chọn phụ đề không có trạng thái xử lý tương ứng.
- **Khắc phục:** Bổ sung contract, lưu trạng thái và enforce allowComments khi tạo comment; nối autoSubtitles với pipeline/trạng thái caption và player. Khi chưa hỗ trợ, ẩn/disable các control và bỏ lời hứa chức năng chưa có.
- **Kiểm thử hồi quy đề xuất:** ON/OFF phải tạo trạng thái server khác nhau; comment bị từ chối khi tắt; caption có trạng thái thành công/thất bại và không được tạo khi tắt.
- **Trạng thái:** Đọc binding, request và service; chưa upload media hoặc tạo comment.


### BUG-065 — Drawer Channels và dialog Topics nằm dưới topbar

- **Bằng chứng:** [admin-channels-page.scss:728](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.scss:728)–780; [admin-channels-page.html:445](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:445)–466; [admin-topics-page.scss:139](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/topics/admin-topics-page.scss:139)–150; [admin-shell-layout.component.scss:2](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/layouts/shell-layout/admin-shell-layout.component.scss:2)–8.
- **Điều kiện:** Mở detail drawer Channels; hoặc mở dialog Topics ở cửa sổ thấp/zoom khiến phần đầu modal nằm trong vùng topbar.
- **Cách xảy ra:** Drawer/backdrop Topics đều z-index100, topbar sticky sibling z-index120. Channel drawer fixed full-height bắt đầu y0, header padding-top22, nút đóng nằm trong vùng0..76px của topbar (66px ở mobile). Topics đã có body scroll nhưng layer vẫn thấp hơn topbar.
- **Tái hiện theo mã:** Mở drawer channel: header/nút× ở vùng topbar và bị layer120 phủ. Topics ở landscape thấp cũng có thể đưa header vào vùng này. Không áp dụng kết luận này cho RBAC đã có override z200.
- **Ảnh hưởng:** Nút đóng/tiêu đề bị che; topbar vẫn nhận thao tác trên dialog, có thể điều hướng nền trong khi form đang mở.
- **Khắc phục:** Đưa overlay vào layer chung cao hơn shell, ưu tiên CDK Overlay; inert nền, focus/restore focus và giữ title/actions trong viewport.
- **Kiểm thử hồi quy đề xuất:** Channels ở desktop/mobile, Topics cửa sổ thấp/zoom; kiểm tra stacking, hit-test và focus khi mở/đóng.
- **Trạng thái:** Đối chiếu DOM và cascade; chưa render browser.

### BUG-066 — Các trang kiểm duyệt chỉ tải trang đầu của backlog

- **Bằng chứng:** [admin-moderation-page.ts:97](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-moderation-page.ts:97)–110; [admin-reports-page.ts:96](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-reports-page.ts:96)–107; [admin-appeals-page.ts:90](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-appeals-page.ts:90)–103; [admin-strikes-page.ts:130](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.ts:130)–143; [admin-moderation.service.ts:189](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-moderation.service.ts:189)–201, [admin-moderation.service.ts:258](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-moderation.service.ts:258)–286; [ModerationService.cs:20](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ModerationService.cs:20)–48, [AppealService.cs:226](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AppealService.cs:226)–255, [StrikeService.cs:95](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/StrikeService.cs:95)–129.
- **Điều kiện:** Queue có trên100 case trong nhóm tải; Reports có trên100 report CASES theo targetType/status đã chọn (không phải100 lượt báo cáo gom cùng case); appeals/strikes có trên50. Muốn duyệt/tìm record ngoài slice đầu.
- **Cách xảy ra:** Queue tải page1,size100 active và processed; Reports page1,size100; Appeals/Strikes mặc định page1,size50. Reports đã gửi status/targetType lên server, nhưng mọi lần tải vẫn trang1; text search/local filtered view chỉ thấy slice đã tải. Server thực sự Skip/Take nhưng UI không có Next/load-more.
- **Tái hiện theo mã:** Tạo tình huống dữ liệu vượt giới hạn; record nằm ở trang2 không xuất hiện trong list/search đang dùng page1. Refresh vẫn nạp cùng trang; không suy ra record đã mất trong DB hoặc vĩnh viễn không thể xử lý sau khi backlog thay đổi.
- **Ảnh hưởng:** Backlog và kết quả tìm kiếm không đầy đủ; trường hợp cũ khó tiếp cận, thống kê trên slice có thể gây hiểu sai phạm vi.
- **Khắc phục:** Giữ metadata phân trang và cung cấp next/load-more; chuyển search/filter phù hợp xuống query server, count cùng predicate; không tăng pageSize cố định để che lỗi.
- **Kiểm thử hồi quy đề xuất:** 101 queue cases/report cases cùng predicate,51 appeals/strikes; tìm record trang2, đổi filter/reset page, retry page lỗi và kiểm tra tổng độc lập slice.
- **Trạng thái:** Đối chiếu call sites và truy vấn; chưa dùng dataset/database thật.
- **Bằng chứng Reports bổ sung:** [admin-moderation.service.ts:228](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-moderation.service.ts:228)–232 gọi endpoint cases; [ReportService.cs:374](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:374)–386 lọc/count/Skip/Take trên report_case.

### BUG-067 — Open target của report nối cứng localhost:4200

- **Bằng chứng:** [admin-reports-page.ts:107](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-reports-page.ts:107); [admin-reports-page.html:52](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-reports-page.html:52); [ReportService.cs:485](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:485), [ReportService.cs:491](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:491), [ReportService.cs:500](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ReportService.cs:500).
- **Điều kiện:** Admin chạy trên môi trường triển khai, máy người kiểm duyệt không có User Web ở localhost:4200.
- **Cách xảy ra:** Backend trả relative targetUrl nhưng targetHref luôn ghép http://localhost:4200, không sử dụng địa chỉ User Web của môi trường.
- **Tái hiện theo mã:** Report có targetUrl=/watch/id → href trở thành http://localhost:4200/watch/id và trỏ về máy admin.
- **Ảnh hưởng:** Không mở được nội dung cần kiểm duyệt qua link trong report ở triển khai thông thường.
- **Khắc phục:** Cấu hình public User Web base URL theo môi trường, ghép URL an toàn với relative target; localhost chỉ là giá trị dev.
- **Kiểm thử hồi quy đề xuất:** Dev/staging/production, target video/comment/channel và base có subpath; link trỏ đúng site tương ứng.
- **Trạng thái:** Đọc hàm tạo href và producer targetUrl; chưa bấm link/network.

### BUG-068 — Response video cũ ghi đè form và có thể lưu nhầm sang video khác

- **Bằng chứng:** [admin-videos-page.ts:342](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.ts:342)–381; [admin-videos-page.html:633](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:633)–705; [AdminContentService.cs:444](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AdminContentService.cs:444)–466.
- **Điều kiện:** Mở Edit A có description không rỗng/category khác B, đóng rồi mở Edit B khi getVideo(A) còn pending; hoặc gõ description trước khi detail có description của chính video đó trả về.
- **Cách xảy ra:** openEdit cho dùng form ngay; callback đặt field khi detail.description/categoryId truthy nhưng không kiểm tra response còn thuộc editingVideo hiện tại. closeEdit không hủy/invalidate request; Save dùng editingVideo hiện tại và không đợi detail/loading hay kiểm tra field dirty.
- **Tái hiện theo mã:** A request pending → mở B → B detail về → A detail về và ghi description/category của A vào draft → Save dùng ID B. Server cập nhật thực các field của B. Cùng video, response muộn cũng ghi đè chữ vừa gõ.
- **Ảnh hưởng:** Mất draft và có thể làm sai metadata video khác bằng một thao tác lưu hợp lệ; không cần vượt quyền backend.
- **Khắc phục:** Gắn request generation/videoId với editor, hủy khi close/switch; chỉ hydrate field chưa dirty của đúng video. Disable Save hoặc editor cho tới khi dữ liệu đúng ID đã được nạp.
- **Kiểm thử hồi quy đề xuất:** Response A/B đảo thứ tự, đóng trước response, gõ trước response; payload Save luôn thuộc đúng video và giữ nội dung người dùng đã sửa.
- **Trạng thái:** Phân tích event order và backend write path; chưa chạy race/API thật.

### BUG-069 — Rule base ghi đè breakpoint một cột của form RBAC

- **Bằng chứng:** [admin-rbac-page.scss:1](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/rbac/admin-rbac-page.scss:1); [admin-rbac-page.html:263](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/rbac/admin-rbac-page.html:263)–275.
- **Điều kiện:** Create role ở viewport≤840px, đặc biệt320/360px.
- **Cách xảy ra:** Trong SCSS minified, media≤840 đặt role-form/permission-picker một cột; các rule base cùng specificity xuất hiện sau lại đặt role-form 1fr 1fr và picker hai cột. Input chưa được giới hạn min-width/width phù hợp; media không còn hiệu lực.
- **Tái hiện theo mã:** Áp dụng cascade ở320px: form vẫn hai cột thay vì một cột được định nghĩa trong breakpoint. Hai input giữ intrinsic width có thể buộc pan ngang trong dialog; không khẳng định nút Save biến mất.
- **Ảnh hưởng:** Form/picker không chuyển một cột theo breakpoint đã viết, nội dung bị bó hẹp trên điện thoại; viewport hẹp có thể phải cuộn ngang tùy intrinsic width/font/input của trình duyệt.
- **Khắc phục:** Đặt base trước media hoặc media cuối file; minmax(0,1fr), min-width:0/width:100% cho input và breakpoint theo vùng chứa.
- **Kiểm thử hồi quy đề xuất:** 320/360/840/841px, tên permission dài/zoom; role form và picker chuyển đúng số cột, không cần pan ngang để nhập.
- **Trạng thái:** Kiểm tra thứ tự rule và specificity; chưa render layout.

### BUG-070 — Lỗi form/modal chỉ hiện ở trang nền dưới backdrop

- **Bằng chứng:** [admin-strikes-page.ts:166](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.ts:166)–192; [admin-strikes-page.html:35](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.html:35)–44, [admin-strikes-page.html:243](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.html:243)–300; [admin-strikes-page.scss:708](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/moderation/admin-strikes-page.scss:708)–728; ví dụ tương tự [admin-topics-page.ts:129](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/topics/admin-topics-page.ts:129)–149, [admin-topics-page.html:25](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/topics/admin-topics-page.html:25)–26, [admin-topics-page.html:145](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/topics/admin-topics-page.html:145)–165.
- **Điều kiện:** Mở Create Strike, để trống Channel ID/reason rồi Confirm; hoặc API trả lỗi trong modal sửa Topics/Video và các action dialog dùng error ở page.
- **Cách xảy ra:** Confirm chỉ disabled submitting nên có thể chạy validation. Handler đặt error nhưng giữ modal mở; template error nằm ngoài modal ở trang nền. Backdrop phủ/blur trang, modal không có vùng error; người dùng không thấy hướng dẫn sửa ngay trong form.
- **Tái hiện theo mã:** Create Strike để trống → submitCreateStrike return sau đặt channelReasonRequired → modal giữ nguyên, không có thông báo lỗi trong modal. Error API cũng dùng đường feedback này.
- **Ảnh hưởng:** Form trông không phản hồi hoặc chỉ dừng spinner, user lặp submit/đóng dialog mới thấy lỗi; khó khắc phục lỗi tại chỗ.
- **Khắc phục:** Tách error của dialog khỏi load error trang, hiện role=alert/field error trong modal, giữ draft và focus trường lỗi; validation/submitting nhất quán.
- **Kiểm thử hồi quy đề xuất:** Required empty, API403/409/500/network; thông báo có trong dialog, draft còn và field sai được chỉ rõ.
- **Trạng thái:** Đối chiếu state/template/layer; chưa gửi request. Không gộp flow dùng window.alert đã hiển thị riêng.

### BUG-071 — Xóa description bị serialize thành không thay đổi nhưng vẫn báo thành công

- **Bằng chứng:** [admin-videos-page.ts:366](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.ts:366)–387; [admin-videos-page.html:655](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:655)–664; [admin-videos.service.ts:181](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos.service.ts:181)–182; [AdminContentService.cs:456](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/AdminContentService.cs:456).
- **Điều kiện:** Video có description; xóa hết text, nhập reason hợp lệ rồi Save.
- **Cách xảy ra:** trim() || undefined đổi chuỗi trống thành undefined, JSON bỏ trường Description. Backend chỉ thay đổi khi request.Description!=null; nhánh clear bằng chuỗi rỗng đã có nhưng frontend không gửi tới.
- **Tái hiện theo mã:** Draft description='' → payload thiếu description → request thành công → backend giữ text cũ → UI đóng và báo thành công.
- **Ảnh hưởng:** Không gỡ được mô tả sai/không phù hợp qua form mặc dù đã được phép sửa và UI báo lưu.
- **Khắc phục:** Gửi chuỗi rỗng cho hành động clear hoặc dùng clearDescription/patch semantics phân biệt untouched với cleared.
- **Kiểm thử hồi quy đề xuất:** Giữ nguyên, sửa text, xóa hết và chỉ whitespace; reload phải phản ánh đúng hành động clear.
- **Trạng thái:** Đọc serialization và mutation predicate; chưa Save thật.


### BUG-072 — Sheet playlist, report và sửa video không cuộn khi bàn phím chiếm chiều cao

- **Bằng chứng:** [playlists_screen.dart:78](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/playlists/playlists_screen.dart:78)–139; [report_dialog.dart:31](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/moderation/report_dialog.dart:31)–94; [creator_content_screen.dart:72](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_content_screen.dart:72)–77, [creator_content_screen.dart:430](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_content_screen.dart:430)–501.
- **Điều kiện:** Điện thoại thấp/landscape hoặc portrait360×640 với bàn phím chiếm nhiều chiều cao; mở các form sheet và nhập mô tả.
- **Cách xảy ra:** isScrollControlled=true chỉ nới giới hạn sheet. Nội dung vẫn Padding(viewInsets.bottom+padding) → Column(mainAxisSize:min) với mọi field/button; không có scroll viewport. Keyboard padding cộng chiều cao form có thể vượt ràng buộc, không đưa nút dưới cùng lên được.
- **Tái hiện theo mã:** Mở create/edit playlist (autofocus), hoặc report có mô tả3–5 dòng, ở cửa sổ thấp; bàn phím làm vùng còn lại nhỏ hơn form. Column không có đường cuộn để tới privacy/submit.
- **Ảnh hưởng:** Field hoặc nút xác nhận bị khuất/overflow trong lúc nhập, cản hoàn thành báo cáo hoặc chỉnh sửa mà vẫn giữ bàn phím.
- **Khắc phục:** Dùng viewport cuộn giới hạn theo size.height−viewInsets.bottom, SafeArea và padding keyboard đúng tầng; giữ nút/field đang focus trong vùng nhìn.
- **Kiểm thử hồi quy đề xuất:** Portrait nhỏ/landscape, keyboard mở/đóng, mô tả nhiều dòng và text scale; có thể cuộn tới mọi field và submit.
- **Trạng thái:** Đọc cấu trúc/ràng buộc; chưa mở bàn phím hoặc chạy Flutter.

### BUG-073 — Offline player lấy chiều cao theo chiều rộng và tràn ở landscape

- **Bằng chứng:** [offline_player_screen.dart:114](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/offline_player_screen.dart:114)–160.
- **Điều kiện:** Mở video offline ở landscape640×360 hoặc844×390 logical px, ngoài native fullscreen.
- **Cách xảy ra:** Scaffold có AppBar, body Column không scroll. AspectRatio16/9 dùng full width, không giới hạn theo body height; Chip backgroundPlayback thêm chiều cao nếu được phép.
- **Tái hiện theo mã:** Ở844px rộng, player cần844×9/16=474,75px, đã lớn hơn390px toàn màn hình trước khi trừ AppBar/insets. Tại640px rộng cần360px trong body ngắn hơn360px.
- **Ảnh hưởng:** Đáy vùng video vượt phần body nhìn được; Chip bên dưới cũng bị đẩy ra ngoài. Không kết luận crash hoặc hành vi controls native chưa quan sát.
- **Khắc phục:** LayoutBuilder/Flexible tính kích thước từ cả maxWidth/maxHeight, fit video trong vùng còn lại; xử lý landscape/fullscreen và SafeArea.
- **Kiểm thử hồi quy đề xuất:** 640×360/844×390 và portrait với/không backgroundPlayback; toàn player vừa body, nội dung phụ có chỗ hoặc cuộn được.
- **Trạng thái:** Phép tính constraint từ source; chưa chạy native player.

### BUG-074 — Reaction trả muộn của video A ghi đè metadata video B

- **Bằng chứng:** [watch_screen.dart:69](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:69)–71, [watch_screen.dart:169](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:169)–208, [watch_screen.dart:761](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:761); [video_card.dart:27](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/video_card.dart:27)–29; [mobile_app.dart:172](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_app.dart:172)–177.
- **Điều kiện:** Watch A đã mở bằng context.go (deep link hoặc đã chuyển related một lần); reaction A pending, mở related B và load B hoàn thành trước reaction A.
- **Cách xảy ra:** Go→go cùng route pattern có thể tái sử dụng WatchScreen State; didUpdateWidget nạp B. _react giữ video A trước await, sau await chỉ kiểm tra mounted, rồi dựng toàn bộ _video từ A, không kiểm tra videoId/generation.
- **Tái hiện theo mã:** A Like → go B → B detail/player commit → reaction A về → _video trở lại A trong khi route/player là B. Push→go lần đầu có imperative page key riêng nên không dùng làm điều kiện chứng minh.
- **Ảnh hưởng:** Title/channel/chapter/reaction không thuộc video đang phát; thao tác sau có thể dùng identity A. Đây là đường Flutter riêng, khác race User Web BUG-012.
- **Khắc phục:** Snapshot ID/request generation, chỉ commit khi ID vẫn hiện hành; invalidate trên didUpdateWidget, cân nhắc key theo videoId. _load cũng snapshot identity xuyên suốt chuỗi await.
- **Kiểm thử hồi quy đề xuất:** Go A→B với response đảo thứ tự, reaction/rating và đóng screen; dữ liệu hiển thị và mọi payload thuộc route hiện tại.
- **Trạng thái:** Đối chiếu router/widget lifecycle và async; chưa chạy GoRouter/Flutter.

### BUG-075 — Profile giữ snapshot danh sách phiên nên refresh không cập nhật UI

- **Bằng chứng:** [account_hub_screen.dart:78](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/account/account_hub_screen.dart:78)–106; [account_controller.dart:181](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/state/account_controller.dart:181)–214; [profile_screen.dart:493](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/profile_screen.dart:493)–522.
- **Điều kiện:** Mở Account → quản lý phiên ở viewport đủ cao để tới Refresh; dữ liệu server thay đổi rồi bấm Refresh. Lỗi snapshot cũng hiện qua callback refresh không phụ thuộc layout; controller cần hiển thị loading/error sau thao tác.
- **Cách xảy ra:** Hub load một lần rồi truyền sessions và sessionsLoading vào ProfileScreen. Route không có Listenable/Provider/AnimatedBuilder nghe controller. loadSessions gán một list mới và notifyListeners nhưng Profile vẫn đọc props/list ban đầu.
- **Tái hiện theo mã:** Mở với list S1 → refresh trả S2 → controller.sessions=S2, Profile.widget.sessions vẫn S1; notify không có subscriber để cập nhật props. Loading/error/success của controller cũng không được đưa vào route.
- **Ảnh hưởng:** Không thấy phiên mới/đã mất sau refresh và không có phản hồi trạng thái sống; khó xác nhận quản lý thiết bị. Revoke sửa list cũ có thể chỉ thấy sau rebuild khác, không có cập nhật chủ động.
- **Khắc phục:** Để route nghe controller và đọc live state hoặc tự quản lý sessions bằng setState sau thao tác; render loading/submitting/error/success của route.
- **Kiểm thử hồi quy đề xuất:** Refresh trả list mới, revoke thành công/thất bại và logout others; list/indicator/feedback cập nhật ngay theo kết quả.
- **Trạng thái:** Đối chiếu ownership/subscription/callback; chưa gọi auth API.

### BUG-076 — Đóng thanh toán chưa paid vẫn báo đăng ký gói thành công

- **Bằng chứng:** [plans_screen.dart:124](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/plans_screen.dart:124)–148, [plans_screen.dart:993](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/plans_screen.dart:993)–999.
- **Điều kiện:** Chọn gói trả phí, đóng PaymentDialog khi còn pending/expired/chưa paid.
- **Cách xảy ra:** Dialog trả _paid=false khi bấm Đóng. Code chỉ hiện paymentConfirmed trong nhánh paid=true, nhưng subscribeSuccess nằm sau nhánh và vẫn chạy với paid=false.
- **Tái hiện theo mã:** Payment pending → Đóng trả false → không chạy paymentConfirmed nhưng vẫn chạy snackbar subscribeSuccess và reload.
- **Ảnh hưởng:** User được báo đăng ký thành công khi payment/gói chưa được kích hoạt; thông báo sai gây hiểu nhầm trạng thái mua.
- **Khắc phục:** Return hoặc hiển thị pending/cancelled khi paid!=true; chỉ báo thành công sau xác nhận server và snapshot gói tương ứng.
- **Kiểm thử hồi quy đề xuất:** Pending/expired/cancelled/paid và đóng dialog; snackbar phản ánh đúng trạng thái, gói miễn phí vẫn xử lý riêng.
- **Trạng thái:** Phân tích boolean/control flow; chưa tạo payment.


### BUG-077 — Download menu không khớp trạng thái server nên thiếu Resume/Pause

- **Bằng chứng:** [downloads_screen.dart:51](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/downloads_screen.dart:51)–57, [downloads_screen.dart:179](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/downloads_screen.dart:179)–206; [ContentService.cs:1396](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1396), [ContentService.cs:1420](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:1420)–1433.
- **Điều kiện:** Cancel một download request remote; hoặc request ở trạng thái processing theo API.
- **Cách xảy ra:** Client dùng contains(pause/hold) để hiện resume, contains(progress/download) cho pause, fail cho retry. Server trả ready/cancelled/processing/failed; cancelled không match nhóm phục hồi, processing không chứa progress. _operate cũng bỏ response fileUrl, không nối resume/retry với transfer local.
- **Tái hiện theo mã:** Ready → Cancel → server cancelled → menu chỉ còn cancel/delete, không có resume/retry dù API hỗ trợ. Bấm cancel lần nữa bị409; processing không có Pause.
- **Ảnh hưởng:** Không phục hồi request đã cancel từ UI, trạng thái/action không nhất quán; thay đổi server không đồng nghĩa file local tiếp tục tải.
- **Khắc phục:** Enum status chung, action mapping đúng contract thay heuristic contains; tách trạng thái request media khỏi transfer cục bộ và nối các action được hứa với download manager.
- **Kiểm thử hồi quy đề xuất:** Mọi state ready/pending/processing/cancelled/failed, các transition hợp lệ và409; resume/retry thực sự cập nhật transfer nếu được hỗ trợ.
- **Trạng thái:** Đọc client/endpoint/service contract; chưa tải file hoặc gửi request.

### BUG-078 — Form auth giữ nền trắng nhưng dùng chữ gần trắng của dark theme

- **Bằng chứng:** [app_shell.dart:524](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/widgets/app_shell.dart:524)–530, [app_shell.dart:592](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/widgets/app_shell.dart:592)–621; [app_theme.dart:16](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/theme/app_theme.dart:16), [app_theme.dart:29](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/theme/app_theme.dart:29), [app_theme.dart:98](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/theme/app_theme.dart:98)–112, [app_theme.dart:134](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/theme/app_theme.dart:134)–138.
- **Điều kiện:** Theme dark/system-dark, mở login/register/verify/reset, kể cả logout từ phiên đã lưu dark theme.
- **Cách xảy ra:** Container auth dùng AppColors.surface=white cố định. Title lấy colorScheme.onSurface, description lấy textTheme.bodyMedium.color; dark theme đặt hai màu chữ gần #FFFBFE, không có light Theme override đồng bộ form.
- **Tái hiện theo mã:** Dark theme → card trắng → title/instructions nhận màu gần trắng; cặp màu xảy ra ngay từ token/CSS tương đương, chưa đo contrast trên thiết bị.
- **Ảnh hưởng:** Tiêu đề/hướng dẫn xác minh và đặt lại mật khẩu khó đọc hoặc hòa vào nền; lỗi màu chức năng, không chỉ sở thích thiết kế.
- **Khắc phục:** Dùng surfaceFor(context)/colorScheme.surface hoặc bọc vùng auth bằng Theme nhất quán; rà text/field/button khi system-dark và logout.
- **Kiểm thử hồi quy đề xuất:** Light/dark/system, các trang auth và đổi theme/logout; chữ và nền theo cùng theme, đo contrast khi kiểm tra UI được phép.
- **Trạng thái:** Đối chiếu màu và consumer; chưa render/đo tương phản thực.

### BUG-079 — Empty/error view chung vượt chiều cao landscape và khuất nút phục hồi

- **Bằng chứng:** [hutube_widgets.dart:143](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/widgets/hutube_widgets.dart:143)–184; [app_theme.dart:198](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/core/theme/app_theme.dart:198)–203; [library_screen.dart:82](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/library_screen.dart:82)–89; [creator_hub_screen.dart:93](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_hub_screen.dart:93)–111; [mobile_scaffold.dart:122](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:122)–138, [mobile_scaffold.dart:214](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:214)–256.
- **Điều kiện:** Landscape640×360 (width<720 còn bottom navigation), library lỗi hoặc creator chưa có kênh/cần retry; compact=false.
- **Cách xảy ra:** HuTubeStateView là Center/Padding(vertical72)/Column không scroll. Riêng padding144+icon72+gap16/7/18+button50 đã307px chưa text; body nhỏ hơn toàn màn hình sau AppBar/navigation.
- **Tái hiện theo mã:** Vùng body khoảng232px hoặc ít hơn sau AppBar56/navigation72/insets, nhưng nội dung cố định đã tối thiểu307px trước title/message → overflow, không cuộn tới nút.
- **Ảnh hưởng:** Nút Retry/Create ở state page bị khuất, cản phục hồi mạng hoặc bắt đầu tạo kênh; chữ lớn làm tình huống nặng hơn.
- **Khắc phục:** State view cuộn được hoặc LayoutBuilder chọn compact theo height; giảm padding theo vùng khả dụng và text scale, giữ semantics và action truy cập được.
- **Kiểm thử hồi quy đề xuất:** 640×360 và portrait nhỏ, lỗi/chưa có kênh, text scale lớn; nút phục hồi luôn nhìn thấy hoặc cuộn tới được.
- **Trạng thái:** Tính từ chiều cao cố định và call sites; chưa chạy Flutter.

### BUG-080 — Library, comments, channel và creator bỏ metadata phân trang

- **Bằng chứng:** [library_screen.dart:42](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/library_screen.dart:42)–48; [content_service.dart:125](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/content_service.dart:125)–143, [content_service.dart:301](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/content_service.dart:301)–326; [watch_screen.dart:83](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:83)–95, [watch_screen.dart:744](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:744)–751; [channel_screen.dart:79](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/channel/screens/channel_screen.dart:79)–92, [channel_screen.dart:551](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/channel/screens/channel_screen.dart:551)–562; [creator_service.dart:106](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_service.dart:106)–131, [creator_service.dart:239](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_service.dart:239)–252; [creator_content_screen.dart:45](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_content_screen.dart:45)–52, [creator_comments_screen.dart:43](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_comments_screen.dart:43)–47.
- **Điều kiện:** History/liked/watch comments trên20 item; kênh trên30 video; creator trên50 video/comments trong điều kiện query hiện tại.
- **Cách xảy ra:** Các screen chỉ giữ items, bỏ page/pageSize/total và không có load-more. Service dùng mặc định page1 hoặc hardcode page1,size50; refresh tiếp tục cùng slice.
- **Tái hiện theo mã:** Record ở trang2 không xuất hiện khi duyệt danh sách; channel Videos chỉ render _videos30, watch chỉ render comments20. Bộ lọc có thể thay slice nhưng không cung cấp cách duyệt toàn bộ kết quả của filter.
- **Ảnh hưởng:** Không xem được toàn bộ collection qua màn này; item cũ và công cụ quản lý gắn với chúng khó tiếp cận, số count có thể lớn hơn số nội dung duyệt được. Không suy ra dữ liệu DB bị xóa.
- **Khắc phục:** Giữ PageResult metadata, pagination/infinite scroll/load-more theo từng collection, server search khi cần; page chỉ commit sau thành công và invalidate khi filter đổi.
- **Kiểm thử hồi quy đề xuất:** 21/31/51 item, tải trang2, đổi filter, retry page lỗi; duyệt được toàn bộ collection theo query không mất/trùng trang.
- **Trạng thái:** Đọc call sites và contracts; chưa dùng dataset thực. Khác BUG-055 của Studio Web và BUG-034 của CF backend.

### BUG-081 — Comment mới bị mất khỏi giao diện do State cũ được tái sử dụng theo vị trí

- **Bằng chứng:** [watch_screen.dart:495](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:495)–501, [watch_screen.dart:744](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:744)–751, [watch_screen.dart:1233](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:1233)–1256, [watch_screen.dart:1436](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:1436)–1455, [watch_screen.dart:1485](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:1485)–1489.
- **Điều kiện:** Watch đã có comment A (hoặc A/B), gửi comment N thành công trên chính màn.
- **Cách xảy ra:** _comments prepend N; các _CommentTile cùng runtimeType không key được ghép lại theo vị trí. State cache _item từ initState, không didUpdateWidget cập nhật khi props đổi. Nội dung và action tiếp tục đọc _item cũ.
- **Tái hiện theo mã:** Model [A,B] → [N,A,B], State tại vị trí0 vẫn A, vị trí1 vẫn B, vị trí2 mới nhận B → render [A,B,B] thay vì [N,A,B]. Đây suy luận từ reconciliation, chưa chạy widget.
- **Ảnh hưởng:** Comment mới đã lưu nhưng không thấy; comment cũ lặp và interaction dùng identity cache cũ, dễ khiến user gửi lại.
- **Khắc phục:** ValueKey(commentId) cho tile và super.key; đồng bộ props/local item khi dữ liệu cùng ID đổi, giữ reaction state theo đúng identity hoặc bỏ bản sao cache không cần thiết.
- **Kiểm thử hồi quy đề xuất:** Prepend comment khi có1/nhiều comment, thay dữ liệu cùng ID, xóa/reorder; nội dung và reaction/report ID luôn khớp item hiện tại.
- **Trạng thái:** Đối chiếu list construction/State/build/action; chưa render hoặc POST.


### BUG-082 — Thu nhỏ Watch sau go/deep link không rời trang và dựng thêm mini-player

- **Bằng chứng:** [watch_screen.dart:545](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:545)–551, [watch_screen.dart:761](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:761); [video_card.dart:27](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/video_card.dart:27)–29; [mobile_app.dart:172](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_app.dart:172)–177, [mobile_app.dart:307](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_app.dart:307)–318; [playback_session.dart:189](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/playback_session.dart:189)–193; [mobile_scaffold.dart:214](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:214)–220; [mini_player.dart:17](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/mini_player.dart:17)–20.
- **Điều kiện:** Mở related bằng context.go hoặc deep link tới watch; Navigator của shell chỉ còn watch page rồi bấm thu nhỏ.
- **Cách xảy ra:** onMinimize bật minimized rồi gọi maybePop và bỏ kết quả. Khi không có page để pop, Watch vẫn là child của shell; MiniPlayer bắt đầu render vì flagtrue trong khi full video stage vẫn render player.
- **Tái hiện theo mã:** Home push A → related go B thay stack → thu nhỏ B → maybePop=false, route vẫn watch B; shell giữ Watch và thêm MiniPlayer cho session hiện tại.
- **Ảnh hưởng:** Thu nhỏ không quay lại feed; cùng trang có full player và mini-player chồng vùng nội dung. Chưa kết luận việc hai native views dùng một controller gây crash.
- **Khắc phục:** Kiểm tra router.canPop và pop; khi không có backstack thì go Home với playback session được giữ. Điều chỉnh related navigation nếu cần giữ feed và chỉ cho một surface dựng controller.
- **Kiểm thử hồi quy đề xuất:** Watch qua push, related go, deep link và restore route; minimize luôn chuyển tới trang phù hợp và chỉ còn một player surface.
- **Trạng thái:** Đối chiếu route stack, conditional render và flag; chưa chạy native player.

### BUG-083 — Chất lượng mặc định đã lưu nhưng Watch luôn chọn rendition cao nhất

- **Bằng chứng:** [preferences_screen.dart:53](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/preferences_screen.dart:53)–64, [preferences_screen.dart:204](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/preferences_screen.dart:204)–235; [watch_screen.dart:92](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/content/watch_screen.dart:92)–107; [ContentService.cs:606](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:606)–616.
- **Điều kiện:** User được xem1080p, lưu defaultPlaybackQuality=480p rồi mở video có nhiều rendition480/720/1080.
- **Cách xảy ra:** Preferences gửi/lưu lựa chọn, nhưng Watch sort height tăng rồi chọn _renditions.last.url. Đường chọn nguồn không đọc defaultPlaybackQuality; playback API trả tập rendition được phép theo gói, không chọn dựa preference.
- **Tái hiện theo mã:** Setting480p đã lưu, tập trả về[480,720,1080] → source=1080. Lựa chọn mặc định không tham gia thuật toán chọn nguồn.
- **Ảnh hưởng:** Tùy chọn tiết kiệm dữ liệu không có tác dụng; mỗi video phải đổi thủ công và có thể dùng băng thông cao hơn ý muốn. Chưa đo lưu lượng thực.
- **Khắc phục:** Tải/cache preference theo user, chọn rendition phù hợp trong tập được phép và fallback rõ ràng; auto cần policy thích nghi riêng.
- **Kiểm thử hồi quy đề xuất:** 480/720/1080/auto, không có rendition đúng height, gói giới hạn và đổi user; nguồn đầu phát theo setting hợp lệ.
- **Trạng thái:** Đọc setting write, player selection và API; chưa phát video/đo mạng.

### BUG-084 — Upload cho nhập tiêu đề 150 ký tự nhưng API chỉ nhận tối đa 100

- **Bằng chứng:** [video_upload_screen.dart:270](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/video_upload_screen.dart:270)–279; [creator_service.dart:85](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/creator/creator_service.dart:85)–90; [ContentService.cs:629](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Infrastructure/Videos/ContentService.cs:629)–630.
- **Điều kiện:** Video hợp lệ, title101–150 ký tự ASCII sau trim, các điều kiện upload khác hợp lệ.
- **Cách xảy ra:** TextFormField maxLength150, validator chỉ kiểm tra rỗng. Service gửi nguyên title.trim; backend reject Trim().Length>100. Client không chặn dải input này trước multipart.
- **Tái hiện theo mã:** Nhập101 ký tự trong counter dưới150 → form hợp lệ → multipart → backend INVALID_TITLE vì vượt100.
- **Ảnh hưởng:** Upload bị từ chối với dữ liệu UI cho là hợp lệ; có thể tốn thời gian/dữ liệu truyền file trước validation service. Không có đo thời gian/traffic thực.
- **Khắc phục:** maxLength và validator thống nhất giới hạn100 của contract; chia sẻ schema/rule và định nghĩa cách đếm Unicode/whitespace nhất quán.
- **Kiểm thử hồi quy đề xuất:** 0/1/100/101/150 ký tự, whitespace và Unicode; client chặn input không hợp lệ trước gửi file.
- **Trạng thái:** Đối chiếu form/request/service validation; chưa upload.

### BUG-085 — Menu thao tác bị clip khi filter chỉ còn ít dòng và mở lên trong bảng

- **Bằng chứng:** [admin-channels-page.html:332](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:332)–375; [admin-channels-page.scss:287](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.scss:287)–290, [admin-channels-page.scss:555](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.scss:555)–588, [admin-channels-page.scss:1432](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.scss:1432)–1438; [admin-videos-page.html:418](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:418)–440; [admin-videos-page.scss:249](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.scss:249)–275, [admin-videos-page.scss:686](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.scss:686)–704, [admin-videos-page.scss:1384](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.scss:1384)–1393.
- **Điều kiện:** Viewport>720px, filter/search còn1–2 dòng, mở menu dòng đầu với nhiều thao tác.
- **Cách xảy ra:** idx>=length−2 luôn buộc mở lên với danh sách1–2 dòng. Menu absolute bottom100% vẫn nằm trong table container overflow-x:auto (overflow-y tính thành auto); Videos outer card còn overflow:hidden. Phần menu vượt phía trên scrollport bị clip, z-index không vượt được clipping.
- **Tái hiện theo mã:** Filter còn một channel → dòng đầu cũng open-upwards → menu nhiều button cao hơn khoảng trên anchor đến đầu bảng → các lựa chọn đầu bị cắt. Khoảng trống bên dưới Channels min-height360 không được dùng vì heuristic chọn hướng lên.
- **Ảnh hưởng:** Một số action đầu menu không nhìn/click được khi ít kết quả, đúng lúc user tìm một record để xử lý. Không quy kết mobile≤720 đã đổi overflowvisible.
- **Khắc phục:** Connected overlay/portal ngoài scrollport, chọn hướng theo khoảng trống thực và reposition khi scroll; không dựa index dòng hoặc chỉ tăng z-index.
- **Kiểm thử hồi quy đề xuất:** 1/2/nhiều dòng, dòng đầu/cuối, viewport720/721/desktop và cuộn bảng; mọi lựa chọn đều trong vùng dùng được.
- **Trạng thái:** Đối chiếu flip, overflow và media override; chưa đo clip trên browser.

### BUG-086 — Bảng Policies cắt cột bên phải trên mobile và không có đường cuộn ngang

- **Bằng chứng:** [admin-policies-page.html:75](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/policies/admin-policies-page.html:75)–145; [admin-policies-page.scss:1](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/policies/admin-policies-page.scss:1)–5, [admin-policies-page.scss:127](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/policies/admin-policies-page.scss:127)–135, [admin-policies-page.scss:144](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/policies/admin-policies-page.scss:144)–180.
- **Điều kiện:** Có policy, mở bảng ở320/360px hoặc cửa sổ hẹp hơn min-content của bảng.
- **Cách xảy ra:** Bảng8 cột trực tiếp trong table-container overflow:hidden, không có horizontal-scroll wrapper hay breakpoint chuyển layout. Ở320px, page padding32 mỗi bên để lại khoảng256px; riêng padding18 mỗi bên×8 cột đã288px trước text/width220 của cột code. Search cũng cố định280px trong toolbar hẹp.
- **Tái hiện theo mã:** Giữ width320px: bảng tối thiểu rộng hơn container, phần bên phải bị card clip; cuộn trang ngoài không đi tới phần đã bị clip trong card.
- **Ảnh hưởng:** Cột trạng thái/action bên phải không tiếp cận bằng pointer trên mobile; không mở detail/update từ hàng bị cắt. Toolbar cũng không thích nghi.
- **Khắc phục:** Scrollable table region có tên hoặc mobile stacked rows; min-width hợp lý, breakpoint giảm page padding và search width theo container/wrap.
- **Kiểm thử hồi quy đề xuất:** 320/360/390px, policy code/name dài và zoom; mọi cột/action có thể xem và thao tác, search nằm trong viewport.
- **Trạng thái:** Đối chiếu markup/cascade và phép tính width; chưa render screenshot.

### BUG-087 — Controls Channels/Videos mời thao tác mà role chỉ xem không thể hoàn tất

- **Bằng chứng:** [admin-channels-page.ts:88](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.ts:88)–92; [admin-channels-page.html:341](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:341)–375, [admin-channels-page.html:531](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/channels/admin-channels-page.html:531)–549; [admin-videos-page.ts:115](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.ts:115)–119; [admin-videos-page.html:389](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/frontend/admin-web/src/app/features/videos/admin-videos-page.html:389)–440; [AdminController.cs:270](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/AdminController.cs:270)–287, [AdminController.cs:313](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/backend/src/HuTube.Api/Controllers/AdminController.cs:313)–330.
- **Điều kiện:** Role có channel.view/video.view nhưng thiếu quyền mutation tương ứng.
- **Cách xảy ra:** canSuspend/canBan/canDelete/canEdit/... đã có, nhưng template không dùng để gate action; button chỉ xét status. Handler mở/submit form cũng không gate permission này. API RequirePermission vẫn từ chối403 đúng policy.
- **Tái hiện theo mã:** Role chỉ xem → vẫn thấy Edit/Hide/Ban/Delete phù hợp status → mở form, nhập reason, Confirm → API deny. Lỗi modal còn có thể nằm dưới backdrop như BUG-070.
- **Ảnh hưởng:** UI dẫn vào flow không thể hoàn thành và không giải thích thiếu quyền; mất công nhập lý do, dễ nhầm lỗi form với quyền. Không có kết luận bypass phân quyền backend.
- **Khắc phục:** Gate từng entry và submit theo permission, ẩn hoặc disable với lý do phù hợp; mapping restore đúng quyền và giữ enforce server.
- **Kiểm thử hồi quy đề xuất:** Role view-only và từng mutation permission riêng; controls khớp quyền, expired/changed permissions có feedback403 ngay trong form.
- **Trạng thái:** Đọc computed/template/handlers/API; chưa tạo role hoặc gửi mutation.


### BUG-088 — Màn thiết bị mở từ AccountHub không có vùng cuộn cho nội dung dài

- **Bằng chứng:** [account_hub_screen.dart:58](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/account/account_hub_screen.dart:58)–59, [account_hub_screen.dart:78](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/features/account/account_hub_screen.dart:78)–105; [profile_screen.dart:106](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/profile_screen.dart:106)–118, [profile_screen.dart:415](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/profile_screen.dart:415)–539; [mobile_app.dart:116](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_app.dart:116)–122; [mobile_scaffold.dart:214](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/app/mobile_scaffold.dart:214)–220.
- **Điều kiện:** Đăng nhập, từ AccountHub mở quản lý thiết bị/phiên ở viewport thấp, nhất là landscape640×360; nhiều sessions hoặc text scale lớn tăng chiều cao.
- **Cách xảy ra:** _open push page=ProfileScreen trực tiếp, không wrapper scroll. ProfileScreen trả Column gồm profile card, nhiều section, năm menu rồi Sessions/logout; file không có ScrollView/ListView. MobileScaffold chỉ cung cấp SafeArea/Stack, không tạo đường cuộn cho child.
- **Tái hiện theo mã:** Mở đường AccountHub._openSessions ở landscape; Column yêu cầu toàn bộ chiều cao các section nhưng body hữu hạn. Controls Refresh/sessions/logout ở cuối vượt vùng nhìn, không có gesture cuộn tới. Lỗi listener BUG-075 độc lập và vẫn tồn tại khi viewport đủ cao.
- **Ảnh hưởng:** Không tới được các thao tác quản lý/thu hồi phiên hoặc đăng xuất ở cuối màn qua đường mở này, dù đã có account page dùng cuộn ở nơi khác.
- **Khắc phục:** Tách SessionsScreen với Scaffold/SafeArea/ListView hoặc bọc viewport cuộn tại route AccountHub; tránh thêm scroll lồng vào mọi nơi dùng ProfileScreen vì AppShell cũ đã bọc scroll. Đồng thời sửa listener theo BUG-075.
- **Kiểm thử hồi quy đề xuất:** 360×640/640×360,0/1/nhiều sessions, text scale lớn và cả đường AppShell cũ; cuộn tới mọi action, không overflow hoặc scroll lồng bất hợp lý.
- **Trạng thái:** Đối chiếu route wrapper, Column và shell constraints; chưa render Flutter.


## Thứ tự khắc phục đề xuất

1. **Chặn cấp quyền/gói ngoài policy:** BUG-001, BUG-005, BUG-006, BUG-023, BUG-035, BUG-037; xử lý kiểm tra thanh toán, kiểm định media, transaction, khóa phiên và idempotency BUG-036 cùng đợt.
2. **Đóng đường lộ dữ liệu và đảo quyết định kiểm duyệt:** BUG-002–BUG-004, BUG-007, BUG-009, BUG-010, BUG-017, BUG-019, BUG-025, BUG-026; thực thi restriction BUG-024 từ policy chung.
3. **Bảo vệ file và tính đúng dữ liệu:** BUG-008, BUG-016, BUG-020, BUG-021, BUG-030. Sửa thứ tự purge và constraint trước khi bật lại job purge bị ảnh hưởng; không thử lại xóa object khi DB chưa lưu được trạng thái.
4. **Sửa luồng sử dụng và độ tin cậy:** BUG-011–BUG-015, BUG-018, BUG-022, BUG-027–BUG-029, BUG-031–BUG-034, BUG-038, BUG-039. BUG-029/BUG-030 cần ưu tiên khi có nhiều instance. BUG-032 có phạm vi quản trị hẹp, xử lý sau các P1.

5. **Ưu tiên giao diện có ảnh hưởng lớn:** BUG-042 (điều hướng Admin mobile) và BUG-068 (lưu sai metadata) xử lý cùng các P1. Sau đó sửa identity/generation ở BUG-049–BUG-051, BUG-059, BUG-074, BUG-075, BUG-081; không chỉ thêm spinner để che race.
6. **Sửa các vùng không dùng được trên màn hình nhỏ/keyboard/dark:** BUG-040, BUG-043–BUG-045, BUG-048, BUG-053, BUG-054, BUG-060, BUG-062, BUG-065, BUG-069, BUG-072, BUG-073, BUG-078, BUG-079, BUG-085, BUG-086, BUG-088. Dùng primitive modal/overlay, breakpoint theo vùng chứa, viewport cuộn và theme tokens chung; kiểm tra từng call site sau sửa.
7. **Đồng bộ UI với dữ liệu và contract:** BUG-041, BUG-046, BUG-047, BUG-052, BUG-055–BUG-058, BUG-061, BUG-063, BUG-064, BUG-066, BUG-067, BUG-070, BUG-071, BUG-076, BUG-077, BUG-080, BUG-082–BUG-084, BUG-087. Ưu tiên dữ liệu đầy đủ, trạng thái thanh toán đúng, lựa chọn thực sự được lưu/enforce và thông báo lỗi ngay tại form.

## Bao phủ và giới hạn kết luận

- **Đã rà soát:** đường authentication/session, resource authorization, webhook/subscription, API video/playlist/download/report/appeal, EF mapping và migration liên quan, quota/purge/worker, luồng chính User Web/Admin Web/Flutter và pipeline CF/model jobs. Đây là rà soát có trọng tâm theo luồng dữ liệu, không phải chứng nhận mọi dòng mã đều không còn lỗi.
- **Truy vấn:** đã đối chiếu điều kiện lọc, pagination, unique/CHECK constraint, transaction, snapshot EF và claim job. Các sửa hiệu năng ghi trong [memory.md](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/memory.md) được đối chiếu với mã hiện tại; không lặp lại lỗi đã sửa. Chưa chạy EXPLAIN ANALYZE, benchmark, thử đồng thời hoặc migration trên PostgreSQL thật.
- **Kết quả có trước yêu cầu chỉ xem code:** bộ unit tests .NET hiện có đạt 106/106; bộ tests recommendation đạt 29/29, có 2 cảnh báo deprecation. Các proof dùng key/dataset giả, EF InMemory, storage/router/HTTP/hub mock hoặc helper cô lập. Kết quả xanh không phủ tất cả điều kiện mới; InMemory không kiểm tra constraint/isolation của PostgreSQL.
- **Phân quyền và parser đã thấy có bảo vệ:** kiểm tra JWT issuer/audience/lifetime và session trong DB; hash token, khóa per-user trong các flow auth đã dùng AuthStore; RBAC trên nhiều API admin; EF SQL có tham số ở các vị trí được rà; bộ đọc model Python có allow_pickle=False, giới hạn ZIP/memory và hash artifact. Không ghi nhận SQL injection đã chứng minh trong phạm vi đọc này, không suy ra mọi truy vấn đều an toàn.
- **Giới hạn môi trường:** không kiểm tra traffic/secret production, load balancer, R2 thực, browser/Flutter thực hoặc mở công thức spreadsheet. BUG-029/BUG-030 phụ thuộc nhiều worker/instance; BUG-001 phụ thuộc thiếu key. Không quét CVE dependency trong đợt này; không đọc dump dữ liệu người dùng để kiểm tra.
- **Phạm vi tệp:** repository chính HuTube tại commit nêu trên; không coi build outputs, package caches, bản copy upload chưa được commit, repo clone khác và tài liệu ngoài repo là mã đang triển khai.
- **Đối chiếu STRIDE ở mức luồng:** giả mạo/cấp quyền sai (BUG-001/005/037), sửa policy hoặc dữ liệu sai (BUG-008/009/026/035), lộ thông tin (BUG-002/003/004/007/010/017/025), mất khả năng phục vụ hoặc mất file (BUG-016/018/021/028/030/033). Nhãn giúp gom hướng sửa, không thay thế điều kiện và bằng chứng riêng từng lỗi.
- **Kết luận trong phạm vi:** các P1 cần được sửa và kiểm tra hồi quy trước khi chốt phiên bản. Báo cáo mô tả đường mã có lỗi; không khẳng định production đã bị khai thác hoặc đưa ra điểm số bảo mật tổng thể.

Đợt mở rộng thêm **49 mục BUG-040–BUG-088** vào 39 mục có trước; các vị trí cùng nguyên nhân được gộp trong BUG-044/045/052. Phạm vi đọc giao diện:

| Nhóm | Các vùng đã đọc/đối chiếu | Loại kiểm tra |
| --- | --- | --- |
| User Web | Shell/topbar/sidebar, Home/Explore/Search/Watch/channel/playlist/library; Studio upload/edit/overview/content/analytics/comments/subtitles/settings; account/preferences/privacy, plans/payment, policy/notification flows | Template/controller/CSS cascade, routing, async state, request/API contract |
| Admin Web | Shell/auth/account/theme; dashboard/users/channels/videos/topics; plans/RBAC/policies; moderation queue/reports/appeals/strikes; notifications/recommendation/CF seeder và các dialog liên quan | Encapsulation/layer/overflow/breakpoints, keyboard, permission visibility, paging/filter và feedback |
| Flutter | Shell/navigation/theme/mini-player; auth/account/profile/sessions/preferences, plans/payment/share/invitations; feed/search/channel/library/playlists/comments/download/offline/watch; creator upload/content/comments, report/appeal/notification/policy/HuAI flows | Widget constraints, route/state lifecycle, controller subscriptions, service/API contracts |
| Liên kết backend | Channel/public routes, notifications/preferences, upload/comment/playlist, playback/download, moderation pagination và metadata writes; các phần auth/quota/worker/recommender đã đọc trong đợt trước | Kiểm tra đường dữ liệu và điều kiện có ảnh hưởng UI; không chạy dịch vụ thật |

Đây là danh mục vùng đã kiểm tra bằng nguồn, không phải kết quả chạy mọi trang ở mọi viewport. Các lỗi CSS/widget geometry được nêu với điều kiện cụ thể; chưa có screenshot, đo glyph, layout shift, keyboard thực, screen reader hay native-player runtime. Một giao diện có thể còn lỗi thẩm mỹ hoặc responsive chỉ hiện khi render; không gán điểm đẹp/xấu hay chứng nhận WCAG từ lần đọc này.

## Điểm giao diện cần kiểm chứng thêm

**UI-C01 — Row chọn chất lượng mặc định có nguy cơ tràn khi tăng chữ (chưa tính trong 88 phát hiện).**

- **Bằng chứng:** [preferences_screen.dart:89](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/preferences_screen.dart:89)–90, [preferences_screen.dart:182](F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/mobile/user-app/lib/account/screens/preferences_screen.dart:182)–239.
- **Điều kiện cần kiểm chứng:** viewport320 logical px, text scale2–3×, ngôn ngữ/tên lựa chọn dài.
- **Cơ chế nghi ngờ:** Row có Column nhãn/mô tả và DropdownButton đều non-flex, không Expanded/Flexible/Wrap; ListView chỉ cuộn dọc. Row đo intrinsic width của con; nếu tổng vượt vùng280px còn lại sau padding, control bị đẩy ngang. Chưa đo glyph/render nên chưa xác định ngưỡng scale thật sự tràn.
- **Cách xác nhận và hướng sửa:** khi được phép chạy giao diện, render các scale/ngôn ngữ trên thiết bị phù hợp và kiểm tra overflow/hit area. Nếu tràn, giới hạn vùng copy bằng Flexible/Expanded hoặc chuyển Column/Wrap theo LayoutBuilder, giữ dropdown có vùng thao tác đủ rộng.
- **Trạng thái:** candidate từ ràng buộc widget; tách khỏi các mục có đường lỗi xác định để không đánh đồng suy đoán typography với kết luận đã đối chiếu.

## Nhật ký rà soát

- Khởi tạo báo cáo trước khi kiểm tra chi tiết. Đã xác định repository chính và ghi nhận các tệp chưa được commit có sẵn.
- Skill áp dụng: `context-compression`, `context-optimization`, `filesystem-context`, `memory-systems`, `007`. Dùng ghi chú có nguồn và phiên bản, đọc theo phạm vi, lưu kết quả từng đợt để bảo toàn thông tin qua quá trình rà soát.
- Đợt 1: ghi BUG-001, BUG-002 ngay sau xác minh. Đợt 2: bổ sung BUG-003–BUG-006; kiểm tra lại controller và service trước khi ghi.
- Đợt 3: bổ sung BUG-007–BUG-015 sau khi đối chiếu đường mã. Unit tests hiện có chạy đạt 106/106; kết quả này không phủ các kịch bản mới trong báo cáo.
- Proof verifier cục bộ (source link trực tiếp): key rỗng + chữ ký tùy ý → `True`; chữ ký đúng SePay → `False`; body-only signature không timestamp hoặc timestamp invalid → `True`. Không dùng key thật.
- Đợt 4: ghi BUG-016–BUG-026 và tiếp nhận proof đã chạy trước yêu cầu “xem code thôi”. Từ yêu cầu này, chỉ tiếp tục đọc mã nguồn và viết báo cáo; không chạy thêm thử nghiệm.
- Đợt 5: đối chiếu mã và ghi BUG-027–BUG-038. Các lỗi nhiều instance ghi rõ điều kiện; các race/constraint chưa chạy database thật giữ nhãn static.
- Đợt 6: bổ sung BUG-039 từ EF mapping/account flow; cập nhật nhãn xác minh, số lượng, hướng ưu tiên và giới hạn kết luận. Chốt báo cáo 39 phát hiện; toàn bộ thay đổi trong repository của đợt này là file BUG.md.
- Đợt 7 (01/10/2026): bắt đầu rà soát mở rộng toàn dự án và ba giao diện; ghi ngay BUG-040–BUG-043 sau đối chiếu shell/sidebar, route/guard và custom select. Các phát hiện giao diện mới đều source-only; không chạy app/test/browser.
- Đợt 8 (01/10/2026): ghi BUG-044–BUG-051 sau đối chiếu popup thanh toán, wizard upload, sheet mobile và state phân trang/tìm kiếm/feed. Báo cáo đạt 51 mục; vẫn chỉ đọc mã và viết tài liệu.
- Đợt 9 (01/10/2026): bổ sung BUG-052–BUG-056 về filter không tham gia query, dark theme, geometry editor và số liệu/dataset Studio. Ghi 56 mục trước khi rà tiếp các flow còn lại.
- Đợt 10 (01/10/2026): ghi BUG-057–BUG-061 về tín hiệu xác minh sai, privacy tools giả trạng thái, restore phiên/geometry trang gói và preference thông báo không được lọc. Tổng61, chưa chạy app/test.
- Đợt 11 (01/10/2026): ghi BUG-062–BUG-064 về Home mobile, lỗi playlist bị nuốt và lựa chọn upload không truyền lên server. Tổng64, chỉ đọc mã nguồn.
- Đợt 12 (01/10/2026): ghi BUG-065–BUG-071 về layer dialog, backlog moderation, link môi trường, stale metadata, RBAC responsive và feedback/clear description. Tổng71; BUG-068 ưu tiên P1 vì có đường lưu sai metadata.
- Đợt 13 (01/10/2026): ghi BUG-072–BUG-076 về keyboard sheet, offline landscape, watch reaction, phiên thiết bị và thông báo thanh toán mobile. Tổng76, không chạy app.
- Đợt 14 (01/10/2026): ghi BUG-077–BUG-081 về download state mapping, dark auth, state view landscape, pagination mobile và identity comment. Tổng81, các bước tái hiện vẫn là phân tích theo mã.
- Đợt 15 (01/10/2026): ghi BUG-082–BUG-087 về minimize/backstack, playback preference, title upload, menu clipping, bảng Policies và permission UX. Tổng87; không tính candidate typography chưa đo render.
- Đợt 16 (01/10/2026): sau kiểm tra chéo ghi BUG-088 về Profile/Sessions không cuộn qua route AccountHub; gộp phạm vi modal/picker/filter vào044/045/052 và sửa điều kiện/tác động/citation ở048/050/051/054/060/066/068/069/075. Tổng88.
- Đợt 17 (01/10/2026): hoàn tất đối chiếu User Web/Admin Web/Flutter và liên kết backend, cập nhật phạm vi/ưu tiên/candidate còn cần render. Dùng lại bốn skill context, thêm tiêu chí kỹ thuật từ impeccable và accessibility-compliance-accessibility-audit; lưu notes có nguồn/phiên bản và kiểm tra chéo độc lập. Chốt88 mục (19P1/67P2/2P3); không chạy thêm app/test/harness/browser/network hoặc sửa mã ứng dụng.
- Kiểm tra tài liệu cuối: 88 mục chi tiết khớp88 dòng index, ID liên tục, trường mô tả đủ; 403 liên kết đến153 tệp nguồn tồn tại và dòng/range hợp lệ. Header khớp19P1/67P2/2P3; HEAD vẫn018ebc9, không có diff mã ứng dụng được theo dõi. Đây là kiểm tra tài liệu, không phải test ứng dụng mới.
