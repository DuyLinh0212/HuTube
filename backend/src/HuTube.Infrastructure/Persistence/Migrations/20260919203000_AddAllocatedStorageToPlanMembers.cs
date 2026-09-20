using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260919203000_AddAllocatedStorageToPlanMembers")]
public sealed class AddAllocatedStorageToPlanMembers : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plan_histories ADD COLUMN IF NOT EXISTS owner_allocated_storage BIGINT NULL;
        ALTER TABLE public.plan_members ADD COLUMN IF NOT EXISTS allocated_storage BIGINT NULL;
    """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.plan_members DROP COLUMN IF EXISTS allocated_storage;
        ALTER TABLE public.plan_histories DROP COLUMN IF EXISTS owner_allocated_storage;
    """);
}
