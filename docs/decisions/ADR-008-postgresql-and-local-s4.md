# ADR-008 — PostgreSQL và phạm vi triển khai S4-01/S4-02

- Ngày: 2026-09-05
- Trạng thái: Đã chấp nhận theo yêu cầu triển khai
- Phạm vi: S4-01 và S4-02; không thay đổi phạm vi các slice S4-03 trở đi.

## Bối cảnh

`PROJECT_ARCHITECTURE.md` còn đề cập SQL Server. `TECH_STACK.md`, SQL nguồn `database/HuTube.sql` được người dùng cung cấp bên ngoài repository, và yêu cầu hiện tại đều sử dụng PostgreSQL. Máy phát triển đã có PostgreSQL/psql. Người dùng xác nhận chưa có Render hoặc API staging, và yêu cầu tạm dùng local.

## Quyết định

1. Dùng PostgreSQL với EF Core/Npgsql. Giữ Clean Architecture bốn project và một API dùng chung cho ba client. Các đoạn SQL Server trong tài liệu kiến trúc cũ không còn là lựa chọn triển khai database hiện hành.
2. Lưu database trên PostgreSQL local. Docker Compose là lựa chọn bổ sung, dùng cổng 5433 để tránh trùng PostgreSQL native ở cổng 5432. Không thay thế hoặc xóa database native.
3. API local mặc định `http://localhost:5080`; base URL của client có `/api/v1`. Android emulator dùng `10.0.2.2` để truy cập máy host. Mọi host có thể đổi bằng cấu hình, không sửa nghiệp vụ client.
4. Migration là bước riêng (`--migrate`), có lịch sử trong source control. API startup bình thường không tự sửa schema. Không tự động chạy down migration khi rollback phiên bản ứng dụng.
5. CI kiểm tra backend, hai web và Flutter; build container. Publish GHCR trên `develop`. Render là bước thủ công opt-in sau khi cấu hình secrets, database, email và pre-deploy migration.
6. Chưa có URL staging và chưa chạy E2E trên staging. Các tiêu chí staging gốc trong `Sprint4.md` được hoãn theo chỉ đạo người dùng, không được đánh dấu đã hoàn tất.

## Hệ quả

Có thể phát triển và nghiệm thu luồng local ngay. Việc merge `develop` không đồng nghĩa đã deploy cloud. Cần bổ sung bằng chứng deploy và smoke trên staging khi có hạ tầng. OAuth Google/Facebook và RBAC permission engine toàn phần thuộc phạm vi chưa triển khai; S4-02 chỉ yêu cầu chặn tài khoản thường hoặc admin bị vô hiệu hóa ở biên API admin.
