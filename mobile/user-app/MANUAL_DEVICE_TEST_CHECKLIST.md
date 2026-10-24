# Checklist test mobile trên máy thật

Ngày lập: 23/10/2026. Cập nhật: 24/10/2026. Phạm vi: ứng dụng `mobile/user-app` hiện tại.

## APK mới cho lượt tự test PLAY/SOCIAL/LIB

Bản ngày 24/10 đã build thành công tại `build/app/outputs/flutter-apk/app-debug.apk`.
Bản này **chưa cài lên điện thoại**; người dùng chọn tự test theo checklist.
Các ghi nhận máy thật bên dưới thuộc các bản trước, không phải xác nhận APK mới.

Ưu tiên test lại PLAY-11, PLAY-12, PLAY-13, SOCIAL-02, SOCIAL-06, LIB-01,
LIB-02 và nhóm POPUP ở cuối file. PiP/phát nền cần tài khoản có quyền tương ứng.
Với chế độ Chỉ tai nghe/loa ngoài, khi chưa kết nối app hiển thị Chờ tai nghe;
có thể tắt yêu cầu phát nền ngay từ player hoặc kết nối thiết bị âm thanh.

Cài cập nhật giữ dữ liệu; không gỡ app trước. Với bản local qua USB, backend
cần chạy cổng 5080 và thiết lập lại `adb reverse tcp:5080 tcp:5080` sau khi cắm
máy. Build khi không có thiết bị không thiết lập được reverse, dù script Gradle
cũ vẫn in dòng thành công. Hồi quy: **202 passed, 1 skipped**; sau sửa thông báo
chờ tai nghe chạy lại **10 passed**; analyzer sạch, Android debug build thành công.

## Lượt kiểm thử trực tiếp ngày 23–24/10/2026

**Thiết bị:** Samsung SM-G965F, Android 10 (API 29), kết nối USB. Đã cài APK
bằng `install -r`, không xóa dữ liệu hoặc đăng xuất tài khoản đang có.

**Đã tiếp tục sau khi chủ máy mở khóa:** Trang chủ, BXH/chủ đề Khám phá,
Theo dõi, tìm kiếm, tài khoản/cài đặt, thư viện, creator, thông báo, gói và chính
sách đều đã mở với dữ liệu thật. Đã thấy khung hình video thực và trạng thái
phát/tạm dừng; chưa nghe/đo âm thanh. Ba bộ lọc đề xuất đổi được danh sách và
nằm bên trái (tọa độ đầu 53px trên màn 1080px, tương ứng padding 20 logical px).
Đổi lại bộ lọc đã xem sử dụng cache trong màn xem.

**Giới hạn:** lượt fullscreen bị lớp cửa sổ nổi của ứng dụng khác che nên chưa
kết luận đạt. Không gửi bình luận/report, không sửa/xóa nội dung thật, không
đăng xuất hoặc đổi mật khẩu, không thực hiện thanh toán. Cài đặt seek đã thử
15 giây rồi khôi phục 10 giây; zoom đã khôi phục tắt, autoplay giữ bật, PiP giữ
tắt. Đã khôi phục `stay_on_while_plugged_in` về giá trị ban đầu `0` sau test;
player đã đóng và app trở về Trang chủ.

**Đo tại máy phát triển qua các URL local:** `/system/info` khoảng 0,076s;
`/feed/home?pageSize=10` khoảng 0,201s. Đây là số đo HTTP từ máy phát triển,
không phải thời gian từ lúc chạm đến khi render trên điện thoại.
Cổng recommendation 8000 không có dịch vụ lắng nghe; ADB chỉ reverse cổng 5080.

**Đã sửa trong mobile:** tải detail/playback/quyền/chất lượng đồng thời; thông tin
chủ kênh tải riêng; đề xuất bắt đầu ngay khi có detail. Request cá nhân hóa trên
màn xem có ngân sách chờ 1,2s trước khi resolve catalogue qua API nội dung;
đây không phải cam kết mọi ảnh thumbnail hiển thị trong 1,2s và không làm mô hình
AI chạy nhanh hơn. Cache từng bộ lọc trong màn xem để tránh tải lại khi đổi qua lại.
Khi inference lỗi, kiểm tra kết nối API nội dung thay vì coi cả app mất mạng.

**Bằng chứng:** `../../.work/mobile-audit/device/` có ảnh các màn đã quan sát.
Các kết quả `Một phần` chỉ xác nhận phần ghi rõ; không thay thế ca end-to-end.

**Sửa bổ sung khi test:** thiếu bản dịch `search.sort.title` (đã xác nhận trên
APK máy thật); request độc lập của tài khoản và lịch sử/đã thích chạy đồng thời,
lookup kênh lỗi không chặn dữ liệu tài khoản còn lại. Thẻ phát tiếp được thay mới,
hủy timer khi rời màn/tắt autoplay hoặc người dùng phát/tua lại, đóng ở mốc 2 giây và truyền yêu cầu
phát vào video kế tiếp. Xử lý sự kiện completed của Android thay vì chỉ dựa
vào tick tiến độ cuối; native tự đặt tiến độ về 0 không hủy nhầm đếm ngược. Chính sách có khoảng cách card, ngày định dạng theo ngôn
ngữ, phần ngày/phiên bản tách khỏi nội dung để dễ đọc.

**Kết quả cuối:** `flutter test --no-pub --concurrency=2 --reporter expanded`:
**173 đạt, 1 bỏ qua** (API smoke thiếu cấu hình); `flutter analyze --no-pub`:
**No issues found**; build APK debug thành công và đã `install -r` lên thiết bị.
Một lượt chạy trước gặp Windows khóa thư mục tạm của test tải file; chạy riêng
13 bài hiệu năng và lượt toàn bộ cuối đều đạt. Log: `native-final-all.log`,
`native-final-analyze.log`, `native-final-build.log` trong thư mục bằng chứng.

