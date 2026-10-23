using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

// Revisions are changed by PostgreSQL in the SAME transaction as the data.
// This also covers bulk updates, background workers and rolled-back transactions.
[DbContext(typeof(HuTubeDbContext))]
[Migration("20261024080000_ReadCacheRevisions")]
public sealed class ReadCacheRevisions : Migration
{
    private static readonly (string Table, string Scope)[] Shared = [
        ("categories", "catalog"), ("tags", "catalog"), ("video_tags", "content"),
        ("violation_types", "catalog"), ("policies", "catalog"),
        ("roles", "catalog"), ("permissions", "catalog"), ("role_permissions", "catalog"),
        ("videos", "content"), ("video_renditions", "content"),
        ("channels", "channels"), ("channel_members", "channels"),
        ("channel_invitations", "channels"), ("channel_quotas", "channels"),
        ("subscriptions", "channels"), ("users", "accounts"),
        ("playlists", "playlists"), ("playlist_videos", "playlists"),
        ("comments", "comments"), ("comment_reactions", "comments"),
        ("comment_moderation_actions", "comments"),
        ("plans", "plans"), ("plan_histories", "plans"), ("plan_members", "plans"),
        ("payments", "plans"), ("reports", "moderation"),
        ("appeals", "moderation"), ("channel_strikes", "moderation"),
        ("moderation_cases", "moderation"), ("strike_policy_settings", "moderation"),
        ("recommendation_jobs", "jobs")
    ];
    private static readonly (string Table, string Scope)[] Private = [
        ("users", "account"), ("notification_settings", "account"),
        ("viewing_histories", "library"), ("video_reactions", "library"),
        ("video_ratings", "library"), ("video_downloads", "library"),
        ("subscriptions", "library"), ("notifications", "notifications")
    ];

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            CREATE TABLE public.read_cache_revisions (
                scope text PRIMARY KEY,
                revision uuid NOT NULL DEFAULT gen_random_uuid()
            );
            INSERT INTO public.read_cache_revisions(scope) VALUES ('shared');
            CREATE FUNCTION public.collect_read_cache_revision() RETURNS trigger LANGUAGE plpgsql AS $$
            DECLARE cache_scope text; row_data jsonb; prior_user text; pending jsonb;
            BEGIN
                pending := COALESCE(NULLIF(current_setting('dalitu.read_cache_scopes', true), ''), '{}')::jsonb;
                cache_scope := TG_ARGV[0];
                IF TG_NARGS > 1 THEN
                    IF TG_OP = 'DELETE' THEN row_data := to_jsonb(OLD);
                    ELSE row_data := to_jsonb(NEW); END IF;
                    cache_scope := cache_scope || ':' || (row_data ->> 'user_id');
                    -- A reassigned owner must invalidate BOTH private partitions.
                    IF TG_OP = 'UPDATE' THEN
                        prior_user := to_jsonb(OLD) ->> 'user_id';
                        IF prior_user IS DISTINCT FROM (row_data ->> 'user_id') AND prior_user IS NOT NULL THEN
                            pending := pending || jsonb_build_object(TG_ARGV[0] || ':' || prior_user, true);
                        END IF;
                    END IF;
                END IF;
                IF cache_scope IS NOT NULL THEN
                    pending := pending || jsonb_build_object(cache_scope, true);
                END IF;
                PERFORM set_config('dalitu.read_cache_scopes', pending::text, true);
                RETURN NULL;
            END;
            $$;
            CREATE FUNCTION public.flush_read_cache_revisions() RETURNS trigger LANGUAGE plpgsql AS $$
            DECLARE pending jsonb; cache_scope text;
            BEGIN
                pending := COALESCE(NULLIF(current_setting('dalitu.read_cache_scopes', true), ''), '{}')::jsonb;
                PERFORM set_config('dalitu.read_cache_scopes', '{}', true);
                -- Every transaction takes revision locks in the SAME order, only
                -- after its business statements. Bulk read-all and concurrent
                -- single-item updates cannot invert business/cache row locks.
                FOR cache_scope IN SELECT jsonb_object_keys(pending) ORDER BY 1 LOOP
                    INSERT INTO public.read_cache_revisions(scope, revision)
                    VALUES (cache_scope, gen_random_uuid())
                    ON CONFLICT (scope) DO UPDATE SET revision = EXCLUDED.revision;
                END LOOP;
                RETURN NULL;
            END;
            $$;
            """);
        // Collect first; rotate each domain once at COMMIT in a consistent lock
        // order, without holding revision-row locks during an upload.
        // High-frequency history/reactions only rotate the affected user's key.
        foreach (var (table, scope) in Shared)
            migrationBuilder.Sql($"CREATE TRIGGER read_cache_shared AFTER INSERT OR UPDATE OR DELETE ON public.{table} FOR EACH ROW EXECUTE FUNCTION public.collect_read_cache_revision('{scope}');");
        foreach (var (table, scope) in Private)
            migrationBuilder.Sql($"CREATE TRIGGER read_cache_private AFTER INSERT OR UPDATE OR DELETE ON public.{table} FOR EACH ROW EXECUTE FUNCTION public.collect_read_cache_revision('{scope}', 'user');");
        foreach (var table in Shared.Select(x => x.Table).Concat(Private.Select(x => x.Table)).Distinct())
            migrationBuilder.Sql($"CREATE CONSTRAINT TRIGGER read_cache_flush AFTER INSERT OR UPDATE OR DELETE ON public.{table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.flush_read_cache_revisions();");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        foreach (var table in Shared.Select(x => x.Table).Concat(Private.Select(x => x.Table)).Distinct())
            migrationBuilder.Sql($"DROP TRIGGER IF EXISTS read_cache_flush ON public.{table};");
        foreach (var (table, _) in Private)
            migrationBuilder.Sql($"DROP TRIGGER IF EXISTS read_cache_private ON public.{table};");
        foreach (var (table, _) in Shared)
            migrationBuilder.Sql($"DROP TRIGGER IF EXISTS read_cache_shared ON public.{table};");
        migrationBuilder.Sql("DROP FUNCTION public.collect_read_cache_revision(); DROP FUNCTION public.flush_read_cache_revisions(); DROP TABLE public.read_cache_revisions;");
    }
}
