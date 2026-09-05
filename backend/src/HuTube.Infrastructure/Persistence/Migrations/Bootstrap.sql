/*=============================================================================
  HuTube - PostgreSQL lean schema
  Based on the original HuTube SQL Server schema + updated class design.
  Total base tables: exactly 42.

  Original tables preserved: 35
  Updated class-design tables: 2
    - channel_comment_moderators
    - comment_moderation_actions
  Additional business tables: 5
    - channel_members
    - channel_invitations
    - video_ratings
    - moderation_cases
    - audit_logs
=============================================================================*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
SET TIME ZONE 'UTC';

CREATE TABLE IF NOT EXISTS roles (

        role_id       UUID NOT NULL DEFAULT gen_random_uuid(),
        code          VARCHAR(50) NOT NULL,
        name          VARCHAR(100) NOT NULL,
        description   TEXT NULL,
        is_default    BOOLEAN NOT NULL DEFAULT FALSE,
        status        VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_roles PRIMARY KEY (role_id),
        CONSTRAINT ck_roles_code CHECK (char_length(btrim(code)) > 0),
        CONSTRAINT ck_roles_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_roles_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS permissions (

        permission_id UUID NOT NULL DEFAULT gen_random_uuid(),
        code          VARCHAR(100) NOT NULL,
        name          VARCHAR(150) NOT NULL,
        description   TEXT NULL,
        status        VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_permissions PRIMARY KEY (permission_id),
        CONSTRAINT ck_permissions_code CHECK (char_length(btrim(code)) > 0),
        CONSTRAINT ck_permissions_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_permissions_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS plans (

        plan_id             UUID NOT NULL DEFAULT gen_random_uuid(),
        code                VARCHAR(50) NOT NULL,
        name                VARCHAR(100) NOT NULL,
        description         TEXT NULL,
        price               NUMERIC(15,2) NOT NULL DEFAULT 0,
        duration_days       INT NOT NULL,
        storage_limit       BIGINT NOT NULL,
        max_upload_size     BIGINT NOT NULL,
        max_video_duration  INT NOT NULL,
        status              VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_plans PRIMARY KEY (plan_id),
        CONSTRAINT ck_plans_code CHECK (char_length(btrim(code)) > 0),
        CONSTRAINT ck_plans_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_plans_price CHECK (price >= 0),
        CONSTRAINT ck_plans_duration CHECK (duration_days > 0),
        CONSTRAINT ck_plans_storage CHECK (storage_limit >= 0),
        CONSTRAINT ck_plans_upload CHECK (max_upload_size > 0),
        CONSTRAINT ck_plans_video_duration CHECK (max_video_duration > 0),
        CONSTRAINT ck_plans_status CHECK (status IN ('active', 'inactive', 'archived'))
);

CREATE TABLE IF NOT EXISTS users (

        user_id                UUID NOT NULL DEFAULT gen_random_uuid(),
        username               VARCHAR(50) NOT NULL,
        email                  VARCHAR(254) NOT NULL,
        password_hash          VARCHAR(255) NOT NULL,
        avatar_url             VARCHAR(2048) NULL,
        status                 VARCHAR(20) NOT NULL DEFAULT 'pending',
        email_verified_at      TIMESTAMPTZ NULL,
        last_login_at          TIMESTAMPTZ NULL,
        failed_login_attempts  INT NOT NULL DEFAULT 0,
        locked_until           TIMESTAMPTZ NULL,
        role_id                UUID NOT NULL,
        plan_id                UUID NULL,
        created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_users PRIMARY KEY (user_id),
        CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(role_id),
        CONSTRAINT fk_users_plan FOREIGN KEY (plan_id) REFERENCES plans(plan_id) ON DELETE SET NULL,
        CONSTRAINT ck_users_username CHECK (
            char_length(username) BETWEEN 3 AND 50 AND username ~ '^[A-Za-z0-9_.-]+$'
        ),
        CONSTRAINT ck_users_email CHECK (char_length(btrim(email)) > 3 AND email LIKE '%_@_%._%'),
        CONSTRAINT ck_users_password CHECK (char_length(btrim(password_hash)) > 0),
        CONSTRAINT ck_users_failed_login CHECK (failed_login_attempts >= 0),
        CONSTRAINT ck_users_status CHECK (
            status IN ('pending', 'active', 'suspended', 'banned', 'deleted')
        )
);

CREATE TABLE IF NOT EXISTS role_permissions (

        role_permission_id UUID NOT NULL DEFAULT gen_random_uuid(),
        role_id            UUID NOT NULL,
        permission_id      UUID NOT NULL,
        assigned_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_role_permissions PRIMARY KEY (role_permission_id),
        CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE,
        CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE,
        CONSTRAINT uq_role_permissions UNIQUE (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_permissions (

        user_permission_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id            UUID NOT NULL,
        permission_id      UUID NOT NULL,
        is_granted         BOOLEAN NOT NULL DEFAULT TRUE,
        granted_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expired_at         TIMESTAMPTZ NULL,
        CONSTRAINT pk_user_permissions PRIMARY KEY (user_permission_id),
        CONSTRAINT fk_user_permissions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_user_permissions_permission FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE,
        CONSTRAINT uq_user_permissions UNIQUE (user_id, permission_id),
        CONSTRAINT ck_user_permissions_expiry CHECK (expired_at IS NULL OR expired_at > granted_at)
);

CREATE TABLE IF NOT EXISTS refresh_tokens (

        refresh_token_id      UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id               UUID NOT NULL,
        jti                   UUID NOT NULL DEFAULT gen_random_uuid(),
        token_hash            VARCHAR(128) NOT NULL,
        issued_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at            TIMESTAMPTZ NOT NULL,
        revoked_at            TIMESTAMPTZ NULL,
        revoke_reason         VARCHAR(255) NULL,
        replaced_by_token_id  UUID NULL,
        ip_address            VARCHAR(45) NULL,
        user_agent            VARCHAR(1000) NULL,
        CONSTRAINT pk_refresh_tokens PRIMARY KEY (refresh_token_id),
        CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_refresh_tokens_replaced FOREIGN KEY (replaced_by_token_id) REFERENCES refresh_tokens(refresh_token_id),
        CONSTRAINT uq_refresh_tokens_jti UNIQUE (jti),
        CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash),
        CONSTRAINT ck_refresh_tokens_expiry CHECK (expires_at > issued_at),
        CONSTRAINT ck_refresh_tokens_revoked CHECK (revoked_at IS NULL OR revoked_at >= issued_at)
);

CREATE TABLE IF NOT EXISTS notification_settings (

        notification_setting_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id                  UUID NOT NULL,
        in_app_enabled           BOOLEAN NOT NULL DEFAULT TRUE,
        email_enabled            BOOLEAN NOT NULL DEFAULT TRUE,
        new_video_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
        comment_reply_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
        report_result_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
        moderation_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
        plan_enabled             BOOLEAN NOT NULL DEFAULT TRUE,
        updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_notification_settings PRIMARY KEY (notification_setting_id),
        CONSTRAINT fk_notification_settings_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT uq_notification_settings_user UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS notifications (

        notification_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id         UUID NOT NULL,
        type            VARCHAR(50) NOT NULL,
        title           VARCHAR(200) NOT NULL,
        content         TEXT NOT NULL,
        action_url      VARCHAR(2048) NULL,
        is_read         BOOLEAN NOT NULL DEFAULT FALSE,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        read_at         TIMESTAMPTZ NULL,
        CONSTRAINT pk_notifications PRIMARY KEY (notification_id),
        CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT ck_notifications_type CHECK (char_length(btrim(type)) > 0),
        CONSTRAINT ck_notifications_title CHECK (char_length(btrim(title)) > 0),
        CONSTRAINT ck_notifications_content CHECK (char_length(btrim(content)) > 0),
        CONSTRAINT ck_notifications_read_at CHECK (
            (is_read = FALSE AND read_at IS NULL) OR (is_read = TRUE AND read_at IS NOT NULL)
        )
);

CREATE TABLE IF NOT EXISTS search_histories (

        search_history_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id           UUID NOT NULL,
        keyword           VARCHAR(500) NOT NULL,
        search_type       VARCHAR(30) NOT NULL DEFAULT 'all',
        searched_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_search_histories PRIMARY KEY (search_history_id),
        CONSTRAINT fk_search_histories_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT ck_search_histories_keyword CHECK (char_length(btrim(keyword)) > 0),
        CONSTRAINT ck_search_histories_type CHECK (
            search_type IN ('all', 'video', 'channel', 'playlist', 'user', 'tag')
        )
);

CREATE TABLE IF NOT EXISTS channels (

        channel_id     UUID NOT NULL DEFAULT gen_random_uuid(),
        owner_user_id  UUID NOT NULL,
        name           VARCHAR(100) NOT NULL,
        handle         VARCHAR(50) NOT NULL,
        description    TEXT NULL,
        avatar_url     VARCHAR(2048) NULL,
        banner_url     VARCHAR(2048) NULL,
        status         VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_channels PRIMARY KEY (channel_id),
        CONSTRAINT fk_channels_owner FOREIGN KEY (owner_user_id) REFERENCES users(user_id),
        CONSTRAINT ck_channels_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_channels_handle CHECK (
            char_length(handle) BETWEEN 3 AND 50 AND handle ~ '^[A-Za-z0-9_.-]+$'
        ),
        CONSTRAINT ck_channels_status CHECK (
            status IN ('active', 'suspended', 'banned', 'deleted')
        )
);

CREATE TABLE IF NOT EXISTS channel_quotas (

        channel_quota_id UUID NOT NULL DEFAULT gen_random_uuid(),
        channel_id       UUID NOT NULL,
        storage_limit    BIGINT NOT NULL,
        storage_used     BIGINT NOT NULL DEFAULT 0,
        updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_channel_quotas PRIMARY KEY (channel_quota_id),
        CONSTRAINT fk_channel_quotas_channel FOREIGN KEY (channel_id) REFERENCES channels(channel_id) ON DELETE CASCADE,
        CONSTRAINT uq_channel_quotas_channel UNIQUE (channel_id),
        CONSTRAINT ck_channel_quotas_limit CHECK (storage_limit >= 0),
        CONSTRAINT ck_channel_quotas_used CHECK (storage_used >= 0 AND storage_used <= storage_limit)
);

CREATE TABLE IF NOT EXISTS channel_actions (

        channel_action_id UUID NOT NULL DEFAULT gen_random_uuid(),
        channel_id        UUID NOT NULL,
        moderator_id      UUID NOT NULL,
        action_type       VARCHAR(30) NOT NULL,
        reason            TEXT NOT NULL,
        created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expired_at        TIMESTAMPTZ NULL,
        status            VARCHAR(20) NOT NULL DEFAULT 'active',
        CONSTRAINT pk_channel_actions PRIMARY KEY (channel_action_id),
        CONSTRAINT fk_channel_actions_channel FOREIGN KEY (channel_id) REFERENCES channels(channel_id) ON DELETE CASCADE,
        CONSTRAINT fk_channel_actions_moderator FOREIGN KEY (moderator_id) REFERENCES users(user_id),
        CONSTRAINT ck_channel_actions_type CHECK (
            action_type IN ('warning', 'restrict', 'suspend', 'ban', 'restore')
        ),
        CONSTRAINT ck_channel_actions_reason CHECK (char_length(btrim(reason)) > 0),
        CONSTRAINT ck_channel_actions_expiry CHECK (expired_at IS NULL OR expired_at > created_at),
        CONSTRAINT ck_channel_actions_status CHECK (status IN ('active', 'expired', 'revoked'))
);

CREATE TABLE IF NOT EXISTS subscriptions (

        subscription_id       UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id               UUID NOT NULL,
        channel_id            UUID NOT NULL,
        subscribed_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
        status                VARCHAR(20) NOT NULL DEFAULT 'active',
        CONSTRAINT pk_subscriptions PRIMARY KEY (subscription_id),
        CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_subscriptions_channel FOREIGN KEY (channel_id) REFERENCES channels(channel_id) ON DELETE CASCADE,
        CONSTRAINT uq_subscriptions UNIQUE (user_id, channel_id),
        CONSTRAINT ck_subscriptions_status CHECK (status IN ('active', 'paused'))
);

CREATE TABLE IF NOT EXISTS plan_histories (

        plan_history_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id         UUID NOT NULL,
        plan_id         UUID NOT NULL,
        start_date      TIMESTAMPTZ NOT NULL,
        end_date        TIMESTAMPTZ NULL,
        status          VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_plan_histories PRIMARY KEY (plan_history_id),
        CONSTRAINT fk_plan_histories_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_plan_histories_plan FOREIGN KEY (plan_id) REFERENCES plans(plan_id),
        CONSTRAINT ck_plan_histories_dates CHECK (end_date IS NULL OR end_date > start_date),
        CONSTRAINT ck_plan_histories_status CHECK (
            status IN ('pending', 'active', 'expired', 'cancelled')
        )
);

CREATE TABLE IF NOT EXISTS payments (

        payment_id       UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id          UUID NOT NULL,
        plan_id          UUID NOT NULL,
        plan_history_id  UUID NULL,
        amount           NUMERIC(15,2) NOT NULL,
        currency         CHAR(3) NOT NULL DEFAULT 'VND',
        payment_method   VARCHAR(30) NOT NULL,
        transaction_code VARCHAR(150) NOT NULL,
        paid_at          TIMESTAMPTZ NULL,
        status           VARCHAR(20) NOT NULL DEFAULT 'pending',
        created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_payments PRIMARY KEY (payment_id),
        CONSTRAINT fk_payments_user FOREIGN KEY (user_id) REFERENCES users(user_id),
        CONSTRAINT fk_payments_plan FOREIGN KEY (plan_id) REFERENCES plans(plan_id),
        CONSTRAINT fk_payments_history FOREIGN KEY (plan_history_id) REFERENCES plan_histories(plan_history_id) ON DELETE SET NULL,
        CONSTRAINT uq_payments_transaction UNIQUE (transaction_code),
        CONSTRAINT ck_payments_amount CHECK (amount >= 0),
        CONSTRAINT ck_payments_currency CHECK (currency ~ '^[A-Z]{3}$'),
        CONSTRAINT ck_payments_method CHECK (
            payment_method IN ('cash', 'bank_transfer', 'card', 'momo', 'vnpay', 'paypal')
        ),
        CONSTRAINT ck_payments_status CHECK (
            status IN ('pending', 'processing', 'paid', 'failed', 'cancelled', 'refunded')
        ),
        CONSTRAINT ck_payments_paid_at CHECK (
            status NOT IN ('paid', 'refunded') OR paid_at IS NOT NULL
        )
);

CREATE TABLE IF NOT EXISTS categories (

        category_id UUID NOT NULL DEFAULT gen_random_uuid(),
        name        VARCHAR(100) NOT NULL,
        slug        VARCHAR(120) NOT NULL,
        description TEXT NULL,
        status      VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_categories PRIMARY KEY (category_id),
        CONSTRAINT ck_categories_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_categories_slug CHECK (
            slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        ),
        CONSTRAINT ck_categories_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS videos (

        video_id       UUID NOT NULL DEFAULT gen_random_uuid(),
        channel_id     UUID NOT NULL,
        category_id    UUID NULL,
        title          VARCHAR(200) NOT NULL,
        description    TEXT NULL,
        video_url      VARCHAR(2048) NOT NULL,
        thumbnail_url  VARCHAR(2048) NULL,
        duration       INT NOT NULL,             -- seconds
        file_size      BIGINT NOT NULL,          -- bytes
        visibility     VARCHAR(20) NOT NULL DEFAULT 'public',
        status         VARCHAR(20) NOT NULL DEFAULT 'processing',
        published_at   TIMESTAMPTZ NULL,
        created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_videos PRIMARY KEY (video_id),
        CONSTRAINT fk_videos_channel FOREIGN KEY (channel_id) REFERENCES channels(channel_id) ON DELETE CASCADE,
        CONSTRAINT fk_videos_category FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE SET NULL,
        CONSTRAINT ck_videos_title CHECK (char_length(btrim(title)) > 0),
        CONSTRAINT ck_videos_url CHECK (char_length(btrim(video_url)) > 0),
        CONSTRAINT ck_videos_duration CHECK (duration > 0),
        CONSTRAINT ck_videos_file_size CHECK (file_size > 0),
        CONSTRAINT ck_videos_visibility CHECK (
            visibility IN ('public', 'unlisted', 'private', 'members')
        ),
        CONSTRAINT ck_videos_status CHECK (
            status IN ('uploading', 'processing', 'published', 'blocked', 'deleted', 'failed')
        ),
        CONSTRAINT ck_videos_published_at CHECK (status <> 'published' OR published_at IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS video_renditions (

        video_rendition_id UUID NOT NULL DEFAULT gen_random_uuid(),
        video_id           UUID NOT NULL,
        quality_label      VARCHAR(20) NOT NULL,
        width              INT NOT NULL,
        height             INT NOT NULL,
        bitrate_kbps       INT NULL,
        codec              VARCHAR(30) NULL,
        file_url           VARCHAR(2048) NOT NULL,
        file_size          BIGINT NOT NULL,
        status             VARCHAR(20) NOT NULL DEFAULT 'processing',
        created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_video_renditions PRIMARY KEY (video_rendition_id),
        CONSTRAINT fk_video_renditions_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT uq_video_renditions_quality UNIQUE (video_id, quality_label),
        CONSTRAINT ck_video_renditions_quality CHECK (char_length(btrim(quality_label)) > 0),
        CONSTRAINT ck_video_renditions_dimensions CHECK (width > 0 AND height > 0),
        CONSTRAINT ck_video_renditions_bitrate CHECK (bitrate_kbps IS NULL OR bitrate_kbps > 0),
        CONSTRAINT ck_video_renditions_url CHECK (char_length(btrim(file_url)) > 0),
        CONSTRAINT ck_video_renditions_file_size CHECK (file_size > 0),
        CONSTRAINT ck_video_renditions_status CHECK (
            status IN ('processing', 'ready', 'failed')
        )
);

CREATE TABLE IF NOT EXISTS tags (

        tag_id      UUID NOT NULL DEFAULT gen_random_uuid(),
        name        VARCHAR(80) NOT NULL,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_tags PRIMARY KEY (tag_id),
        CONSTRAINT ck_tags_name CHECK (char_length(btrim(name)) > 0)
);

CREATE TABLE IF NOT EXISTS video_tags (

        video_tag_id UUID NOT NULL DEFAULT gen_random_uuid(),
        video_id     UUID NOT NULL,
        tag_id       UUID NOT NULL,
        created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_video_tags PRIMARY KEY (video_tag_id),
        CONSTRAINT fk_video_tags_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT fk_video_tags_tag FOREIGN KEY (tag_id) REFERENCES tags(tag_id) ON DELETE CASCADE,
        CONSTRAINT uq_video_tags UNIQUE (video_id, tag_id)
);

CREATE TABLE IF NOT EXISTS playlists (

        playlist_id  UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id      UUID NOT NULL,
        name         VARCHAR(150) NOT NULL,
        description  TEXT NULL,
        visibility   VARCHAR(20) NOT NULL DEFAULT 'private',
        playlist_type VARCHAR(20) NOT NULL DEFAULT 'normal',
        created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_playlists PRIMARY KEY (playlist_id),
        CONSTRAINT fk_playlists_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT ck_playlists_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_playlists_visibility CHECK (visibility IN ('public', 'unlisted', 'private')),
        CONSTRAINT ck_playlists_type CHECK (playlist_type IN ('normal', 'watch_later'))
);

CREATE TABLE IF NOT EXISTS playlist_videos (

        playlist_video_id UUID NOT NULL DEFAULT gen_random_uuid(),
        playlist_id       UUID NOT NULL,
        video_id          UUID NOT NULL,
        position          INT NOT NULL,
        added_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_playlist_videos PRIMARY KEY (playlist_video_id),
        CONSTRAINT fk_playlist_videos_playlist FOREIGN KEY (playlist_id) REFERENCES playlists(playlist_id) ON DELETE CASCADE,
        CONSTRAINT fk_playlist_videos_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT uq_playlist_videos_video UNIQUE (playlist_id, video_id),
        CONSTRAINT uq_playlist_videos_position UNIQUE (playlist_id, position),
        CONSTRAINT ck_playlist_videos_position CHECK (position > 0)
);

CREATE TABLE IF NOT EXISTS viewing_histories (

        viewing_history_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id            UUID NOT NULL,
        video_id           UUID NOT NULL,
        viewed_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        watch_duration     INT NOT NULL DEFAULT 0,
        progress           NUMERIC(5,2) NOT NULL DEFAULT 0,
        CONSTRAINT pk_viewing_histories PRIMARY KEY (viewing_history_id),
        CONSTRAINT fk_viewing_histories_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_viewing_histories_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT ck_viewing_histories_duration CHECK (watch_duration >= 0),
        CONSTRAINT ck_viewing_histories_progress CHECK (progress BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS share_histories (

        share_history_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id          UUID NOT NULL,
        video_id         UUID NOT NULL,
        share_method     VARCHAR(50) NOT NULL DEFAULT 'copy_link',
        shared_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_share_histories PRIMARY KEY (share_history_id),
        CONSTRAINT fk_share_histories_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_share_histories_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT ck_share_histories_method CHECK (char_length(btrim(share_method)) > 0)
);

CREATE TABLE IF NOT EXISTS video_reactions (

        video_reaction_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id           UUID NOT NULL,
        video_id          UUID NOT NULL,
        type              VARCHAR(20) NOT NULL,
        created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_video_reactions PRIMARY KEY (video_reaction_id),
        CONSTRAINT fk_video_reactions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_video_reactions_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT uq_video_reactions UNIQUE (user_id, video_id),
        CONSTRAINT ck_video_reactions_type CHECK (type IN ('like', 'dislike'))
);

CREATE TABLE IF NOT EXISTS comments (

        comment_id        UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id           UUID NOT NULL,
        video_id          UUID NOT NULL,
        parent_comment_id UUID NULL,
        content           TEXT NOT NULL,
        status            VARCHAR(20) NOT NULL DEFAULT 'visible',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_comments PRIMARY KEY (comment_id),
        CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT fk_comments_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id),
        CONSTRAINT ck_comments_content CHECK (char_length(btrim(content)) > 0),
        CONSTRAINT ck_comments_parent_self CHECK (parent_comment_id IS NULL OR parent_comment_id <> comment_id),
        CONSTRAINT ck_comments_status CHECK (status IN ('visible', 'hidden', 'held', 'deleted'))
);

CREATE TABLE IF NOT EXISTS comment_reactions (

        comment_reaction_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id             UUID NOT NULL,
        comment_id          UUID NOT NULL,
        type                VARCHAR(20) NOT NULL,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_comment_reactions PRIMARY KEY (comment_reaction_id),
        -- NO ACTION avoids SQL Server's multiple-cascade path through users -> comments.
        CONSTRAINT fk_comment_reactions_user FOREIGN KEY (user_id) REFERENCES users(user_id),
        CONSTRAINT fk_comment_reactions_comment FOREIGN KEY (comment_id) REFERENCES comments(comment_id) ON DELETE CASCADE,
        CONSTRAINT uq_comment_reactions UNIQUE (user_id, comment_id),
        CONSTRAINT ck_comment_reactions_type CHECK (type IN ('like', 'dislike'))
);

CREATE TABLE IF NOT EXISTS recommendations (

        recommendation_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id           UUID NOT NULL,
        algorithm         VARCHAR(50) NOT NULL DEFAULT 'collaborative_filtering',
        generated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at        TIMESTAMPTZ NULL,
        status            VARCHAR(20) NOT NULL DEFAULT 'active',
        CONSTRAINT pk_recommendations PRIMARY KEY (recommendation_id),
        CONSTRAINT fk_recommendations_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT ck_recommendations_algorithm CHECK (char_length(btrim(algorithm)) > 0),
        CONSTRAINT ck_recommendations_expiry CHECK (expires_at IS NULL OR expires_at > generated_at),
        CONSTRAINT ck_recommendations_status CHECK (
            status IN ('generating', 'active', 'expired', 'failed')
        )
);

CREATE TABLE IF NOT EXISTS recommendation_items (

        recommendation_item_id UUID NOT NULL DEFAULT gen_random_uuid(),
        recommendation_id      UUID NOT NULL,
        video_id               UUID NOT NULL,
        score                  NUMERIC(12,8) NOT NULL,
        rank                   INT NOT NULL,
        reason                 VARCHAR(255) NULL,
        CONSTRAINT pk_recommendation_items PRIMARY KEY (recommendation_item_id),
        CONSTRAINT fk_recommendation_items_recommendation FOREIGN KEY (recommendation_id) REFERENCES recommendations(recommendation_id) ON DELETE CASCADE,
        CONSTRAINT fk_recommendation_items_video FOREIGN KEY (video_id) REFERENCES videos(video_id) ON DELETE CASCADE,
        CONSTRAINT uq_recommendation_items_video UNIQUE (recommendation_id, video_id),
        CONSTRAINT uq_recommendation_items_rank UNIQUE (recommendation_id, rank),
        CONSTRAINT ck_recommendation_items_rank CHECK (rank > 0)
);

CREATE TABLE IF NOT EXISTS violation_types (

        violation_type_id UUID NOT NULL DEFAULT gen_random_uuid(),
        code              VARCHAR(50) NOT NULL,
        name              VARCHAR(150) NOT NULL,
        description       TEXT NULL,
        status            VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_violation_types PRIMARY KEY (violation_type_id),
        CONSTRAINT ck_violation_types_code CHECK (char_length(btrim(code)) > 0),
        CONSTRAINT ck_violation_types_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_violation_types_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS resolution_types (

        resolution_type_id UUID NOT NULL DEFAULT gen_random_uuid(),
        code               VARCHAR(50) NOT NULL,
        name               VARCHAR(150) NOT NULL,
        description        TEXT NULL,
        target_type        VARCHAR(20) NOT NULL,
        status             VARCHAR(20) NOT NULL DEFAULT 'active',
        created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_resolution_types PRIMARY KEY (resolution_type_id),
        CONSTRAINT ck_resolution_types_code CHECK (char_length(btrim(code)) > 0),
        CONSTRAINT ck_resolution_types_name CHECK (char_length(btrim(name)) > 0),
        CONSTRAINT ck_resolution_types_target CHECK (
            target_type IN ('video', 'comment', 'channel', 'any')
        ),
        CONSTRAINT ck_resolution_types_status CHECK (
            status IN ('active', 'inactive')
        )
);

CREATE TABLE IF NOT EXISTS reports (

        report_id         UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id           UUID NOT NULL,
        violation_type_id UUID NOT NULL,
        video_id          UUID NULL,
        channel_id        UUID NULL,
        comment_id        UUID NULL,
        description       TEXT NOT NULL,
        status            VARCHAR(20) NOT NULL DEFAULT 'pending',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_reports PRIMARY KEY (report_id),
        CONSTRAINT fk_reports_user FOREIGN KEY (user_id) REFERENCES users(user_id),
        CONSTRAINT fk_reports_violation_type FOREIGN KEY (violation_type_id) REFERENCES violation_types(violation_type_id),
        -- Reports are audit records, so reported targets use NO ACTION instead of
        -- cascading deletes. Application content should be soft-deleted by status.
        CONSTRAINT fk_reports_video FOREIGN KEY (video_id) REFERENCES videos(video_id),
        CONSTRAINT fk_reports_channel FOREIGN KEY (channel_id) REFERENCES channels(channel_id),
        CONSTRAINT fk_reports_comment FOREIGN KEY (comment_id) REFERENCES comments(comment_id),
        CONSTRAINT ck_reports_description CHECK (char_length(btrim(description)) > 0),
        CONSTRAINT ck_reports_one_target CHECK (
            (CASE WHEN video_id IS NULL THEN 0 ELSE 1 END) +
            (CASE WHEN channel_id IS NULL THEN 0 ELSE 1 END) +
            (CASE WHEN comment_id IS NULL THEN 0 ELSE 1 END) = 1
        ),
        CONSTRAINT ck_reports_status CHECK (
            status IN ('pending', 'reviewing', 'resolved', 'rejected', 'cancelled')
        )
);

CREATE TABLE IF NOT EXISTS report_resolutions (

        resolution_id      UUID NOT NULL DEFAULT gen_random_uuid(),
        report_id          UUID NOT NULL,
        resolver_id        UUID NOT NULL,
        resolution_type_id UUID NOT NULL,
        reason             TEXT NOT NULL,
        status             VARCHAR(20) NOT NULL,
        resolved_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT pk_report_resolutions PRIMARY KEY (resolution_id),
        CONSTRAINT fk_report_resolutions_report FOREIGN KEY (report_id) REFERENCES reports(report_id) ON DELETE CASCADE,
        CONSTRAINT fk_report_resolutions_resolver FOREIGN KEY (resolver_id) REFERENCES users(user_id),
        CONSTRAINT fk_report_resolutions_type FOREIGN KEY (resolution_type_id) REFERENCES resolution_types(resolution_type_id),
        CONSTRAINT uq_report_resolutions_report UNIQUE (report_id),
        CONSTRAINT ck_report_resolutions_reason CHECK (char_length(btrim(reason)) > 0),
        CONSTRAINT ck_report_resolutions_status CHECK (
            status IN ('approved', 'rejected', 'no_violation')
        )
);

CREATE TABLE IF NOT EXISTS appeals (

        appeal_id      UUID NOT NULL DEFAULT gen_random_uuid(),
        user_id        UUID NOT NULL,
        resolution_id  UUID NOT NULL,
        appeal_number  INT NOT NULL DEFAULT 1,
        reviewer_id    UUID NULL,
        reason         TEXT NOT NULL,
        status         VARCHAR(20) NOT NULL DEFAULT 'pending',
        review_note    TEXT NULL,
        created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        resolved_at    TIMESTAMPTZ NULL,
        CONSTRAINT pk_appeals PRIMARY KEY (appeal_id),
        CONSTRAINT fk_appeals_user FOREIGN KEY (user_id) REFERENCES users(user_id),
        CONSTRAINT fk_appeals_resolution FOREIGN KEY (resolution_id) REFERENCES report_resolutions(resolution_id) ON DELETE CASCADE,
        CONSTRAINT fk_appeals_reviewer FOREIGN KEY (reviewer_id) REFERENCES users(user_id),
        CONSTRAINT uq_appeals_attempt UNIQUE (user_id, resolution_id, appeal_number),
        CONSTRAINT ck_appeals_number CHECK (appeal_number > 0),
        CONSTRAINT ck_appeals_reason CHECK (char_length(btrim(reason)) > 0),
        CONSTRAINT ck_appeals_status CHECK (
            status IN ('pending', 'reviewing', 'approved', 'rejected', 'cancelled')
        ),
        CONSTRAINT ck_appeals_resolution_state CHECK (
            status IN ('pending', 'reviewing', 'cancelled') OR
            (status IN ('approved', 'rejected') AND resolved_at IS NOT NULL AND reviewer_id IS NOT NULL)
        )
);

/*=============================================================================
  Compact additions to existing tables for Sprint 4-9 business flows
=============================================================================*/

