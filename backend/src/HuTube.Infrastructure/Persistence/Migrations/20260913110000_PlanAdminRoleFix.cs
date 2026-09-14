using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913110000_PlanAdminRoleFix")]
public sealed class PlanAdminRoleFix : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT role_id, permission_id
        FROM (VALUES
          ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0001-0000-000000000018'::uuid),
          ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0001-0000-000000000019'::uuid),
          ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0001-0000-000000000020'::uuid),
          ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0001-0000-000000000021'::uuid),
          ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0001-0000-000000000018'::uuid),
          ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0001-0000-000000000019'::uuid),
          ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0001-0000-000000000020'::uuid),
          ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0001-0000-000000000021'::uuid)
        ) AS grants(role_id, permission_id)
        WHERE EXISTS (SELECT 1 FROM public.roles r WHERE r.role_id = grants.role_id)
          AND EXISTS (SELECT 1 FROM public.permissions p WHERE p.permission_id = grants.permission_id)
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE role_id IN ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000003'::uuid)
          AND permission_id IN (
            '00000000-0000-0001-0000-000000000018'::uuid,
            '00000000-0000-0001-0000-000000000019'::uuid,
            '00000000-0000-0001-0000-000000000020'::uuid,
            '00000000-0000-0001-0000-000000000021'::uuid);
        """);
}
