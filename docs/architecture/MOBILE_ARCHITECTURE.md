# HuTube Mobile User App - Kiến trúc toàn bộ

> Tài liệu này mô tả kiến trúc của riêng Mobile User App. Backend, database, User Web và Admin Web không thuộc phạm vi chỉnh sửa của tài liệu này.

## 1. Vai trò và phạm vi

Mobile User App là Flutter client cho người dùng cuối. Ứng dụng phụ trách:

- đăng ký, đăng nhập, Google Sign-In và khôi phục session;
- quản lý tài khoản, thiết bị và cài đặt;
- tạo/quản lý channel;
- gửi, nhận và xử lý channel invitation;
- upload avatar/banner;
- mở xác thực email và password reset qua deep link;
- hiển thị dữ liệu, loading, empty state và lỗi nhất quán;
- mở rộng về video, playlist, notification và report.

Ứng dụng không truy cập PostgreSQL trực tiếp, không giữ JWT signing key, không giữ Cloudinary API secret và không thay thế authorization của backend.

Backend API là nguồn sự thật cho identity, permission, channel role, quota, validation và trạng thái dữ liệu.

## 2. Vị trí trong hệ thống

~~~text
Flutter Mobile App
        |
        | HTTPS / JSON / multipart
        v
HuTube ASP.NET Core API
        |
        +-- PostgreSQL
        +-- Cloudinary hoặc local storage
        +-- Email provider
        +-- Google token validation
~~~

Mobile chỉ nhận API base URL và các cấu hình client-safe. Secret của database, JWT, mail và storage chỉ tồn tại ở backend/environment server.

## 3. Công nghệ hiện tại

- Flutter/Dart.
- Material UI và theme dùng chung.
- package http cho REST request.
- package flutter_secure_storage cho refresh token.
- package google_sign_in cho đăng nhập Google native.
- package app_links cho deep link.
- package image_picker cho chọn ảnh.
- package http_parser cho MIME type multipart.
- ChangeNotifier cho auth/session state hiện tại.

## 4. Nguyên tắc kiến trúc

1. Widget không gọi HTTP trực tiếp.
2. Feature service không tự lưu token.
3. Access token chỉ ở memory.
4. Refresh token chỉ ở secure storage.
5. Mọi protected request đi qua một ApiClient dùng chung.
6. Backend luôn kiểm tra lại quyền, dù UI đã ẩn nút.
7. Model phải typed và parse nullability đúng với API.
8. API error phải được map thành AppError thống nhất.
9. Logout phải dọn local session kể cả khi server mất mạng.
10. Feature mới phải có state, loading, empty, error và test.
11. Core không import ngược feature cụ thể.
12. Không đưa nghiệp vụ quan trọng vào một screen hoặc main.dart.

## 5. Cấu trúc thư mục mục tiêu

~~~text
mobile/
└─ user-app/
   ├─ lib/
   │  ├─ main.dart
   │  ├─ auth.dart
   │  ├─ core/
   │  │  ├─ config/
   │  │  ├─ network/
   │  │  ├─ storage/
   │  │  ├─ errors/
   │  │  ├─ routing/
   │  │  ├─ deep_links/
   │  │  ├─ widgets/
   │  │  └─ theme/
   │  ├─ account/
   │  │  ├─ models/
   │  │  ├─ services/
   │  │  ├─ state/
   │  │  ├─ screens/
   │  │  └─ widgets/
   │  ├─ channel/
   │  │  ├─ models/
   │  │  ├─ services/
   │  │  ├─ state/
   │  │  ├─ screens/
   │  │  └─ widgets/
   │  ├─ video/
   │  ├─ playlist/
   │  ├─ notifications/
   │  └─ moderation/
   ├─ test/
   │  ├─ api_smoke_test.dart
   │  ├─ auth_test.dart
   │  ├─ channel_upload_test.dart
   │  ├─ flows_test.dart
   │  └─ widget_test.dart
   ├─ android/
   ├─ ios/
   ├─ pubspec.yaml
   └─ README.md
