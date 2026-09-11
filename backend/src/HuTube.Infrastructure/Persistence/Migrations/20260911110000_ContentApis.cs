using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260911110000_ContentApis")]
public sealed class ContentApis : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users
          ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(10) NOT NULL DEFAULT 'vi',
          ADD COLUMN IF NOT EXISTS theme VARCHAR(20) NOT NULL DEFAULT 'system',
          ADD COLUMN IF NOT EXISTS keep_subscriptions_private BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN IF NOT EXISTS keep_playlists_private BOOLEAN NOT NULL DEFAULT TRUE,
          ADD COLUMN IF NOT EXISTS location VARCHAR(120) DEFAULT 'Việt Nam';

        CREATE TABLE IF NOT EXISTS public.video_downloads (
          video_download_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
          video_id UUID NOT NULL REFERENCES public.videos(video_id) ON DELETE CASCADE,
          quality_label VARCHAR(20) NOT NULL,
          file_url VARCHAR(2048) NOT NULL,
          file_size BIGINT NOT NULL,
          status VARCHAR(20) NOT NULL DEFAULT 'ready',
          created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT uq_video_downloads_user_video_quality UNIQUE(user_id, video_id, quality_label),
          CONSTRAINT ck_video_downloads_status CHECK(status IN ('pending','processing','ready','failed','cancelled')),
          CONSTRAINT ck_video_downloads_size CHECK(file_size > 0)
        );
        CREATE INDEX IF NOT EXISTS ix_video_downloads_user_time ON public.video_downloads(user_id, created_at DESC);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS public.video_downloads;
        ALTER TABLE public.users
          DROP COLUMN IF EXISTS preferred_language,
          DROP COLUMN IF EXISTS theme,
          DROP COLUMN IF EXISTS keep_subscriptions_private,
          DROP COLUMN IF EXISTS keep_playlists_private,
          DROP COLUMN IF EXISTS location;
        """);
}
