using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913130000_PlanHistoryCompatibility")]
public sealed class PlanHistoryCompatibility : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plan_histories
          ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
          ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ NULL,
          ADD COLUMN IF NOT EXISTS owner_user_id UUID NULL,
          ADD COLUMN IF NOT EXISTS auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
          ADD COLUMN IF NOT EXISTS payment_reference VARCHAR(255) NULL;

        UPDATE public.plan_histories
        SET started_at = COALESCE(started_at, start_date, created_at),
            ended_at = COALESCE(ended_at, end_date),
            owner_user_id = COALESCE(owner_user_id, user_id)
        WHERE started_at IS NULL OR owner_user_id IS NULL;

        ALTER TABLE public.plan_histories
          ALTER COLUMN started_at SET NOT NULL,
          ALTER COLUMN owner_user_id SET NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plan_histories
          DROP COLUMN IF EXISTS started_at,
          DROP COLUMN IF EXISTS ended_at,
          DROP COLUMN IF EXISTS owner_user_id,
          DROP COLUMN IF EXISTS auto_renew,
          DROP COLUMN IF EXISTS payment_reference;
        """);
}