ALTER TABLE plans
    ADD COLUMN IF NOT EXISTS max_video_quality VARCHAR(20),
    ADD COLUMN IF NOT EXISTS features JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS display_name VARCHAR(120);

ALTER TABLE notification_settings
    ADD COLUMN IF NOT EXISTS recommendation_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS mention_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS channel_activity_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS payment_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS resource_type VARCHAR(30),
    ADD COLUMN IF NOT EXISTS resource_id UUID;

ALTER TABLE channels
    ADD COLUMN IF NOT EXISTS contact_email CITEXT,
    ADD COLUMN IF NOT EXISTS watermark_url TEXT,
    ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(120),
    ADD COLUMN IF NOT EXISTS currency CHAR(3) NOT NULL DEFAULT 'VND',
    ADD COLUMN IF NOT EXISTS gateway_payload JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE videos
    ADD COLUMN IF NOT EXISTS language_code VARCHAR(10),
    ADD COLUMN IF NOT EXISTS age_restricted BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(20) NOT NULL DEFAULT 'not_submitted',
    ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE recommendations
    ADD COLUMN IF NOT EXISTS model_version VARCHAR(80),
    ADD COLUMN IF NOT EXISTS fallback_used BOOLEAN NOT NULL DEFAULT FALSE;

/*=============================================================================
  36-42. Updated class design + compact business additions
=============================================================================*/