**Phát tiếp trên máy thật (24/10):** tua video Black Myth Wukong gần cuối rồi
phát đến hết; thẻ phát tiếp hiện tên video PEWPEW, đếm ngược và biến mất khi đổi
màn. Video PEWPEW tự phát từ đầu: snapshot sau chuyển có nút Tạm dừng video,
tiến độ 0:13/14:14 và khung hình thay đổi. Đã dừng và đóng player sau xác nhận.
Bằng chứng: `device/autoplay-fixed.mp4`, `fixed-frame-26.jpg` (thẻ),
`fixed-frame-30.jpg` (chuyển màn, thẻ đã đóng), `after-autoplay-fixed.png`
(video kế tiếp đang phát). Mốc đúng 2 giây được kiểm bằng clock widget test;
video quay lấy mẫu chỉ xác nhận diễn tiến thực tế, không đo chính xác đến ms.
Nút Hủy, tắt autoplay, tua lại, rời màn và native reset đã có hồi quy tự động;
chưa thực hiện đủ các tình huống đó trên điện thoại.

**UI chính sách trên bản cuối:** cả ba nhóm Nguyên tắc cộng đồng, Quyền riêng tư,
Điều khoản dịch vụ đổi đúng nội dung; ngày hiển thị `Hiệu lực từ 18/09/2026`,
phiên bản tách riêng và card có khoảng cách. Chưa thử xuất PDF/in hệ thống.
Không có phép đo chính xác độ trễ render đề xuất trước/sau trên thiết bị.

### Phần chưa thể kiểm thử và điều kiện để làm tiếp

| Nhóm | Chưa xác minh trên máy thật | Cần chuẩn bị |
| --- | --- | --- |
| Tài khoản | Đăng ký, xác minh, Google, reset/đổi mật khẩu, thu hồi phiên, đổi A/B | Tài khoản thử và truy cập email/Google; thiết bị thứ hai cho phiên |
| Player | Âm thanh/đồng bộ, đổi chất lượng/tốc độ, phụ đề thật, fullscreen/zoom, queue đầy đủ | Video có rendition/track thực; không bị overlay ngoài app che |
| Quyền media | PiP, phát nền, tai nghe/cuộc gọi, khóa/mở khi phát | Tài khoản có quyền, OS cho phép PiP, phụ kiện/tình huống thực |
| Tương tác | Gửi/sửa/xóa/reply bình luận, đánh giá, follow, chia sẻ, lưu playlist | Dữ liệu thử để kiểm tra thao tác ghi |
| Creator | Upload/chọn ảnh/quyền máy ảnh, draft, pause/resume, publish, thành viên | Chủ kênh có quyền, tệp video/ảnh thử, tài khoản thành viên |
| Offline | Tải thật, chế độ máy bay, file bị mất/xóa, phân tách A/B | Video đủ quyền tải, hai tài khoản thử, dung lượng trống |
| Thông báo | Quyền OS, nhận push/SignalR, mở app từ thông báo | Sự kiện thật tạo notification và trạng thái foreground/background |
| Gói/thanh toán | Giao dịch, mời/nhận/rời gói, hạn mức | Môi trường thanh toán thử, tài khoản phù hợp; không giao dịch tiền thật tự động |
| UI/phục hồi | Theme/ngôn ngữ/chữ lớn, mất mạng, bấm nhanh, chạy lâu | Tiếp tục theo các ID bên dưới |
| CF | Độ trễ xếp hạng cá nhân hóa thực tế | Recommendation service chạy và truy cập được từ điện thoại |

## Cách ghi kết quả

Điền `Đạt`, `Lỗi` hoặc `Chưa test` vào cột KQ. Với tính năng yêu cầu quyền/gói,
ghi `Không áp dụng` nếu tài khoản không đáp ứng điều kiện; không đánh dấu Đạt.

Thông tin lượt test:

- Máy / Android hoặc iOS / phiên bản hệ điều hành:
- Phiên bản APK / thời gian cài:
- Backend đang dùng:
- Mạng: Wi-Fi / 4G,5G:
- Tài khoản thường / chủ kênh / có gói PiP, phát nền, tải xuống:

Chuẩn bị hai tài khoản thử nghiệm A/B, một kênh có video đã xử lý xong, một video
có nhiều bình luận, một video dài và các chất lượng/phụ đề có sẵn nếu muốn kiểm
tra lựa chọn tương ứng. Để test phiên đăng nhập, đăng nhập cùng tài khoản trên
một thiết bị hoặc trình duyệt khác. Backend phải truy cập được từ điện thoại.

Ưu tiên làm nhóm **1–5 và 8** trước, rồi các nhóm còn lại. Với thao tác xóa/thu hồi,
dùng dữ liệu và phiên thử nghiệm. Phần thanh toán dùng môi trường thử nghiệm.

## 1. Cài đặt và khởi động

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| APP-01 | Cài APK và mở lần đầu | Mở được Trang chủ; không crash hoặc bắt đăng nhập vô lý | Đạt cài APK cập nhật và mở Trang chủ; chưa test cài mới sạch |
| APP-02 | Đóng hẳn app rồi mở lại | Khởi động được, khôi phục phiên hợp lệ và cài đặt đã lưu | Một phần: khởi động lại sau cập nhật APK vẫn giữ phiên và cài đặt; chưa thử đóng/mở lặp dài hạn |
| APP-03 | Chuyển các tab Trang chủ, Khám phá, Theo dõi, Tài khoản; mở menu | Đúng màn hình; tab hiện tại rõ ràng; nút quay lại hoạt động | Một phần: đã mở các tab chính, menu, cài đặt và quay lại; chưa hết mọi nhánh điều hướng |
| APP-04 | Mở chức năng cần tài khoản khi chưa đăng nhập | Có hướng dẫn đăng nhập; không hiển thị dữ liệu riêng của người khác | Chưa test |

