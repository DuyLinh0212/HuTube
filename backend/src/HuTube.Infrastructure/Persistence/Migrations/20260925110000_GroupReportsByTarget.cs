using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925110000_GroupReportsByTarget")]
public sealed class GroupReportsByTarget : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.reports
          ADD COLUMN IF NOT EXISTS moderation_case_id UUID,
          ADD COLUMN IF NOT EXISTS disposition VARCHAR(20),
          ADD COLUMN IF NOT EXISTS disposition_by_user_id UUID REFERENCES public.users(user_id) ON DELETE SET NULL,
          ADD COLUMN IF NOT EXISTS disposition_reason TEXT,
          ADD COLUMN IF NOT EXISTS disposition_at TIMESTAMPTZ,
          ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128),
          ADD COLUMN IF NOT EXISTS abuse_flag BOOLEAN NOT NULL DEFAULT FALSE;

        ALTER TABLE public.moderation_cases
          ADD COLUMN IF NOT EXISTS target_type VARCHAR(20),
          ADD COLUMN IF NOT EXISTS target_id UUID;

        ALTER TABLE public.moderation_cases DROP CONSTRAINT IF EXISTS ck_moderation_cases_target;
        ALTER TABLE public.moderation_cases ADD CONSTRAINT ck_moderation_cases_target
          CHECK (num_nonnulls(video_id, report_id, target_id) = 1);
        ALTER TABLE public.moderation_cases DROP CONSTRAINT IF EXISTS ck_moderation_cases_type;
        ALTER TABLE public.moderation_cases ADD CONSTRAINT ck_moderation_cases_type
          CHECK (case_type IN ('upload_review','report_review','report_case','manual_review'));

        INSERT INTO public.moderation_cases
          (moderation_case_id, video_id, report_id, reviewer_id, case_type, status, submitted_at, claimed_at, resolved_at, updated_at, target_type, target_id)
        SELECT gen_random_uuid(), NULL, NULL,
          (array_agg(old_case.reviewer_id ORDER BY old_case.claimed_at DESC NULLS LAST)
            FILTER (WHERE old_case.status = 'reviewing' AND old_case.reviewer_id IS NOT NULL))[1],
          'report_case',
          CASE
            WHEN bool_or(r.status = 'reviewing') THEN 'reviewing'
            WHEN bool_or(r.status = 'pending') THEN 'pending'
            WHEN bool_or(old_case.status = 'escalated') THEN 'escalated'
            ELSE 'resolved'
          END,
          min(r.created_at), max(old_case.claimed_at) FILTER (WHERE old_case.status = 'reviewing'),
          max(r.updated_at) FILTER (WHERE old_case.status IN ('resolved','rejected','escalated')), max(r.updated_at),
          CASE WHEN r.video_id IS NOT NULL THEN 'video' WHEN r.comment_id IS NOT NULL THEN 'comment' ELSE 'channel' END,
          COALESCE(r.video_id, r.comment_id, r.channel_id)
        FROM public.reports r
        LEFT JOIN public.moderation_cases old_case ON old_case.report_id = r.report_id
        GROUP BY CASE WHEN r.video_id IS NOT NULL THEN 'video' WHEN r.comment_id IS NOT NULL THEN 'comment' ELSE 'channel' END,
          COALESCE(r.video_id, r.comment_id, r.channel_id)
        ON CONFLICT DO NOTHING;

        UPDATE public.reports r
        SET moderation_case_id = mc.moderation_case_id,
            disposition = CASE WHEN r.status = 'resolved' THEN 'accepted' WHEN r.status IN ('rejected','cancelled') THEN 'rejected' ELSE NULL END
        FROM public.moderation_cases mc
        WHERE mc.case_type = 'report_case'
          AND mc.target_type = CASE WHEN r.video_id IS NOT NULL THEN 'video' WHEN r.comment_id IS NOT NULL THEN 'comment' ELSE 'channel' END
          AND mc.target_id = COALESCE(r.video_id, r.comment_id, r.channel_id);

        ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS fk_reports_moderation_case;
        ALTER TABLE public.reports ADD CONSTRAINT fk_reports_moderation_case
          FOREIGN KEY (moderation_case_id) REFERENCES public.moderation_cases(moderation_case_id) ON DELETE SET NULL;
        CREATE INDEX IF NOT EXISTS ix_reports_moderation_case ON public.reports(moderation_case_id);
        CREATE UNIQUE INDEX IF NOT EXISTS ux_reports_user_idempotency ON public.reports(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS ux_moderation_cases_report_target
          ON public.moderation_cases(case_type, target_type, target_id) WHERE case_type = 'report_case';
        CREATE INDEX IF NOT EXISTS ix_moderation_cases_target ON public.moderation_cases(target_type, target_id, status);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ix_moderation_cases_target;
        DROP INDEX IF EXISTS public.ux_moderation_cases_report_target;
        DROP INDEX IF EXISTS public.ux_reports_user_idempotency;
        DROP INDEX IF EXISTS public.ix_reports_moderation_case;
        ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS fk_reports_moderation_case;
        ALTER TABLE public.reports
          DROP COLUMN IF EXISTS moderation_case_id,
          DROP COLUMN IF EXISTS disposition,
          DROP COLUMN IF EXISTS disposition_by_user_id,
          DROP COLUMN IF EXISTS disposition_reason,
          DROP COLUMN IF EXISTS disposition_at,
          DROP COLUMN IF EXISTS idempotency_key,
          DROP COLUMN IF EXISTS abuse_flag;
        DELETE FROM public.moderation_cases WHERE case_type = 'report_case';
        ALTER TABLE public.moderation_cases DROP CONSTRAINT IF EXISTS ck_moderation_cases_target;
        ALTER TABLE public.moderation_cases ADD CONSTRAINT ck_moderation_cases_target CHECK (num_nonnulls(video_id, report_id) = 1);
        ALTER TABLE public.moderation_cases DROP CONSTRAINT IF EXISTS ck_moderation_cases_type;
        ALTER TABLE public.moderation_cases ADD CONSTRAINT ck_moderation_cases_type CHECK (case_type IN ('upload_review','report_review','manual_review'));
        ALTER TABLE public.moderation_cases DROP COLUMN IF EXISTS target_type, DROP COLUMN IF EXISTS target_id;
        """);
}
