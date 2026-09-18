# Sprint 6 — Người dùng, thuật toán và kiểm duyệt

> **Mục tiêu Sprint:** Hoàn thiện các chức năng người dùng thường xuyên sử dụng, đưa dữ liệu và thống kê thuật toán vào quy trình quản trị, đồng thời chuẩn hóa luồng Warning/Strike, Báo cáo và Khiếu nại.

## 1. Phạm vi và kết quả cần đạt

Sprint 6 tập trung vào ba nhóm việc:

1. **Tú:** trải nghiệm người dùng và luồng thanh toán/gói dịch vụ.
2. **Linh:** dữ liệu, thuật toán, kiểm thử thuật toán và dashboard thống kê trên Admin.
3. **Danh:** kiểm duyệt, Warning/Strike, Báo cáo/Khiếu nại và phân quyền Policy.

Các chức năng trong Sprint phải được xử lý xuyên suốt từ giao diện đến API, database, phân quyền và kiểm thử. Không chỉ hoàn thiện UI; các quy tắc quan trọng phải được kiểm tra ở backend để tránh việc người dùng gọi API trực tiếp và bỏ qua giới hạn nghiệp vụ.

## 2. Phân công chi tiết

---

# 2.1. Tú — Chức năng người dùng và thanh toán

## 2.1.1. Đăng ký và theo dõi kênh

### Mục tiêu

Cho phép người dùng đăng ký/theo dõi một kênh để xem lại danh sách kênh đang theo dõi và nhận nội dung mới từ các kênh đó.

### Chức năng cần thực hiện

- Hiển thị nút **Đăng ký/Theo dõi** trên trang kênh và các thẻ video.
- Cho phép đăng ký một kênh.
- Cho phép hủy đăng ký.
- Hiển thị đúng trạng thái hiện tại khi tải lại trang:
  - Chưa đăng ký.
  - Đã đăng ký.
  - Đang xử lý.
  - Thao tác thất bại.
- Hiển thị số lượng người đăng ký của kênh.
- Xây dựng danh sách các kênh mà người dùng đang theo dõi.
- Cho phép mở nhanh video mới từ danh sách kênh theo dõi.
- Không cho người dùng tự đăng ký chính kênh của mình nếu nghiệp vụ không cho phép.
- Người dùng chưa đăng nhập phải được yêu cầu đăng nhập khi thực hiện thao tác thay đổi trạng thái.

### Yêu cầu xử lý

- Một người dùng chỉ có một quan hệ đăng ký với một kênh.
- Gửi lại cùng một request không được tạo bản ghi trùng.
- Khi hủy đăng ký, số lượng đăng ký phải được cập nhật chính xác.
- Nếu kênh bị khóa hoặc bị xóa mềm, không cho đăng ký mới và phải xử lý các quan hệ cũ theo Policy.
- Lỗi mạng hoặc lỗi API phải trả trạng thái rõ ràng, không làm nút đăng ký bị kẹt ở trạng thái loading.

### Tiêu chí hoàn thành

- [ ] Đăng ký/hủy đăng ký hoạt động trên trang kênh.
- [ ] Trạng thái và số lượng người đăng ký được đồng bộ sau khi refresh.
- [ ] Danh sách kênh theo dõi hiển thị đúng dữ liệu.
- [ ] Backend chống bản ghi trùng và kiểm tra quyền đăng nhập.
- [ ] Có test cho đăng ký, hủy đăng ký, request lặp và kênh không còn hoạt động.

## 2.1.2. Playlist

### Mục tiêu

Cho phép người dùng lưu và sắp xếp các video thành danh sách phát để xem lại hoặc chia sẻ.

### Chức năng cần thực hiện

- Tạo playlist mới với:
  - Tên playlist.
  - Mô tả tùy chọn.
  - Trạng thái hiển thị: Public, Unlisted hoặc Private.
- Đổi tên, sửa mô tả và thay đổi quyền hiển thị.
- Xóa playlist theo cơ chế phù hợp, ưu tiên xóa mềm nếu playlist đã phát sinh hoạt động.
- Thêm video vào playlist.
- Xóa video khỏi playlist.
- Sắp xếp lại thứ tự video.
- Phát toàn bộ playlist theo đúng thứ tự đã lưu.
- Hiển thị trạng thái video không còn khả dụng:
  - Video bị xóa.
  - Video bị chuyển sang Private.
  - Video bị từ chối hoặc gỡ khỏi hệ thống.