## 2. Tài khoản và phiên đăng nhập

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| AUTH-01 | Đăng ký email mới, mở email xác minh rồi đăng nhập | Luồng hoàn tất; trạng thái xác minh đúng | Chưa test |
| AUTH-02 | Nhập email/mật khẩu sai, để trống trường, mật khẩu không hợp lệ | Báo lỗi rõ; không kẹt loading; sửa và gửi lại được | Chưa test |
| AUTH-03 | Đăng nhập Google, thử hủy hộp thoại Google | Đăng nhập được nếu OAuth cấu hình đúng; hủy không làm app kẹt | Chưa test |
| AUTH-04 | Quên mật khẩu, mở link email, đặt mật khẩu mới | Đổi được; đăng nhập bằng mật khẩu mới; link sai/hết hạn có thông báo | Chưa test |
| AUTH-05 | Chỉnh tên, mô tả hồ sơ và ảnh đại diện; quay ra rồi mở lại | Thông tin được lưu; ảnh đúng hướng và không vỡ bố cục | Chưa test |
| AUTH-06 | Từ chối quyền chọn ảnh; sau đó cấp quyền và thử lại | Không crash; có thể phục hồi hoặc chọn lại | Chưa test |
| AUTH-07 | Đổi mật khẩu bằng mật khẩu hiện tại sai, sau đó đúng | Sai có báo lỗi; đúng đổi thành công | Chưa test |
| AUTH-08 | Mở danh sách phiên, lịch sử đăng nhập; thu hồi phiên thử trên máy khác | Danh sách cập nhật; phiên bị thu hồi không tiếp tục dùng tài khoản | Chưa test |
| AUTH-09 | Đăng xuất, đóng app, mở lại | Vẫn đăng xuất; không lộ dữ liệu riêng hoặc video tải của tài khoản cũ | Một phần: hộp thoại mới mở được, Hủy đóng hộp thoại và giữ phiên; chưa xác nhận đăng xuất thật |
| AUTH-10 | Đăng xuất A rồi đăng nhập B | Hồ sơ, playlist, thông báo và tải xuống thuộc B | Chưa test |

## 3. Trang chủ, Khám phá, Tìm kiếm, Theo dõi

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| FEED-01 | Mở Trang chủ khi chưa và đã đăng nhập | Có nội dung hoặc trạng thái rỗng/lỗi rõ; video bấm mở được | Đã thấy nội dung khi đăng nhập; chưa test khách |
| FEED-02 | Kéo làm mới và cuộn xuống | Tải/làm mới đúng; không trùng vô hạn hoặc kẹt spinner | Chưa test |
| FEED-03 | Mở Khám phá, đổi chủ đề nhanh A → B → A | Danh sách khớp lựa chọn cuối; kết quả cũ không ghi đè | Một phần: chủ đề Đời sống → Giải trí → Đời sống đúng nội dung/lựa chọn; chưa bấm dồn tốc độ cao trên máy |
| FEED-04 | Tìm tên video, tên kênh/handle, từ không có kết quả | Kết quả phù hợp hoặc báo không tìm thấy; mở đúng video/kênh | Một phần: Wukong ra video, Gio ra trạng thái rỗng; xóa từ khóa được; chưa hết tìm kênh/handle |
| FEED-05 | Đổi sắp xếp, thời lượng, thời gian đăng; tải thêm kết quả | Bộ lọc áp dụng đúng và được giữ khi tải thêm | Một phần: mở được sheet và nhãn Sắp xếp theo đúng sau sửa; chưa xác minh mọi tổ hợp lọc/phân trang |
| FEED-06 | Chọn lại lịch sử tìm kiếm, xóa một mục, xóa tất cả; mở lại app | Thao tác đúng; lịch sử được lưu/xóa như mong đợi | Một phần: chọn Wukong từ lịch sử chạy lại tìm kiếm đúng; chưa xóa một/tất cả mục lịch sử |
| FEED-07 | Theo dõi rồi bỏ theo dõi kênh | Nút và danh sách Theo dõi cập nhật; mở lại vẫn đúng | Chưa test |
| FEED-08 | Trong Theo dõi, chọn từng kênh và bộ lọc | Nội dung khớp kênh/bộ lọc; không lẫn kết quả cũ | Một phần: đã mở Theo dõi và thấy kênh/video, chưa hết bộ lọc |