-- 36. General channel collaborators (manager/editor/viewer).
CREATE TABLE IF NOT EXISTS channel_members (
    channel_member_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id        UUID NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role_code         VARCHAR(30) NOT NULL,
    status            VARCHAR(20) NOT NULL DEFAULT 'active',
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_channel_members UNIQUE(channel_id, user_id),
    CONSTRAINT ck_channel_members_role CHECK (role_code IN ('manager','editor','viewer')),
    CONSTRAINT ck_channel_members_status CHECK (status IN ('active','suspended','removed'))
);

-- 37. Channel member invitation lifecycle.
CREATE TABLE IF NOT EXISTS channel_invitations (
    channel_invitation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id            UUID NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    invited_user_id       UUID REFERENCES users(user_id) ON DELETE CASCADE,
    invited_email         CITEXT,
    invited_by_user_id    UUID NOT NULL REFERENCES users(user_id),
    role_code             VARCHAR(30) NOT NULL,
    token_hash            VARCHAR(255),
    status                VARCHAR(20) NOT NULL DEFAULT 'pending',
    expires_at            TIMESTAMPTZ NOT NULL,
    responded_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_channel_invitations_target CHECK (invited_user_id IS NOT NULL OR invited_email IS NOT NULL),
    CONSTRAINT ck_channel_invitations_role CHECK (role_code IN ('manager','editor','viewer','comment_moderator')),
    CONSTRAINT ck_channel_invitations_status CHECK (status IN ('pending','accepted','declined','expired','revoked')),
    CONSTRAINT ck_channel_invitations_expiry CHECK (expires_at > created_at)
);

