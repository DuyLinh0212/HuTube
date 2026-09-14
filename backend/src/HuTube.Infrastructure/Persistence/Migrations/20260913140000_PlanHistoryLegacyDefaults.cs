using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913140000_PlanHistoryLegacyDefaults")]
public sealed class PlanHistoryLegacyDefaults : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plan_histories
          ALTER COLUMN start_date DROP NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.plan_histories SET start_date = COALESCE(start_date, started_at) WHERE start_date IS NULL;
        ALTER TABLE public.plan_histories ALTER COLUMN start_date SET NOT NULL;
        """);
}
