using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913100000_PlanAdminPermissions")]
public sealed class PlanAdminPermissions : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000018', 'plan.view', 'Xem Gói dịch vụ', 'Xem toàn bộ gói dịch vụ và trạng thái.', 'active'),
          ('00000000-0000-0001-0000-000000000019', 'plan.create', 'Tạo Gói dịch vụ', 'Tạo gói dịch vụ mới.', 'active'),
          ('00000000-0000-0001-0000-000000000020', 'plan.edit', 'Sửa Gói dịch vụ', 'Cập nhật giới hạn và giá gói dịch vụ.', 'active'),
          ('00000000-0000-0001-0000-000000000021', 'plan.archive', 'Lưu trữ Gói dịch vụ', 'Ngừng cung cấp gói dịch vụ mà không xóa lịch sử.', 'active')
        ON CONFLICT (permission_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description, status = EXCLUDED.status;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id
        FROM public.roles r CROSS JOIN public.permissions p
        WHERE r.code IN ('super_admin', 'admin') AND p.code IN ('plan.view', 'plan.create', 'plan.edit', 'plan.archive')
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions WHERE permission_id IN (
          '00000000-0000-0001-0000-000000000018'::uuid,
          '00000000-0000-0001-0000-000000000019'::uuid,
          '00000000-0000-0001-0000-000000000020'::uuid,
          '00000000-0000-0001-0000-000000000021'::uuid);
        DELETE FROM public.permissions WHERE permission_id IN (
          '00000000-0000-0001-0000-000000000018'::uuid,
          '00000000-0000-0001-0000-000000000019'::uuid,
          '00000000-0000-0001-0000-000000000020'::uuid,
          '00000000-0000-0001-0000-000000000021'::uuid);
        """);
}