## 4. Xem video — ưu tiên cao trên thiết bị thật

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| PLAY-01 | Mở video, phát, tạm dừng, phát lại | Có hình và tiếng, đồng bộ; loading kết thúc hoặc có lỗi rõ | Một phần: thấy hình thật và trạng thái phát/tạm dừng; chưa nghe/đo đồng bộ âm thanh |
| PLAY-02 | Kéo thanh tiến độ; nhấn đúp hai phía | Tua đúng hướng, đúng khoảng cấu hình; không vượt đầu/cuối video | Một phần: tua Wukong đến 6:25 rồi phát đến hết được; chưa kiểm nhấn đúp hai phía/biên đầu-cuối đầy đủ |
| PLAY-03 | Đổi chất lượng và tốc độ phát nếu có lựa chọn | Video tiếp tục phát; lựa chọn áp dụng; không mất trạng thái bất thường | Một phần: menu có 360p/480p/720p; chưa xác nhận chuyển rendition/tốc độ thực tế |
| PLAY-04 | Bật/tắt và đổi phụ đề có sẵn trên video | Phụ đề đúng lựa chọn, hiển thị đọc được; không có track thì báo phù hợp | Một phần: video thử chỉ có Tắt; cần video có track phụ đề thực |
| PLAY-05 | Vào/thoát toàn màn hình; xoay máy; thử zoom | Bố cục đúng, nút còn bấm được, âm thanh không phát chồng | Chưa xác nhận: lượt thử bị cửa sổ nổi ngoài app che; chưa kết luận lỗi player |
| PLAY-06 | Thu nhỏ thành mini-player rồi đổi tab | Tiếp tục đúng video; nội dung phía dưới vẫn cuộn/bấm được | Một phần: Back tạo mini-player đúng tiêu đề; chưa xác minh phát liên tục khi đổi hết các tab |
| PLAY-07 | Mở lại video từ mini-player, bấm Back, đóng mini-player | Điều hướng đúng; đóng thì dừng; không có hai player phát cùng lúc | Một phần: đóng được mini-player; khôi phục từ mini-player chưa kiểm tra đủ trên máy |
| PLAY-08 | Mở hàng đợi, đổi thứ tự/xóa mục, chuyển bài, shuffle/loop nếu hiển thị | Phát đúng mục; video đang xem không đổi sai do thay đổi chỉ số | Chưa test |
| PLAY-09 | Bật/tắt autoplay rồi để video chạy hết | Chuyển video tiếp theo theo cài đặt, không chuyển nhiều lần | Một phần: bật autoplay chuyển Wukong → PEWPEW và tự phát từ đầu trên APK cuối; chưa thử tắt trên máy |
| PLAY-10 | Xem một đoạn, rời video rồi mở lại | Lưu tiến độ và khôi phục theo luồng app; lịch sử được cập nhật | Một phần: video Gió mở lại gần cuối theo tiến độ đã lưu; chưa xác minh nhiều đoạn/tài khoản |
| PLAY-11 | Dùng tài khoản có quyền PiP, bật PiP rồi về Home của điện thoại | Cửa sổ PiP xuất hiện; điều khiển và quay lại app được | Đã sửa luồng PiP Android dùng player hiện có, bỏ chờ đóng fullscreen; quyền và lỗi unsupported có test tự động. Chưa test PiP thật trên APK mới |
| PLAY-12 | Bật phát nền tại player bằng tài khoản có quyền; khóa màn hình rồi mở lại | Âm thanh theo trạng thái đã chọn; quay lại không tạo player trùng | Test controller/native-channel xác nhận 6 tổ hợp quyền/chế độ, đổi tai nghe và cùng player sau lifecycle pause/resume. Vẫn cần khóa/mở màn hình thật |
| PLAY-13 | Thử PiP/phát nền với tài khoản không có quyền | Có chặn/hướng dẫn phù hợp; không tự cấp quyền tính năng | Đã sửa phép kiểm tra quyền PiP; bật cài đặt không cấp quyền gói. Đạt hồi quy controller, cần xác nhận UI máy thật |
| PLAY-14 | Rút/cắm tai nghe, nhận cuộc gọi hoặc phát âm thanh từ app khác | Kiểm tra dừng/tiếp tục và audio focus; không phát chồng bất thường | Chưa test |
| PLAY-15 | Đổi Tất cả/Liên quan/Cùng kênh rồi chọn lại bộ lọc đã xem | Danh sách đổi phù hợp, chip căn trái; lựa chọn đã xem không tải lại vô ích | Đạt phần thao tác/bố cục trên máy; cache/request có test tự động, chưa đo độ trễ render chính xác |
| PLAY-16 | Khi autoplay bật, để video hết và quan sát thẻ phát tiếp | Thẻ có tên video/đếm ngược, đóng sau 2 giây; video kế tiếp tự phát | Đạt luồng Wukong → PEWPEW trên máy; mốc 2 giây có kiểm thử tự động |

| PLAY-17 | Chạm video từ Trang chủ/tìm kiếm/playlist/đề xuất, không bấm Play | Video mới tự phát sau khi nguồn tải xong, kể cả khi tắt Tự phát video tiếp theo; video thường giữ tiến độ cũ, video chuyển tiếp bắt đầu từ đầu | 2 widget test đạt và native-channel test xác nhận load trước play; cần tự test trên APK mới |

## 5. Tương tác và bình luận

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| SOCIAL-01 | Thích/bỏ thích và đánh giá video; tải lại | Trạng thái và số liệu cập nhật, không tăng trùng do bấm nhanh | Chưa test |
| SOCIAL-02 | Gửi bình luận, trả lời, sửa/xóa bình luận của mình | Nội dung lưu đúng; quyền sửa/xóa đúng; bàn phím không che nút gửi | Đã làm lại composer, popup trả lời/sửa/xóa; CRUD, hủy xóa và gửi khi có bàn phím đạt bằng widget/API mock. Chưa ghi bình luận thật trên APK mới |
| SOCIAL-03 | Đổi sắp xếp, tải thêm bình luận và câu trả lời | Danh sách đúng; không trùng hoặc mất mục bất thường | Một phần: mở sheet và chọn Mới nhất được; chưa xác minh thứ tự toàn bộ/phân trang/câu trả lời |
| SOCIAL-04 | Thích bình luận; chủ kênh ghim, thả tim, ẩn nếu có quyền | Trạng thái đúng; tài khoản thường không có thao tác của creator | Chưa test |
| SOCIAL-05 | Chia sẻ video qua hộp thoại hệ thống; hủy chia sẻ | Link/nội dung đúng; hủy quay về bình thường | Chưa test |
| SOCIAL-06 | Lưu video vào playlist từ màn xem hoặc menu thẻ video | Video nằm trong playlist chọn; trùng có xử lý phù hợp | Dùng chung popup cho màn xem/thẻ video, có tạo mới cố định và lỗi trùng rõ ràng; lưu/tạo/trùng đạt bằng API mock. Cần kiểm lại máy thật |

