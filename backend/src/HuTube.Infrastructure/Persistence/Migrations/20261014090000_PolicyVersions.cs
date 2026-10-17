using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261014090000_PolicyVersions")]
public sealed class PolicyVersions : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            ALTER TABLE public.policies DROP CONSTRAINT IF EXISTS policies_code_key;
            DROP INDEX IF EXISTS public.ix_policies_code;
            CREATE UNIQUE INDEX ix_policies_code_version ON public.policies (code, version);
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            DO $$ BEGIN
              IF EXISTS (SELECT code FROM public.policies GROUP BY code HAVING count(*) > 1) THEN
                RAISE EXCEPTION 'Cannot roll back policy versions while published history exists';
              END IF;
            END $$;
            DROP INDEX IF EXISTS public.ix_policies_code_version;
            CREATE UNIQUE INDEX ix_policies_code ON public.policies (code);
            """);
    }
}
