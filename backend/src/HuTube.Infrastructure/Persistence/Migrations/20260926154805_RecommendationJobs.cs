using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260926154805_RecommendationJobs")]
public sealed class RecommendationJobs : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Earlier migrations use targeted SQL against the live public schema. The
        // scaffolded diff included legacy schema renames; only this table is new.
        migrationBuilder.CreateTable(
            name: "recommendation_jobs", schema: "public",
            columns: table => new {
                job_id = table.Column<Guid>(type: "uuid", nullable: false),
                actor_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                kind = table.Column<string>(type: "text", nullable: false),
                status = table.Column<string>(type: "text", nullable: false),
                step = table.Column<string>(type: "text", nullable: false),
                payload_json = table.Column<string>(type: "jsonb", nullable: false),
                logs_json = table.Column<string>(type: "jsonb", nullable: false),
                error = table.Column<string>(type: "text", nullable: true),
                completed = table.Column<int>(type: "integer", nullable: false),
                total = table.Column<int>(type: "integer", nullable: false),
                created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table => table.PrimaryKey("PK_recommendation_jobs", x => x.job_id));
        migrationBuilder.CreateIndex(name: "IX_recommendation_jobs_status_created_at",
            schema: "public", table: "recommendation_jobs", columns: new[] { "status", "created_at" });
        migrationBuilder.Sql("""
            CREATE UNIQUE INDEX ux_recommendation_model_job_active
            ON public.recommendation_jobs (kind)
            WHERE kind = 'model_update' AND status IN ('queued', 'running');
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder) =>
        migrationBuilder.DropTable(name: "recommendation_jobs", schema: "public");
}