- Không làm hỏng playlist khi một video trong danh sách không thể phát.

### Quy tắc nghiệp vụ

- Chủ playlist mới được sửa, xóa, thêm hoặc xóa video.
- Playlist Private không được xuất hiện với khách hoặc người dùng không có quyền.
- Playlist Unlisted chỉ truy cập được khi có đường dẫn hợp lệ.
- Không thêm trùng một video vào cùng playlist, trừ khi Product quyết định cho phép nhiều vị trí.
- Khi kéo thả sắp xếp, thứ tự phải được lưu ở backend; không chỉ thay đổi tạm thời trên giao diện.
- Thao tác thêm/xóa/sắp xếp phải có trạng thái loading và xử lý được double-click.

### Tiêu chí hoàn thành

- [ ] Tạo, sửa, xóa playlist.
- [ ] Thay đổi Public/Unlisted/Private.
- [ ] Thêm, xóa và sắp xếp video.
- [ ] Phát playlist theo thứ tự đã lưu.
- [ ] Hiển thị đúng video không khả dụng.
- [ ] Guest bị chặn khi truy cập playlist Private.
- [ ] Có test về quyền sở hữu, video trùng, thứ tự và visibility.

## 2.1.3. Tìm kiếm và lọc

### Mục tiêu

Giúp người dùng tìm đúng video/kênh cần xem và thu hẹp kết quả theo các thuộc tính có sẵn trong hệ thống.

### Chức năng cần thực hiện

- Tìm kiếm theo từ khóa:
  - Tiêu đề video.
  - Tên kênh.
  - Mô tả hoặc tag nếu dữ liệu hỗ trợ.
- Lọc theo:
  - Danh mục.
  - Tag.
  - Kênh.
  - Khoảng thời gian đăng.
  - Thời lượng video.
  - Đánh giá hoặc mức độ liên quan nếu Product đã hỗ trợ.
- Sắp xếp kết quả theo:
  - Liên quan.
  - Mới nhất.
  - Lượt xem.
  - Mức độ tương tác.
- Phân trang hoặc infinite scroll tùy layout hiện tại.
- Hiển thị số lượng kết quả và trạng thái bộ lọc đang áp dụng.
- Cho phép xóa từng bộ lọc hoặc reset toàn bộ bộ lọc.
- Hiển thị Empty State khi không có kết quả.

### Yêu cầu kỹ thuật và UX

- Không gửi request cho từng phím gõ; cần debounce ô tìm kiếm.
- Query tìm kiếm và bộ lọc phải được truyền lên backend, không tải toàn bộ dữ liệu về frontend rồi mới lọc.
- Giữ từ khóa và bộ lọc khi người dùng quay lại trang kết quả.
- Kết quả phải loại trừ video không được phép hiển thị công khai.
- Phân biệt rõ lỗi request, không có kết quả và không có quyền truy cập.
- Backend cần giới hạn page size để tránh request quá lớn.

### Tiêu chí hoàn thành

- [ ] Tìm kiếm theo từ khóa hoạt động ổn định.
- [ ] Các bộ lọc kết hợp được với nhau.
- [ ] Reset bộ lọc và phân trang hoạt động đúng.
- [ ] Không trả về video Private, Removed hoặc Rejected trong kết quả public.
- [ ] Có test cho từ khóa rỗng, ký tự đặc biệt, không có kết quả và nhiều bộ lọc.

## 2.1.4. Tự động thanh toán và quản lý gói

### Mục tiêu

Chuẩn hóa luồng chọn gói, thanh toán, kích hoạt subscription và cấp dung lượng theo gói mà không tin tưởng giá hoặc mã gói do frontend tự gửi lên.

### Ràng buộc mã gói theo tên

- Mỗi gói phải có một `code` duy nhất và ổn định.
- Tên gói dùng để hiển thị cho người dùng; mã gói dùng cho xử lý nội bộ và tích hợp thanh toán.
- Backend phải lấy giá, thời hạn, giới hạn upload và quyền lợi từ bản ghi gói trong database.
- Không cho client tự gửi giá, thời hạn hoặc dung lượng để thay thế giá trị của gói.
- Khi tạo phiên thanh toán, server phải kiểm tra:
  - Mã gói có tồn tại hay không.
  - Mã gói có đang Active hay không.
  - Mã gói có đúng với gói mà người dùng đã chọn hay không.
  - Số tiền từ cổng thanh toán có khớp với giá trị server tính hay không.
