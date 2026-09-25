using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925140000_ChannelAndVideoModerationReasons")]
public sealed class ChannelAndVideoModerationReasons : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS status_reason TEXT;
        ALTER TABLE public.videos ADD COLUMN IF NOT EXISTS moderation_reason TEXT;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos DROP COLUMN IF EXISTS moderation_reason;
        ALTER TABLE public.channels DROP COLUMN IF EXISTS status_reason;
        """);
}
