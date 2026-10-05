using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using HuTube.Infrastructure.Persistence;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261005100000_PlaylistCover")]
public sealed class PlaylistCover : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.playlists ADD COLUMN IF NOT EXISTS cover_url TEXT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.playlists DROP COLUMN IF EXISTS cover_url;
        """);
}
