# CI/CD và triển khai AWS EC2

## CI hiện tại

`.github/workflows/ci.yml` chạy khi push `develop`, nhánh feature/fix/ci/test/db hoặc PR vào `develop`; có thể chạy thủ công. Các job độc lập kiểm tra:

1. .NET 10 restore/build Release, unit test và integration test PostgreSQL 18, publish API artifact.
2. Node 22 `npm ci`, Karma ChromeHeadless và Angular build cho cả hai web.
3. Flutter stable `pub get`, `analyze --fatal-infos`, `test` tại `mobile/user-app` và build release APK. Job mobile dùng GitHub Environment `mobile`; có thể override hai biến public `MOBILE_API_BASE_URL` và `GOOGLE_WEB_CLIENT_ID`, mặc định trỏ về API EC2 hiện tại và Google Web client hiện tại.
4. Sau khi cả ba nhóm pass, build Docker API. Chỉ push image GHCR từ `develop` với tag commit SHA và `develop`; feature/PR chỉ kiểm tra build container.

CI PostgreSQL là service dùng một lần, tài khoản test có quyền tạo database. Connection string CI chỉ thuộc service tạm thời, không phải credential local hay staging. Test không dùng database ứng dụng. Kết quả TRX và sản phẩm publish được lưu bằng workflow artifacts.

Flutter HTTP smoke yêu cầu `LIVE_API_BASE_URL` và `EMAIL_PICKUP_DIRECTORY`, nên mặc định được skip có lý do trong CI unit/widget và được chạy riêng trên local. Workflow hiện không build APK hoặc chạy kiểm thử thiết bị native. Docker build context là `backend`; các exclusions phải nằm ở `backend/.dockerignore`, file ignore root không áp dụng cho context này.

`scripts/test.ps1` cung cấp cùng các kiểm tra build/test cốt lõi trên local; container publish và deploy chỉ thuộc CI. Khi CI không chạy hoặc chưa xong phải báo đúng trạng thái; không coi test local là bằng chứng GitHub Actions đã pass.

## Triển khai AWS EC2

Backend API và Recommendation Service triển khai qua `dalitu-autodeploy.timer` trên EC2. Timer kiểm tra GitHub mỗi 5 phút và chỉ chọn commit mới nhất của `main` khi lần chạy CI thuộc sự kiện `push` cùng toàn bộ job và hai trạng thái Vercel đều thành công. CI thất bại hoặc chưa hoàn tất khiến EC2 giữ phiên bản đang chạy.

Workflow giữ **Run workflow** để chạy kiểm tra thủ công. Cơ chế tự deploy EC2 yêu cầu lượt CI `push` trên `main`; một lượt chạy thủ công hoặc CI thành công trên nhánh khác chưa đủ điều kiện triển khai.

Luồng Render staging đã được gỡ khỏi CI. Workflow không yêu cầu Environment `staging`, deploy hook hoặc URL Render. Khóa SSH và cấu hình runtime của EC2 được giữ ngoài Git.

EC2 build image theo commit đã đạt kiểm tra, chạy migration trước khi thay container, rồi xác nhận health và `/api/v1/system/info.commitSha` trùng commit mới. Xem [EC2_AUTO_DEPLOY.md](EC2_AUTO_DEPLOY.md) để cài đặt, xem log, kiểm tra điều kiện và xử lý rollback; cấu hình ứng dụng tại [EC2_API_RECOMMENDER.md](EC2_API_RECOMMENDER.md).

Web runtime config nằm tại `frontend/<app>/public/config.json`, sau build tại `dist/<app>/browser/config.json`. Đặt `API_BASE_URL=https://<api-host>/api/v1` lúc build hoặc cập nhật config file deploy; không chứa secret. Mobile build dùng `--dart-define=API_BASE_URL=https://<api-host>/api/v1`. Bổ sung allowed origins cho hostname client trước khi smoke cả ba client.

## Backup và rollback

Backup PostgreSQL bằng công cụ phù hợp trước migration trên môi trường dùng chung. Kiểm tra việc restore backup ở môi trường riêng. Đọc migration change notes và backward compatibility trước deploy.

Khi rollout lỗi, rollback image/revision ứng dụng về bản đã kiểm tra nếu schema còn tương thích. Không tự động drop schema hoặc chạy down migration; migration bootstrap có thể chứa toàn bộ bảng nền của SQL nguồn. Nếu schema không tương thích, lập kế hoạch restore snapshot và dữ liệu phát sinh cùng downtime được chấp thuận.

## Merge

Tuân thủ naming convention và Conventional Commits; merge sau khi kiểm tra đạt. Khi đưa thay đổi lên `main`, kiểm tra CI/Vercel và log EC2 để xác nhận commit đã thực sự được triển khai. Git push/merge riêng lẻ chưa phải bằng chứng deploy thành công.
