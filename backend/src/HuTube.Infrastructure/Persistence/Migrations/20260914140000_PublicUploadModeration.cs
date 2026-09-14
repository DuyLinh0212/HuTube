using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260914140000_PublicUploadModeration")]
public sealed class PublicUploadModeration : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Public videos created before upload-time moderation was enforced
        -- must be held until a reviewer resolves their moderation case.
        UPDATE public.videos
        SET moderation_status = 'pending',
            updated_at = CURRENT_TIMESTAMP
        WHERE visibility = 'public'
          AND status <> 'deleted'
          AND moderation_status = 'not_submitted';

        INSERT INTO public.moderation_cases
          (video_id, case_type, status, risk_level, submitted_at, updated_at)
        SELECT v.video_id,
               'upload_review',
               'pending',
               'low',
               v.created_at,
               CURRENT_TIMESTAMP
        FROM public.videos AS v
        WHERE v.visibility = 'public'
          AND v.status <> 'deleted'
          AND v.moderation_status = 'pending'
          AND NOT EXISTS (
            SELECT 1
            FROM public.moderation_cases AS existing
            WHERE existing.video_id = v.video_id
              AND existing.case_type = 'upload_review'
              AND existing.status IN ('pending', 'reviewing')
          );
        """);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Do not discard moderation cases or reopen public videos on rollback.
    }
}
