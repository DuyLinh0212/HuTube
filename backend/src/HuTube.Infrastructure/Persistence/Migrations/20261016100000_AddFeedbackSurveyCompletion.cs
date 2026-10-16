using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261016100000_AddFeedbackSurveyCompletion")]
public sealed class AddFeedbackSurveyCompletion : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users ADD COLUMN IF NOT EXISTS feedback_survey_completed_at timestamp with time zone NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.users DROP COLUMN IF EXISTS feedback_survey_completed_at;
        """);
}
