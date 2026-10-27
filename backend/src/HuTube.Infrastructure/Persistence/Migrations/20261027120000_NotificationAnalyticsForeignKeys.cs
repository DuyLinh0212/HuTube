using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261027120000_NotificationAnalyticsForeignKeys")]
public sealed class NotificationAnalyticsForeignKeys : Migration
{
    // The currently deployed application can insert a notification and its delivery
    // in either order in the same transaction. Check references at commit time.
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.notification_deliveries
            ADD CONSTRAINT fk_notification_deliveries_users FOREIGN KEY (user_id)
                REFERENCES public.users (user_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
            ADD CONSTRAINT fk_notification_deliveries_notifications FOREIGN KEY (notification_id)
                REFERENCES public.notifications (notification_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
        ALTER TABLE public.channel_analytics_events
            ADD CONSTRAINT fk_channel_analytics_events_channels FOREIGN KEY (channel_id)
                REFERENCES public.channels (channel_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
            ADD CONSTRAINT fk_channel_analytics_events_videos FOREIGN KEY (video_id)
                REFERENCES public.videos (video_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.notification_deliveries DROP CONSTRAINT fk_notification_deliveries_users,
            DROP CONSTRAINT fk_notification_deliveries_notifications;
        ALTER TABLE public.channel_analytics_events DROP CONSTRAINT fk_channel_analytics_events_channels,
            DROP CONSTRAINT fk_channel_analytics_events_videos;
        """);
}
