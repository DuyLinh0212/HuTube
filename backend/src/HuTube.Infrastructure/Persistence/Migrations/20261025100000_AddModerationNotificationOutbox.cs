using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261025100000_AddModerationNotificationOutbox")]
public sealed class AddModerationNotificationOutbox : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE public.moderation_outbox_events (
            event_id uuid PRIMARY KEY, event_type text NOT NULL, payload jsonb NOT NULL,
            occurred_at timestamptz NOT NULL, available_at timestamptz NOT NULL,
            published_at timestamptz, attempts integer NOT NULL DEFAULT 0, last_error text);
        CREATE INDEX ix_moderation_outbox_events_available_at ON public.moderation_outbox_events (available_at) WHERE published_at IS NULL;
        CREATE TABLE public.notification_inbox_events (
            event_id uuid PRIMARY KEY, owner_processed boolean NOT NULL DEFAULT false,
            last_subscription_id uuid, completed_at timestamptz);
        CREATE TABLE public.notification_deliveries (
            delivery_id uuid PRIMARY KEY, event_id uuid NOT NULL, user_id uuid NOT NULL,
            notification_id uuid, type text NOT NULL, payload jsonb NOT NULL,
            realtime_done boolean NOT NULL DEFAULT false, email_done boolean NOT NULL DEFAULT false,
            push_done boolean NOT NULL DEFAULT false, attempts integer NOT NULL DEFAULT 0,
            available_at timestamptz NOT NULL, completed_at timestamptz, last_error text);
        CREATE UNIQUE INDEX ix_notification_deliveries_event_id_user_id_type ON public.notification_deliveries (event_id, user_id, type);
        CREATE INDEX ix_notification_deliveries_available_at ON public.notification_deliveries (available_at) WHERE completed_at IS NULL;
        CREATE TABLE public.push_devices (
            push_device_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
            session_id uuid NOT NULL REFERENCES public.refresh_tokens(refresh_token_id) ON DELETE CASCADE,
            token text NOT NULL, token_hash varchar(64) NOT NULL, platform text NOT NULL,
            updated_at timestamptz NOT NULL);
        CREATE UNIQUE INDEX ix_push_devices_token_hash ON public.push_devices (token_hash);
        CREATE INDEX ix_push_devices_user_id ON public.push_devices (user_id);
        CREATE INDEX ix_push_devices_session_id ON public.push_devices (session_id);
        CREATE INDEX ix_subscriptions_notification_fanout ON public.subscriptions (channel_id, subscription_id)
            WHERE status = 'active' AND notifications_enabled;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DO $$ BEGIN
            IF EXISTS (SELECT 1 FROM public.moderation_outbox_events WHERE published_at IS NULL)
                OR EXISTS (SELECT 1 FROM public.notification_inbox_events WHERE completed_at IS NULL)
                OR EXISTS (SELECT 1 FROM public.notification_deliveries WHERE completed_at IS NULL) THEN
                RAISE EXCEPTION 'Drain moderation messages and notification deliveries before rollback.';
            END IF;
        END $$;
        DROP INDEX IF EXISTS public.ix_subscriptions_notification_fanout;
        DROP TABLE public.push_devices;
        DROP TABLE public.notification_deliveries;
        DROP TABLE public.notification_inbox_events;
        DROP TABLE public.moderation_outbox_events;
        """);
}
