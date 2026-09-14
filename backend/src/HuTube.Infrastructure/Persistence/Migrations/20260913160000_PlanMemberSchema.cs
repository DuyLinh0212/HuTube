using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913160000_PlanMemberSchema")]
public sealed class PlanMemberSchema : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE IF NOT EXISTS public.plan_members (
          plan_member_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          plan_history_id UUID NOT NULL REFERENCES public.plan_histories(plan_history_id) ON DELETE CASCADE,
          owner_user_id UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
          member_email CITEXT NOT NULL,
          member_user_id UUID NULL REFERENCES public.users(user_id) ON DELETE SET NULL,
          status VARCHAR(20) NOT NULL DEFAULT 'pending',
          invited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          accepted_at TIMESTAMPTZ NULL,
          revoked_at TIMESTAMPTZ NULL
        );

        ALTER TABLE public.plan_members
          ADD COLUMN IF NOT EXISTS owner_user_id UUID NULL,
          ADD COLUMN IF NOT EXISTS member_email CITEXT NULL,
          ADD COLUMN IF NOT EXISTS member_user_id UUID NULL,
          ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'pending',
          ADD COLUMN IF NOT EXISTS invited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ NULL,
          ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ NULL;

        CREATE TABLE IF NOT EXISTS public.plan_invitation_tokens (
          plan_invitation_token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          plan_member_id UUID NOT NULL REFERENCES public.plan_members(plan_member_id) ON DELETE CASCADE,
          token VARCHAR(256) NOT NULL,
          expires_at TIMESTAMPTZ NOT NULL,
          used_at TIMESTAMPTZ NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS public.plan_invitation_tokens;
        DROP TABLE IF EXISTS public.plan_members;
        """);
}
