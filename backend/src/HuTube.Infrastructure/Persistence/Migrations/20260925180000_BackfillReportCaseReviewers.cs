using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925180000_BackfillReportCaseReviewers")]
public sealed class BackfillReportCaseReviewers : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.moderation_cases AS grouped_case
        SET reviewer_id = legacy.reviewer_id
        FROM (
            SELECT r.moderation_case_id,
                   (array_agg(old_case.reviewer_id ORDER BY old_case.resolved_at DESC NULLS LAST,
                              old_case.updated_at DESC NULLS LAST,
                              old_case.claimed_at DESC NULLS LAST)
                    FILTER (WHERE old_case.reviewer_id IS NOT NULL))[1] AS reviewer_id
            FROM public.reports AS r
            JOIN public.moderation_cases AS old_case ON old_case.report_id = r.report_id
            WHERE r.moderation_case_id IS NOT NULL
              AND old_case.reviewer_id IS NOT NULL
            GROUP BY r.moderation_case_id
        ) AS legacy
        WHERE grouped_case.moderation_case_id = legacy.moderation_case_id
          AND grouped_case.case_type = 'report_case'
          AND grouped_case.status IN ('resolved', 'escalated')
          AND grouped_case.reviewer_id IS NULL;
        """);

    // The backfill only restores missing values and cannot distinguish them from
    // values that may be edited after the migration, so rollback is intentionally
    // a no-op to avoid deleting valid reviewer assignments.
    protected override void Down(MigrationBuilder migrationBuilder) { }
}
