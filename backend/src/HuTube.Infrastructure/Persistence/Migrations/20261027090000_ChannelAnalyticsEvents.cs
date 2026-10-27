using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261027090000_ChannelAnalyticsEvents")]
public sealed class ChannelAnalyticsEvents : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE public.channel_analytics_events (
            event_id uuid PRIMARY KEY,
            channel_id uuid NOT NULL,
            video_id uuid NULL,
            occurred_at timestamptz NOT NULL,
            metric varchar(24) NOT NULL,
            value bigint NOT NULL
        );
        CREATE INDEX ix_channel_analytics_channel_time ON public.channel_analytics_events (channel_id, occurred_at);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) =>
        migrationBuilder.Sql("DROP TABLE public.channel_analytics_events;");
}
