using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260913120000_PlanEntitlementsSchema")]
public sealed class PlanEntitlementsSchema : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plans
          ADD COLUMN IF NOT EXISTS max_video_quality VARCHAR(20) NOT NULL DEFAULT '720p',
          ADD COLUMN IF NOT EXISTS max_members INT NOT NULL DEFAULT 1,
          ADD COLUMN IF NOT EXISTS features JSONB NOT NULL DEFAULT '{}'::jsonb,
          ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plans
          DROP COLUMN IF EXISTS max_video_quality,
          DROP COLUMN IF EXISTS max_members,
          DROP COLUMN IF EXISTS features;
        """);
}
