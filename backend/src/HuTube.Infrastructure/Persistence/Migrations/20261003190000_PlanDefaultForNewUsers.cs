using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261003190000_PlanDefaultForNewUsers")]
public sealed class PlanDefaultForNewUsers : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plans
          ADD COLUMN IF NOT EXISTS is_default_for_new_users BOOLEAN NOT NULL DEFAULT FALSE;

        UPDATE public.plans
        SET is_default_for_new_users = TRUE
        WHERE code = 'free' AND status = 'active'
          AND NOT EXISTS (SELECT 1 FROM public.plans WHERE is_default_for_new_users);

        CREATE UNIQUE INDEX IF NOT EXISTS ux_plans_default_for_new_users
          ON public.plans (is_default_for_new_users) WHERE is_default_for_new_users;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_plans_default_for_new_users;
        ALTER TABLE public.plans DROP COLUMN IF EXISTS is_default_for_new_users;
        """);
}
