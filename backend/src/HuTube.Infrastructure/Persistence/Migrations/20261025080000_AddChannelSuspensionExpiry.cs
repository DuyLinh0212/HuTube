using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261025080000_AddChannelSuspensionExpiry")]
public sealed class AddChannelSuspensionExpiry : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(
            name: "suspended_until", schema: "public", table: "channels",
            type: "timestamp with time zone", nullable: true);
        migrationBuilder.CreateIndex(
            name: "ix_channels_suspended_until", schema: "public", table: "channels",
            column: "suspended_until", filter: "status = 'suspended'");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(name: "ix_channels_suspended_until", schema: "public", table: "channels");
        migrationBuilder.DropColumn(name: "suspended_until", schema: "public", table: "channels");
    }
}