-- 38. Explicit channel comment moderator from the updated class diagram.
CREATE TABLE IF NOT EXISTS channel_comment_moderators (
    channel_comment_moderator_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id                   UUID NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    user_id                      UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    appointed_by_user_id         UUID NOT NULL REFERENCES users(user_id),
    status                       VARCHAR(20) NOT NULL DEFAULT 'active',
    accepted_at                  TIMESTAMPTZ,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_channel_comment_moderators UNIQUE(channel_id, user_id),
    CONSTRAINT ck_channel_comment_moderators_status CHECK (status IN ('pending','active','revoked'))
);

-- 39. Comment moderation action from the updated class diagram.
CREATE TABLE IF NOT EXISTS comment_moderation_actions (
    comment_moderation_action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id                   UUID NOT NULL REFERENCES comments(comment_id) ON DELETE CASCADE,
    moderator_user_id            UUID NOT NULL REFERENCES users(user_id),
    action_type                  VARCHAR(30) NOT NULL,
    reason                       TEXT,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_comment_moderation_actions_type CHECK (action_type IN ('hold','release','hide','unhide','delete','restore'))
);

-- 40. Explicit 1..5 rating used by the current MBMF design.
CREATE TABLE IF NOT EXISTS video_ratings (
    video_rating_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    video_id        UUID NOT NULL REFERENCES videos(video_id) ON DELETE CASCADE,
    score           SMALLINT NOT NULL,
    evaluated_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_video_ratings UNIQUE(user_id, video_id),
    CONSTRAINT ck_video_ratings_score CHECK (score BETWEEN 1 AND 5)
);

