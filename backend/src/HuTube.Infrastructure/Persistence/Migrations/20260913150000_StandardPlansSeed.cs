using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913150000_StandardPlansSeed")]
public sealed class StandardPlansSeed : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Keep this seed safe when applied before PlanQuotaAndDisplayOrder.
        ALTER TABLE public.plans
          ADD COLUMN IF NOT EXISTS display_order INT NOT NULL DEFAULT 0;

        INSERT INTO public.plans
          (plan_id, code, name, description, price, duration_days, storage_limit, max_upload_size, max_video_duration,
           max_video_quality, max_download_quality, max_members, display_order, status, features, created_at, updated_at)
        VALUES
          ('00000000-0000-0000-0000-000000000100', 'free', 'Free', 'Gói miễn phí cho người mới bắt đầu.', 0, 3650,
           10737418240, 1073741824, 43200, '720p', '720p', 1, 1, 'active', '{"download":false,"background_play":false,"pip":false}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0000-0000-000000000101', 'creator', 'Creator', 'Gói dành cho người sáng tạo.', 99000, 30,
           107374182400, 21474836480, 43200, '1080p', '1080p', 1, 2, 'active', '{"download":true,"background_play":true,"pip":true}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0000-0000-000000000102', 'pro_family', 'Pro Group', 'Gói nhóm gồm chủ gói và 4 thành viên qua Gmail.', 299000, 30,
           536870912000, 53687091200, 86400, '2160p', '2160p', 5, 3, 'active', '{"download":true,"background_play":true,"pip":true,"shared_seats":5}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (code) DO UPDATE SET
          name = EXCLUDED.name, description = EXCLUDED.description, price = EXCLUDED.price,
          duration_days = EXCLUDED.duration_days, storage_limit = EXCLUDED.storage_limit,
          max_upload_size = EXCLUDED.max_upload_size, max_video_duration = EXCLUDED.max_video_duration,
          max_video_quality = EXCLUDED.max_video_quality, max_members = EXCLUDED.max_members,
          max_download_quality = EXCLUDED.max_download_quality,
          display_order = EXCLUDED.display_order,
          status = EXCLUDED.status, features = EXCLUDED.features, updated_at = CURRENT_TIMESTAMP;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.plans WHERE code IN ('free', 'creator', 'pro_family');
        """);
}
