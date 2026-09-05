using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

// The preceding Bootstrap migration creates these tables from the supplied SQL.
// This no-op establishes the EF snapshot for the application's auth projection.
public partial class AuthProjectionBaseline : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) { }
    protected override void Down(MigrationBuilder migrationBuilder) { }
}
