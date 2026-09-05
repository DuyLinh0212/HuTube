# CI/CD và chuẩn bị Render

## CI hiện tại

`.github/workflows/ci.yml` chạy khi push `develop`, nhánh feature/fix/ci/test/db hoặc PR vào `develop`; có thể chạy thủ công. Các job độc lập kiểm tra:

1. .NET 10 restore/build Release, unit test và integration test PostgreSQL 18, publish API artifact.
2. Node 22 `npm ci`, Karma ChromeHeadless và Angular build cho cả hai web.
3. Flutter stable `pub get`, `analyze --fatal-infos`, `test` tại `mobile/user-app`.
4. Sau khi cả ba nhóm pass, build Docker API. Chỉ push image GHCR từ `develop` với tag commit SHA và `develop`; feature/PR chỉ kiểm tra build container.

CI PostgreSQL là service dùng một lần, tài khoản test có quyền tạo database. Connection string CI chỉ thuộc service tạm thời, không phải credential local hay staging. Test không dùng database ứng dụng. Kết quả TRX và sản phẩm publish được lưu bằng workflow artifacts.

Flutter HTTP smoke yêu cầu `LIVE_API_BASE_URL` và `EMAIL_PICKUP_DIRECTORY`, nên mặc định được skip có lý do trong CI unit/widget và được chạy riêng trên local. Workflow hiện không build APK hoặc chạy kiểm thử thiết bị native. Docker build context là `backend`; các exclusions phải nằm ở `backend/.dockerignore`, file ignore root không áp dụng cho context này.

`scripts/test.ps1` cung cấp cùng các kiểm tra build/test cốt lõi trên local; container publish và deploy chỉ thuộc CI. Khi CI không chạy hoặc chưa xong phải báo đúng trạng thái; không coi test local là bằng chứng GitHub Actions đã pass.

## Render — chưa bật

Hiện chưa có Render service/domain, nên không có URL staging hoặc smoke cloud đã đạt. Job deploy chỉ bật khi **Run workflow → deploy_staging = true**, trên nhánh `develop`, sau toàn bộ CI. Cần thiết lập trước:

- Render Web Service dùng Docker từ repository, branch `develop`, Dockerfile `backend/Dockerfile`, build context `backend`.
- Tắt auto-deploy để CI kiểm soát thời điểm trigger. Workflow truyền `ref` commit SHA vào deploy hook, và kiểm tra API báo đúng commit của lần chạy theo [Render deploy hooks](https://render.com/docs/deploy-hooks).
- PostgreSQL staging riêng; credential chỉ đặt trong Render Environment, TLS theo yêu cầu nhà cung cấp.
- Pre-deploy command: `dotnet HuTube.Api.dll --migrate`. Render hiện hỗ trợ pre-deploy command ở web service trả phí; kiểm tra gói trước khi bật theo [quy trình deploy của Render](https://render.com/docs/deploys). Migration thất bại phải chặn rollout; không thay thế bằng migration trong startup của mọi instance.
- Start command dùng Docker entrypoint. API bind `http://+:8080`; health path `/health`.
- Environment `ASPNETCORE_ENVIRONMENT=Staging`, `ASPNETCORE_URLS=http://+:8080`, `ConnectionStrings__Database`, `Jwt__SigningKey`, `Jwt__Issuer=HuTube`, `Jwt__Audience=HuTube.Clients`.
- URL HTTPS thật cho `Auth__WebBaseUrl`, `Auth__AdminBaseUrl`; backend lấy hai origin này làm CORS allowlist. Cấu hình `Email__Mode=Smtp`, `Email__Host`, `Email__Port`, `Email__From`, `Email__Username`, `Email__Password`; không dùng pickup Development cho staging.
- Render tự cung cấp `RENDER_GIT_COMMIT` cho `/api/v1/system/info` theo [default environment variables](https://render.com/docs/environment-variables). Không đặt commit giả hoặc giá trị cố định.
- GitHub Environment `staging`: secret `RENDER_DEPLOY_HOOK`, variable `STAGING_API_URL` chỉ chứa server root HTTPS, không có `/api/v1`. Hook là secret, không đưa vào source/logs.

Sau khi trigger hook, workflow đợi `/health` thành công **và** `/api/v1/system/info.commitSha` trùng commit chạy CI. API cũ còn khỏe không được tính là deploy mới thành công. Lỗi/migration chậm hơn thời hạn khiến job thất bại; kiểm tra Render logs rồi sửa nguyên nhân, không tự chuyển sang database khác.

Web runtime config nằm tại `frontend/<app>/public/config.json`, sau build tại `dist/<app>/browser/config.json`. Đặt `API_BASE_URL=https://<api-host>/api/v1` lúc build hoặc cập nhật config file deploy; không chứa secret. Mobile build dùng `--dart-define=API_BASE_URL=https://<api-host>/api/v1`. Bổ sung allowed origins cho hostname client trước khi smoke cả ba client.

## Backup và rollback

Backup PostgreSQL bằng công cụ phù hợp trước migration trên môi trường dùng chung. Kiểm tra việc restore backup ở môi trường riêng. Đọc migration change notes và backward compatibility trước deploy.

Khi rollout lỗi, rollback image/revision ứng dụng về bản đã kiểm tra nếu schema còn tương thích. Không tự động drop schema hoặc chạy down migration; migration bootstrap có thể chứa toàn bộ bảng nền của SQL nguồn. Nếu schema không tương thích, lập kế hoạch restore snapshot và dữ liệu phát sinh cùng downtime được chấp thuận.

## Merge

Theo naming convention, dùng `feature/s4-staging-auth` và Conventional Commits; PR/merge đích `develop`. Tạo `develop` nếu remote chưa có. Merge sau khi kiểm tra đạt; giữ `main` nguyên trạng. Git push/merge là tích hợp mã nguồn, không phải bằng chứng deploy Render.
