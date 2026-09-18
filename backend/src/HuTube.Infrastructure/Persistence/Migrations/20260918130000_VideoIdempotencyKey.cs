using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260918130000_VideoIdempotencyKey")]
public sealed class VideoIdempotencyKey : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);

        CREATE UNIQUE INDEX IF NOT EXISTS ux_videos_channel_idempotency
          ON public.videos (channel_id, idempotency_key)
          WHERE idempotency_key IS NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Compatibility migration: keep the column and idempotency data during
        // rollback because older installations may already have used this field.
    }
}
