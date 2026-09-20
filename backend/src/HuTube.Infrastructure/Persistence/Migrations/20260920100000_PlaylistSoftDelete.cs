using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260920100000_PlaylistSoftDelete")]
public sealed class PlaylistSoftDelete : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.playlists ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'active';
        ALTER TABLE public.playlists ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;
        CREATE INDEX IF NOT EXISTS ix_playlists_status ON public.playlists (status);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ix_playlists_status;
        ALTER TABLE public.playlists DROP COLUMN IF EXISTS deleted_at;
        ALTER TABLE public.playlists DROP COLUMN IF EXISTS status;
        """);
}
