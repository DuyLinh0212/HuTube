using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261003170000_StrikePolicySettings")]
public sealed class StrikePolicySettings : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE public.strike_policy_settings (
            id integer NOT NULL PRIMARY KEY,
            rejected_videos_per_strike integer NOT NULL,
            first_strike_restriction_days integer NOT NULL,
            second_strike_restriction_days integer NOT NULL,
            strike_expiration_days integer NOT NULL,
            suspension_strike_count integer NOT NULL,
            rejected_videos_effective_at timestamp with time zone NOT NULL,
            updated_at timestamp with time zone NOT NULL
        );

        INSERT INTO public.strike_policy_settings (
            id, rejected_videos_per_strike, first_strike_restriction_days,
            second_strike_restriction_days, strike_expiration_days,
            suspension_strike_count, rejected_videos_effective_at, updated_at
        ) VALUES (1, 5, 7, 14, 90, 3, now(), now())
        ON CONFLICT (id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS public.strike_policy_settings;
        """);
}
