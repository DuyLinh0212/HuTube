using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260918120000_CfSeederPermission")]
public sealed class CfSeederPermission : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000024', 'cf_seed.manage', 'Quản lý CF Data Seeder', 'Tạo tài khoản, kênh và upload video phục vụ thực nghiệm Collaborative Filtering.', 'active')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id
        FROM public.roles r
        CROSS JOIN public.permissions p
        WHERE r.code IN ('admin', 'super_admin')
          AND p.code = 'cf_seed.manage'
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE permission_id = '00000000-0000-0001-0000-000000000024'::uuid;

        DELETE FROM public.permissions
        WHERE permission_id = '00000000-0000-0001-0000-000000000024'::uuid;
        """);
}
