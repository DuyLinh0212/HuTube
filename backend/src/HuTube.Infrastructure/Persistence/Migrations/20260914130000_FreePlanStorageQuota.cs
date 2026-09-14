using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260914130000_FreePlanStorageQuota")]
public sealed class FreePlanStorageQuota : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Keep the Free plan at 1 GiB on both fresh and existing local databases.
        UPDATE public.plans
        SET storage_limit = 1073741824,
            updated_at = CURRENT_TIMESTAMP
        WHERE code = 'free'
          AND storage_limit <> 1073741824;

        -- Reconcile existing Free/default channel quotas without reducing a
        -- quota below bytes already stored on that channel.
        UPDATE public.channel_quotas AS q
        SET storage_limit = GREATEST(q.storage_used, 1073741824),
            updated_at = CURRENT_TIMESTAMP
        FROM public.channels AS c
        JOIN public.users AS u ON u.user_id = c.owner_user_id
        LEFT JOIN public.plans AS p ON p.plan_id = u.plan_id
        WHERE q.channel_id = c.channel_id
          AND (p.code = 'free' OR p.plan_id IS NULL)
          AND q.storage_limit <> GREATEST(q.storage_used, 1073741824);
        """);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // This normalization cannot safely restore arbitrary previous quota
        // values, so rollback intentionally leaves the corrected limits intact.
    }
}