~~~

Account và channel là các feature đang có. Video, playlist, notifications và moderation là các boundary mở rộng; không dồn chúng vào auth hoặc app entry point.

## 6. Phân lớp bên trong mobile

~~~text
Screen / Widget
        |
        v
Feature State / Controller
        |
        v
Feature Service
        |
        v
ApiClient / SecureTokenStore / DeepLinkService
        |
        v
HTTP / platform SDK / device storage
~~~

### 6.1. Presentation layer

Chứa screen, widget, form, dialog, loading, empty và error state.

Presentation chỉ nhận action, gọi state/controller, render state và điều hướng. Presentation không tự ghép URL, tự gắn Authorization, tự parse JSON hoặc tự quyết định permission.

### 6.2. State layer

Controller/state giữ:

- trạng thái loading, submitting, refreshing;
- dữ liệu hiện tại;
- empty state;
- lỗi có thể hiển thị;
- pagination;
- optimistic state nếu use case an toàn;
- trạng thái retry/cancel.

Auth hiện dùng ChangeNotifier. Khi feature tăng, có thể tách controller theo feature hoặc chuyển sang Riverpod/BLoC mà không đổi API contract.

### 6.3. Feature service layer

Service là nơi định nghĩa use case:

- AuthService/AuthController: login, restore, refresh, logout.
- AccountService: profile, avatar, password, settings.
- ChannelService: channel, member, role, invitation, upload.
- VideoService: feed, detail, upload, playback khi triển khai.

Service trả model/result đã chuẩn hóa, không trả raw HTTP response cho UI.

### 6.4. Core layer

Core chứa config, network, secure storage, error mapping, routing, deep link, theme, shared widgets và logging adapter. Core phải độc lập với từng feature.

## 7. Bootstrap và app lifecycle

~~~text
main
  -> initialize Flutter binding
  -> load app configuration
  -> create ApiClient
  -> create SecureTokenStore
  -> create AuthController
  -> register deep-link listener
  -> restore session
  -> runApp
~~~

Khi restore:

- hiển thị splash/loading;
- không render protected screen trước khi biết session;
- refresh thành công thì vào app shell;
- token invalid thì xóa token và về auth screen;
- lỗi mạng tạm thời thì cho retry, không crash.

Không gọi network tùy ý trong build vì widget có thể build nhiều lần. Khi app chuyển background/foreground, có thể refresh dữ liệu stale nhưng phải tránh tạo nhiều request trùng.

## 8. Authentication và session

### 8.1. Auth state

Các trạng thái chuẩn:

- unauthenticated;
- restoring;
- authenticating;
- authenticated;
- refreshing;
- signing out;
- auth error.

Authenticated state chứa access token trong memory và user hiện tại. Refresh token không đưa vào UI state, log hoặc model hiển thị.

### 8.2. Email/password login

~~~text
LoginScreen
  -> local form validation
  -> AuthController.login
  -> POST /api/v1/auth/login
       X-HuTube-Client: mobile
  -> receive access and refresh token
  -> access token in memory
  -> refresh token in secure storage
  -> load current user
  -> authenticated
~~~

Local validation chỉ cải thiện UX; backend vẫn validate đầy đủ.

### 8.3. Restore session

~~~text
app start
  -> read refresh token from secure storage
  -> missing token: unauthenticated
  -> token exists: POST /auth/refresh
  -> success: replace rotated tokens
  -> failure: delete tokens and sign out
~~~

Khi refresh thành công phải ghi đè refresh token cũ. Không giữ nhiều refresh token song song.

### 8.4. Logout

~~~text
logout
  -> call POST /auth/logout when possible
  -> clear access token
  -> delete refresh token
  -> clear protected cache/state
  -> navigate to auth flow
~~~

Nếu API logout thất bại do mất mạng, vẫn xóa local credential để không giữ session trên thiết bị.

### 8.5. Google Sign-In

