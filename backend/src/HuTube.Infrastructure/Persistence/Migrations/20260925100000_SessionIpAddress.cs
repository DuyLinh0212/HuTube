using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925100000_SessionIpAddress")]
public sealed class SessionIpAddress : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(
        "ALTER TABLE public.refresh_tokens ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);");

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(
        "ALTER TABLE public.refresh_tokens DROP COLUMN IF EXISTS ip_address;");
}
