# Khảo sát trải nghiệm HuTube

Popup được gắn tại root của User Web và bắt đầu đếm 120 giây sau khi nhận diện tài khoản đăng nhập, trên các trang ngoài đăng nhập/đăng ký. Chuyển trang nội bộ không đặt lại đồng hồ. Mỗi lần tải lại hoặc mở website là một lượt mới. Khách chưa đăng nhập không được nhắc vì chưa có tài khoản để đồng bộ.

Trong mỗi lượt, lời mời xuất hiện một lần. Bấm X, Escape hoặc click nền chuyển lời mời sang popup nhỏ có GIF Tenor đã chọn. Từ popup nhỏ có thể đóng hẳn, hoặc mở khảo sát. “Làm khảo sát” mở Google Form ở tab mới và điền sẵn họ tên cùng mã tài khoản có chữ ký. Việc mở form không đánh dấu hoàn thành.

Sau khi Google Forms thực sự nhận bài gửi, trigger gửi webhook có chữ ký HMAC SHA256 về HuTube. Backend xác thực chữ ký và mã tài khoản rồi ghi `public.users.feedback_survey_completed_at`. API trả `hasCompleted` từ thời điểm này, áp dụng cho mọi trình duyệt/thiết bị dùng tài khoản. Khi quay lại tab HuTube, trạng thái được đọc lại; lúc chờ trên HuTube, đọc lại mỗi 10 giây tối đa 10 phút. Trả lời khảo sát được giữ trong Google Forms; HuTube lưu thời điểm hoàn thành.

## Cài đặt một lần bằng tài khoản sở hữu Google Form

1. Mở **bản chỉnh sửa** của Google Form khảo sát, chọn **⋮ → Trình chỉnh sửa tập lệnh / Apps Script**. Phải mở từ Form, không phải từ Google Sheet nhận câu trả lời.
2. Dán nội dung `scripts/google-forms/hutube-feedback.gs` vào Apps Script.
3. Bấm **⚙ Cài đặt dự án (Project Settings)** ở thanh bên trái, kéo đến **Thuộc tính tập lệnh (Script properties) → Thêm thuộc tính tập lệnh (Add script property)**. Đây là cấu hình riêng của script, không phải câu hỏi trong Google Form. Thêm hai dòng và bấm **Lưu thuộc tính tập lệnh (Save script properties)**:
   - `HUTUBE_API_BASE_URL`: `https://hutube.onrender.com/api/v1` (hoặc API HTTPS tương ứng môi trường).
   - `HUTUBE_WEBHOOK_SECRET`: chuỗi ngẫu nhiên ít nhất 32 ký tự, giữ riêng. Có thể sinh bằng PowerShell: `[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))`.
4. Chạy **installHuTubeFeedback** và cấp quyền Google yêu cầu. Hàm kiểm tra đúng Form, thêm câu trả lời ngắn **Mã khảo sát HuTube**, tạo trigger **On form submit** và trigger thử lại mỗi 5 phút. Chạy lại bằng cùng tài khoản không tạo thêm câu hỏi/trigger. Đừng đổi loại hoặc xóa câu hỏi mã sau khi cài.
5. Execution log in ra `FeedbackSurvey__TokenEntryId=...`. Đặt biến môi trường backend:

   ```dotenv
   FeedbackSurvey__Enabled=true
   FeedbackSurvey__TokenEntryId=<ID từ log cài đặt>
   FeedbackSurvey__WebhookSecret=<đúng chuỗi HUTUBE_WEBHOOK_SECRET>
   ```

6. Triển khai backend và User Web cùng thay đổi này. Áp dụng migration `20261016100000_AddFeedbackSurveyCompletion` trước khi API phục vụ yêu cầu (theo quy trình migration của môi trường). Migration chỉ thêm một cột nullable vào `users`; tài khoản hiện có bắt đầu ở trạng thái chưa hoàn thành. Không cần bảng mới.

Popup tự tắt nếu cấu hình entry ID hoặc secret chưa đầy đủ, tránh mời người dùng làm khảo sát khi chưa thể đồng bộ. Không đưa secret vào Vercel frontend config hoặc nội dung câu hỏi. Giữ secret ổn định để link khảo sát đang mở tiếp tục hợp lệ.

