using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260906130000_GoogleExternalLogin")]
public sealed class GoogleExternalLogin : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users ADD COLUMN IF NOT EXISTS google_subject VARCHAR(255) NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS ux_users_google_subject
          ON public.users (google_subject) WHERE google_subject IS NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) =>
        throw new NotSupportedException("GoogleExternalLogin is intentionally forward-only.");
}
