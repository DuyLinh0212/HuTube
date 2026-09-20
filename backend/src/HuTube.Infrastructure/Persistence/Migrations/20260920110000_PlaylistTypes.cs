using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260920110000_PlaylistTypes")]
public sealed class PlaylistTypes : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.playlists DROP CONSTRAINT IF EXISTS ck_playlists_type;
        ALTER TABLE public.playlists ADD CONSTRAINT ck_playlists_type CHECK (playlist_type IN ('personal', 'channel', 'normal', 'watch_later'));
        UPDATE public.playlists SET playlist_type = 'channel' WHERE playlist_type = 'normal';
        UPDATE public.playlists SET playlist_type = 'personal' WHERE playlist_type = 'watch_later';
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.playlists DROP CONSTRAINT IF EXISTS ck_playlists_type;
        ALTER TABLE public.playlists ADD CONSTRAINT ck_playlists_type CHECK (playlist_type IN ('personal', 'channel', 'normal', 'watch_later'));
        """);
}
