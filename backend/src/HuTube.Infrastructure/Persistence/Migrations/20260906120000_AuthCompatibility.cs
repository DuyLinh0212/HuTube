using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Infrastructure;
using HuTube.Infrastructure.Persistence;

namespace HuTube.Infrastructure.Persistence.Migrations;

/// <summary>Maps the application auth projection onto the supplied 42-table schema.</summary>
[DbContext(typeof(HuTubeDbContext))]
[Migration("20260906120000_AuthCompatibility")]
public partial class AuthCompatibility : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            ALTER TABLE public.users
              ADD COLUMN IF NOT EXISTS display_name VARCHAR(120) NOT NULL DEFAULT '',
              ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS email_verification_token_hash VARCHAR(128) NULL,
              ADD COLUMN IF NOT EXISTS email_verification_created_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS email_verification_expires_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS email_verification_used_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS password_reset_token_hash VARCHAR(128) NULL,
              ADD COLUMN IF NOT EXISTS password_reset_created_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ NULL,
              ADD COLUMN IF NOT EXISTS password_reset_used_at TIMESTAMPTZ NULL;

            ALTER TABLE public.refresh_tokens
              ADD COLUMN IF NOT EXISTS device_name VARCHAR(200) NOT NULL DEFAULT 'Unknown device',
              ADD COLUMN IF NOT EXISTS platform VARCHAR(20) NOT NULL DEFAULT 'web',
              ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

            INSERT INTO public.roles (role_id, code, name, description, is_default, status)
            VALUES
              ('00000000-0000-0000-0000-000000000001', 'user', 'User', 'Standard HuTube user', TRUE, 'active'),
              ('00000000-0000-0000-0000-000000000002', 'admin', 'Administrator', 'HuTube administrator', FALSE, 'active')
            ON CONFLICT (role_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name;
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder) =>
        throw new NotSupportedException("AuthCompatibility is intentionally forward-only.");
}
