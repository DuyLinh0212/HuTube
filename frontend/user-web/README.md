# HuTube User Web

Ứng dụng Angular độc lập cho S4-01/S4-02. Các route: `/register`, `/verify-email?token=…`, `/login`, `/forgot-password`, `/reset-password?token=…`, `/account`.

```powershell
npm ci
$env:API_BASE_URL = 'http://localhost:5080/api/v1'
npm start
```

Mặc định chạy tại `http://localhost:4200`. API phải cho phép origin này qua CORS. Theo quyết định hiện tại của chủ dự án, API dùng local; chưa có Render Staging.

`public/config.json` là cấu hình runtime, được tải trước khi Angular khởi động. `npm start` và `npm run build` nhận biến môi trường `API_BASE_URL` qua `scripts/configure-api.mjs`. Nếu không có biến, giữ giá trị trong config. Có thể thay `dist/user-web/browser/config.json` sau build mà không biên dịch lại. Không đặt secret trong cấu hình web. Hosting phải fallback các route về `index.html` và phục vụ `config.json` với Cache-Control no-store.

```powershell
npm run build
$env:CHROME_BIN = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
npm run test:ci
```

Access token chỉ lưu trong bộ nhớ. Refresh token là cookie HttpOnly do API cấp; mọi request API có credentials và `X-HuTube-Client: web`. Interceptor chỉ gắn token với đúng base API. Refresh trong cùng tab được gộp; Web Locks tuần tự hóa xoay cookie giữa các tab khi trình duyệt hỗ trợ. Khi reload, route bảo vệ khôi phục phiên rồi kiểm tra `/auth/me`. `returnUrl` chỉ nhận đường dẫn nội bộ an toàn.

Luồng email Development: API ghi email vào thư mục pickup local. Người vận hành mở liên kết trong email; ứng dụng không hiển thị token trên giao diện. Cấu hình URL email phía API phải trỏ đến origin của User Web.

Các nghiệp vụ video/kênh và chỉnh sửa hồ sơ thuộc slice sau; trang Account hiện chỉ chứa thông tin đăng nhập và quản lý phiên.

## Browser E2E

`e2e/auth.cjs` chạy luồng thật trên hai web và API, tạo tài khoản kiểm thử mới mỗi lần. Yêu cầu API Development dùng email pickup, cả hai web đang chạy, migrations hoàn tất.

```powershell
npx playwright install chromium
npm run test:e2e
```

Hoặc dùng Chrome đã cài: `$env:PLAYWRIGHT_CHANNEL = 'chrome'`. Cấu hình tùy chọn: `USER_WEB_URL`, `ADMIN_WEB_URL`, `API_BASE_URL`, `EMAIL_PICKUP_DIRECTORY`, `E2E_OUTPUT_DIR`. Mặc định dùng các URL local nêu trên và thư mục `.work/mail` / `.work/screenshots` ở repository root.

Để kiểm tra quản trị được cấp quyền rồi bị vô hiệu hóa, đặt `RUN_ADMIN_DB_TESTS=1` cùng các biến PostgreSQL `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`; `PSQL_BINARY` trỏ đến psql nếu chưa nằm trên PATH. Chỉ chạy trên database kiểm thử/local: script cấp/vô hiệu hóa quyền của đúng tài khoản ngẫu nhiên do lần chạy đó tạo, sau đó xác nhận tài khoản User vẫn đăng nhập được. Không đưa mật khẩu vào câu lệnh hoặc source.

Script kiểm tra đăng ký → email pickup → xác minh → đăng nhập → cookie HttpOnly → restore khi reload → đăng xuất thiết bị khác → forgot/reset → từ chối mật khẩu cũ → logout → chặn User thường ở Admin. Screenshot dùng cho kiểm tra giao diện, không lưu trong Git.
