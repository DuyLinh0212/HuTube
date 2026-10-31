using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261031150000_PasswordResetOtpAttempts")]
public sealed class PasswordResetOtpAttempts : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users
          ADD COLUMN password_reset_failed_attempts integer NOT NULL DEFAULT 0;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users
          DROP COLUMN password_reset_failed_attempts;
        """);
}
