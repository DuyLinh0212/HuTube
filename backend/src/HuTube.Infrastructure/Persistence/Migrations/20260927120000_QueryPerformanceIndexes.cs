using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260927120000_QueryPerformanceIndexes")]
public sealed class QueryPerformanceIndexes : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE EXTENSION IF NOT EXISTS pg_trgm;

        -- Feeds, explore and history windows.
        CREATE INDEX IF NOT EXISTS ix_viewing_histories_video_time
            ON public.viewing_histories(video_id, viewed_at DESC);
        CREATE INDEX IF NOT EXISTS ix_viewing_histories_user_video_time
            ON public.viewing_histories(user_id, video_id, viewed_at DESC, viewing_history_id DESC);
        CREATE INDEX IF NOT EXISTS ix_videos_public_category_published
            ON public.videos(category_id, published_at DESC)
            WHERE status = 'published' AND moderation_status = 'approved' AND visibility = 'public';
        CREATE INDEX IF NOT EXISTS ix_videos_public_published
            ON public.videos(published_at DESC)
            WHERE status = 'published' AND moderation_status = 'approved' AND visibility = 'public';

        -- Aggregated interaction counts and batch comment enrichment.
        CREATE INDEX IF NOT EXISTS ix_video_reactions_video_type
            ON public.video_reactions(video_id, type);
        CREATE INDEX IF NOT EXISTS ix_video_ratings_video_score
            ON public.video_ratings(video_id, score);
        CREATE INDEX IF NOT EXISTS ix_share_histories_video_time
            ON public.share_histories(video_id, shared_at DESC);
        CREATE INDEX IF NOT EXISTS ix_comments_video_status_time
            ON public.comments(video_id, status, created_at DESC);
        CREATE INDEX IF NOT EXISTS ix_comments_parent_status_time
            ON public.comments(parent_comment_id, status, created_at);
        CREATE INDEX IF NOT EXISTS ix_comment_reactions_comment_type
            ON public.comment_reactions(comment_id, type);
        CREATE INDEX IF NOT EXISTS ix_video_tags_tag_video
            ON public.video_tags(tag_id, video_id);
        CREATE INDEX IF NOT EXISTS ix_subscriptions_channel_active
            ON public.subscriptions(channel_id, user_id)
            WHERE status = 'active';

        -- Moderation/admin queues and target lookups.
        CREATE INDEX IF NOT EXISTS ix_reports_video
            ON public.reports(video_id, created_at DESC)
            WHERE video_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS ix_moderation_cases_target_status
            ON public.moderation_cases(target_type, target_id, status);
        CREATE INDEX IF NOT EXISTS ix_moderation_cases_video_status
            ON public.moderation_cases(video_id, status, submitted_at DESC)
            WHERE video_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS ix_appeals_target_status_time
            ON public.appeals(target_type, target_id, status, created_at DESC);

        -- ILIKE search predicates.  These indexes keep title/channel/tag search
        -- index-backed once the query no longer applies LOWER() to every row.
        CREATE INDEX IF NOT EXISTS ix_videos_title_trgm
            ON public.videos USING gin (title gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_videos_description_trgm
            ON public.videos USING gin (description gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_channels_name_trgm
            ON public.channels USING gin (name gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_tags_name_trgm
            ON public.tags USING gin (name gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_users_username_trgm
            ON public.users USING gin (username gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_users_display_name_trgm
            ON public.users USING gin (display_name gin_trgm_ops);
        CREATE INDEX IF NOT EXISTS ix_users_email_trgm
            ON public.users USING gin (email gin_trgm_ops);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ix_tags_name_trgm;
        DROP INDEX IF EXISTS public.ix_channels_name_trgm;
        DROP INDEX IF EXISTS public.ix_users_email_trgm;
        DROP INDEX IF EXISTS public.ix_users_display_name_trgm;
        DROP INDEX IF EXISTS public.ix_users_username_trgm;
        DROP INDEX IF EXISTS public.ix_videos_description_trgm;
        DROP INDEX IF EXISTS public.ix_videos_title_trgm;
        DROP INDEX IF EXISTS public.ix_appeals_target_status_time;
        DROP INDEX IF EXISTS public.ix_moderation_cases_video_status;
        DROP INDEX IF EXISTS public.ix_moderation_cases_target_status;
        DROP INDEX IF EXISTS public.ix_reports_video;
        DROP INDEX IF EXISTS public.ix_subscriptions_channel_active;
        DROP INDEX IF EXISTS public.ix_video_tags_tag_video;
        DROP INDEX IF EXISTS public.ix_comment_reactions_comment_type;
        DROP INDEX IF EXISTS public.ix_comments_parent_status_time;
        DROP INDEX IF EXISTS public.ix_comments_video_status_time;
        DROP INDEX IF EXISTS public.ix_share_histories_video_time;
        DROP INDEX IF EXISTS public.ix_video_ratings_video_score;
        DROP INDEX IF EXISTS public.ix_video_reactions_video_type;
        DROP INDEX IF EXISTS public.ix_videos_public_published;
        DROP INDEX IF EXISTS public.ix_videos_public_category_published;
        DROP INDEX IF EXISTS public.ix_viewing_histories_user_video_time;
        DROP INDEX IF EXISTS public.ix_viewing_histories_video_time;
        """);
}