Google Forms không hỗ trợ ẩn trường mã bằng link điền sẵn; người dùng sẽ thấy trường này và hướng dẫn giữ nguyên. Bài gửi trực tiếp từ link gốc không có mã vẫn được Google Forms lưu nhưng không thể đối chiếu chắc chắn với một tài khoản HuTube. Những bài cũ chỉ có họ tên cũng không thể tự ghép chính xác.

## Khi chạy cài đặt báo lỗi

- Log dừng ở `[1/4]`: kiểm tra hai thuộc tính ở bước 3. Script chỉ rõ tên thuộc tính thiếu hoặc không hợp lệ; không in giá trị bí mật ra log. `HUTUBE_WEBHOOK_SECRET` do chủ hệ thống tự tạo và phải khớp với `FeedbackSurvey__WebhookSecret` trên backend Render.
- Log dừng ở `[2/4]`: mở dự án từ **⋮ → Apps Script** của đúng Google Form bằng tài khoản có quyền chỉnh sửa Form. Dự án độc lập tạo tại script.google.com không có Form đang liên kết.
- Chỉ thấy **“Đã xảy ra lỗi không xác định. Vui lòng thử lại sau.”**, không có `[1/4]`: chưa đủ bằng chứng để kết luận lỗi ở code. Lưu dự án và thử chạy lại, xem chi tiết trong **Lần thực thi (Executions)**. Nếu đang đăng nhập nhiều tài khoản Google, mở cửa sổ riêng tư và chỉ đăng nhập tài khoản chỉnh sửa Form; Google ghi nhận Apps Script không hỗ trợ nhiều tài khoản cùng đăng nhập. Khi chạy lần đầu, hoàn tất hộp thoại cấp quyền.
- Không cần bấm **Triển khai** hoặc tạo web app. Chạy `installHuTubeFeedback` là bước cài trigger; chỉ chép code vào dự án chưa kích hoạt đồng bộ.

Tham khảo: [Google hướng dẫn xử lý lỗi và nhiều tài khoản](https://developers.google.com/apps-script/guides/support/troubleshooting), [cấp quyền Apps Script](https://developers.google.com/apps-script/guides/services/authorization).

## Khi API chưa sẵn sàng

Apps Script ghi xác nhận vào Script Properties trước khi gửi webhook. Nếu API lỗi hoặc Render đang khởi động, trigger mỗi 5 phút gửi lại với timestamp/chữ ký mới. Backend xử lý lặp an toàn và giữ nguyên lần hoàn thành đầu tiên. Kiểm tra mục **Executions** của Apps Script nếu tài khoản vẫn bị nhắc sau khi gửi. Không tự chạy `onHuTubeFeedbackSubmit` bằng nút Run vì hàm cần event từ Google Forms.

## Kiểm tra sau triển khai

- Tài khoản chưa hoàn thành: sau 2 phút xuất hiện lời mời; chuyển trang trong thời gian này không đặt lại đồng hồ.
- X / Escape / click nền: hiện popup năn nỉ nhỏ có GIF; lần đóng tiếp theo thoát được hoàn toàn, không lặp ngay trong cùng lượt.
- Mở khảo sát nhưng chưa gửi: tài khoản vẫn chưa hoàn thành. Lần truy cập mới tiếp tục được nhắc sau 2 phút.
- Nộp Google Form có mã: webhook thành công, trở lại HuTube thấy lời cảm ơn nếu popup còn mở; tải lại hoặc đăng nhập ở trình duyệt khác không bị nhắc.
- Sai chữ ký, sai mã, sai Form ID: không cập nhật tài khoản.
- Webhook bị lặp: thời điểm hoàn thành đầu tiên được giữ nguyên.

## Rollback

Đặt `FeedbackSurvey__Enabled=false` để ngừng popup; callback vẫn chấp nhận bài gửi đang chờ nếu entry ID và secret còn hợp lệ. Có thể tắt hai trigger trong Apps Script khi ngừng chức năng. Chỉ sau khi backend đã quay về phiên bản không đọc cột mới, rollback database về `20261012160000_RemoveVnPayTransactionNo` bằng quy trình migration của môi trường. Rollback này xóa trạng thái hoàn thành khảo sát.

Tham khảo API Google chính thức: [FormResponse và link điền sẵn](https://developers.google.com/apps-script/reference/forms/form-response), [sự kiện Google Forms](https://developers.google.com/apps-script/guides/triggers/events#google_forms_events).