- Không đổi `code` của gói đã phát sinh subscription hoặc payment history; nếu cần thay đổi cách hiển thị thì cập nhật tên/mô tả hoặc tạo version mới.

### Luồng thanh toán tự động

```text
Người dùng chọn gói
        ↓
Backend kiểm tra code và giá gói
        ↓
Tạo payment/subscription ở trạng thái Pending
        ↓
Chuyển sang cổng thanh toán
        ↓
Nhận callback/webhook
        ↓
Kiểm tra chữ ký và idempotency
        ↓
Payment thành công → kích hoạt/gia hạn gói
Payment thất bại → ghi nhận lỗi và cho phép thử lại
```

### Bổ sung chia dung lượng từng người

- Dung lượng tổng của subscription lấy theo gói đã mua.
- Dung lượng được phân bổ cho chủ gói và từng thành viên.
- Tổng dung lượng phân bổ không được vượt quá dung lượng của gói.
- Mỗi người chỉ được sử dụng phần dung lượng được cấp, trừ khi Product cho phép dùng chung quota.
- Khi thêm thành viên:
  - Kiểm tra gói có cho phép thêm thành viên hay không.
  - Kiểm tra số lượng thành viên tối đa.
  - Xác định phần dung lượng được cấp cho thành viên.
- Khi thay đổi phần dung lượng:
  - Không được đặt hạn mức nhỏ hơn dung lượng người đó đã sử dụng.
  - Không làm tổng quota âm hoặc vượt quá quota gói.
- Khi thành viên rời nhóm hoặc bị thu hồi quyền, phần dung lượng còn lại phải được giải phóng theo đúng nghiệp vụ.
- Chủ gói và Admin có thể xem:
  - Dung lượng tổng.
  - Dung lượng đã dùng.
  - Dung lượng còn lại.
  - Phần dung lượng của từng thành viên.

### Tiêu chí hoàn thành

- [ ] Chọn gói bằng mã gói hợp lệ.
- [ ] Không thể giả mạo giá hoặc quyền lợi bằng request từ frontend.
- [ ] Payment callback/webhook xử lý được request lặp.
- [ ] Payment thành công kích hoạt đúng gói và thời hạn.
- [ ] Payment thất bại không kích hoạt nhầm subscription.
- [ ] Dung lượng từng người được lưu và kiểm tra ở backend.
- [ ] Có test cho mã gói sai, giá sai, webhook lặp, thanh toán thất bại và vượt quota.

---

# 2.2. Linh — Thuật toán, dữ liệu và chất lượng nội dung

## 2.2.1. Tạo dữ liệu cho thuật toán

### Mục tiêu

Chuẩn bị dữ liệu đủ và đúng định dạng để xây dựng, kiểm thử và theo dõi thuật toán đề xuất/nội dung của HuTube.

### Nguồn dữ liệu cần thu thập

- Người dùng.
- Video.
- Kênh.
- Lịch sử xem và thời lượng xem.
- Lượt thích/bỏ thích.
- Bình luận.
- Chia sẻ.
- Theo dõi kênh.
- Tìm kiếm và bộ lọc đã sử dụng nếu có log.
- Danh mục và tag.
- Trạng thái video: Public, Private, Removed, Rejected.

### Yêu cầu dữ liệu

- Mỗi bản ghi phải xác định được user, video, thời điểm và loại tương tác.
- Không đưa dữ liệu video bị xóa hoặc dữ liệu không hợp lệ vào tập public recommendation.
- Phân biệt dữ liệu thật và dữ liệu seed/test bằng trường `source` hoặc cơ chế tương đương.
- Chuẩn hóa các trường thời gian về cùng timezone.
- Xử lý dữ liệu trùng, thiếu hoặc sai kiểu trước khi đưa vào thuật toán.
- Có dữ liệu cho cả hai trường hợp:
  - User đã có lịch sử tương tác.
  - User/video mới chưa có lịch sử (cold start).

### Sản phẩm đầu ra

- Script hoặc job tạo dữ liệu test/seed.
- Schema hoặc data contract cho tập dữ liệu thuật toán.
- Tài liệu mô tả ý nghĩa từng trường.
- Một tập dữ liệu mẫu có thể tái tạo để chạy test.

## 2.2.2. Xây dựng và tích hợp thuật toán

### Phạm vi

