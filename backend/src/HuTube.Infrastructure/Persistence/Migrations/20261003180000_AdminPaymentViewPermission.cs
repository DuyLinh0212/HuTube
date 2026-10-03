using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261003180000_AdminPaymentViewPermission")]
public sealed class AdminPaymentViewPermission : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES ('00000000-0000-0001-0000-000000000022', 'payment.view', 'Xem doanh thu & thanh toán',
            'Xem giao dịch thanh toán, số liệu doanh thu và báo cáo.', 'active')
        ON CONFLICT (permission_id) DO UPDATE
        SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description, status = EXCLUDED.status;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT role.role_id, permission.permission_id
        FROM public.roles AS role CROSS JOIN public.permissions AS permission
        WHERE role.code IN ('admin', 'super_admin') AND permission.code = 'payment.view'
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE permission_id = '00000000-0000-0001-0000-000000000022'::uuid;
        DELETE FROM public.permissions
        WHERE permission_id = '00000000-0000-0001-0000-000000000022'::uuid;
        """);
}