## 6. Thư viện và playlist

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| LIB-01 | Mở lịch sử và video đã thích; tìm/lọc/sắp xếp | Đúng dữ liệu tài khoản và điều kiện lọc | Đã thay icon sao PNG bằng icon vector bo tròn theo theme; giữ lọc 1–5 sao. Dữ liệu thật trước đó đã tải, chưa test hết lọc/sắp xếp trên APK mới |
| LIB-02 | Tạo playlist; sửa tên, mô tả, quyền riêng tư và ảnh bìa | Lưu đúng; mở lại còn dữ liệu | Nút Tạo luôn ở đầu danh sách, kể cả đã có playlist; có widget test danh sách có dữ liệu và tạo từ popup lưu. Sửa/ảnh bìa/quyền cần kiểm lại máy thật |
| LIB-03 | Thêm/xóa video; kéo hoặc dùng menu đổi thứ tự | Thứ tự được lưu; không xóa nhầm hoặc đổi nhầm mục | Chưa test |
| LIB-04 | Phát playlist và chuyển video | Hàng đợi đúng danh sách/thứ tự; bỏ qua hoặc báo mục không khả dụng | Chưa test |
| LIB-05 | Mở playlist public/private bằng tài khoản khác hoặc chưa đăng nhập | Truy cập theo đúng quyền riêng tư | Chưa test |
| LIB-06 | Xóa playlist thử nghiệm | Có xác nhận; xóa đúng playlist; danh sách cập nhật | Chưa test |

## 7. Kênh và công cụ creator

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| CREATOR-01 | Tạo kênh; thử handle trùng hoặc dữ liệu không hợp lệ | Thành công với dữ liệu hợp lệ; trường hợp sai có lỗi rõ | Chưa test |
| CREATOR-02 | Sửa thông tin kênh, avatar, banner | Lưu đúng; ảnh lỗi/quá giới hạn có thông báo; không crash | Chưa test |
| CREATOR-03 | Mở kênh bằng tài khoản chủ và người xem | Video/playlist/thông tin đúng; quyền quản lý chỉ hiện khi được phép | Một phần: chủ kênh mở DanhHiHi và danh sách 28 video; chưa đối chiếu vai trò người xem/tài khoản khác |
| CREATOR-04 | Mời thành viên thử, nhận/từ chối lời mời; kiểm tra quyền | Trạng thái cập nhật; người không đủ quyền không quản lý được | Chưa test |
| CREATOR-05 | Chọn video để upload, thumbnail, tiêu đề, mô tả, tags, quyền riêng tư | Đọc metadata đúng; validation rõ; upload khởi chạy được | Một phần: mở form upload có chọn video/thumbnail/tiêu đề; chưa chọn tệp hay upload |
| CREATOR-06 | Trong upload: tạm dừng/tiếp tục/hủy, mất mạng rồi thử lại | Trạng thái/progress đúng; không tạo bản upload trùng ngoài ý muốn | Chưa test |
| CREATOR-07 | Lưu draft, đóng/mở lại màn upload | Khôi phục dữ liệu draft; file không còn tồn tại được báo rõ | Chưa test |
| CREATOR-08 | Sửa metadata video, gửi duyệt, xuất bản khi đủ điều kiện | API và UI cùng trạng thái; không xuất bản khi chưa đủ điều kiện | Chưa test |
| CREATOR-09 | Quản lý bình luận, xem analytics và phụ đề | Màn hình tải đúng hoặc báo lỗi; riêng thao tác phụ đề xem mục chưa hoàn thiện bên dưới | Một phần: analytics và quản lý bình luận tải dữ liệu thật; chưa thao tác ghi hoặc kiểm hết bộ lọc/phụ đề |

## 8. Tải xuống và xem offline — ưu tiên cao

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| DL-01 | Yêu cầu tải video đủ quyền, chọn chất lượng và đợi xử lý | Mục tải xuất hiện với trạng thái chính xác | Một phần: mở Bản tải xuống có trạng thái rỗng đúng; chưa yêu cầu/tải file thực |
| DL-02 | Bắt đầu tải file về máy; pause/resume/cancel/retry theo nút có sẵn | Tiến độ/trạng thái đúng; hủy không để phát file dở | Chưa test |
| DL-03 | Tải hoàn tất, bật chế độ máy bay, mở video tải về | Xác minh thực tế phát được file cục bộ; nếu bị chặn thì ghi nguyên thông báo | Chưa test |
| DL-04 | Đóng/mở app sau khi tải xong | Danh sách và file tải còn; không báo hoàn tất khi file bị mất | Chưa test |
| DL-05 | Xóa một mục và xóa tất cả dữ liệu tải thử | Danh sách cập nhật; file không còn phát được sau xóa | Chưa test |
| DL-06 | Đổi A → B sau khi A tải video | B không thấy/phát được file riêng của A | Chưa test |
| DL-07 | Tải file lớn, chuyển app ra nền hoặc khóa màn hình | Ghi lại có tiếp tục/dừng/lỗi; transfer nền chưa được xác nhận đầy đủ | Chưa test |

## 9. Thông báo

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| NOTI-01 | Từ chối quyền thông báo, sau đó bật lại trong hệ điều hành | App không crash; trạng thái quyền phản ánh đúng | Chưa test |
| NOTI-02 | Tạo một sự kiện thật có gửi thông báo cho tài khoản thử | Badge/danh sách cập nhật; kiểm tra cả khi app mở và chạy nền | Một phần: xem được danh sách thông báo cũ; chưa phát sinh/nhận sự kiện mới |
| NOTI-03 | Bấm thông báo hệ thống khi app đang đóng | Mở đúng nội dung, xử lý đăng nhập nếu cần | Chưa test |
| NOTI-04 | Đánh dấu một/tất cả đã đọc, tải thêm danh sách | Badge và trạng thái đồng bộ, không phát sinh mục trùng | Chưa test |

