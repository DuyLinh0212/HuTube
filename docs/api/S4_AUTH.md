# Auth và Session API — S4-02

Base local: `http://localhost:5080/api/v1`. Tất cả request/response JSON camelCase; timestamp ISO 8601 UTC. Health nằm ngoài version prefix: `GET /health`. `GET /system/info` công khai dùng để ba client kiểm tra kết nối và xác định revision triển khai.

## Transport và phiên

Access token JWT dùng `Authorization: Bearer <token>`. Web giữ access token trong memory, refresh token bằng cookie HttpOnly; mọi auth request dùng `credentials: include`, `X-HuTube-Client: web`. Admin Web thêm `X-HuTube-App: admin` để tách cookie của hai web. Production/Staging dùng HTTPS và allowlist origin chính xác. Không lưu refresh token web trong localStorage.

Mobile gửi refresh token trong JSON body và lưu bằng secure storage. Không dùng cookie trình duyệt để giữ mobile session. Sau refresh, client phải thay token cũ bằng token mới. Client chỉ phát một refresh cùng lúc để tránh tự kích hoạt xử lý token cũ.

Auth response: `{accessToken, expiresAt, refreshToken, user}`. `refreshToken` null với web; chuỗi với mobile. `user`: `{userId, username, email, displayName, emailVerified, isAdmin}`. `isAdmin` chỉ hỗ trợ UI; API kiểm tra user status/admin access lại trên server.

## Endpoint

| Method/route | Xác thực | Request / response chính |
| --- | --- | --- |
| `POST /auth/register` | Public | `{username,email,displayName,password}` → 201 `{message}`; không tự login |
| `POST /auth/verify-email` | Public | `{token}` → `{message}` |
| `POST /auth/resend-verification` | Public | `{email}` → `{message}` |
| `POST /auth/forgot-password` | Public | `{email}` → `{message}` |
| `POST /auth/reset-password` | Public | `{token,password}` → `{message}`; thu hồi các phiên |
| `POST /auth/login` | Public | `{email,password,platform,deviceName}` → auth response; platform `web`, `mobile`, `admin` |
| `POST /auth/refresh` | Cookie/token | `{refreshToken?}` → auth response |
| `POST /auth/logout` | Cookie/token | `{refreshToken?}` → `{message}`; thu hồi phiên hiện tại |
| `GET /auth/me` | Bearer | user hiện tại |
| `GET /admin/me` | Bearer + active admin | user; user thường/disabled admin bị từ chối |
| `GET /auth/sessions` | Bearer | `{items:[{sessionId,deviceName,platform,issuedAt,lastActiveAt,expiresAt,isCurrent}]}` |
| `POST /auth/logout-others` | Bearer | `{message}`; giữ phiên hiện tại |
| `DELETE /auth/sessions/{sessionId}` | Bearer, chủ phiên | `{message}` |

Session list trả tập phiên của user hiện tại; không phải endpoint liệt kê mọi session hệ thống và không dùng pagination tổng quát. Register/login không có idempotency key: client phải chặn submit đôi. Verify/reset dùng token có thời hạn, không dùng lại token đã tiêu thụ. Resend/forgot giữ phản hồi chung để hạn chế lộ email đăng ký.

## Validation và lỗi

- Username 3–50 ký tự, chữ/số/underscore/dot/hyphen; email hợp lệ và không trùng theo rule backend.
- Password 10–128 ký tự, có chữ hoa, chữ thường và số.
- Chưa xác minh email không được login nếu policy yêu cầu; suspended/banned/deleted user bị chặn. Disabled admin không được dùng API admin dù tài khoản user vẫn hoạt động.
- Lỗi `application/problem+json`: `{status,title,detail,code,traceId,errors?}`. `code` dùng UPPER_SNAKE_CASE. Không dựa vào chuỗi `detail` để quyết định hành vi client.
- 400 validation/token không hợp lệ tùy endpoint; 401 thiếu hoặc sai authentication; 403 thiếu admin access/trạng thái bị chặn; 409 xung đột dữ liệu; 429 rate limit. OpenAPI được backend sinh là nguồn schema/status chi tiết.

Access token từ session đã logout/revoke không tiếp tục truy cập API được bảo vệ, kể cả JWT chưa hết hạn. Client gặp refresh thất bại phải xóa local session và trở về login; chỉ cho phép return URL nội bộ an toàn để tránh open redirect.

| Code | HTTP | Trường hợp |
| --- | --- | --- |
| `INVALID_OR_EXPIRED_TOKEN` | 400 | Link verify/reset sai, hết hạn hoặc đã sử dụng |
| `VALIDATION_ERROR`, `INVALID_EMAIL`, `INVALID_PASSWORD` | 400 | DTO hoặc quy tắc dữ liệu không đạt |
| `CLIENT_PLATFORM_MISMATCH` | 400 | Header nhận diện client không khớp platform login |
| `INVALID_CREDENTIALS` | 401 | Email/mật khẩu đăng nhập không khớp |
| `INVALID_REFRESH_TOKEN` | 401 | Refresh token thiếu, hết hạn, đã revoke, reuse hoặc sai platform |
| `SESSION_EXPIRED` | 401 | Bearer token/phiên không còn hợp lệ; gồm session admin khi admin access bị vô hiệu hóa |
| `EMAIL_NOT_VERIFIED` | 403 | Login/refresh trước khi xác minh email |
| `ACCOUNT_BLOCKED` | 403 | Auth/link bị chặn bởi trạng thái tài khoản |
| `ADMIN_ACCESS_DENIED` | 403 | Tài khoản không có active admin access tại login, refresh hoặc admin endpoint |
| `ORIGIN_NOT_ALLOWED` | 403 | Origin web không khớp ứng dụng user/admin được cấu hình |
| `EMAIL_ALREADY_EXISTS`, `USERNAME_ALREADY_EXISTS`, `RESOURCE_CONFLICT` | 409 | Trùng dữ liệu hoặc xung đột unique constraint |
| `SESSION_NOT_FOUND` | 404 | Phiên cần revoke không thuộc user hiện tại |
| `ACCOUNT_LOCKED`, `RATE_LIMIT_EXCEEDED` | 429 | Khóa login tạm thời hoặc vượt giới hạn request |
| `EMAIL_DELIVERY_UNAVAILABLE` | 503 | Không gửi được email |
| `INTERNAL_ERROR` | 500 | Lỗi hệ thống không được trả chi tiết nhạy cảm |

## Quy ước nền

API mới dùng `/api/v1`, resource plural theo convention. Các list nghiệp vụ sau này theo pagination convention của backend; không trả toàn bộ bảng không giới hạn. Ghi thời gian UTC, không hard-delete user/channel trong luồng auth. Token thô không lưu trong DB/log; email development pickup có link chứa token nên phải nằm trong thư mục Git bỏ qua.
