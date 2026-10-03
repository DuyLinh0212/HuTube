using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("202610020001_BugFixAccountPayment")]
public sealed class BugFixAccountPaymentMigration : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.recommendation_jobs ADD COLUMN IF NOT EXISTS model_csv_key text;
        ALTER TABLE public.recommendation_jobs ADD COLUMN IF NOT EXISTS model_csv_sha256 text;
        ALTER TABLE public.recommendation_jobs ADD COLUMN IF NOT EXISTS service_job_id text;
        ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS auto_renew boolean NOT NULL DEFAULT false;
        ALTER TABLE public.users ADD COLUMN IF NOT EXISTS bio text;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS allow_comments boolean NOT NULL DEFAULT true;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS moderation_hidden boolean NOT NULL DEFAULT false;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS moderation_age_restricted boolean NOT NULL DEFAULT false;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS recommendation_restricted boolean NOT NULL DEFAULT false;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS media_purge_started_at timestamptz;
        ALTER TABLE public.video_renditions DROP CONSTRAINT IF EXISTS ck_video_renditions_status;
        ALTER TABLE public.video_renditions ADD CONSTRAINT ck_video_renditions_status CHECK (status IN ('processing', 'ready', 'failed', 'deleted'));
        UPDATE public.videos SET recommendation_restricted = true WHERE metadata->>'recommendation_restricted' = 'true';
        UPDATE public.videos SET moderation_hidden = true WHERE admin_original_status IS NOT NULL AND status = 'blocked';
        UPDATE public.videos v SET moderation_hidden = true WHERE EXISTS
            (SELECT 1 FROM public.moderation_cases m WHERE (m.video_id = v.video_id OR (m.target_type = 'video' AND m.target_id = v.video_id))
             AND m.decision = 'hide' AND m.status = 'resolved'
             AND NOT EXISTS (SELECT 1 FROM public.appeals a WHERE a.target_type = 'video' AND a.target_id = v.video_id
                 AND a.status = 'approved' AND a.resolved_at >= COALESCE(m.resolved_at, m.updated_at)));
        UPDATE public.videos v SET moderation_age_restricted = true WHERE EXISTS
            (SELECT 1 FROM public.moderation_cases m WHERE (m.video_id = v.video_id OR (m.target_type = 'video' AND m.target_id = v.video_id))
             AND m.decision = 'age_restrict' AND m.status = 'resolved'
             AND NOT EXISTS (SELECT 1 FROM public.appeals a WHERE a.target_type = 'video' AND a.target_id = v.video_id
                 AND a.status = 'approved' AND a.resolved_at >= COALESCE(m.resolved_at, m.updated_at)));
        UPDATE public.videos SET media_retention_until = updated_at + interval '30 days' WHERE status = 'deleted' AND media_retention_until IS NULL;
        DROP INDEX IF EXISTS public.ux_payments_idempotency;
        CREATE UNIQUE INDEX ux_payments_idempotency ON public.payments(user_id, idempotency_key)
            WHERE idempotency_key IS NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) =>
        throw new NotSupportedException("Preserve account and payment data when reverting this migration.");
}
