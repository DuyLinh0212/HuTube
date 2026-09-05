# HuTube - Quy trình Quản lý thay đổi Database

> Phiên bản: 0.1  
> Trạng thái: Draft

## 1. Mục tiêu

Mọi thay đổi Database phải:

- Có lịch sử.
- Có thể review.
- Có thể chạy lại.
- Có thể rollback khi phù hợp.
- Không phụ thuộc vào việc một thành viên nhớ mình đã sửa gì trực tiếp trong SQL Server.

---

# 2. Cấu trúc thư mục Database

```text
database/
├── migrations/
├── updates/
├── seed/
└── scripts/
```

---

# 3. database/migrations

Dùng để lưu migration được tạo từ Entity Framework Core hoặc SQL export tương ứng.

Ví dụ:

```text
database/migrations/
├── 20260828_initial-schema/
├── 20260903_add-video-status/
└── 20260910_add-report-resolution/
```

Một migration quan trọng có thể có:

```text
20260910_add-report-resolution/
├── migration.sql
└── README.md
```

EF Core migration gốc vẫn có thể nằm trong project Infrastructure theo mặc định.

Thư mục root `database/migrations/` dùng để lưu bản SQL hoặc tài liệu migration phục vụ team/deploy nếu cần.

---

# 4. database/updates

Đây là nơi ghi lại update Database theo version của HuTube.

```text
database/updates/
├── v0.1.0/
├── v0.2.0/
├── v0.3.0/
└── v1.0.0/
```

Ví dụ:

```text
database/updates/v0.3.0/
├── README.md
├── up.sql
└── down.sql
```

---

# 5. Quy định một Database Update

Mỗi update quan trọng nên có:

```text
README.md
up.sql
down.sql
```

`down.sql` có thể bỏ nếu rollback không an toàn, nhưng phải ghi rõ lý do trong README.

Ví dụ README:

```markdown
# Database Update v0.3.0

## Added
- Bảng ReportResolution.
- Cột resolution_type_id.
- Index cho report_id.

## Changed
- Cập nhật quan hệ Report - Resolution.

## Removed
- Không có.

## Migration Order
1. Backup Database.
2. Run up.sql.
3. Run seed script nếu cần.
4. Verify migration.

## Rollback
Run down.sql.
```

---

# 6. Quy định bắt buộc

Mọi thay đổi schema phải có ít nhất một trong hai:

1. EF Core Migration.
2. SQL Update Script.

Thay đổi quan trọng nên có cả hai.

Không được:

- Sửa Production Database rồi không lưu script.
- Xóa migration đã chạy trên môi trường dùng chung.
- Chỉnh migration cũ đã được team sử dụng.
- Đổi schema thủ công nhưng không cập nhật source.
- Commit dữ liệu thật của user vào repository.

Nếu cần sửa migration đã tồn tại:

```text
Tạo migration mới
```

không sửa lịch sử migration cũ.

---

# 7. database/seed

Chứa dữ liệu hệ thống cần khởi tạo.

Ví dụ:

```text
database/seed/
├── roles.sql
├── permissions.sql
├── report-reasons.sql
├── violation-types.sql
└── payment-providers.sql
```

Seed không chứa dữ liệu người dùng thật.

Seed phải có khả năng chạy an toàn nhiều lần nếu có thể.

---

# 8. database/scripts

Chứa script kỹ thuật không phải migration.

```text
database/scripts/
├── create-database.sql
├── backup-database.sql
├── restore-database.sql
├── reset-development-database.sql
└── health-check.sql
```

---

# 9. Naming Database Update

Folder migration:

```text
YYYYMMDD_short-description
```

Ví dụ:

```text
20260910_add-report-resolution
20260915_add-payment-provider
```

Folder update theo release:

```text
vMAJOR.MINOR.PATCH
```

Ví dụ:

```text
v0.3.0
v0.4.0
v1.0.0
```

SQL file:

```text
up.sql
down.sql
```

---

# 10. Branch cho Database

Sử dụng:

```text
db/<short-description>
```

Ví dụ:

```text
db/add-report-resolution
db/add-video-index
db/update-payment-provider
```

---

# 11. Commit cho Database

Ví dụ:

```text
db: add report resolution table
db: add index for video status
db: update payment provider seed
```

---

# 12. Quy trình thay đổi Database

```text
1. Tạo branch db/...
2. Tạo EF Core Migration hoặc SQL Script
3. Update database local
4. Test migration
5. Test rollback nếu có
6. Update database/updates/
7. Update docs/database nếu cần
8. Commit
9. Pull Request
10. Review
11. Merge
```

---

# 13. Quy trình Production

Trước khi update:

```text
Backup
↓
Review Script
↓
Verify Environment
↓
Apply Migration
↓
Run Smoke Test
↓
Monitor
```

Nếu lỗi:

```text
Rollback
hoặc
Restore Backup
```

tùy loại thay đổi.

---

# 14. Quy định thay đổi dữ liệu nguy hiểm

Các thao tác sau phải được review kỹ:

```text
DROP TABLE
DROP COLUMN
DELETE không có điều kiện
UPDATE diện rộng
ALTER COLUMN có nguy cơ mất dữ liệu
Thay đổi FK
Thay đổi unique constraint
```

Không chạy trực tiếp trên Production nếu chưa có backup và kế hoạch rollback.

---

# 15. CHANGELOG và Database

Nếu thay đổi Database ảnh hưởng chức năng hoặc release, phải cập nhật:

```text
CHANGELOG.md
```

Ví dụ:

```markdown
### Changed
- Cập nhật cấu trúc Report Resolution.

### Added
- Thêm bảng PaymentProvider.
```