- Định nghĩa đầu vào của thuật toán.
- Xác định cách tính điểm hoặc thứ tự ưu tiên nội dung.
- Kết hợp các tín hiệu phù hợp như:
  - Lịch sử xem.
  - Thời lượng xem.
  - Like/dislike.
  - Comment/share.
  - Theo dõi kênh.
  - Danh mục/tag.
  - Độ mới của video.
- Loại bỏ hoặc giảm ưu tiên nội dung không còn public.
- Có fallback khi không đủ dữ liệu cá nhân hóa:
  - Video mới.
  - Video phổ biến.
  - Video theo danh mục đang xem.
- Kết quả phải có thứ tự ổn định trong cùng một phiên truy vấn khi dữ liệu không thay đổi.

### Yêu cầu tích hợp

- API phải giới hạn số lượng kết quả trả về.
- Không để thuật toán làm lộ video Private, Removed hoặc Rejected.
- Có thể ghi nhận version/configuration của lần chạy để so sánh kết quả.
- Không làm chậm trang chủ đến mức ảnh hưởng trải nghiệm người dùng; nếu thuật toán lỗi phải dùng fallback an toàn.

## 2.2.3. Kiểm thử thuật toán

### Unit test

- Tính điểm cho một tương tác đơn lẻ.
- Tính điểm khi có nhiều loại tương tác.
- Ưu tiên video phù hợp danh mục/tag.
- Giảm hoặc loại bỏ video không còn public.
- Xử lý user mới và video mới.
- Xử lý dữ liệu trống, null và dữ liệu không hợp lệ.
- Kiểm tra giới hạn số lượng kết quả.

### Integration test

- Tạo dữ liệu mẫu → chạy job → đọc kết quả đề xuất.
- Tạo tương tác mới → kết quả thuật toán thay đổi theo thiết kế.
- Video bị chuyển sang Rejected/Removed → không còn xuất hiện trong feed public.
- User chưa có lịch sử → nhận được fallback hợp lệ.
- Job lỗi giữa chừng → không làm mất kết quả hợp lệ của lần chạy trước.

### Kiểm tra chất lượng

Tối thiểu cần ghi nhận:

- Số lượng bản ghi đầu vào.
- Số lượng user/video hợp lệ.
- Số lượng kết quả tạo ra.
- Tỷ lệ kết quả trùng.
- Tỷ lệ kết quả bị loại do trạng thái nội dung.
- Thời gian chạy.
- Metric đánh giá phù hợp với thuật toán đang dùng nếu đã chốt, ví dụ Precision@K hoặc Recall@K.

## 2.2.4. Dashboard thống kê thuật toán trên Admin

### Mục tiêu

Cho phép Admin theo dõi thuật toán đang có dữ liệu gì, chạy ra sao và kết quả có vấn đề hay không; dashboard không dùng để sửa trực tiếp dữ liệu gốc.

### Thông tin cần hiển thị

- Tổng số user được đưa vào tính toán.
- Tổng số video hợp lệ.
- Tổng số interaction event.
- Số user có lịch sử và user cold start.
- Số video được đề xuất.
- Số kết quả bị loại do Rejected/Removed/Private.
- Thời gian chạy gần nhất.
- Trạng thái job:
  - Pending.
  - Running.
  - Completed.
  - Failed.
- Version thuật toán hoặc cấu hình đang sử dụng.
- Top danh mục/tag được đề xuất.
- Tỷ lệ click, xem tiếp hoặc tương tác nếu hệ thống đã ghi nhận.

### Bộ lọc và chức năng

- Lọc theo ngày/tuần/tháng.
- Lọc theo version thuật toán.
- Xem chi tiết một lần chạy.
- Xem lỗi job nếu có.
- So sánh hai khoảng thời gian hoặc hai version khi dữ liệu cho phép.
- Export số liệu tổng hợp nếu quyền Admin cho phép.
- Hiển thị Loading, Empty State và Error State rõ ràng.

### Phân quyền

- Chỉ Admin có permission xem thống kê thuật toán mới truy cập được dashboard.
- Không hiển thị dữ liệu nhạy cảm của người dùng ngoài phạm vi cần thiết.
- Các thao tác chạy lại job hoặc thay đổi config, nếu có, phải là permission riêng và phải ghi Audit Log.

## 2.2.5. Sửa bug video bị từ chối vẫn hiển thị trên trang chủ

### Hiện trạng cần xử lý

