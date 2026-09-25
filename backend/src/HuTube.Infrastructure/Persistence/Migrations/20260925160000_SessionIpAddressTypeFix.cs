using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925160000_SessionIpAddressTypeFix")]
public sealed class SessionIpAddressTypeFix : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.refresh_tokens
          ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);

        ALTER TABLE public.refresh_tokens
          ALTER COLUMN ip_address TYPE VARCHAR(45) USING ip_address::text;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.refresh_tokens
          ALTER COLUMN ip_address TYPE INET USING NULLIF(ip_address, '')::inet;
        """);
}
