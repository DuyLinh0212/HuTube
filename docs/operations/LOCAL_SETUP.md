# PostgreSQL local riêng của HuTube

Máy này sử dụng một PostgreSQL 18 cluster riêng cho dự án, lưu tại `.local/postgres` dưới root repository HuTube và lắng nghe loopback `127.0.0.1:55432`. Cluster dùng binaries PostgreSQL đã cài trên máy; không thay đổi PostgreSQL service/database khác ở cổng 5432.

Database ứng dụng tên `hutube`, owner là role `hutube`. Test dùng role/connection riêng `hutube_test`; không dùng database ứng dụng để chạy integration test. Mật khẩu ngẫu nhiên và JWT signing key nằm trong `.env.local` do bước thiết lập local tạo; không ghi chúng vào tài liệu, command output hoặc Git. `.env.local`, `.local/` và `.work/` được Git bỏ qua.

## Quản lý cluster đã được thiết lập

Chạy tại root repository:

```powershell
./scripts/local-postgres.ps1 -Action Status
./scripts/local-postgres.ps1 -Action Start
./scripts/local-postgres.ps1 -Action Stop
```

Script tìm `pg_ctl.exe` trong PATH, nếu chưa có thì dùng `D:\PostgreSQL\18\bin`. Có thể chỉ định thư mục binaries:

```powershell
./scripts/local-postgres.ps1 -Action Start -PostgresBin 'D:\PostgreSQL\18\bin'
```

`Start` mặc định dùng cổng 55432, chỉ bind `127.0.0.1`. Đổi cổng bằng `-Port` thì phải cập nhật connection strings trong `.env.local` tương ứng; đang chạy thì script không tự restart hoặc đổi cổng. `Stop` thực hiện PostgreSQL fast shutdown: ngắt client, rollback giao dịch chưa hoàn tất và giữ nguyên dữ liệu. Dừng API trước khi chủ động dừng database.

Script chỉ quản lý cluster có sẵn ở `.local/postgres`; không tạo cluster, tạo database, reset mật khẩu hoặc xóa dữ liệu. Nó từ chối thư mục thiếu, sai phiên bản hoặc bị thay bằng junction/symlink. Clone repository trên máy khác không mang theo database và secret của máy này; thực hiện thiết lập mới theo [hướng dẫn local](LOCAL_DEVELOPMENT.md).

## Khởi động ứng dụng

```powershell
./scripts/local-postgres.ps1 -Action Start
./scripts/run-local.ps1 -Component api
```

Mở các terminal khác để chạy User Web/Admin Web/mobile theo README. API không tự khởi động PostgreSQL. Cluster không đăng ký tự chạy khi Windows khởi động lại; chạy lệnh `Start` trước API sau mỗi lần reboot.

`./scripts/setup-local.ps1` dùng `.env.local` hiện có để restore dependencies và áp dụng migration. `./scripts/test.ps1` dùng connection riêng cho test. Không chạy lại script khởi tạo SQL hoặc tạo role nếu database đã tồn tại.

Log khởi động tại `.local/postgres.log`. Không commit/copy thư mục dữ liệu đang hoạt động làm backup; dùng PostgreSQL backup/restore theo quy trình vận hành. Không xóa `.local/postgres` để xử lý lỗi kết nối.
