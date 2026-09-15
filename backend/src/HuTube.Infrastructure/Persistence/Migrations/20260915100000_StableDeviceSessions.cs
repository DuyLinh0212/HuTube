using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

/// <summary>Stores the stable client identifier used to reuse one session per device.</summary>
[DbContext(typeof(HuTubeDbContext))]
[Migration("20260915100000_StableDeviceSessions")]
public sealed class StableDeviceSessions : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.refresh_tokens
          ADD COLUMN IF NOT EXISTS device_id VARCHAR(128) NOT NULL DEFAULT '';

        CREATE INDEX IF NOT EXISTS ix_refresh_tokens_user_platform_device
          ON public.refresh_tokens (user_id, platform, device_id)
          WHERE revoked_at IS NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ix_refresh_tokens_user_platform_device;
        ALTER TABLE public.refresh_tokens DROP COLUMN IF EXISTS device_id;
        """);
}