Video đã bị Moderator từ chối vẫn có khả năng xuất hiện trong trang chủ hoặc feed đề xuất. Ngoài ra, một số request hợp lệ có thể bị cơ chế chặn request xử lý nhầm.

### Quy tắc kết quả mong muốn

Video chỉ được xuất hiện ở trang chủ/feed public khi đồng thời thỏa mãn:

```text
status = published
moderation_status = approved
visibility = public
```

Video có một trong các trạng thái sau phải bị loại khỏi feed public:

- Rejected.
- Removed.
- Private.
- Processing hoặc Pending moderation.
- Channel bị khóa nếu Policy yêu cầu.

### Phạm vi kiểm tra và sửa

- Kiểm tra query lấy dữ liệu trang chủ.
- Kiểm tra query tìm kiếm và đề xuất có dùng chung bộ lọc hay không.
- Kiểm tra cache hoặc dữ liệu đã snapshot trước thời điểm Moderator từ chối.
- Kiểm tra API chi tiết video và API thumbnail/stream có trả nội dung bị chặn hay không.
- Kiểm tra logic chặn request:
  - Không chặn nhầm request hợp lệ.
  - Không để client bỏ qua bộ lọc moderation bằng cách gọi endpoint khác.
  - Trả mã lỗi nhất quán khi nội dung không được phép truy cập.
- Sau khi thay đổi trạng thái moderation, dữ liệu feed/cache phải được cập nhật hoặc vô hiệu hóa theo thiết kế.

### Tiêu chí hoàn thành

- [ ] Video Rejected không xuất hiện trên trang chủ sau khi refresh.
- [ ] Video Rejected không xuất hiện qua API search/feed/recommendation.
- [ ] Không thể lấy stream hoặc thumbnail public của video đã bị chặn.
- [ ] Request hợp lệ không bị chặn nhầm.
- [ ] Có regression test cho trạng thái Published/Approved/Public và các trạng thái bị loại.

---

# 2.3. Danh — Warning, Strike, Báo cáo, Khiếu nại và Policy

## 2.3.1. Warning & Strike

### Mục tiêu

Ghi nhận lịch sử vi phạm một cách có kiểm soát và tự động áp dụng hình phạt khi kênh đạt ngưỡng từ chối theo quy định của Sprint.

### Quy tắc chính

- Mỗi lần Moderator từ chối video phải lưu:
  - Kênh liên quan.
  - Video và moderation case.
  - Policy vi phạm.
  - Lý do từ chối.
  - Người xử lý.
  - Thời điểm xử lý.
- Khi một kênh có đủ **5 lần từ chối hợp lệ**, hệ thống phải:
  1. Tạo hoặc cập nhật bản ghi Strike.
  2. Tự động khóa kênh.
  3. Ngăn kênh đăng hoặc phát hành nội dung mới theo Policy.
  4. Gửi thông báo cho chủ kênh.
  5. Ghi Audit Log cho toàn bộ hành động tự động.
- Không đếm trùng cùng một moderation case nhiều lần.
- Không tính các case chưa có quyết định cuối cùng là Rejected.
- Việc mở khóa hoặc thu hồi Strike phải lưu người thực hiện, lý do và thời điểm.

### Luồng xử lý

```text
Moderator từ chối video
        ↓
Lưu moderation decision + policy + reason
        ↓
Tính số lần từ chối hợp lệ của kênh
        ↓
Chưa đủ 5 lần → gửi thông báo từ chối
        ↓
Đủ 5 lần → tạo Strike
        ↓
Khóa kênh và áp dụng giới hạn
        ↓
Gửi thông báo + ghi Audit Log
        ↓
Cho phép chủ kênh xem lý do và gửi Khiếu nại
```

### Thông tin Warning/Strike

- ID bản ghi.
- User/kênh bị áp dụng.
- Loại vi phạm.
- Policy và version Policy.
- Số lần vi phạm hoặc từ chối tại thời điểm tạo.
- Mức độ: Low, Medium, High hoặc Critical nếu hệ thống đã sử dụng severity.
- Lý do hiển thị cho người dùng.
- Ghi chú nội bộ.
- Moderator hoặc hệ thống tạo bản ghi.
- Trạng thái: Active, Expired, Revoked.
- Thời điểm tạo, hết hạn hoặc thu hồi.
- Moderation case/report/appeal liên quan.

### Tiêu chí hoàn thành

