using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HuTube.Infrastructure.Persistence.Migrations
{
    public partial class RemovePlaylistType : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "playlist_type",
                schema: "public",
                table: "playlists");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "playlist_type",
                schema: "public",
                table: "playlists",
                type: "text",
                nullable: false,
                defaultValue: "personal");
        }
    }
}
