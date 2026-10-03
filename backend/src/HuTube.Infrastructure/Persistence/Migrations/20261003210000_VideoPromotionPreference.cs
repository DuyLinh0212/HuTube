using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261003210000_VideoPromotionPreference")]
public sealed class VideoPromotionPreference : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS promotion_enabled BOOLEAN NOT NULL DEFAULT FALSE;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          DROP COLUMN IF EXISTS promotion_enabled;
        """);
}
