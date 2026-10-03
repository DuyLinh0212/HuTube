# HuTube User Web

Ứng dụng Angular độc lập cho S4-01/S4-02. Các route: `/register`, `/verify-email?token=…`, `/login`, `/forgot-password`, `/reset-password?token=…`, `/account`.

Bản User Web mặc định gọi API Render `https://hutube.onrender.com/api/v1`. Khi phát triển local, đặt `API_BASE_URL=http://localhost:5080/api/v1` trước `npm start` hoặc `npm run build`.

```powershell
npm ci
$env:API_BASE_URL = 'http://localhost:5080/api/v1'
npm start
```

Mặc định chạy tại `http://localhost:4200`. API phải cho phép origin này qua CORS. Theo quyết định hiện tại của chủ dự án, API dùng local; chưa có Render Staging.

`public/config.json` là cấu hình runtime, được tải trước khi Angular khởi động. `npm start` và `npm run build` nhận biến môi trường `API_BASE_URL` qua `scripts/configure-api.mjs`. Nếu không có biến, giữ giá trị Render trong config. Có thể thay `dist/user-web/browser/config.json` sau build mà không biên dịch lại. Không đặt secret trong cấu hình web. Hosting phải fallback các route về `index.html` và phục vụ `config.json` với Cache-Control no-store.

```powershell
npm run build
$env:CHROME_BIN = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
npm run test:ci
```

Access token chỉ lưu trong bộ nhớ. Refresh token là cookie HttpOnly do API cấp; mọi request API có credentials và `X-HuTube-Client: web`. Interceptor chỉ gắn token với đúng base API. Refresh trong cùng tab được gộp; Web Locks tuần tự hóa xoay cookie giữa các tab khi trình duyệt hỗ trợ. Khi reload, route bảo vệ khôi phục phiên rồi kiểm tra `/auth/me`. `returnUrl` chỉ nhận đường dẫn nội bộ an toàn.

Luồng email Development: API ghi email vào thư mục pickup local. Người vận hành mở liên kết trong email; ứng dụng không hiển thị token trên giao diện. Cấu hình URL email phía API phải trỏ đến origin của User Web.

Các nghiệp vụ video/kênh và chỉnh sửa hồ sơ thuộc slice sau; trang Account hiện chỉ chứa thông tin đăng nhập và quản lý phiên.

## Browser E2E

Luồng E2E trình duyệt cho đăng ký, xác minh email, đăng nhập/đăng xuất User và Admin hiện chạy từ [`frontend/e2e_testing`](../e2e_testing/README.md). Runner tự dựng PostgreSQL kiểm thử, API và bản build của cả hai web; không cần khởi động server bằng tay.

Screenshot và report được tạo trong `frontend/e2e_testing/screenshots/<run-id>/` và `frontend/e2e_testing/artifacts/runs/<run-id>/report.json`. CI chạy cùng runner và upload chúng thành artifact `hutube-e2e-evidence-*` trên GitHub Actions.