## 10. Gói và thanh toán — cần dữ liệu thử

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| PLAN-01 | Xem danh sách gói, chi tiết và gói hiện tại | Giá/quyền/hạn mức khớp dữ liệu backend | Một phần: tải được catalogue và gói Free hiện tại, dung lượng 1,94/3GB; chưa kiểm mọi gói/quyền |
| PLAN-02 | Khởi tạo thanh toán thử, mở trang thanh toán rồi quay về | Trạng thái chờ/thành công/thất bại đúng, không tự ghi nhận đã trả tiền | Chưa test |
| PLAN-03 | Hủy thanh toán thử và cập nhật lại trạng thái | Hủy hoặc thông báo lý do không hủy được; không tạo giao dịch trùng | Chưa test |
| PLAN-04 | Mời/nhận lời mời gói chia sẻ, chỉnh dung lượng, xóa thành viên/rời gói thử | Hạn mức và quyền cập nhật đúng; có xác nhận khi cần | Chưa test |

## 11. Report, kháng nghị và chính sách

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| MOD-01 | Gửi report video/kênh/bình luận bằng dữ liệu thử | Chọn lý do và gửi được; lỗi/thiếu thông tin có hướng dẫn | Chưa test |
| MOD-02 | Mở vi phạm/kháng nghị, tạo kháng nghị cho dữ liệu phù hợp | Lưu và hiển thị đúng trạng thái; không báo thành công khi API lỗi | Chưa test |
| MOD-03 | Mở các trang chính sách | Đúng nội dung, cuộn/đọc và quay lại được | Một phần: cả ba nhóm chính sách tải đúng nội dung, ngày dễ đọc, quay về Trang chủ được; chưa xuất PDF/in |

## 12. Cài đặt, giao diện và phục hồi lỗi

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| UX-01 | Chuyển sáng/tối/theo hệ thống; đóng/mở lại app | Theme áp dụng và được lưu; chữ/nút đọc rõ | Chưa test |
| UX-02 | Chuyển tiếng Việt/Anh | Nhãn đổi theo lựa chọn; không hiện key dịch hoặc tràn chữ | Một phần: giao diện tiếng Việt và nhãn Sắp xếp theo đã kiểm; chưa chuyển toàn app sang Anh trên máy |
| UX-03 | Chỉnh khoảng nhấn đúp, autoplay, zoom, PiP rồi thử trên player | Giá trị được lưu và hành vi khớp, có xét quyền tài khoản | Một phần: seek 15 giây lưu khi mở lại, đã trả 10; zoom tắt, autoplay bật, PiP tắt; chưa đối chiếu hết hành vi player |
| UX-04 | Tăng cỡ chữ hệ thống; xoay ngang; mở bàn phím, sheet và dialog | Không tràn/cắt mất thao tác; vẫn cuộn tới nút cần bấm | Chưa test |
| UX-05 | Tắt mạng lúc đang tải dữ liệu, bấm thử lại sau khi bật mạng | Báo lỗi dễ hiểu, phục hồi được; không kẹt loading hoặc mất dữ liệu đã tải | Chưa test |
| UX-06 | Bấm nhanh nhiều lần nút gửi/lưu/thanh toán | Không tạo thao tác ghi trùng; có phản hồi đang xử lý | Chưa test |
| UX-07 | Rời màn hình ngay khi đang tải/lưu; quay lại | Không crash hoặc cập nhật dữ liệu nhầm màn hình/tài khoản | Chưa test đủ; không suy ra từ test tự động |
| UX-08 | Dùng app liên tục khoảng 15–20 phút, xem và đổi nhiều video | Ghi nhận giật, nóng máy, mất tiếng, crash hoặc player còn phát sau khi đóng | Chưa test |

## Những mục hiện chưa nên tính là chức năng hoàn chỉnh

- **HuAI:** đã gỡ khỏi mobile: thanh trên, menu, route, deep link và màn hình. Backend/web giữ nguyên.
- **Cập nhật 24/10 — các tùy chọn phát/tải đã có consumer runtime:** tải thông
  minh chạy ở cấp ứng dụng, chỉ tự tải qua Wi-Fi, tối đa 3 video trong hạn mức
  128/256/512/1024 MB. Không tự xóa video tải thủ công; chỉ chọn rendition được
  API cấp quyền. Wi-Fi only chặn transfer, chờ khi đổi mạng và tự tiếp tục khi
  hợp lệ; tạm dừng thủ công được giữ nguyên. Đề xuất tải bật/tắt khu vực gợi ý
  trong Bản tải xuống. Chất lượng mặc định dùng mức cao nhất không vượt lựa chọn
  nếu có; khi chỉ có mức cao hơn thì yêu cầu người dùng chọn, tải tự động bỏ qua. Hỏi mỗi lần vẫn
  mở sheet; riêng tải thông minh dùng tối đa 480p theo lựa chọn mặc định đó.
  Background mode áp dụng cho **phát nền**, có kiểm tra gói và tai nghe/loa ngoài.
  Các hành vi này đã có hồi quy tự động; phần cần xác nhận máy thật xem nhóm 13.
- **Creator → tải phụ đề / tạo phụ đề AI:** source hiện chỉ hiện Snackbar; chưa
  chọn/gửi tệp hoặc gọi tác vụ AI. Không đánh dấu Đạt chỉ vì có thông báo.
- **Tải file khi app chạy nền:** manager hiện gắn với tiến trình foreground;
  chưa có bảo đảm tiếp tục tải khi hệ điều hành dừng app.

## 13. Phát/tải đã nối runtime — kiểm tra bổ sung 24/10

