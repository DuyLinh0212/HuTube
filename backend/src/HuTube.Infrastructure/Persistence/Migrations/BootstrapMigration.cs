using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("202609050001_Bootstrap")]
public sealed class BootstrapMigration : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        using var stream = typeof(BootstrapMigration).Assembly.GetManifestResourceStream("HuTube.Infrastructure.Persistence.Migrations.Bootstrap.sql")!;
        using var reader = new StreamReader(stream);
        migrationBuilder.Sql(reader.ReadToEnd());
    }
    protected override void Down(MigrationBuilder migrationBuilder) =>
        throw new NotSupportedException("Bootstrap contains the supplied HuTube schema. Restore a database backup rather than dropping shared business data.");
}
