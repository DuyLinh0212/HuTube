using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261019120000_SharedPlanStorageBillingOwner")]
public sealed class SharedPlanStorageBillingOwner : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.videos
          ADD COLUMN IF NOT EXISTS storage_billing_owner_user_id UUID NULL;

        UPDATE public.videos AS video
        SET storage_billing_owner_user_id = channel.owner_user_id
        FROM public.channels AS channel
        WHERE channel.channel_id = video.channel_id
          AND video.storage_billing_owner_user_id IS NULL;

        UPDATE public.videos AS video
        SET storage_billing_owner_user_id = member.owner_user_id
        FROM public.channels AS channel
        INNER JOIN public.plan_members AS member
          ON member.member_user_id = channel.owner_user_id
         AND member.status = 'accepted'
        INNER JOIN public.plan_histories AS history
          ON history.plan_history_id = member.plan_history_id
         AND history.status = 'active'
         AND (history.ended_at IS NULL OR history.ended_at > now())
        WHERE video.channel_id = channel.channel_id
          AND video.status <> 'deleted';

        UPDATE public.channel_quotas AS quota
        SET storage_used = COALESCE((
          SELECT SUM(video.file_size)
          FROM public.videos AS video
          WHERE video.channel_id = quota.channel_id
            AND video.status <> 'deleted'
            AND video.media_purged_at IS NULL
        ), 0);

        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'fk_videos_storage_billing_owner'
              AND conrelid = 'public.videos'::regclass
          ) THEN
            ALTER TABLE public.videos
              ADD CONSTRAINT fk_videos_storage_billing_owner
              FOREIGN KEY (storage_billing_owner_user_id)
              REFERENCES public.users(user_id)
              ON DELETE RESTRICT;
          END IF;
        END $$;

        CREATE INDEX IF NOT EXISTS ix_videos_storage_billing_owner
          ON public.videos(storage_billing_owner_user_id, status, media_purged_at);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ix_videos_storage_billing_owner;
        ALTER TABLE public.videos DROP CONSTRAINT IF EXISTS fk_videos_storage_billing_owner;
        ALTER TABLE public.videos DROP COLUMN IF EXISTS storage_billing_owner_user_id;
        """);
}
