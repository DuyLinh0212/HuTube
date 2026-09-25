using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925150000_VideoMediaRetention")]
public sealed class VideoMediaRetention : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS media_retention_until TIMESTAMPTZ,
          ADD COLUMN IF NOT EXISTS media_purged_at TIMESTAMPTZ;
        UPDATE public.videos
        SET media_retention_until = updated_at + INTERVAL '30 days'
        WHERE media_retention_until IS NULL AND media_purged_at IS NULL
          AND moderation_status = 'rejected';
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          DROP COLUMN IF EXISTS media_purged_at,
          DROP COLUMN IF EXISTS media_retention_until;
        """);
}
