# HuTube scripts

Các script trong thư mục này dùng cho môi trường local của HuTube trên Windows PowerShell.

## Chuẩn bị

Mở PowerShell tại thư mục gốc `HuTube`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Đảm bảo PostgreSQL đang chạy ở `localhost:5432`, database local là `hutube_local`, và file `.env.local` đã có `ConnectionStrings__Database` cùng các biến cần thiết. Có thể kiểm tra nhanh:

```powershell
.\scripts\local-postgres.ps1 -Action Status
.\scripts\smoke.ps1
```

Các script không in mật khẩu ra màn hình và không đặt mật khẩu trực tiếp trên command line.

## 1. Xuất toàn bộ database local

`export-database.ps1` dùng `pg_dump` định dạng custom để xuất schema, dữ liệu và các object PostgreSQL của database trong `ConnectionStrings__Database`. File backup mặc định được lưu ngay tại thư mục gốc `HuTube`:

```powershell
.\scripts\export-database.ps1
```

Đặt tên file khác nhưng vẫn phải nằm trong thư mục gốc `HuTube`:

```powershell
.\scripts\export-database.ps1 -OutputFile 'hutube-backup-before-demo.dump'
```

Script không ghi đè file đã tồn tại. Backup database chỉ chứa bản ghi và URL tới media; video, ảnh thật đang ở R2/Cloudinary không nằm trong file dump.

## 2. Import và thay thế database cũ

`import-database.ps1` phục hồi file `.dump`, `.backup` hoặc `.sql` vào PostgreSQL. DBeaver không phải nơi trực tiếp thực hiện restore: script thao tác với PostgreSQL, sau đó DBeaver chỉ cần refresh/reconnect để nhìn thấy dữ liệu mới.

Lệnh dưới đây mở hộp thoại chọn file, hỏi username/password PostgreSQL, rồi yêu cầu gõ chính xác `REPLACE` trước khi xóa database đích:

```powershell
.\scripts\import-database.ps1 -ReplaceExisting
```

Hoặc truyền sẵn file và thông tin kết nối (mật khẩu vẫn được hỏi bằng hộp thoại an toàn):

```powershell
.\scripts\import-database.ps1 `
  -BackupFile '.\hutube-backup-20260912-120000.dump' `
  -Server 'localhost' `
  -Port 5432 `
  -Database 'hutube_local' `
  -Username 'postgres' `
  -ReplaceExisting
```

Trước khi thay thế, script tự tạo file `hutube-before-import-YYYYMMDD-HHmmss.dump` trong thư mục gốc nếu database đích đang tồn tại. Chỉ dùng `-SkipTargetBackup` khi đã có bản backup khác:

```powershell
.\scripts\import-database.ps1 -BackupFile '.\backup.dump' -Database 'hutube_local' -Username 'postgres' -ReplaceExisting -SkipTargetBackup
```

Lưu ý: thao tác này `DROP DATABASE` rồi tạo lại database, nên mọi dữ liệu hiện tại trong database đích sẽ bị thay thế. Nếu restore lỗi giữa chừng, database có thể mới chỉ được phục hồi một phần; dùng file safety backup để khôi phục lại.

## 3. Quản lý PostgreSQL local có sẵn

`local-postgres.ps1` chỉ quản lý cluster PostgreSQL đã tồn tại trong `.local/postgres`; script không tự khởi tạo, xóa hay thay thế dữ liệu:

```powershell
.\scripts\local-postgres.ps1 -Action Status
.\scripts\local-postgres.ps1 -Action Start -Port 55432
.\scripts\local-postgres.ps1 -Action Stop
```

Nếu dùng PostgreSQL cài ở nơi khác, truyền thư mục `bin` bằng `-PostgresBin`.

## 4. Cài dependency và chạy migration

`setup-local.ps1` restore dependency và chạy API với tham số `--migrate`, sau đó cài dependency cho web/mobile:

```powershell
.\scripts\setup-local.ps1
```

Không cần chạy migration thủ công sau mỗi lần chạy app. API chỉ gọi `Database.MigrateAsync()` khi được chạy với tham số `--migrate` (đã được `setup-local.ps1` thực hiện); chỉ cần chạy `setup-local.ps1` khi checkout migration mới hoặc muốn chuẩn bị lại môi trường.

## 5. Chạy các thành phần

Mở mỗi thành phần trong một cửa sổ PowerShell riêng:

```powershell
.\scripts\run-local.ps1 -Component api
.\scripts\run-local.ps1 -Component user
.\scripts\run-local.ps1 -Component admin
.\scripts\run-local.ps1 -Component mobile
```

Web người dùng chạy ở `http://localhost:4200`, admin ở `http://localhost:4201`, API ở `http://localhost:5080` theo cấu hình local hiện tại.

## 6. Kiểm tra nhanh và chạy test

Kiểm tra API đang sống:

```powershell
.\scripts\smoke.ps1
```

Chạy toàn bộ backend/web/mobile test cần cấu hình `TEST_DATABASE_CONNECTION` trong `.env.local`:

```powershell
.\scripts\test.ps1
```

## 7. `common.ps1`

Đây là thư viện hàm dùng chung cho các script khác, không chạy trực tiếp. Nó đọc `.env.local`, phân tích connection string, tìm `pg_dump`/`pg_restore`/`psql`, truyền mật khẩu qua biến môi trường tạm thời và kiểm tra exit code.
