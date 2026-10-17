using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261016093000_AppealEscalationResolutionState")]
public sealed class AppealEscalationResolutionState : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.appeals DROP CONSTRAINT IF EXISTS ck_appeals_status;
        ALTER TABLE public.appeals ADD CONSTRAINT ck_appeals_status
            CHECK (status IN ('pending','reviewing','escalated','approved','rejected','cancelled'));
        ALTER TABLE public.appeals DROP CONSTRAINT IF EXISTS ck_appeals_resolution_state;
        ALTER TABLE public.appeals ADD CONSTRAINT ck_appeals_resolution_state CHECK (
            status IN ('pending','reviewing','escalated','cancelled') OR
            (status IN ('approved','rejected') AND resolved_at IS NOT NULL AND reviewer_id IS NOT NULL));
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DO $$ BEGIN
          IF EXISTS (SELECT 1 FROM public.appeals WHERE status='escalated') THEN
            RAISE EXCEPTION 'Resolve escalated appeals before rolling back escalation support';
          END IF;
        END $$;
        ALTER TABLE public.appeals DROP CONSTRAINT ck_appeals_resolution_state;
        ALTER TABLE public.appeals ADD CONSTRAINT ck_appeals_resolution_state CHECK (
            status IN ('pending','reviewing','cancelled') OR
            (status IN ('approved','rejected') AND resolved_at IS NOT NULL AND reviewer_id IS NOT NULL));
        ALTER TABLE public.appeals DROP CONSTRAINT ck_appeals_status;
        ALTER TABLE public.appeals ADD CONSTRAINT ck_appeals_status
            CHECK (status IN ('pending','reviewing','approved','rejected','cancelled'));
        """);
}
