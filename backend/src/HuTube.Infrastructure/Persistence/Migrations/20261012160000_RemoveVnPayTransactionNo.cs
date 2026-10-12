using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261012160000_RemoveVnPayTransactionNo")]
public sealed class RemoveVnPayTransactionNo : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_payments_vnpay_transaction_no;
        ALTER TABLE public.payments DROP COLUMN IF EXISTS vnpay_transaction_no;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.payments
            ADD COLUMN IF NOT EXISTS vnpay_transaction_no character varying(15) NULL;

        CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_vnpay_transaction_no
            ON public.payments(vnpay_transaction_no)
            WHERE vnpay_transaction_no IS NOT NULL;
        """);
}
