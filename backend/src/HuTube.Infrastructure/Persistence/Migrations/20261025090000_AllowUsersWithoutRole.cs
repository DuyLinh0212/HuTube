using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261025090000_AllowUsersWithoutRole")]
public sealed class AllowUsersWithoutRole : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) =>
        migrationBuilder.Sql("ALTER TABLE public.users ALTER COLUMN role_id DROP NOT NULL;");

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DO $$ BEGIN
            IF EXISTS (SELECT 1 FROM public.users WHERE role_id IS NULL) THEN
                RAISE EXCEPTION 'Reassign users without a role before rolling back AllowUsersWithoutRole.';
            END IF;
        END $$;
        ALTER TABLE public.users ALTER COLUMN role_id SET NOT NULL;
        """);
}
