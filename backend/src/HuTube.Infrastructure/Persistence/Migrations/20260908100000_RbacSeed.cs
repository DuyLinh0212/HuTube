using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260908100000_RbacSeed")]
public sealed class RbacSeed : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- 1. Seed Roles
        INSERT INTO public.roles (role_id, code, name, description, is_default, status)
        VALUES
          ('00000000-0000-0000-0000-000000000003', 'super_admin', 'Super Administrator', 'Toàn quyền quản trị hệ thống', FALSE, 'active'),
          ('00000000-0000-0000-0000-000000000004', 'moderator', 'Moderator', 'Kiểm duyệt nội dung và bình luận', FALSE, 'active'),
          ('00000000-0000-0000-0000-000000000005', 'support', 'Support', 'Hỗ trợ người dùng', FALSE, 'active'),
          ('00000000-0000-0000-0000-000000000006', 'finance', 'Finance', 'Quản lý thanh toán và gói cước', FALSE, 'active'),
          ('00000000-0000-0000-0000-000000000007', 'analyst', 'Analyst', 'Báo cáo và thống kê', FALSE, 'active'),
          ('00000000-0000-0000-0000-000000000008', 'auditor', 'Auditor', 'Kiểm tra nhật ký kiểm toán hệ thống', FALSE, 'active')
        ON CONFLICT (role_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description;

        -- 2. Seed Permissions
        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000001', 'dashboard.view', 'Xem Dashboard', 'Xem tổng quan và thống kê hệ thống', 'active'),
          ('00000000-0000-0001-0000-000000000002', 'user.view', 'Xem Người dùng', 'Xem danh sách và chi tiết tài khoản', 'active'),
          ('00000000-0000-0001-0000-000000000003', 'user.edit', 'Chỉnh sửa Người dùng', 'Cập nhật thông tin tài khoản', 'active'),
          ('00000000-0000-0001-0000-000000000004', 'user.ban', 'Khóa Người dùng', 'Khóa hoặc đình chỉ người dùng', 'active'),
          ('00000000-0000-0001-0000-000000000005', 'role.view', 'Xem Vai trò', 'Xem danh sách vai trò và quyền hạn', 'active'),
          ('00000000-0000-0001-0000-000000000006', 'role.edit', 'Chỉnh sửa Vai trò', 'Gán và thay đổi quyền của vai trò', 'active'),
          ('00000000-0000-0001-0000-000000000007', 'channel.view', 'Xem Kênh', 'Xem thông tin các kênh', 'active'),
          ('00000000-0000-0001-0000-000000000008', 'channel.edit', 'Quản lý Kênh', 'Cập nhật hoặc vô hiệu hóa kênh', 'active'),
          ('00000000-0000-0001-0000-000000000009', 'video.view', 'Xem Video', 'Xem danh sách và metadata video', 'active'),
          ('00000000-0000-0001-0000-000000000010', 'moderation.view_queue', 'Xem Hàng đợi Kiểm duyệt', 'Xem danh sách báo cáo vi phạm', 'active'),
          ('00000000-0000-0001-0000-000000000011', 'moderation.claim', 'Nhận Phiếu Kiểm duyệt', 'Tiếp nhận xử lý báo cáo vi phạm', 'active'),
          ('00000000-0000-0001-0000-000000000012', 'moderation.review', 'Đánh giá Vi phạm', 'Xem xét nội dung bị báo cáo', 'active'),
          ('00000000-0000-0001-0000-000000000013', 'moderation.approve', 'Duyệt Nội dung', 'Phê duyệt nội dung hợp lệ', 'active'),
          ('00000000-0000-0001-0000-000000000014', 'moderation.reject', 'Gỡ Nội dung', 'Từ chối hoặc gỡ bỏ nội dung vi phạm', 'active'),
          ('00000000-0000-0001-0000-000000000015', 'audit.view', 'Xem Nhật ký Kiểm toán', 'Xem nhật ký hoạt động hệ thống', 'active'),
          ('00000000-0000-0001-0000-000000000016', 'system.view_setting', 'Xem Cấu hình Hệ thống', 'Xem các thông số cấu hình hệ thống', 'active'),
          ('00000000-0000-0001-0000-000000000017', 'system.edit_setting', 'Chỉnh sửa Cấu hình Hệ thống', 'Thay đổi cấu hình hệ thống', 'active')
        ON CONFLICT (permission_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description;

        -- 3. Seed Role Permissions
        -- Super Admin: all 17 permissions
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000003'::uuid, p.permission_id
        FROM public.permissions p
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- Admin: 15 permissions (all except role.edit and system.edit_setting)
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000002'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code NOT IN ('role.edit', 'system.edit_setting')
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- Moderator: moderation.view_queue, moderation.claim, moderation.review, video.view, dashboard.view
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000004'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code IN ('dashboard.view', 'video.view', 'moderation.view_queue', 'moderation.claim', 'moderation.review')
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- Auditor: dashboard.view, audit.view
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000008'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code IN ('dashboard.view', 'audit.view')
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE permission_id IN (
          SELECT permission_id FROM public.permissions
          WHERE permission_id >= '00000000-0000-0001-0000-000000000001'::uuid
            AND permission_id <= '00000000-0000-0001-0000-000000000017'::uuid
        );

        DELETE FROM public.permissions
        WHERE permission_id >= '00000000-0000-0001-0000-000000000001'::uuid
          AND permission_id <= '00000000-0000-0001-0000-000000000017'::uuid;

        DELETE FROM public.roles
        WHERE role_id IN (
          '00000000-0000-0000-0000-000000000003'::uuid,
          '00000000-0000-0000-0000-000000000004'::uuid,
          '00000000-0000-0000-0000-000000000005'::uuid,
          '00000000-0000-0000-0000-000000000006'::uuid,
          '00000000-0000-0000-0000-000000000007'::uuid,
          '00000000-0000-0000-0000-000000000008'::uuid
        )
        AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.role_id = roles.role_id);
        """);
}
