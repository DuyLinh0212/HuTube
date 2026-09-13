using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913170000_PlanQuotaAndDisplayOrder")]
public sealed class PlanQuotaAndDisplayOrder : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plans
          ADD COLUMN IF NOT EXISTS display_order INT NOT NULL DEFAULT 0,
          ADD COLUMN IF NOT EXISTS max_download_quality VARCHAR(20) NOT NULL DEFAULT '720p';

        ALTER TABLE public.channel_quotas
          DROP CONSTRAINT IF EXISTS ck_channel_quotas_used;
        ALTER TABLE public.channel_quotas
          ADD CONSTRAINT ck_channel_quotas_used CHECK (storage_used >= 0);

        CREATE UNIQUE INDEX IF NOT EXISTS ux_plan_members_active_email
          ON public.plan_members (plan_history_id, lower(member_email))
          WHERE status IN ('pending', 'accepted');
        CREATE UNIQUE INDEX IF NOT EXISTS ux_plan_invitation_tokens_member
          ON public.plan_invitation_tokens (plan_member_id);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_plan_invitation_tokens_member;
        DROP INDEX IF EXISTS public.ux_plan_members_active_email;
        ALTER TABLE public.channel_quotas DROP CONSTRAINT IF EXISTS ck_channel_quotas_used;
        -- Keep the non-negative invariant during rollback. Reintroducing a
        -- storage_used <= storage_limit check could make a valid existing row
        -- impossible to update after an administrator lowers a plan quota.
        ALTER TABLE public.channel_quotas ADD CONSTRAINT ck_channel_quotas_used CHECK (storage_used >= 0);
        ALTER TABLE public.plans DROP COLUMN IF EXISTS display_order;
        """);
}
