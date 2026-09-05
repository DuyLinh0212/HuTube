# HuTube Admin Web

Ứng dụng Angular quản trị build độc lập cho S4-01/S4-02.

```powershell
npm ci
$env:API_BASE_URL = 'http://localhost:5080/api/v1'
npm start
```

Mặc định chạy tại `http://localhost:4201`. API phải cho phép origin này qua CORS. Hiện dùng API local theo quyết định của chủ dự án.

Cấu hình runtime ở `public/config.json`. `scripts/configure-api.mjs` nhận biến `API_BASE_URL` trước `npm start` / `npm run build`. Có thể đổi `dist/admin-web/browser/config.json` sau build. Không chứa secret. Hosting phải fallback route về `index.html`, phục vụ config không cache.

```powershell
npm run build
$env:CHROME_BIN = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
npm run test:ci
```

Đăng nhập gửi `platform: admin`, `X-HuTube-Client: web`, `X-HuTube-App: admin`, sử dụng cookie riêng với User Web. Access token chỉ nằm trong bộ nhớ. Sau đăng nhập và restore, `/admin/me` phải xác nhận quyền truy cập. User thường hoặc quyền Admin bị vô hiệu hóa bị chặn. Backend là ranh giới bảo mật; route guard không thay thế authorization của API.

Phạm vi hiện tại: đăng nhập, xác minh/khôi phục mật khẩu, account/session, đăng xuất và thu hồi các phiên khác. Không có route đăng ký quản trị công khai. RBAC theo permission, menu nghiệp vụ và dashboard thuộc S4-06; không giả lập dữ liệu hoặc quyền ở client.

Browser E2E dùng chung nằm tại `frontend/user-web/e2e/auth.cjs` (chạy `npm run test:e2e` từ User Web). Kiểm tra User thường bị chặn; với `RUN_ADMIN_DB_TESTS=1`, kiểm tra cấp quyền Admin → truy cập thành công → vô hiệu hóa → bị chặn khi reload/đăng nhập lại, trong khi tài khoản User vẫn hoạt động. Cấu hình PostgreSQL chỉ nhận qua biến môi trường; xem README User Web.
