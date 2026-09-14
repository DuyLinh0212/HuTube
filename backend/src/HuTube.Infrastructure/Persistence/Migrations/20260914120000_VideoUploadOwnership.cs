using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260914120000_VideoUploadOwnership")]
public sealed class VideoUploadOwnership : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Older local databases may already contain this column. Keep the
        -- migration safe for both those databases and fresh installations.
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS uploaded_by_user_id UUID;

        UPDATE public.videos AS v
        SET uploaded_by_user_id = c.owner_user_id
        FROM public.channels AS c
        WHERE c.channel_id = v.channel_id
          AND v.uploaded_by_user_id IS NULL;

        ALTER TABLE public.videos
          ALTER COLUMN uploaded_by_user_id SET NOT NULL;

        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'fk_videos_uploaded_by_user'
              AND conrelid = 'public.videos'::regclass
          ) THEN
            ALTER TABLE public.videos
              ADD CONSTRAINT fk_videos_uploaded_by_user
              FOREIGN KEY (uploaded_by_user_id)
              REFERENCES public.users(user_id)
              ON DELETE RESTRICT;
          END IF;
        END $$;
        """);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // This is a compatibility migration. The column may have existed in
        // a local database before this migration was added, so do not remove
        // user ownership data during rollback.
    }
}
