# Render, Neon và Google Login

Backend nhận trực tiếp `ConnectionStrings__Database` ở dạng PostgreSQL URL của Neon hoặc connection string Npgsql. URL được chuẩn hoá trong ứng dụng, nên có thể dán nguyên giá trị từ Neon vào Render; không commit URL này vào Git.

`render.yaml` khai báo các biến môi trường. Tạo dịch vụ bằng **New → Blueprint** và chọn repository/nhánh `develop`, thay vì tạo Web Service thủ công như ảnh. Render sẽ nhận các key và yêu cầu điền mọi giá trị có `sync: false` ở lần sync đầu.

| Key Render | Giá trị cần điền |
| --- | --- |
| `ConnectionStrings__Database` | PostgreSQL URL từ Neon |
| `Auth__WebBaseUrl` | URL HTTPS của User Web, ví dụ `https://hutube-web.onrender.com` |
| `Auth__AdminBaseUrl` | URL HTTPS của Admin Web, ví dụ `https://hutube-admin.onrender.com` |
| `Auth__AllowedOrigins__0` | Tùy chọn: User Web local, `http://localhost:4200` |
| `Auth__AllowedOrigins__1` | Tùy chọn: Admin Web local, `http://localhost:4201` |
| `Google__ClientId` | OAuth 2.0 **Web client ID** từ Google Cloud Console |
| `Email__Host`, `Email__From`, `Email__Username`, `Email__Password` | SMTP production; dùng port 587 mặc định hoặc đổi `Email__Port` theo nhà cung cấp |

`Jwt__SigningKey` được Render tự tạo khi Blueprint được tạo. Các biến `ASPNETCORE_ENVIRONMENT`, JWT issuer/audience, email mode và port HTTP có giá trị sẵn trong Blueprint.

Nếu chỉ deploy API/database để phát triển, bạn có thể giữ `Auth__WebBaseUrl=http://localhost:4200` và `Auth__AdminBaseUrl=http://localhost:4201` miễn là đồng thời cấu hình hai biến `Auth__AllowedOrigins__0=http://localhost:4200` và `Auth__AllowedOrigins__1=http://localhost:4201`. Backend chỉ chấp nhận hai origin loopback được khai báo rõ; origin HTTP khác vẫn bị chặn.

## Google Cloud Console

Tạo OAuth 2.0 Client ID loại **Web application**, rồi thêm đúng URL User Web vào **Authorized JavaScript origins**. Luồng web dùng Google Identity Services để nhận ID token, vì vậy không cần client secret hay redirect URI. Dán Client ID đó vào `Google__ClientId` của Render. Backend kiểm tra chữ ký token, issuer, expiry, audience và `email_verified`, sau đó phát access/refresh token HuTube riêng.

Ứng dụng Flutter cũng có nút Google. Khi build Android, truyền Web client ID đó làm `GOOGLE_WEB_CLIENT_ID`; Google Console cần thêm Android OAuth client có package name `com.hutube.user_app` và SHA-1/SHA-256 của từng khóa ký (debug, upload/release). Lấy fingerprint local bằng `cd mobile/user-app/android; ./gradlew signingReport`. Khi build iOS, truyền thêm `GOOGLE_IOS_CLIENT_ID`, tạo iOS OAuth client và thêm reversed client ID vào `Info.plist`. Các giá trị này là client ID công khai, không phải Render secret:

```powershell
flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID='<web-client-id>'
flutter build ipa --dart-define=GOOGLE_WEB_CLIENT_ID='<web-client-id>' --dart-define=GOOGLE_IOS_CLIENT_ID='<ios-client-id>'
```

## Migration Neon

Neon database đã được migration từ source hiện tại. Mỗi lần có migration mới, chạy trước deploy:

```powershell
$env:ConnectionStrings__Database = '<Neon PostgreSQL URL>'
$env:ASPNETCORE_ENVIRONMENT = 'Staging'
$env:Jwt__SigningKey = '<64+ random characters>'
$env:Auth__WebBaseUrl = 'https://your-user-web.example'
$env:Auth__AdminBaseUrl = 'https://your-admin-web.example'
dotnet backend/src/HuTube.Api/bin/Release/net10.0/HuTube.Api.dll --migrate
```

Render pre-deploy command phù hợp với paid web service. Free plan không có pre-deploy command, nên chạy migration từ máy local/CI trước khi deploy; API startup không tự thay đổi schema.