~~~text
Google native SDK
  -> choose Google account
  -> receive Google ID token
  -> POST /api/v1/auth/google
       X-HuTube-Client: mobile
  -> backend validates issuer, audience and expiry
  -> find/create HuTube identity
  -> issue HuTube access and refresh session
~~~

Google token chỉ dùng để chứng minh danh tính với backend. Mobile không dùng Google token để gọi API HuTube sau bước login.

Google login của mobile là user flow, không cấp quyền admin. Role và permission luôn do backend RBAC quyết định.

## 9. Token security

### 9.1. Access token

- chỉ lưu trong memory;
- gắn Bearer header;
- không lưu plain preferences/file;
- không đưa vào URL;
- không log;
- xóa khi logout hoặc refresh thất bại.

### 9.2. Refresh token

- lưu bằng flutter_secure_storage;
- không hiển thị;
- không log;
- rotate khi refresh;
- xóa khi logout/revoke/session invalid;
- chỉ gửi tới API HuTube.

### 9.3. Refresh concurrency

Nhiều request cùng nhận 401 không được tự refresh độc lập:

~~~text
request A -> 401
request B -> 401
  -> một refresh lock duy nhất
  -> A và B chờ cùng kết quả
  -> success: retry request an toàn
  -> failure: sign out một lần
~~~

Chỉ retry request idempotent hoặc request có idempotency key. Không retry mù upload/mutation vì có thể tạo dữ liệu trùng.

## 10. ApiClient

ApiClient là cổng duy nhất cho REST API.

Trách nhiệm:

- ghép base URL và path;
- set Accept/Content-Type;
- set X-HuTube-Client: mobile;
- attach access token;
- encode JSON;
- gửi multipart;
- timeout/cancellation;
- parse JSON;
- map status code thành AppError;
- chuyển 401 cho auth refresh flow.

Header chuẩn:

- Accept: application/json;
- Content-Type: application/json cho JSON body;
- Authorization: Bearer access token khi protected;
- X-HuTube-Client: mobile.

Multipart phải xác định MIME type đúng, kiểm tra file trước khi gửi và không dùng extension làm kiểm tra duy nhất.

## 11. Error handling

AppError nên có nhóm:

- network unavailable;
- timeout;
- cancelled;
- unauthorized;
- forbidden;
- not found;
- validation;
- conflict;
- server;
- unknown.

Backend trả ProblemDetails gồm title, status, detail, code và traceId. Mobile hiển thị message an toàn theo code/detail; không hiển thị stack trace, SQL hoặc secret.

Với lỗi 500:

- hiển thị thông báo thử lại;
- giữ traceId để hỗ trợ;
- không reset dữ liệu hiện tại nếu chưa cần;
- log tối thiểu và đã redact.

## 12. Routing và app shell

Nên tách các flow:

- auth flow;
- protected app shell;
- account;
- channel;
- video;
- playlist;
- settings;
- notifications.

App shell chịu trách nhiệm auth gate, navigation bar/tab, theme, global snackbar/dialog, deep-link target và refresh khi resume.

Feature screen không tạo MaterialApp thứ hai. Nếu hiện tại auth screen chứa nhiều page nội bộ, khi feature tăng nên chuyển sang route map rõ ràng để back stack và deep link ổn định.

## 13. Account feature

### 13.1. Use cases

- xem/cập nhật profile;
- upload avatar;
- đổi password;
- notification settings;
- user preferences;
- xem active sessions;
- revoke session.

### 13.2. Avatar upload

~~~text
AccountScreen
  -> ImagePicker
  -> validate local file
  -> multipart POST /account/avatar
  -> backend checks type, size and ownership
  -> storage provider saves object
  -> response returns profile/avatar URL
  -> update account state
~~~

Không giữ binary lớn trong state quá lâu. Nếu widget bị dispose trong lúc upload, không gọi setState trên widget đã hủy.

Profile cache có thể dùng ngắn hạn để render nhanh; sau mutation phải update/invalidate cache. Token không được nằm trong profile cache.

