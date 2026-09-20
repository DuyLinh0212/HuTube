using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260920223000_AssignFreePlanToExistingUsers")]
public sealed class AssignFreePlanToExistingUsers : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Gán plan_id cho những user chưa có gói
        UPDATE public.users
        SET plan_id = p.plan_id,
            updated_at = CURRENT_TIMESTAMP
        FROM (
            SELECT plan_id FROM public.plans WHERE code = 'free' AND status = 'active' LIMIT 1
        ) AS p
        WHERE users.plan_id IS NULL;

        -- Tạo bản ghi plan_histories active cho những user chưa có lịch sử gói
        INSERT INTO public.plan_histories (plan_history_id, user_id, plan_id, owner_user_id, status, started_at, ended_at, auto_renew, created_at)
        SELECT
            gen_random_uuid(),
            u.user_id,
            p.plan_id,
            u.user_id,
            'active',
            u.created_at,
            u.created_at + INTERVAL '3650 days',
            false,
            u.created_at
        FROM public.users u
        JOIN public.plans p ON p.code = 'free' AND p.status = 'active'
        WHERE NOT EXISTS (
            SELECT 1 FROM public.plan_histories ph
            WHERE ph.user_id = u.user_id AND ph.status = 'active'
        );
    """);

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Safe no-op on rollback to prevent breaking users who actively use the assigned free plan.
    }
}