-- 41. Compact moderation queue for upload/report review.
CREATE TABLE IF NOT EXISTS moderation_cases (
    moderation_case_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id           UUID REFERENCES videos(video_id),
    report_id          UUID REFERENCES reports(report_id),
    reviewer_id        UUID REFERENCES users(user_id),
    case_type          VARCHAR(30) NOT NULL,
    status             VARCHAR(20) NOT NULL DEFAULT 'pending',
    note               TEXT,
    submitted_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at         TIMESTAMPTZ,
    resolved_at        TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_moderation_cases_target CHECK (num_nonnulls(video_id, report_id) = 1),
    CONSTRAINT ck_moderation_cases_type CHECK (case_type IN ('upload_review','report_review','manual_review')),
    CONSTRAINT ck_moderation_cases_status CHECK (status IN ('pending','reviewing','approved','rejected','escalated','resolved'))
);

-- 42. Important administrative/moderation audit trail.
CREATE TABLE IF NOT EXISTS audit_logs (
    audit_log_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id  UUID REFERENCES users(user_id) ON DELETE SET NULL,
    action         VARCHAR(100) NOT NULL,
    resource_type  VARCHAR(50),
    resource_id    UUID,
    reason         TEXT,
    old_values     JSONB,
    new_values     JSONB,
    ip_address     INET,
    user_agent     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_audit_logs_action CHECK (char_length(btrim(action)) > 0)
);