| ID | Thao tác | Kết quả cần thấy | KQ |
| --- | --- | --- | --- |
| RUNTIME-01 | Chọn 720p rồi tải video có 360/480/720/1080p | Tạo yêu cầu 720p; không mở sheet Hỏi mỗi lần | Đạt bằng API mock; máy thật chưa đủ ca |
| RUNTIME-02 | Chọn Hỏi mỗi lần, bấm tải | Sheet chỉ có chất lượng được server cấp quyền; hủy không tạo yêu cầu | Chưa xác minh trên APK cuối |
| RUNTIME-03 | Bật Wi-Fi only, bắt đầu khi dùng mobile data | Hiện Chờ Wi-Fi, không gửi request tải file | Đạt bằng test manager; cần xác nhận đổi mạng trên máy |
| RUNTIME-04 | Đang tải qua Wi-Fi thì mất Wi-Fi, rồi bật lại | Không đánh dấu hoàn tất nhầm; tự tiếp tục khi có Wi-Fi; kiểm tra cấp quyền lại | Đạt bằng test manager; chưa tái hiện đủ trên thiết bị |
| RUNTIME-05 | Chủ động pause rồi đổi mạng | Vẫn pause, không tự chạy lại cho đến khi người dùng tiếp tục | Đạt bằng test manager |
| RUNTIME-06 | Bật tải thông minh trên Wi-Fi với video đủ quyền | Tối đa 3 video, trong hạn mức, đánh dấu Tải thông minh; không lấy video đã tải | Đạt bằng test coordinator; chưa tải file thật trên thiết bị |
| RUNTIME-07 | Giảm hạn mức hoặc tắt tải thông minh khi đang tải | Mục tự động chờ cấu hình/dung lượng; video hoàn tất và video thủ công được giữ | Đã triển khai; cần xác nhận đầy đủ trên thiết bị |
| RUNTIME-08 | Tắt/bật đề xuất tải | Khu vực gợi ý ẩn/hiện; tắt không gọi ranking mới; không thay đổi tính năng smart | Đạt bằng API mock; cần xem UI thật |
| RUNTIME-09 | Chọn Luôn bật/Tắt và ra nền | Hành vi theo lựa chọn, chỉ cho phép với gói có background_play | Đạt bằng controller/native-channel mock; cần gói đủ quyền và thiết bị |
| RUNTIME-10 | Chọn Chỉ tai nghe hoặc loa ngoài, cắm/rút khi ở nền | Cấp/quản lý phát nền theo route; rút thì pause; không tự cấp quyền gói | Đạt bằng controller/native-channel mock; chưa có phụ kiện/gói để kiểm đủ trên máy |
| RUNTIME-11 | Ở màn đăng nhập, bấm mũi tên góc trên / nút Back / cử chỉ cạnh trái | Trở về feed, app vẫn mở; không còn nút Về trang chủ ở cuối form | Đạt bằng widget test; máy thật đang đăng nhập nên chưa kiểm lại màn login, không đăng xuất để test |
| RUNTIME-12 | Đăng ký tên trùng rồi sửa sang tên mới | Hiện rõ trùng tên, giữ dữ liệu nhập; không yêu cầu nhập lại tất cả | Đạt bằng widget/API mock; đọc DB xác nhận tên trong ảnh đã tồn tại |
| RUNTIME-13 | Đăng ký email mới, nhận mail, dán link xác minh và đăng nhập | Có màn Kiểm tra hộp thư, link đúng origin, xác minh rồi đăng nhập được | Đạt với API mock; chưa tạo tài khoản/gửi email thật do auto-review chặn POST thử |
| RUNTIME-14 | Mở link hết hạn/đã dùng/sai nguồn; gửi lại email | Báo lỗi cụ thể; link sai nguồn không gọi API xác minh | Link sai nguồn có test; email thật chưa chạy |

Chưa đổi backend hoặc bỏ kiểm tra quyền gói. Truy vấn chẩn đoán tài khoản chỉ
đọc hai giá trị tồn tại/không tồn tại, không đọc mật khẩu/token. Lần POST thử
đăng ký thật đã bị automatic approval review chặn do có thể tạo tài khoản bền
vững và gửi email; không thực hiện lại qua đường khác.

Email xác minh web cần `AUTH_WEB_BASE_URL` khi build để khớp origin frontend
đang dùng. Mặc định Development là `http://localhost:4200`. Người dùng có thể
dán liên kết email vào mobile; app chỉ trích token rồi gửi tới API đã cấu hình,
không truy cập URL dán vào. Link `hutube://auth/verify-email` cũng được hỗ trợ.

Chỉ có Android đã build trên máy Windows. Bridge iOS dùng NWPathMonitor và
AVAudioSession, chưa build/ký/chạy iOS nên không được tính là đã xác minh iOS.

APK mới đã build và `adb install -r` thành công ngày 24/10; xác nhận Trang chủ
hiển thị và vẫn giữ phiên đăng nhập. Sau đó ADB không còn thiết bị kết nối,
nên các ca đổi mạng/phụ kiện/cài đặt trên APK cuối vẫn giữ trạng thái chưa
xác minh. Hồi quy: 194 passed, 1 skipped; chạy lại auth/navigation/download
sau bỏ nút cuối form: 15 passed; analyzer sạch.

## Mẫu gửi lỗi

```text
ID ca test:
Máy / hệ điều hành / bản APK:
Tài khoản hoặc loại quyền (không gửi mật khẩu/token):
Các bước:
1.
2.
3.
Mong đợi:
Thực tế / thông báo lỗi:
Có lặp lại không:
Ảnh hoặc video quay màn hình:
```

## 14. Popup và điều hướng — lượt sửa theo phản hồi 24/10