- [ ] Một video bị từ chối tạo được lịch sử vi phạm đầy đủ.
- [ ] Cùng một case không bị tính nhiều lần.
- [ ] Đúng 5 lần từ chối hợp lệ thì kênh bị khóa tự động.
- [ ] Strike và lý do được hiển thị cho chủ kênh theo quyền.
- [ ] Kênh bị khóa không thể đăng/phát hành nội dung trái Policy.
- [ ] Có thông báo và Audit Log cho hành động tự động.
- [ ] Có thể xem lịch sử, thu hồi hoặc mở khóa theo permission.

## 2.3.2. Báo cáo nội dung và tài khoản

### Đối tượng được báo cáo

- Kênh.
- Comment.
- Video.

### Chức năng người dùng

- Mở form báo cáo từ trang kênh, video hoặc comment.
- Chọn lý do theo danh sách Policy được phép công khai.
- Nhập mô tả bổ sung nếu cần.
- Gửi báo cáo một cách idempotent để tránh bấm nhiều lần tạo nhiều case trùng.
- Xem trạng thái báo cáo của chính mình nếu nghiệp vụ cho phép.
- Không cho người dùng báo cáo đối tượng đã bị xóa hoặc không còn tồn tại.

### Chức năng Admin/Moderator

- Danh sách báo cáo với phân trang, tìm kiếm và bộ lọc:
  - Loại đối tượng.
  - Policy.
  - Trạng thái.
  - Mức độ ưu tiên.
  - Thời gian tạo.
  - Người xử lý.
- Gom các báo cáo trùng cùng một đối tượng thành một case khi phù hợp.
- Claim case để tránh hai Moderator xử lý đồng thời.
- Xem nội dung bị báo cáo và lịch sử vi phạm liên quan.
- Chọn quyết định:
  - Dismiss.
  - Warning.
  - Strike.
  - Hide.
  - Remove.
  - Lock channel.
  - Escalate.
- Bắt buộc nhập lý do đối với quyết định làm thay đổi trạng thái nội dung/tài khoản.
- Gửi thông báo kết quả cho người bị báo cáo hoặc người báo cáo theo Policy.
- Ghi Moderation History và Audit Log.

### Trạng thái báo cáo

```text
Pending → InReview → Resolved
                   ↘ Dismissed
                   ↘ Escalated
```

Không cho chuyển trạng thái tùy ý nếu không có quyền hoặc không thỏa điều kiện nghiệp vụ.

## 2.3.3. Khiếu nại

### Mục tiêu

Cho phép chủ kênh, chủ video hoặc tác giả comment yêu cầu xem xét lại một quyết định moderation phù hợp với Policy.

### Đối tượng có thể khiếu nại

- Video bị từ chối, ẩn hoặc gỡ.
- Kênh bị khóa.
- Warning hoặc Strike.
- Comment bị ẩn/gỡ nếu Policy cho phép.

### Thông tin khiếu nại

- Người gửi.
- Đối tượng bị ảnh hưởng.
- Quyết định gốc.
- Policy liên quan.
- Lý do khiếu nại.
- Evidence hoặc nội dung bổ sung.
- Thời gian gửi.
- Người xem xét.
- Kết quả và ghi chú xử lý.
- Liên kết đến moderation case/report/strike gốc.

### Trạng thái khiếu nại

- Pending.
- InReview.
- Approved.
- Rejected.
- Escalated.

### Quy tắc xử lý

- Không cho người đã ra quyết định gốc tự duyệt khiếu nại của chính quyết định đó nếu hệ thống có người review khác.
- Khi khiếu nại được chấp thuận:
  - Khôi phục nội dung hoặc kênh nếu phù hợp.
  - Thu hồi Warning/Strike nếu quyết định liên quan bị đảo ngược.
  - Cập nhật trạng thái và gửi thông báo.
- Không xóa lịch sử quyết định cũ; phải giữ được timeline trước và sau khi khiếu nại.
- Hết thời hạn khiếu nại phải trả trạng thái rõ ràng và không cho gửi lại nếu Policy không cho phép.

### Tiêu chí hoàn thành

- [ ] Chủ thể đủ điều kiện gửi khiếu nại.
- [ ] Khiếu nại liên kết đúng với quyết định gốc.
- [ ] Moderator có thể claim, review, approve, reject hoặc escalate.
- [ ] Khi approve, trạng thái nội dung/strike được cập nhật đúng.
- [ ] Giữ nguyên lịch sử cũ và ghi lại quyết định mới.
- [ ] Có test ngăn người không có quyền hoặc người xử lý gốc tự duyệt sai quy trình.

