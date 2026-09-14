using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260914110000_PolicySeed")]
public sealed class PolicySeed : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(PolicySeedSql.Sql);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Policy rows may have been edited or referenced by moderation cases;
        // keep them on rollback rather than deleting business data.
    }
}
