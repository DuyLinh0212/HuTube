using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925130000_AdminVideoState")]
public sealed class AdminVideoState : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS admin_original_status VARCHAR(20),
          ADD COLUMN IF NOT EXISTS admin_original_visibility VARCHAR(20),
          ADD COLUMN IF NOT EXISTS admin_original_moderation_status VARCHAR(30);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          DROP COLUMN IF EXISTS admin_original_status,
          DROP COLUMN IF EXISTS admin_original_visibility,
          DROP COLUMN IF EXISTS admin_original_moderation_status;
        """);
}
