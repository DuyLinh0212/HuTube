using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260914100000_PoliciesTable")]
public sealed class PoliciesTable : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";

        CREATE TABLE IF NOT EXISTS public.policies (
          policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          code VARCHAR(100) NOT NULL UNIQUE,
          name VARCHAR(200) NOT NULL,
          "group" VARCHAR(50) NOT NULL DEFAULT 'content',
          content TEXT NOT NULL DEFAULT '',
          severity VARCHAR(30) NOT NULL DEFAULT 'medium',
          version VARCHAR(20) NOT NULL DEFAULT '1.0',
          status VARCHAR(30) NOT NULL DEFAULT 'published',
          effective_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE UNIQUE INDEX IF NOT EXISTS ix_policies_code ON public.policies (code);
        CREATE INDEX IF NOT EXISTS ix_policies_group_status ON public.policies ("group", status);

        -- moderation_cases is part of the bootstrap schema, but these fields were
        -- added after bootstrap. Keep this safe for both fresh and existing DBs.
        DO $$
        BEGIN
          IF EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = 'moderation_cases'
          ) THEN
            ALTER TABLE public.moderation_cases
              ADD COLUMN IF NOT EXISTS policy_code VARCHAR(100),
              ADD COLUMN IF NOT EXISTS policy_version VARCHAR(20),
              ADD COLUMN IF NOT EXISTS decision VARCHAR(50),
              ADD COLUMN IF NOT EXISTS internal_note TEXT,
              ADD COLUMN IF NOT EXISTS risk_level VARCHAR(20) NOT NULL DEFAULT 'normal';
          END IF;
        END $$;
        """);

        migrationBuilder.Sql(PolicySeedSql.Sql);
    }

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS public.policies;
        """);
}
