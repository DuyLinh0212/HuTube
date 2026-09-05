# HuTube Mobile — S4-01 / S4-02

Ứng dụng Flutter dùng chung API với User Web và Admin Web. Giao diện tiếng Việt bám mẫu sáng, điểm nhấn xanh trong `docs/design`.

## Chạy local

Backend cần chạy cổng 5080. Theo quyết định hiện tại của chủ dự án, local thay Staging cho giai đoạn này.

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/api/v1
```

- Android Emulator: `10.0.2.2` là máy host; đây cũng là fallback Development khi không truyền biến.
- Điện thoại Android nối USB: chạy `adb reverse tcp:5080 tcp:5080` rồi dùng `http://127.0.0.1:5080/api/v1`.
- iOS Simulator: dùng `http://localhost:5080/api/v1` khi backend chạy trên máy Mac. iOS cần Xcode để build.
- Điện thoại thật cùng LAN: truyền IP LAN máy backend và bind backend vào địa chỉ có thể truy cập. Không lưu URL vào source để chuyển môi trường.
- Khi có Staging, truyền `--dart-define=API_BASE_URL=https://<staging-host>/api/v1`. Build release dùng HTTPS; Android chỉ cho HTTP ở debug/profile.

Biểu tượng kết nối trên thanh đầu trang gọi `GET /system/info`, hiện trạng thái thực từ backend.

## Auth và phiên

Đăng ký → xác minh email → đăng nhập. Hỗ trợ gửi lại xác minh, quên/đặt lại mật khẩu, khôi phục phiên, tự refresh một lần khi API trả 401, tải/thu hồi phiên và đăng xuất thiết bị khác. Tài khoản bị tạm khóa/cấm được xử lý từ lỗi backend.

Access token chỉ ở bộ nhớ. Refresh token nằm trong `flutter_secure_storage` (Keychain / Android encrypted storage); không ghi token, mật khẩu vào log hoặc UI. Refresh đồng thời được hợp nhất. Phản hồi đăng nhập/refresh đến sau logout bị bỏ và phiên mới bị thu hồi. Mất mạng khi khôi phục không xóa refresh token để người dùng có thể thử lại. Logout xóa phiên thiết bị ngay; nếu chưa thu hồi được trên server, thông báo nêu rõ trạng thái đó.

## Deep link

Đã đăng ký scheme `hutube` trên Android và iOS. App chỉ nhận host `auth` và các route được whitelist:

- `hutube://auth/account`: yêu cầu đăng nhập rồi mở tài khoản.
- `hutube://auth/login`
- `hutube://auth/verify-email?token=<url-encoded-token>`
- `hutube://auth/reset-password?token=<url-encoded-token>`

Email hiện mở trang web; trang xác minh/đặt lại có thể chuyển sang app bằng các URL trên. Mã thật lấy từ email do backend gửi (Development dùng pickup `.eml`); không có API giả trả mã và không có trường nhập token kỹ thuật trong UI. Trên Android có thể kiểm tra routing bằng `adb shell am start -a android.intent.action.VIEW -d "hutube://auth/account" com.hutube.user_app`.

Custom scheme phục vụ local. Trước khi phát hành, cấu hình HTTPS App Links / Universal Links với domain đã sở hữu để xác minh chủ ứng dụng.

## Kiểm tra

```powershell
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:5080/api/v1
```

Test controller kiểm tra rotation, 401 đồng thời, phiên hết hạn, mất mạng, phản hồi trễ sau logout, suspended, whitelist link và password. Widget test kiểm tra validation, deep link qua login, lỗi suspended, link reset thiếu token và bố cục khi bàn phím mở trên màn hình hẹp. HTTP trong test được thay bằng mock có assertion contract; runtime luôn dùng API thật.

APK debug phục vụ local; cấu hình ký release của scaffold chưa phải khóa phát hành và không được dùng để đưa lên store.

### Smoke với API và PostgreSQL thật

```powershell
flutter test test/api_smoke_test.dart --dart-define=LIVE_API_BASE_URL=http://localhost:5080/api/v1 --dart-define=EMAIL_PICKUP_DIRECTORY=F:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/.work/mail --reporter expanded
```

Chỉ chạy với Development pickup email. Test tạo một tài khoản smoke có email duy nhất, kiểm tra Register → Verify → Login → Me → Refresh → Restore → Logout others → Forgot/Reset → từ chối phiên cũ → Login mới → Logout. Mặc định test được bỏ qua khi thiếu hai biến, nên unit/widget suite không đòi backend. HTTP và AuthController trong smoke là code thật; TokenStore thay bằng memory để chạy trên Windows, không thay cho kiểm thử Keychain/Android trên thiết bị.

Dòng `flutter_secure_storage` 10 được khóa theo major vì tương thích compileSdk 36 của Flutter hiện tại; dòng 11 yêu cầu SDK 37. Khóa resolved dependencies trong `pubspec.lock` được commit để CI dùng cùng phiên bản.
