using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925170000_RoleSoftDeleteStatus")]
public sealed class RoleSoftDeleteStatus : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.roles DROP CONSTRAINT IF EXISTS ck_roles_status;
        ALTER TABLE public.roles
          ADD CONSTRAINT ck_roles_status
          CHECK (status IN ('active', 'inactive', 'deleted'));
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.roles SET status = 'inactive' WHERE status = 'deleted';
        ALTER TABLE public.roles DROP CONSTRAINT IF EXISTS ck_roles_status;
        ALTER TABLE public.roles
          ADD CONSTRAINT ck_roles_status
          CHECK (status IN ('active', 'inactive'));
        """);
}
