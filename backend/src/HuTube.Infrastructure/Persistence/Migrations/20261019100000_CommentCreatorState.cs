using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261019100000_CommentCreatorState")]
public sealed class CommentCreatorState : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false;
        ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS has_creator_heart boolean NOT NULL DEFAULT false;
        CREATE UNIQUE INDEX IF NOT EXISTS ux_comments_pinned_video ON public.comments(video_id)
          WHERE is_pinned AND status = 'visible' AND parent_comment_id IS NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_comments_pinned_video;
        ALTER TABLE public.comments DROP COLUMN IF EXISTS is_pinned;
        ALTER TABLE public.comments DROP COLUMN IF EXISTS has_creator_heart;
        """);
}
