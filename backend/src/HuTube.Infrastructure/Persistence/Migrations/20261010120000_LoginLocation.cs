using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using HuTube.Infrastructure.Persistence;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261010120000_LoginLocation")]
public sealed class LoginLocation : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.login_history
          ADD COLUMN IF NOT EXISTS country_code character varying(8),
          ADD COLUMN IF NOT EXISTS region character varying(120),
          ADD COLUMN IF NOT EXISTS city character varying(120),
          ADD COLUMN IF NOT EXISTS latitude double precision,
          ADD COLUMN IF NOT EXISTS longitude double precision;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.login_history
          DROP COLUMN IF EXISTS longitude,
          DROP COLUMN IF EXISTS latitude,
          DROP COLUMN IF EXISTS city,
          DROP COLUMN IF EXISTS region,
          DROP COLUMN IF EXISTS country_code;
        """);
}
