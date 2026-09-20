using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260920230000_UpdatePaymentsForSepay")]
public sealed class UpdatePaymentsForSepay : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- Thêm cột sepay_transaction_id và expires_at nếu chưa tồn tại
        ALTER TABLE public.payments
            ADD COLUMN IF NOT EXISTS sepay_transaction_id BIGINT NULL,
            ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 minutes');

        -- Cập nhật constraint ck_payments_method để cho phép 'sepay'
        ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS ck_payments_method;
        ALTER TABLE public.payments ADD CONSTRAINT ck_payments_method CHECK (
            payment_method IN ('cash', 'bank_transfer', 'card', 'momo', 'vnpay', 'paypal', 'sepay')
        );

        -- Index chống trùng lặp giao dịch SePay
        CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_sepay_id
            ON public.payments(sepay_transaction_id)
            WHERE sepay_transaction_id IS NOT NULL;
    """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_payments_sepay_id;

        ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS ck_payments_method;
        ALTER TABLE public.payments ADD CONSTRAINT ck_payments_method CHECK (
            payment_method IN ('cash', 'bank_transfer', 'card', 'momo', 'vnpay', 'paypal')
        );

        ALTER TABLE public.payments
            DROP COLUMN IF EXISTS sepay_transaction_id,
            DROP COLUMN IF EXISTS expires_at;
    """);
}