/*=============================================================================
  Indexes
=============================================================================*/
CREATE UNIQUE INDEX IF NOT EXISTS ux_roles_code ON roles(code);
CREATE UNIQUE INDEX IF NOT EXISTS ux_permissions_code ON permissions(code);
CREATE UNIQUE INDEX IF NOT EXISTS ux_plans_code ON plans(code);
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_ci ON users(lower(username));
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email_ci ON users(lower(email));
CREATE UNIQUE INDEX IF NOT EXISTS ux_channels_handle_ci ON channels(lower(handle));
CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_slug ON categories(slug);
CREATE UNIQUE INDEX IF NOT EXISTS ux_tags_name_ci ON tags(lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_idempotency ON payments(idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_notifications_user_unread ON notifications(user_id, created_at DESC) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS ix_search_histories_user_time ON search_histories(user_id, searched_at DESC);
CREATE INDEX IF NOT EXISTS ix_videos_channel_time ON videos(channel_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_videos_moderation ON videos(moderation_status, created_at);
CREATE INDEX IF NOT EXISTS ix_viewing_histories_user_time ON viewing_histories(user_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS ix_comments_video_time ON comments(video_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_reports_status_time ON reports(status, created_at);
CREATE INDEX IF NOT EXISTS ix_moderation_cases_queue ON moderation_cases(status, submitted_at);
CREATE INDEX IF NOT EXISTS ix_audit_logs_resource ON audit_logs(resource_type, resource_id, created_at DESC);


/*=============================================================================
  Verification: should return 42 for this HuTube schema in a clean database.
=============================================================================*/
SELECT COUNT(*) AS hutube_table_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name IN (
      'roles','permissions','plans','users','role_permissions','user_permissions',
      'refresh_tokens','notification_settings','notifications','search_histories',
      'channels','channel_quotas','channel_actions','subscriptions','plan_histories',
      'payments','categories','videos','video_renditions','tags','video_tags','playlists',
      'playlist_videos','viewing_histories','share_histories','video_reactions','comments',
      'comment_reactions','recommendations','recommendation_items','violation_types',
      'resolution_types','reports','report_resolutions','appeals','channel_members',
      'channel_invitations','channel_comment_moderators','comment_moderation_actions',
      'video_ratings','moderation_cases','audit_logs'
  );