- POPUP-01: mở danh sách playlist đã có dữ liệu, nút **Tạo** có ở đầu với cả danh sách có dữ liệu; mở form rồi hủy không mất danh sách.
- POPUP-02: lưu video từ màn xem và menu thẻ; cùng một popup, nút tạo mới luôn trên danh sách kể cả có nhiều playlist.
- POPUP-03: chọn video đã có trong playlist; thông báo rõ đã lưu, không báo lỗi chung.
- POPUP-04: gửi/trả lời/sửa bình luận với bàn phím mở; nút gửi còn thấy; hủy xóa không gửi DELETE, xác nhận xóa mới thực hiện.
- POPUP-05: mở đánh giá sao, trả lời/sửa, xác nhận xóa ở sáng/tối, màn 320px và chữ lớn; không tràn, đóng được bằng nút rõ ràng.
- POPUP-06: mở cài đặt tài khoản/ngôn ngữ; nền theo theme, header có nút đóng. Menu ba chấm và hộp thoại dùng style chung.
- POPUP-07: mở hàng đợi; chỉ có một thanh kéo, nội dung tránh vùng hệ thống.
- POPUP-08: Trang chủ và menu không còn HuAI; link HuAI cũ không mở tính năng đã gỡ.

Các ca POPUP-01..05 đã có hồi quy tự động/ảnh render; POPUP-06..08 đã rà source.
Người dùng chọn tự test trên máy thật. APK mới đã build, chưa cài/xác nhận
trên thiết bị. Không ghi đè kết quả máy thật cũ thành kết quả của APK mới.

Khi test PLAY-11, thử cả nút PiP trên player và bật cài đặt PiP rồi về Home.
Mở lại app và xác nhận đúng video/tiến độ. Khi test PLAY-12, thử bật rồi tắt
phát nền từ player, khóa/mở máy, và thử chế độ tai nghe khi chưa có phụ kiện;
không được báo nhầm lỗi gói nếu chỉ đang thiếu thiết bị âm thanh.

## 15. Tự phát khi chọn video — cập nhật 24/10

Đã sửa luồng mở video thông thường: tự gửi lệnh play sau khi load thành công.
Cài đặt tự phát video tiếp theo không chặn phát video người dùng vừa chọn.
Tách cờ bắt đầu từ đầu khỏi lệnh tự phát để không xóa tiến độ đã lưu khi mở
video thông thường. Luồng chuyển tiếp sau khi hết video vẫn bắt đầu từ 0.
Không khởi tạo lại player khi khôi phục phiên xem đang có.

Cần thử PLAY-17 trên máy thật: chọn video lần đầu, chọn video đã xem dở,
chọn video đề xuất và thử lại khi tắt tự phát tiếp. Bản này cần cài cập nhật;
chưa được kiểm trực tiếp trên thiết bị.

APK tự phát mới đã build thành công tại `build/app/outputs/flutter-apk/app-debug.apk`;
analyzer sạch. Cài cập nhật bản này trước khi test PLAY-17.

## 16. Giao diện trung tính và gộp main — 24/10/2026

Đã gộp `origin/main` tại `20de970c` vào `fix/mobile` (merge `ea439ddd`).
208 test mobile đạt; 41 test tích hợp Content API đạt trên PostgreSQL local cô lập.
1 test live đăng ký/xác minh email được bỏ qua vì cần bật môi trường API/email
pickup riêng; đây là **chưa chạy**, không phải lỗi đã phát hiện.
Health của `https://api.dalitu.app/health` trả HTTP 200. Chưa xác nhận toàn bộ
nghiệp vụ trên server này bằng tài khoản thật; không xem health là test đăng nhập.

| ID | Cách tự kiểm tra trên APK mới | Mong đợi | Trạng thái máy thật |
| --- | --- | --- | --- |
| UI-09 | Vào kênh của mình, chọn Quản lý kênh và Cài đặt | Hàng trung tính có icon và chevron, mở đúng cài đặt, không còn khối nút hồng nhạt | Chưa chạy |
| UI-10 | Mở lưu playlist, tạo playlist, đánh giá, sửa/trả lời, báo cáo, xóa và đăng xuất | Nền sáng/tối rõ ràng, nút phụ viền xám, thao tác chính nổi bật, đóng/hủy không thay đổi dữ liệu | Chưa chạy |
| UI-11 | Tăng chữ hệ thống, xoay ngang và mở bàn phím ở các popup | Nội dung cuộn được, nút xác nhận/đóng còn chạm được, không tràn | Chưa chạy |
| SYNC-01 | Lọc lịch sử theo từ khóa/ngày/sắp xếp, tải thêm; chuyển tab đã đánh giá | Giữ bộ lọc khi tải trang tiếp; không lặp video hoặc lẫn dữ liệu hai tab | Chưa chạy |
| SYNC-02 | Lọc video quản lý theo trạng thái/quyền riêng tư/từ khóa, tải thêm | Trang tiếp theo giữ bộ lọc; chức năng sửa/xóa/tải lên vẫn hoạt động | Chưa chạy |
| SYNC-03 | Theo dõi kênh ở Khám phá, đổi danh mục nhanh, kéo làm mới | Không bị phản hồi cũ ghi đè thao tác; dữ liệu cập nhật sau làm mới | Chưa chạy |
| SYNC-04 | Mở video, chọn đề xuất, tự phát tiếp; thử tải, PiP và phát nền | Giữ hành vi theo PLAY-11, PLAY-12, PLAY-17 và cài đặt hiện tại | Chưa chạy |
| SYNC-05 | Chạy với API server mới, xem thumbnail/video và đăng nhập/refresh phiên | URL ảnh/video đúng; không lỗi do host local hoặc token khi chuyển màn hình | Chưa chạy |

APK debug mặc định vẫn dùng API local `127.0.0.1:5080` và recommendation
`127.0.0.1:8000`, cần `adb reverse` khi dùng USB. Để test server mới, build/run
với `--dart-define=API_BASE_URL=https://api.dalitu.app/api/v1` và
`--dart-define=RECOMMENDATION_BASE_URL=https://recommendation.dalitu.app/api/v1`.

APK sau gộp main đã build thành công: `build/app/outputs/flutter-apk/app-debug.apk`.
Analyzer sạch; chưa cài APK này lên máy thật. Cài bản mới trước khi thực hiện mục 16.
