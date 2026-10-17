using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261016103000_ReviewerClaimLeases")]
public sealed class ReviewerClaimLeases : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.moderation_cases ADD COLUMN claim_id uuid NULL;
        ALTER TABLE public.moderation_cases ADD COLUMN claim_expires_at timestamptz NULL;
        ALTER TABLE public.appeals ADD COLUMN claimed_at timestamptz NULL;
        ALTER TABLE public.appeals ADD COLUMN claim_id uuid NULL;
        ALTER TABLE public.appeals ADD COLUMN claim_expires_at timestamptz NULL;
        UPDATE public.moderation_cases SET status='pending',reviewer_id=NULL,claimed_at=NULL
          WHERE status='reviewing' AND resolved_at IS NULL;
        UPDATE public.appeals SET status='pending',reviewer_id=NULL
          WHERE status='reviewing' AND resolved_at IS NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.moderation_cases DROP COLUMN claim_id, DROP COLUMN claim_expires_at;
        ALTER TABLE public.appeals DROP COLUMN claimed_at, DROP COLUMN claim_id, DROP COLUMN claim_expires_at;
        """);
}