## 2.3.4. Bổ sung quyền Policy

### Mục tiêu

Tách quyền xem, quản lý Policy và thực hiện các hành động moderation để mỗi vai trò chỉ làm được phần việc được giao.

### Nhóm quyền đề xuất

| Nhóm | Quyền | Mô tả |
|---|---|---|
| Policy | `policy.read` | Xem danh sách và nội dung Policy được phép |
| Policy | `policy.manage` | Tạo, sửa bản nháp, archive hoặc publish Policy |
| Moderation | `moderation.read` | Xem moderation case và lịch sử xử lý |
| Moderation | `moderation.resolve` | Approve, Reject, Hide, Remove hoặc Escalate |
| Report | `report.read` | Xem báo cáo và đối tượng bị báo cáo |
| Report | `report.resolve` | Dismiss, Resolve hoặc áp dụng hình phạt |
| Appeal | `appeal.read` | Xem danh sách và chi tiết khiếu nại |
| Appeal | `appeal.resolve` | Approve, Reject hoặc Escalate khiếu nại |
| Strike | `strike.read` | Xem Warning/Strike và lịch sử |
| Strike | `strike.manage` | Tạo, thu hồi Strike hoặc mở khóa theo Policy |
| Channel | `channel.lock` | Khóa/mở khóa kênh |
| Audit | `audit.read` | Xem Audit Log liên quan |

### Yêu cầu phân quyền

- Frontend ẩn hoặc disable chức năng khi không có permission phù hợp.
- Backend luôn kiểm tra permission; không được chỉ dựa vào việc ẩn nút trên UI.
- Permission phải được kiểm tra cùng với business rule và trạng thái đối tượng.
- Hành động nhạy cảm phải ghi actor, action, resource, reason và timestamp.
- Không cho role thấp tự cấp thêm permission cho chính mình.
- Permission dùng cho quyết định moderation phải giữ được lịch sử khi Policy thay đổi version.

### Tiêu chí hoàn thành

- [ ] Permission được seed/migrate đầy đủ.
- [ ] Role phù hợp được gán đúng quyền.
- [ ] API trả 401 khi chưa đăng nhập và 403 khi không đủ quyền.
- [ ] UI không hiển thị thao tác không được phép.
- [ ] Test cả frontend guard và backend authorization.
- [ ] Audit Log được tạo cho thao tác quản lý Policy, Strike, Report và Appeal.

---

# 3. Phối hợp giữa các thành viên

## 3.1. Điểm giao nhau

- Tú cung cấp các trạng thái video/kênh và subscription mà Linh dùng để lọc dữ liệu thuật toán.
- Linh phải đảm bảo video Rejected/Removed không đi vào trang chủ, search hoặc recommendation.
- Danh cung cấp Policy code, trạng thái moderation và lịch sử Strike cho dashboard và dữ liệu thuật toán.
- Các thay đổi quyền Policy của Danh phải được kiểm tra lại trên các màn hình Admin do Linh hoặc thành viên khác tích hợp.
- Thanh toán và quota của Tú phải ghi được lịch sử để Admin có thể kiểm tra khi xử lý báo cáo/khiếu nại liên quan đến tài khoản.

## 3.2. Dữ liệu dùng chung

- `user_id`.
- `channel_id`.
- `video_id`.
- `plan_id` và `plan.code`.
- `moderation_case_id`.
- `policy_id`, `policy.code` và version Policy.
- Trạng thái video/kênh/subscription/payment.
- Audit Log và notification.

## 3.3. Nguyên tắc API chung

- API trả lỗi có mã ổn định để frontend hiển thị đúng thông báo.
- Request thay đổi dữ liệu quan trọng phải có cơ chế chống gửi lặp.
- Không trả dữ liệu nội bộ của moderation, payment hoặc Policy cho người không có quyền.
- Các thao tác có thể chạy lại phải idempotent.
- Thao tác nguy hiểm phải yêu cầu reason và ghi Audit Log.

---

# 4. Kịch bản kiểm thử Sprint 6

