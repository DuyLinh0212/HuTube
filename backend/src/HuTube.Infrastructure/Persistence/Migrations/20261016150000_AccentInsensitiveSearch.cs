using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261016150000_AccentInsensitiveSearch")]
public sealed class AccentInsensitiveSearch : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) =>
        migrationBuilder.Sql("CREATE EXTENSION IF NOT EXISTS unaccent;");

    // Other searches may share this extension; rollback must preserve it.
    protected override void Down(MigrationBuilder migrationBuilder) { }
}