## 14. Channel feature

### 14.1. Models

Mobile cần model typed cho:

- Channel;
- ChannelMember;
- ChannelInvitation;
- ChannelRole;
- ChannelQuota nếu API trả;
- paged list khi API phân trang.

### 14.2. Create/manage channel

~~~text
ChannelScreen
  -> validate name and handle
  -> POST /channels
  -> backend creates channel, owner membership and quota
  -> receive channel model
  -> update current channel
~~~

Handle uniqueness và owner permission do backend quyết định.

### 14.3. Invitation

Gửi lời mời:

~~~text
manager/editor
  -> enter email and role
  -> local email/role validation
  -> POST /channels/{id}/invite
  -> show success, conflict or forbidden state
~~~

Nhận lời mời:

~~~text
my invitations
  -> GET /channels/invitations
  -> accept or decline
  -> refresh invitations and memberships
~~~

Role hợp lệ:

- manager;
- editor;
- moderator;
- viewer.

Mobile không gửi role comment_moderator cũ. Role đúng là moderator; backend/database constraint là lớp bảo vệ cuối.

### 14.4. Members

Đổi role/remove member chỉ hiển thị khi phù hợp, nhưng backend vẫn authorize request. Sau mutation nên refresh member list thay vì tự sửa local theo giả định.

## 15. Video feature boundary

Khi hoàn thiện video, tách:

- Video model;
- VideoRendition model;
- VideoService;
- feed/detail state;
- upload state;
- processing state;
- player abstraction;
- pagination.

Upload file lớn nên theo flow:

~~~text
select file
  -> validate size/type
  -> request upload session
  -> upload object or direct upload
  -> notify API
  -> poll processing status
  -> show playback/renditions
~~~

Không giữ toàn bộ video trong memory. Cần progress, cancel, retry/resume và idempotency cho upload lớn.

## 16. Playlist, notification và moderation

### 16.1. Playlist

Tách playlist list/detail/edit khỏi video screen. Reorder phải gửi thứ tự rõ ràng và xử lý conflict khi nhiều thiết bị cùng sửa.

### 16.2. Notification

Notification record lấy từ API. Push notification chỉ là delivery adapter:

~~~text
backend notification
  -> optional push provider
  -> mobile receives deep-link payload
  -> app opens target
  -> app fetches fresh entity
~~~

Payload push không phải nguồn sự thật; mobile phải fetch lại dữ liệu.

### 16.3. Moderation/report

Mobile chỉ gửi target, reason và evidence metadata theo API. Quyết định xử lý thuộc backend/admin; không nhúng rule phạt vào app.

## 17. Deep link

Scheme hiện dùng là hutube://auth/....

DeepLinkService cần:

- đọc initial link khi cold start;
- subscribe link khi app đang chạy;
- parse path/query;
- xử lý success, error và expired;
- chống xử lý một link hai lần;
- chuyển kết quả tới AuthController/screen đúng mục tiêu.

Android cần intent filter đúng scheme/host/path. iOS cần URL scheme hoặc universal link và forwarding qua scene/app delegate. Phải test cả cold start và warm start.

Backend/frontend phải tạo link đúng scheme đã đăng ký. Không dùng link Android cho iOS.

## 18. Configuration theo môi trường

### 18.1. API URL

- Android emulator: http://10.0.2.2:5080/api/v1
- Android thật qua USB reverse: http://127.0.0.1:5080/api/v1
- iOS simulator: http://localhost:5080/api/v1
- thiết bị thật trong LAN: http://IP-máy-chạy-api:5080/api/v1
- production: HTTPS domain API

localhost trên điện thoại thật là chính điện thoại, không phải máy phát triển.

### 18.2. Môi trường

- Development: API local, database local, email pickup.
- Staging: API/dependency staging.
- Production: Render API, Neon PostgreSQL, Cloudinary và email thật.

API base URL và Google client ID là client-safe nhưng phải tách theo build flavor. Không đưa vào app:

- database connection string;
- JWT signing key;
- Cloudinary API secret;
- SMTP password;
- Gmail refresh token;
- admin credential.

### 18.3. Build flavors

Khuyến nghị có dev, staging và production flavor. Mỗi flavor có API URL, app name/icon, Google config và logging policy riêng. Không sửa endpoint thủ công sau khi build.

## 19. Network, offline và lifecycle

Ứng dụng phải xử lý:

- mất mạng;
- timeout;
- API free instance cold start;
- app background/foreground;
- request bị hủy khi rời screen;
- token hết hạn khi app đang ngủ;
- thiết bị đổi network.

Nguyên tắc:

- loading có giới hạn;
- có retry rõ ràng;
- không xóa dữ liệu đang hiển thị vì lỗi refresh tạm thời;
- protected action kiểm tra session trước khi submit;
- request dài có timeout/cancel;
- mutation có pending state;
- foreground resume refresh dữ liệu stale.

Offline cache chỉ nên bắt đầu với read-only data hoặc mutation có idempotency. Không tự xây cơ chế lưu refresh token ngoài secure storage.

## 20. Theme, localization và accessibility

### 20.1. Theme

core/theme tập trung color scheme, typography, spacing, shape, button/input style và light/dark policy. Feature dùng token chung thay vì hard-code màu/layout.

### 20.2. Localization

Text UI phải dùng localization key. Không trộn tiếng Việt, tiếng Anh và tiếng Nhật bằng chuỗi hard-code. Ngôn ngữ mặc định và fallback được định nghĩa một nơi.

Khi thêm ngôn ngữ:

- thêm đủ translation key;
- kiểm tra text dài/ngắn;
- không ghép câu bằng các mảnh cố định nếu ngữ pháp khác;
- kiểm tra date, number và role label.

### 20.3. Accessibility

- semantic label cho icon button;
- vùng chạm đủ lớn;
- contrast đủ;
- hỗ trợ text scale;
- focus order hợp lý;
- không chỉ dùng màu để biểu thị lỗi/trạng thái.

## 21. Media và upload

Trước upload:

- kiểm tra file tồn tại;
- kiểm tra kích thước;
- xác định MIME;
- preview nếu phù hợp;
- cảnh báo file lớn trên mobile network;
- cho phép cancel.

Trong upload:

- progress;
- khóa submit trùng;
- timeout;
- xử lý cancel;
- không retry mù mutation;
- dùng response làm nguồn URL cuối.

Sau upload:

- dọn temporary reference;
- refresh profile/channel;
- hiển thị provider error an toàn.

## 22. Testing strategy

### 22.1. Unit test

Test model JSON parsing, AppError mapping, token state transition, refresh lock, email/role validation, deep-link parser, pagination và localization key.

### 22.2. Service test

Mock HTTP để kiểm tra method/path/header, JSON body, multipart file, access token, 401 refresh, 403/409/500 mapping và logout cleanup.

### 22.3. Widget test

Kiểm tra form validation, loading/error/success, invitation accept/decline, action visibility, empty list, retry, text overflow và semantics.

### 22.4. Integration/E2E

Luồng tối thiểu:

1. Cold start và restore session.
2. Register/login/logout.
3. Google login trên platform tương ứng.
4. Verify/reset flow qua deep link.
5. Tạo channel.
6. Gửi invitation.
7. Accept/decline invitation.
8. Upload avatar/banner.
9. Token expiry và refresh.
10. 401 đồng thời không tạo refresh race.
11. Deep link cold start/warm start.
12. Mất mạng, retry và cancel.

Test cần chạy Android emulator; trước release cần thêm thiết bị thật. iOS phải test riêng scheme, bundle ID và signing.

## 23. Build và release

Development flow:

~~~text
flutter pub get
flutter analyze
flutter test
flutter run
~~~

Release checklist:

- API URL đúng flavor và dùng HTTPS ở staging/production;
- debug log nhạy cảm đã tắt;
- Google client ID đúng package/bundle/signing;
- deep link đúng platform;
- app icon/name/version đúng;
- secure token storage hoạt động trên release;
- upload permission đã khai báo;
- không còn mock endpoint;
- crash/error reporting đã redact token và PII.

## 24. Performance

- dùng const widget khi có thể;
- resize/decode ảnh theo kích thước hiển thị;
- dùng thumbnail cho list;
- pagination;
- debounce search;
- không gọi API trong mỗi build;
- cancel request khi dispose;
- không giữ media/list lớn trong memory;
- tách parsing nặng khỏi UI isolate nếu cần.

## 25. Logging và support

Log mobile nên có feature, action, status, duration và traceId backend nếu có.

Không log password, access token, refresh token, Google ID token, secret hoặc PII không cần thiết.

Thông tin hữu ích khi hỗ trợ lỗi:

- app version;
- platform/device;
- environment;
- action/endpoint;
- HTTP status;
- traceId;
- timestamp.

## 26. Quy tắc thêm feature

Mỗi feature mới nên có:

~~~text
feature/
  models/
  services/
  state/
  screens/
  widgets/
  tests/
~~~

Trình tự:

1. chốt API contract;
2. tạo typed model;
3. tạo service dùng ApiClient;
4. tạo state/controller;
5. tạo screen/widget;
6. thêm loading/empty/error;
7. thêm auth/permission UX;
8. thêm unit/service/widget/E2E test;
9. cập nhật localization/theme;
10. cập nhật tài liệu và release checklist.

Không gọi HTTP trực tiếp từ widget và không mở rộng một screen thành file khổng lồ.

## 27. Những phần cần hoàn thiện tiếp

- tách core config/network/storage/deep_links nếu code hiện tại còn tập trung;
- chuẩn hóa AppError và ProblemDetails mapping;
- thêm refresh lock cho nhiều request 401;
- hoàn thiện route/auth gate cho protected shell;
- tách state/controller riêng cho account và channel;
- hoàn thiện Google config Android/iOS release;
- kiểm thử deep link cold/warm start;
- chuẩn hóa localization;
- bổ sung upload progress/cancel;
- triển khai video, playlist, notification và moderation theo boundary;
- thêm push notification và deep-link payload;
- thêm crash/error reporting có redaction.

## 28. Definition of Done cho màn hình mobile

Một màn hình chỉ hoàn thành khi:

- có route/entry point rõ;
- có loading, success, empty và error state;
- không gọi API trực tiếp từ UI;
- dùng typed model;
- xử lý 401, 403 và 409;
- có back/retry/cancel behavior;
- dùng localization key và theme token;
- hỗ trợ text scale/accessibility cơ bản;
- có widget/service test;
- không log secret/PII;
- chạy được với API local và môi trường target.

## 29. Tài liệu và mã nguồn liên quan

- mobile/user-app/README.md: hướng dẫn chạy mobile.
- mobile/user-app/pubspec.yaml: SDK và dependencies.
- mobile/user-app/lib/main.dart: bootstrap/app entry point.
- mobile/user-app/lib/auth.dart: auth/session controller.
- mobile/user-app/lib/account: account feature.
- mobile/user-app/lib/channel: channel feature.
- mobile/user-app/test: mobile test suite.
- README.md: URL local và cách chạy hệ thống.
- docs/development/LOCAL_DEVELOPMENT.md: API/database local.
- docs/deployment/RENDER_NEON_GOOGLE.md: cloud và Google OAuth.

## 30. Kết luận

Mobile User App là Flutter client phân lớp: UI gọi state/controller, state gọi feature service, feature service dùng ApiClient và các adapter platform. Auth/session là trục ngang của ứng dụng: access token ở memory, refresh token ở secure storage, Google chỉ cung cấp danh tính và backend HuTube cấp session/quyền. Account và channel là feature hiện có; video, playlist, notification và moderation được mở rộng độc lập theo cùng boundary mà không làm phình app entry point hoặc trộn nghiệp vụ vào widget.