| Mã | Kịch bản | Kết quả mong đợi |
|---|---|---|
| S6-T01 | User đăng ký rồi hủy theo dõi một kênh | Trạng thái, số lượng và danh sách theo dõi được cập nhật đúng |
| S6-T02 | Gửi lặp request đăng ký | Không tạo bản ghi trùng, response nhất quán |
| S6-T03 | Tạo playlist Private và truy cập bằng Guest | Guest bị chặn, chủ playlist vẫn truy cập được |
| S6-T04 | Thêm, xóa và kéo thả video trong playlist | Thay đổi được lưu và giữ nguyên sau refresh |
| S6-T05 | Tìm kiếm kết hợp nhiều bộ lọc | Backend trả đúng kết quả, không tải toàn bộ dữ liệu về frontend |
| S6-T06 | Thanh toán bằng mã gói không tồn tại | Request bị từ chối, không tạo subscription |
| S6-T07 | Client gửi giá khác với giá trong database | Backend bỏ qua giá client gửi và dùng giá server |
| S6-T08 | Webhook thanh toán gửi hai lần | Chỉ kích hoạt/gia hạn một lần |
| S6-T09 | Thành viên dùng vượt dung lượng được cấp | Request bị từ chối và quota không bị âm |
| S6-L01 | Tạo dataset từ user, video và interaction | Dataset đúng schema, phân biệt được dữ liệu thật/seed |
| S6-L02 | User mới không có lịch sử xem | Thuật toán trả fallback hợp lệ |
| S6-L03 | Video chuyển sang Rejected | Không còn xuất hiện trên home/search/recommendation |
| S6-L04 | Chạy job thuật toán bị lỗi | Kết quả lần chạy trước vẫn an toàn, lỗi được ghi nhận |
| S6-L05 | Admin mở dashboard thuật toán | Xem được KPI, trạng thái job, bộ lọc và lỗi |
| S6-D01 | Video bị từ chối lần thứ năm | Kênh bị khóa, Strike được tạo, thông báo và Audit Log được ghi |
| S6-D02 | Cùng case bị xử lý lại | Không tăng số lần từ chối hoặc tạo Strike trùng |
| S6-D03 | User báo cáo video/comment/channel | Report được tạo đúng loại đối tượng và trạng thái Pending |
| S6-D04 | Moderator claim và resolve report | Chỉ người có quyền xử lý, lịch sử được lưu |
| S6-D05 | Chủ kênh gửi khiếu nại | Appeal liên kết đúng quyết định gốc và có timeline |
| S6-D06 | Role không có `strike.manage` gọi API khóa/mở khóa | API trả 403 và không thay đổi dữ liệu |

---

# 5. Definition of Done

Một đầu việc chỉ được xem là hoàn thành khi:

- [ ] Giao diện hoàn thiện cho trạng thái bình thường, loading, empty và error.
- [ ] API và database đã xử lý đủ luồng thành công/thất bại.
- [ ] Có kiểm tra authentication, authorization và business rule ở backend.
- [ ] Không tạo dữ liệu trùng khi người dùng gửi lại request.
- [ ] Có unit test cho logic chính.
- [ ] Có integration test cho các luồng liên quan đến database/API.
- [ ] Các lỗi hồi quy quan trọng đã được kiểm tra trên frontend.
- [ ] Thay đổi schema có migration và có thể chạy trên database mới/lẫn database hiện tại.
- [ ] Hành động nhạy cảm có notification hoặc Audit Log theo yêu cầu.
- [ ] Cập nhật tài liệu API hoặc hướng dẫn sử dụng nếu contract thay đổi.
- [ ] Không còn secret, credential hoặc dữ liệu test nhạy cảm trong source code.

# 6. Tiêu chí kết thúc Sprint

- [ ] Tú hoàn tất đăng ký/theo dõi, playlist, tìm kiếm/lọc và luồng thanh toán tự động.
- [ ] Ràng buộc mã gói theo tên/code hoạt động đúng và không thể giả mạo giá từ frontend.
- [ ] Chia dung lượng cho từng thành viên được lưu, kiểm tra và hiển thị đúng.
- [ ] Linh có dataset tái tạo được, test thuật toán và dashboard trên Admin.
- [ ] Video Rejected không còn lọt vào trang chủ hoặc các API public.
- [ ] Danh hoàn tất Warning/Strike, tự động khóa sau 5 lần từ chối hợp lệ.
- [ ] Báo cáo và Khiếu nại hoạt động cho Kênh, Comment và Video.
- [ ] Quyền Policy được kiểm tra ở cả UI và backend.
- [ ] Các kịch bản kiểm thử Sprint 6 đạt kết quả mong đợi.
