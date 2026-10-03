--
-- PostgreSQL database dump
--

\restrict MPJkUmrjDYS0XmfdoPhPQhUAuQj4PeMW1bq3Ci13jaAWh2jVk0QW4VLZUQdiwS0

-- Dumped from database version 18.6 (4e955f5)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: __EFMigrationsHistory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."__EFMigrationsHistory" (
    "MigrationId" character varying(150) NOT NULL,
    "ProductVersion" character varying(32) NOT NULL
);


--
-- Name: appeals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appeals (
    appeal_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    resolution_id uuid,
    appeal_number integer DEFAULT 1 NOT NULL,
    reviewer_id uuid,
    reason text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    review_note text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resolved_at timestamp with time zone,
    target_type character varying(30) DEFAULT 'video'::character varying NOT NULL,
    target_id uuid,
    moderation_case_id uuid,
    strike_id uuid,
    evidence_url text,
    evidence_note text,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_appeals_number CHECK ((appeal_number > 0)),
    CONSTRAINT ck_appeals_reason CHECK ((char_length(btrim(reason)) > 0)),
    CONSTRAINT ck_appeals_resolution_state CHECK ((((status)::text = ANY ((ARRAY['pending'::character varying, 'reviewing'::character varying, 'cancelled'::character varying])::text[])) OR (((status)::text = ANY ((ARRAY['approved'::character varying, 'rejected'::character varying])::text[])) AND (resolved_at IS NOT NULL) AND (reviewer_id IS NOT NULL)))),
    CONSTRAINT ck_appeals_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'reviewing'::character varying, 'approved'::character varying, 'rejected'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    audit_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_user_id uuid,
    action character varying(100) NOT NULL,
    resource_type character varying(50),
    resource_id uuid,
    reason text,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_audit_logs_action CHECK ((char_length(btrim((action)::text)) > 0))
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    category_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(120) NOT NULL,
    description text,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_categories_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_categories_slug CHECK (((slug)::text ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)),
    CONSTRAINT ck_categories_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: channel_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_actions (
    channel_action_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    moderator_id uuid NOT NULL,
    action_type character varying(30) NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expired_at timestamp with time zone,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    CONSTRAINT ck_channel_actions_expiry CHECK (((expired_at IS NULL) OR (expired_at > created_at))),
    CONSTRAINT ck_channel_actions_reason CHECK ((char_length(btrim(reason)) > 0)),
    CONSTRAINT ck_channel_actions_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'expired'::character varying, 'revoked'::character varying])::text[]))),
    CONSTRAINT ck_channel_actions_type CHECK (((action_type)::text = ANY ((ARRAY['warning'::character varying, 'restrict'::character varying, 'suspend'::character varying, 'ban'::character varying, 'restore'::character varying])::text[])))
);


--
-- Name: channel_comment_moderators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_comment_moderators (
    channel_comment_moderator_id uuid DEFAULT gen_random_uuid() CONSTRAINT channel_comment_moderators_channel_comment_moderator_i_not_null NOT NULL,
    channel_id uuid NOT NULL,
    user_id uuid NOT NULL,
    appointed_by_user_id uuid NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_channel_comment_moderators_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'active'::character varying, 'revoked'::character varying])::text[])))
);


--
-- Name: channel_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_invitations (
    channel_invitation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    invited_user_id uuid,
    invited_email public.citext,
    invited_by_user_id uuid NOT NULL,
    role_code character varying(30) NOT NULL,
    token_hash character varying(255),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    responded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_channel_invitations_expiry CHECK ((expires_at > created_at)),
    CONSTRAINT ck_channel_invitations_role CHECK (((role_code)::text = ANY ((ARRAY['manager'::character varying, 'editor'::character varying, 'moderator'::character varying, 'viewer'::character varying])::text[]))),
    CONSTRAINT ck_channel_invitations_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'declined'::character varying, 'expired'::character varying, 'revoked'::character varying])::text[]))),
    CONSTRAINT ck_channel_invitations_target CHECK (((invited_user_id IS NOT NULL) OR (invited_email IS NOT NULL)))
);


--
-- Name: channel_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_members (
    channel_member_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role_code character varying(30) NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    joined_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_channel_members_role CHECK (((role_code)::text = ANY ((ARRAY['manager'::character varying, 'editor'::character varying, 'moderator'::character varying, 'viewer'::character varying])::text[]))),
    CONSTRAINT ck_channel_members_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying, 'removed'::character varying])::text[])))
);


--
-- Name: channel_quotas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_quotas (
    channel_quota_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    storage_limit bigint NOT NULL,
    storage_used bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_channel_quotas_limit CHECK ((storage_limit >= 0)),
    CONSTRAINT ck_channel_quotas_used CHECK ((storage_used >= 0))
);


--
-- Name: channel_strikes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_strikes (
    strike_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    user_id uuid NOT NULL,
    strike_number integer DEFAULT 1 NOT NULL,
    severity character varying(20) DEFAULT 'high'::character varying NOT NULL,
    policy_code character varying(100),
    reason text NOT NULL,
    internal_note text,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by_user_id uuid,
    revocation_reason text,
    source_moderation_case_id uuid,
    source_report_id uuid,
    upload_restricted_until timestamp with time zone
);


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    channel_id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_user_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    handle character varying(50) NOT NULL,
    description text,
    avatar_url character varying(2048),
    banner_url character varying(2048),
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    contact_email public.citext,
    watermark_url text,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    status_reason text,
    CONSTRAINT ck_channels_handle CHECK ((((char_length((handle)::text) >= 3) AND (char_length((handle)::text) <= 50)) AND ((handle)::text ~ '^[A-Za-z0-9_.-]+$'::text))),
    CONSTRAINT ck_channels_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_channels_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying, 'banned'::character varying, 'deleted'::character varying])::text[])))
);


--
-- Name: comment_moderation_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_moderation_actions (
    comment_moderation_action_id uuid DEFAULT gen_random_uuid() CONSTRAINT comment_moderation_actions_comment_moderation_action_i_not_null NOT NULL,
    comment_id uuid NOT NULL,
    moderator_user_id uuid NOT NULL,
    action_type character varying(30) NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_comment_moderation_actions_type CHECK (((action_type)::text = ANY ((ARRAY['hold'::character varying, 'release'::character varying, 'hide'::character varying, 'unhide'::character varying, 'delete'::character varying, 'restore'::character varying])::text[])))
);


--
-- Name: comment_reactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_reactions (
    comment_reaction_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    comment_id uuid NOT NULL,
    type character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_comment_reactions_type CHECK (((type)::text = ANY ((ARRAY['like'::character varying, 'dislike'::character varying])::text[])))
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    comment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    parent_comment_id uuid,
    content text NOT NULL,
    status character varying(20) DEFAULT 'visible'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_comments_content CHECK ((char_length(btrim(content)) > 0)),
    CONSTRAINT ck_comments_parent_self CHECK (((parent_comment_id IS NULL) OR (parent_comment_id <> comment_id))),
    CONSTRAINT ck_comments_status CHECK (((status)::text = ANY ((ARRAY['visible'::character varying, 'hidden'::character varying, 'held'::character varying, 'deleted'::character varying])::text[])))
);


--
-- Name: login_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_history (
    login_history_id uuid NOT NULL,
    user_id uuid NOT NULL,
    device_id character varying(128) DEFAULT ''::character varying NOT NULL,
    device_name character varying(200) NOT NULL,
    platform character varying(20) NOT NULL,
    ip_address character varying(45),
    login_at timestamp with time zone NOT NULL
);


--
-- Name: moderation_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moderation_cases (
    moderation_case_id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid,
    report_id uuid,
    reviewer_id uuid,
    case_type character varying(30) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    note text,
    submitted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    claimed_at timestamp with time zone,
    resolved_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    policy_code character varying(100),
    policy_version character varying(20),
    decision character varying(50),
    internal_note text,
    risk_level character varying(20) DEFAULT 'normal'::character varying NOT NULL,
    target_type character varying(20),
    target_id uuid,
    CONSTRAINT ck_moderation_cases_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'reviewing'::character varying, 'approved'::character varying, 'rejected'::character varying, 'escalated'::character varying, 'resolved'::character varying])::text[]))),
    CONSTRAINT ck_moderation_cases_target CHECK ((num_nonnulls(video_id, report_id, target_id) = 1)),
    CONSTRAINT ck_moderation_cases_type CHECK (((case_type)::text = ANY ((ARRAY['upload_review'::character varying, 'report_review'::character varying, 'report_case'::character varying, 'manual_review'::character varying])::text[])))
);


--
-- Name: notification_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_settings (
    notification_setting_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    in_app_enabled boolean DEFAULT true NOT NULL,
    email_enabled boolean DEFAULT true NOT NULL,
    new_video_enabled boolean DEFAULT true NOT NULL,
    comment_reply_enabled boolean DEFAULT true NOT NULL,
    report_result_enabled boolean DEFAULT true NOT NULL,
    moderation_enabled boolean DEFAULT true NOT NULL,
    plan_enabled boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    recommendation_enabled boolean DEFAULT true NOT NULL,
    mention_enabled boolean DEFAULT true NOT NULL,
    channel_activity_enabled boolean DEFAULT true NOT NULL,
    payment_enabled boolean DEFAULT true NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    notification_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type character varying(50) NOT NULL,
    title character varying(200) NOT NULL,
    content text NOT NULL,
    action_url character varying(2048),
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    read_at timestamp with time zone,
    resource_type character varying(30),
    resource_id uuid,
    CONSTRAINT ck_notifications_content CHECK ((char_length(btrim(content)) > 0)),
    CONSTRAINT ck_notifications_read_at CHECK ((((is_read = false) AND (read_at IS NULL)) OR ((is_read = true) AND (read_at IS NOT NULL)))),
    CONSTRAINT ck_notifications_title CHECK ((char_length(btrim((title)::text)) > 0)),
    CONSTRAINT ck_notifications_type CHECK ((char_length(btrim((type)::text)) > 0))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    plan_history_id uuid,
    amount numeric(15,2) NOT NULL,
    currency character(3) DEFAULT 'VND'::bpchar NOT NULL,
    payment_method character varying(30) NOT NULL,
    transaction_code character varying(150) NOT NULL,
    paid_at timestamp with time zone,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    idempotency_key character varying(120),
    gateway_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    sepay_transaction_id bigint,
    expires_at timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '00:30:00'::interval) NOT NULL,
    auto_renew boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_payments_amount CHECK ((amount >= (0)::numeric)),
    CONSTRAINT ck_payments_currency CHECK ((currency ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT ck_payments_method CHECK (((payment_method)::text = ANY ((ARRAY['cash'::character varying, 'bank_transfer'::character varying, 'card'::character varying, 'momo'::character varying, 'vnpay'::character varying, 'paypal'::character varying, 'sepay'::character varying])::text[]))),
    CONSTRAINT ck_payments_paid_at CHECK ((((status)::text <> ALL ((ARRAY['paid'::character varying, 'refunded'::character varying])::text[])) OR (paid_at IS NOT NULL))),
    CONSTRAINT ck_payments_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'paid'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'refunded'::character varying])::text[])))
);


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    permission_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(100) NOT NULL,
    name character varying(150) NOT NULL,
    description text,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_permissions_code CHECK ((char_length(btrim((code)::text)) > 0)),
    CONSTRAINT ck_permissions_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_permissions_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: plan_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_histories (
    plan_history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    owner_user_id uuid NOT NULL,
    auto_renew boolean DEFAULT false NOT NULL,
    payment_reference character varying(255),
    owner_allocated_storage bigint,
    CONSTRAINT ck_plan_histories_dates CHECK (((end_date IS NULL) OR (end_date > start_date))),
    CONSTRAINT ck_plan_histories_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'active'::character varying, 'expired'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: plan_invitation_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_invitation_tokens (
    plan_invitation_token_id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_member_id uuid NOT NULL,
    token character varying(256) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: plan_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_members (
    plan_member_id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_history_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    member_email public.citext NOT NULL,
    member_user_id uuid,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    invited_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    accepted_at timestamp with time zone,
    revoked_at timestamp with time zone,
    allocated_storage bigint
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    plan_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    price numeric(15,2) DEFAULT 0 NOT NULL,
    duration_days integer NOT NULL,
    storage_limit bigint NOT NULL,
    max_upload_size bigint NOT NULL,
    max_video_duration integer NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    max_video_quality character varying(20),
    features jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_download_quality character varying(20) DEFAULT '720p'::character varying NOT NULL,
    max_members integer DEFAULT 1 NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    CONSTRAINT ck_plans_code CHECK ((char_length(btrim((code)::text)) > 0)),
    CONSTRAINT ck_plans_duration CHECK ((duration_days > 0)),
    CONSTRAINT ck_plans_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_plans_price CHECK ((price >= (0)::numeric)),
    CONSTRAINT ck_plans_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'archived'::character varying])::text[]))),
    CONSTRAINT ck_plans_storage CHECK ((storage_limit >= 0)),
    CONSTRAINT ck_plans_upload CHECK ((max_upload_size > 0)),
    CONSTRAINT ck_plans_video_duration CHECK ((max_video_duration > 0))
);


--
-- Name: playlist_videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlist_videos (
    playlist_video_id uuid DEFAULT gen_random_uuid() NOT NULL,
    playlist_id uuid NOT NULL,
    video_id uuid NOT NULL,
    "position" integer NOT NULL,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_playlist_videos_position CHECK (("position" > 0))
);


--
-- Name: playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlists (
    playlist_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    description text,
    visibility character varying(20) DEFAULT 'private'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_playlists_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_playlists_visibility CHECK (((visibility)::text = ANY ((ARRAY['public'::character varying, 'unlisted'::character varying, 'private'::character varying])::text[])))
);


--
-- Name: policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policies (
    policy_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(100) NOT NULL,
    name character varying(200) NOT NULL,
    "group" character varying(50) DEFAULT 'content'::character varying NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    severity character varying(30) DEFAULT 'medium'::character varying NOT NULL,
    version character varying(20) DEFAULT '1.0'::character varying NOT NULL,
    status character varying(30) DEFAULT 'published'::character varying NOT NULL,
    effective_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: recommendation_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recommendation_items (
    recommendation_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    recommendation_id uuid NOT NULL,
    video_id uuid NOT NULL,
    score numeric(12,8) NOT NULL,
    rank integer NOT NULL,
    reason character varying(255),
    CONSTRAINT ck_recommendation_items_rank CHECK ((rank > 0))
);


--
-- Name: recommendation_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recommendation_jobs (
    job_id uuid NOT NULL,
    actor_user_id uuid NOT NULL,
    kind text NOT NULL,
    status text NOT NULL,
    step text NOT NULL,
    payload_json jsonb NOT NULL,
    logs_json jsonb NOT NULL,
    error text,
    completed integer NOT NULL,
    total integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    model_csv_key text,
    model_csv_sha256 text,
    service_job_id text
);


--
-- Name: recommendations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recommendations (
    recommendation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    algorithm character varying(50) DEFAULT 'collaborative_filtering'::character varying NOT NULL,
    generated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    model_version character varying(80),
    fallback_used boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_recommendations_algorithm CHECK ((char_length(btrim((algorithm)::text)) > 0)),
    CONSTRAINT ck_recommendations_expiry CHECK (((expires_at IS NULL) OR (expires_at > generated_at))),
    CONSTRAINT ck_recommendations_status CHECK (((status)::text = ANY ((ARRAY['generating'::character varying, 'active'::character varying, 'expired'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_tokens (
    refresh_token_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    jti uuid DEFAULT gen_random_uuid() NOT NULL,
    token_hash character varying(128) NOT NULL,
    issued_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    revoke_reason character varying(255),
    replaced_by_token_id uuid,
    ip_address character varying(45),
    user_agent character varying(1000),
    device_name character varying(200) DEFAULT 'Unknown device'::character varying NOT NULL,
    platform character varying(20) DEFAULT 'web'::character varying NOT NULL,
    last_active_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    device_id character varying(128) DEFAULT ''::character varying NOT NULL,
    CONSTRAINT ck_refresh_tokens_expiry CHECK ((expires_at > issued_at)),
    CONSTRAINT ck_refresh_tokens_revoked CHECK (((revoked_at IS NULL) OR (revoked_at >= issued_at)))
);


--
-- Name: report_resolutions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_resolutions (
    resolution_id uuid DEFAULT gen_random_uuid() NOT NULL,
    report_id uuid NOT NULL,
    resolver_id uuid NOT NULL,
    resolution_type_id uuid NOT NULL,
    reason text NOT NULL,
    status character varying(20) NOT NULL,
    resolved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_report_resolutions_reason CHECK ((char_length(btrim(reason)) > 0)),
    CONSTRAINT ck_report_resolutions_status CHECK (((status)::text = ANY ((ARRAY['approved'::character varying, 'rejected'::character varying, 'no_violation'::character varying])::text[])))
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    report_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    violation_type_id uuid NOT NULL,
    video_id uuid,
    channel_id uuid,
    comment_id uuid,
    description text NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    moderation_case_id uuid,
    disposition character varying(20),
    disposition_by_user_id uuid,
    disposition_reason text,
    disposition_at timestamp with time zone,
    idempotency_key character varying(128),
    abuse_flag boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_reports_description CHECK ((char_length(btrim(description)) > 0)),
    CONSTRAINT ck_reports_one_target CHECK ((((
CASE
    WHEN (video_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (channel_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (comment_id IS NULL) THEN 0
    ELSE 1
END) = 1)),
    CONSTRAINT ck_reports_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'reviewing'::character varying, 'resolved'::character varying, 'rejected'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: resolution_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resolution_types (
    resolution_type_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(150) NOT NULL,
    description text,
    target_type character varying(20) NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_resolution_types_code CHECK ((char_length(btrim((code)::text)) > 0)),
    CONSTRAINT ck_resolution_types_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_resolution_types_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[]))),
    CONSTRAINT ck_resolution_types_target CHECK (((target_type)::text = ANY ((ARRAY['video'::character varying, 'comment'::character varying, 'channel'::character varying, 'any'::character varying])::text[])))
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_permission_id uuid DEFAULT gen_random_uuid() NOT NULL,
    role_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    role_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    is_default boolean DEFAULT false NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_roles_code CHECK ((char_length(btrim((code)::text)) > 0)),
    CONSTRAINT ck_roles_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_roles_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'deleted'::character varying])::text[])))
);


--
-- Name: search_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_histories (
    search_history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    keyword character varying(500) NOT NULL,
    search_type character varying(30) DEFAULT 'all'::character varying NOT NULL,
    searched_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_search_histories_keyword CHECK ((char_length(btrim((keyword)::text)) > 0)),
    CONSTRAINT ck_search_histories_type CHECK (((search_type)::text = ANY ((ARRAY['all'::character varying, 'video'::character varying, 'channel'::character varying, 'playlist'::character varying, 'user'::character varying, 'tag'::character varying])::text[])))
);


--
-- Name: share_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.share_histories (
    share_history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    share_method character varying(50) DEFAULT 'copy_link'::character varying NOT NULL,
    shared_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_share_histories_method CHECK ((char_length(btrim((share_method)::text)) > 0))
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    subscription_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    subscribed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    notifications_enabled boolean DEFAULT true NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    CONSTRAINT ck_subscriptions_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'paused'::character varying])::text[])))
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    tag_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(80) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_tags_name CHECK ((char_length(btrim((name)::text)) > 0))
);


--
-- Name: user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_permissions (
    user_permission_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    is_granted boolean DEFAULT true NOT NULL,
    granted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expired_at timestamp with time zone,
    CONSTRAINT ck_user_permissions_expiry CHECK (((expired_at IS NULL) OR (expired_at > granted_at)))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(254) NOT NULL,
    password_hash character varying(255) NOT NULL,
    avatar_url character varying(2048),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    email_verified_at timestamp with time zone,
    last_login_at timestamp with time zone,
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    role_id uuid NOT NULL,
    plan_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    display_name character varying(120),
    deleted_at timestamp with time zone,
    email_verification_token_hash character varying(128),
    email_verification_created_at timestamp with time zone,
    email_verification_expires_at timestamp with time zone,
    email_verification_used_at timestamp with time zone,
    password_reset_token_hash character varying(128),
    password_reset_created_at timestamp with time zone,
    password_reset_expires_at timestamp with time zone,
    password_reset_used_at timestamp with time zone,
    google_subject character varying(255),
    preferred_language character varying(10) DEFAULT 'vi'::character varying NOT NULL,
    theme character varying(20) DEFAULT 'system'::character varying NOT NULL,
    keep_subscriptions_private boolean DEFAULT true NOT NULL,
    keep_playlists_private boolean DEFAULT true NOT NULL,
    location character varying(120) DEFAULT 'Việt Nam'::character varying,
    bio text,
    CONSTRAINT ck_users_email CHECK (((char_length(btrim((email)::text)) > 3) AND ((email)::text ~~ '%_@_%._%'::text))),
    CONSTRAINT ck_users_failed_login CHECK ((failed_login_attempts >= 0)),
    CONSTRAINT ck_users_password CHECK ((char_length(btrim((password_hash)::text)) > 0)),
    CONSTRAINT ck_users_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'active'::character varying, 'suspended'::character varying, 'banned'::character varying, 'deleted'::character varying])::text[]))),
    CONSTRAINT ck_users_username CHECK ((((char_length((username)::text) >= 3) AND (char_length((username)::text) <= 50)) AND ((username)::text ~ '^[A-Za-z0-9_.-]+$'::text)))
);


--
-- Name: video_downloads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_downloads (
    video_download_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    quality_label character varying(20) NOT NULL,
    file_url character varying(2048) NOT NULL,
    file_size bigint NOT NULL,
    status character varying(20) DEFAULT 'ready'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_video_downloads_size CHECK ((file_size > 0)),
    CONSTRAINT ck_video_downloads_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'ready'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: video_ratings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_ratings (
    video_rating_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    score smallint NOT NULL,
    evaluated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_video_ratings_score CHECK (((score >= 1) AND (score <= 5)))
);


--
-- Name: video_reactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_reactions (
    video_reaction_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    type character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_video_reactions_type CHECK (((type)::text = ANY ((ARRAY['like'::character varying, 'dislike'::character varying])::text[])))
);


--
-- Name: video_renditions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_renditions (
    video_rendition_id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    quality_label character varying(20) NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    bitrate_kbps integer,
    codec character varying(30),
    file_url character varying(2048) NOT NULL,
    file_size bigint NOT NULL,
    status character varying(20) DEFAULT 'processing'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_video_renditions_bitrate CHECK (((bitrate_kbps IS NULL) OR (bitrate_kbps > 0))),
    CONSTRAINT ck_video_renditions_dimensions CHECK (((width > 0) AND (height > 0))),
    CONSTRAINT ck_video_renditions_file_size CHECK ((file_size > 0)),
    CONSTRAINT ck_video_renditions_quality CHECK ((char_length(btrim((quality_label)::text)) > 0)),
    CONSTRAINT ck_video_renditions_status CHECK (((status)::text = ANY ((ARRAY['processing'::character varying, 'ready'::character varying, 'failed'::character varying, 'deleted'::character varying])::text[]))),
    CONSTRAINT ck_video_renditions_url CHECK ((char_length(btrim((file_url)::text)) > 0))
);


--
-- Name: video_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_tags (
    video_tag_id uuid DEFAULT gen_random_uuid() NOT NULL,
    video_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.videos (
    video_id uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id uuid NOT NULL,
    category_id uuid,
    title character varying(200) NOT NULL,
    description text,
    video_url character varying(2048) NOT NULL,
    thumbnail_url character varying(2048),
    duration integer NOT NULL,
    file_size bigint NOT NULL,
    visibility character varying(20) DEFAULT 'public'::character varying NOT NULL,
    status character varying(20) DEFAULT 'processing'::character varying NOT NULL,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    language_code character varying(10),
    age_restricted boolean DEFAULT false NOT NULL,
    moderation_status character varying(20) DEFAULT 'not_submitted'::character varying NOT NULL,
    scheduled_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    uploaded_by_user_id uuid NOT NULL,
    idempotency_key character varying(128),
    admin_original_status character varying(20),
    admin_original_visibility character varying(20),
    admin_original_moderation_status character varying(30),
    moderation_reason text,
    media_retention_until timestamp with time zone,
    media_purged_at timestamp with time zone,
    allow_comments boolean DEFAULT true NOT NULL,
    moderation_hidden boolean DEFAULT false NOT NULL,
    moderation_age_restricted boolean DEFAULT false NOT NULL,
    recommendation_restricted boolean DEFAULT false NOT NULL,
    media_purge_started_at timestamp with time zone,
    CONSTRAINT ck_videos_duration CHECK ((duration > 0)),
    CONSTRAINT ck_videos_file_size CHECK ((file_size > 0)),
    CONSTRAINT ck_videos_published_at CHECK ((((status)::text <> 'published'::text) OR (published_at IS NOT NULL))),
    CONSTRAINT ck_videos_status CHECK (((status)::text = ANY ((ARRAY['uploading'::character varying, 'processing'::character varying, 'published'::character varying, 'blocked'::character varying, 'deleted'::character varying, 'failed'::character varying])::text[]))),
    CONSTRAINT ck_videos_title CHECK ((char_length(btrim((title)::text)) > 0)),
    CONSTRAINT ck_videos_url CHECK ((char_length(btrim((video_url)::text)) > 0)),
    CONSTRAINT ck_videos_visibility CHECK (((visibility)::text = ANY ((ARRAY['public'::character varying, 'unlisted'::character varying, 'private'::character varying, 'members'::character varying])::text[])))
);


--
-- Name: viewing_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.viewing_histories (
    viewing_history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    video_id uuid NOT NULL,
    viewed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    watch_duration integer DEFAULT 0 NOT NULL,
    progress numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT ck_viewing_histories_duration CHECK ((watch_duration >= 0)),
    CONSTRAINT ck_viewing_histories_progress CHECK (((progress >= (0)::numeric) AND (progress <= (100)::numeric)))
);


--
-- Name: violation_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.violation_types (
    violation_type_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(150) NOT NULL,
    description text,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_violation_types_code CHECK ((char_length(btrim((code)::text)) > 0)),
    CONSTRAINT ck_violation_types_name CHECK ((char_length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_violation_types_status CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])))
);


--
-- Name: __EFMigrationsHistory PK___EFMigrationsHistory; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."__EFMigrationsHistory"
    ADD CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId");


--
-- Name: login_history PK_login_history; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT "PK_login_history" PRIMARY KEY (login_history_id);


--
-- Name: recommendation_jobs PK_recommendation_jobs; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_jobs
    ADD CONSTRAINT "PK_recommendation_jobs" PRIMARY KEY (job_id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (audit_log_id);


--
-- Name: channel_comment_moderators channel_comment_moderators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_comment_moderators
    ADD CONSTRAINT channel_comment_moderators_pkey PRIMARY KEY (channel_comment_moderator_id);


--
-- Name: channel_invitations channel_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_invitations
    ADD CONSTRAINT channel_invitations_pkey PRIMARY KEY (channel_invitation_id);


--
-- Name: channel_members channel_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_members
    ADD CONSTRAINT channel_members_pkey PRIMARY KEY (channel_member_id);


--
-- Name: channel_strikes channel_strikes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_pkey PRIMARY KEY (strike_id);


--
-- Name: comment_moderation_actions comment_moderation_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_moderation_actions
    ADD CONSTRAINT comment_moderation_actions_pkey PRIMARY KEY (comment_moderation_action_id);


--
-- Name: moderation_cases moderation_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_cases
    ADD CONSTRAINT moderation_cases_pkey PRIMARY KEY (moderation_case_id);


--
-- Name: appeals pk_appeals; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT pk_appeals PRIMARY KEY (appeal_id);


--
-- Name: categories pk_categories; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT pk_categories PRIMARY KEY (category_id);


--
-- Name: channel_actions pk_channel_actions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_actions
    ADD CONSTRAINT pk_channel_actions PRIMARY KEY (channel_action_id);


--
-- Name: channel_quotas pk_channel_quotas; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_quotas
    ADD CONSTRAINT pk_channel_quotas PRIMARY KEY (channel_quota_id);


--
-- Name: channels pk_channels; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT pk_channels PRIMARY KEY (channel_id);


--
-- Name: comment_reactions pk_comment_reactions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT pk_comment_reactions PRIMARY KEY (comment_reaction_id);


--
-- Name: comments pk_comments; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT pk_comments PRIMARY KEY (comment_id);


--
-- Name: notification_settings pk_notification_settings; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_settings
    ADD CONSTRAINT pk_notification_settings PRIMARY KEY (notification_setting_id);


--
-- Name: notifications pk_notifications; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT pk_notifications PRIMARY KEY (notification_id);


--
-- Name: payments pk_payments; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT pk_payments PRIMARY KEY (payment_id);


--
-- Name: permissions pk_permissions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT pk_permissions PRIMARY KEY (permission_id);


--
-- Name: plan_histories pk_plan_histories; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_histories
    ADD CONSTRAINT pk_plan_histories PRIMARY KEY (plan_history_id);


--
-- Name: plans pk_plans; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT pk_plans PRIMARY KEY (plan_id);


--
-- Name: playlist_videos pk_playlist_videos; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT pk_playlist_videos PRIMARY KEY (playlist_video_id);


--
-- Name: playlists pk_playlists; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT pk_playlists PRIMARY KEY (playlist_id);


--
-- Name: recommendation_items pk_recommendation_items; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_items
    ADD CONSTRAINT pk_recommendation_items PRIMARY KEY (recommendation_item_id);


--
-- Name: recommendations pk_recommendations; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendations
    ADD CONSTRAINT pk_recommendations PRIMARY KEY (recommendation_id);


--
-- Name: refresh_tokens pk_refresh_tokens; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT pk_refresh_tokens PRIMARY KEY (refresh_token_id);


--
-- Name: report_resolutions pk_report_resolutions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_resolutions
    ADD CONSTRAINT pk_report_resolutions PRIMARY KEY (resolution_id);


--
-- Name: reports pk_reports; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT pk_reports PRIMARY KEY (report_id);


--
-- Name: resolution_types pk_resolution_types; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resolution_types
    ADD CONSTRAINT pk_resolution_types PRIMARY KEY (resolution_type_id);


--
-- Name: role_permissions pk_role_permissions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT pk_role_permissions PRIMARY KEY (role_permission_id);


--
-- Name: roles pk_roles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT pk_roles PRIMARY KEY (role_id);


--
-- Name: search_histories pk_search_histories; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_histories
    ADD CONSTRAINT pk_search_histories PRIMARY KEY (search_history_id);


--
-- Name: share_histories pk_share_histories; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.share_histories
    ADD CONSTRAINT pk_share_histories PRIMARY KEY (share_history_id);


--
-- Name: subscriptions pk_subscriptions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT pk_subscriptions PRIMARY KEY (subscription_id);


--
-- Name: tags pk_tags; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT pk_tags PRIMARY KEY (tag_id);


--
-- Name: user_permissions pk_user_permissions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT pk_user_permissions PRIMARY KEY (user_permission_id);


--
-- Name: users pk_users; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users PRIMARY KEY (user_id);


--
-- Name: video_reactions pk_video_reactions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_reactions
    ADD CONSTRAINT pk_video_reactions PRIMARY KEY (video_reaction_id);


--
-- Name: video_renditions pk_video_renditions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_renditions
    ADD CONSTRAINT pk_video_renditions PRIMARY KEY (video_rendition_id);


--
-- Name: video_tags pk_video_tags; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_tags
    ADD CONSTRAINT pk_video_tags PRIMARY KEY (video_tag_id);


--
-- Name: videos pk_videos; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT pk_videos PRIMARY KEY (video_id);


--
-- Name: viewing_histories pk_viewing_histories; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.viewing_histories
    ADD CONSTRAINT pk_viewing_histories PRIMARY KEY (viewing_history_id);


--
-- Name: violation_types pk_violation_types; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.violation_types
    ADD CONSTRAINT pk_violation_types PRIMARY KEY (violation_type_id);


--
-- Name: plan_invitation_tokens plan_invitation_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_invitation_tokens
    ADD CONSTRAINT plan_invitation_tokens_pkey PRIMARY KEY (plan_invitation_token_id);


--
-- Name: plan_members plan_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_members
    ADD CONSTRAINT plan_members_pkey PRIMARY KEY (plan_member_id);


--
-- Name: policies policies_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policies
    ADD CONSTRAINT policies_code_key UNIQUE (code);


--
-- Name: policies policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policies
    ADD CONSTRAINT policies_pkey PRIMARY KEY (policy_id);


--
-- Name: appeals uq_appeals_attempt; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT uq_appeals_attempt UNIQUE (user_id, resolution_id, appeal_number);


--
-- Name: channel_comment_moderators uq_channel_comment_moderators; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_comment_moderators
    ADD CONSTRAINT uq_channel_comment_moderators UNIQUE (channel_id, user_id);


--
-- Name: channel_members uq_channel_members; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_members
    ADD CONSTRAINT uq_channel_members UNIQUE (channel_id, user_id);


--
-- Name: channel_quotas uq_channel_quotas_channel; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_quotas
    ADD CONSTRAINT uq_channel_quotas_channel UNIQUE (channel_id);


--
-- Name: comment_reactions uq_comment_reactions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT uq_comment_reactions UNIQUE (user_id, comment_id);


--
-- Name: notification_settings uq_notification_settings_user; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_settings
    ADD CONSTRAINT uq_notification_settings_user UNIQUE (user_id);


--
-- Name: payments uq_payments_transaction; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uq_payments_transaction UNIQUE (transaction_code);


--
-- Name: playlist_videos uq_playlist_videos_position; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT uq_playlist_videos_position UNIQUE (playlist_id, "position");


--
-- Name: playlist_videos uq_playlist_videos_video; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT uq_playlist_videos_video UNIQUE (playlist_id, video_id);


--
-- Name: recommendation_items uq_recommendation_items_rank; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_items
    ADD CONSTRAINT uq_recommendation_items_rank UNIQUE (recommendation_id, rank);


--
-- Name: recommendation_items uq_recommendation_items_video; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_items
    ADD CONSTRAINT uq_recommendation_items_video UNIQUE (recommendation_id, video_id);


--
-- Name: refresh_tokens uq_refresh_tokens_hash; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash);


--
-- Name: refresh_tokens uq_refresh_tokens_jti; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT uq_refresh_tokens_jti UNIQUE (jti);


--
-- Name: report_resolutions uq_report_resolutions_report; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_resolutions
    ADD CONSTRAINT uq_report_resolutions_report UNIQUE (report_id);


--
-- Name: role_permissions uq_role_permissions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT uq_role_permissions UNIQUE (role_id, permission_id);


--
-- Name: subscriptions uq_subscriptions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT uq_subscriptions UNIQUE (user_id, channel_id);


--
-- Name: user_permissions uq_user_permissions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT uq_user_permissions UNIQUE (user_id, permission_id);


--
-- Name: video_downloads uq_video_downloads_user_video_quality; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_downloads
    ADD CONSTRAINT uq_video_downloads_user_video_quality UNIQUE (user_id, video_id, quality_label);


--
-- Name: video_ratings uq_video_ratings; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_ratings
    ADD CONSTRAINT uq_video_ratings UNIQUE (user_id, video_id);


--
-- Name: video_reactions uq_video_reactions; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_reactions
    ADD CONSTRAINT uq_video_reactions UNIQUE (user_id, video_id);


--
-- Name: video_renditions uq_video_renditions_quality; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_renditions
    ADD CONSTRAINT uq_video_renditions_quality UNIQUE (video_id, quality_label);


--
-- Name: video_tags uq_video_tags; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_tags
    ADD CONSTRAINT uq_video_tags UNIQUE (video_id, tag_id);


--
-- Name: video_downloads video_downloads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_downloads
    ADD CONSTRAINT video_downloads_pkey PRIMARY KEY (video_download_id);


--
-- Name: video_ratings video_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_ratings
    ADD CONSTRAINT video_ratings_pkey PRIMARY KEY (video_rating_id);


--
-- Name: IX_recommendation_jobs_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IX_recommendation_jobs_status_created_at" ON public.recommendation_jobs USING btree (status, created_at);


--
-- Name: ix_appeals_target_status_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_appeals_target_status_time ON public.appeals USING btree (target_type, target_id, status, created_at DESC);


--
-- Name: ix_audit_logs_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_resource ON public.audit_logs USING btree (resource_type, resource_id, created_at DESC);


--
-- Name: ix_channel_strikes_channel_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_channel_strikes_channel_status ON public.channel_strikes USING btree (channel_id, status);


--
-- Name: ix_channel_strikes_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_channel_strikes_user_status ON public.channel_strikes USING btree (user_id, status);


--
-- Name: ix_channels_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_channels_name_trgm ON public.channels USING gin (name public.gin_trgm_ops);


--
-- Name: ix_comment_reactions_comment_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_comment_reactions_comment_type ON public.comment_reactions USING btree (comment_id, type);


--
-- Name: ix_comments_parent_status_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_comments_parent_status_time ON public.comments USING btree (parent_comment_id, status, created_at);


--
-- Name: ix_comments_video_status_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_comments_video_status_time ON public.comments USING btree (video_id, status, created_at DESC);


--
-- Name: ix_comments_video_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_comments_video_time ON public.comments USING btree (video_id, created_at DESC);


--
-- Name: ix_login_history_user_id_login_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_login_history_user_id_login_at ON public.login_history USING btree (user_id, login_at DESC);


--
-- Name: ix_moderation_cases_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_moderation_cases_queue ON public.moderation_cases USING btree (status, submitted_at);


--
-- Name: ix_moderation_cases_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_moderation_cases_target ON public.moderation_cases USING btree (target_type, target_id, status);


--
-- Name: ix_moderation_cases_target_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_moderation_cases_target_status ON public.moderation_cases USING btree (target_type, target_id, status);


--
-- Name: ix_moderation_cases_video_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_moderation_cases_video_status ON public.moderation_cases USING btree (video_id, status, submitted_at DESC) WHERE (video_id IS NOT NULL);


--
-- Name: ix_notifications_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_user_unread ON public.notifications USING btree (user_id, created_at DESC) WHERE (is_read = false);


--
-- Name: ix_playlists_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_playlists_status ON public.playlists USING btree (status);


--
-- Name: ix_policies_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_policies_code ON public.policies USING btree (code);


--
-- Name: ix_policies_group_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_policies_group_status ON public.policies USING btree ("group", status);


--
-- Name: ix_refresh_tokens_user_platform_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_tokens_user_platform_device ON public.refresh_tokens USING btree (user_id, platform, device_id) WHERE (revoked_at IS NULL);


--
-- Name: ix_reports_moderation_case; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reports_moderation_case ON public.reports USING btree (moderation_case_id);


--
-- Name: ix_reports_status_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reports_status_time ON public.reports USING btree (status, created_at);


--
-- Name: ix_reports_video; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_reports_video ON public.reports USING btree (video_id, created_at DESC) WHERE (video_id IS NOT NULL);


--
-- Name: ix_search_histories_user_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_search_histories_user_time ON public.search_histories USING btree (user_id, searched_at DESC);


--
-- Name: ix_share_histories_video_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_share_histories_video_time ON public.share_histories USING btree (video_id, shared_at DESC);


--
-- Name: ix_subscriptions_channel_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subscriptions_channel_active ON public.subscriptions USING btree (channel_id, user_id) WHERE ((status)::text = 'active'::text);


--
-- Name: ix_tags_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tags_name_trgm ON public.tags USING gin (name public.gin_trgm_ops);


--
-- Name: ix_video_downloads_user_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_video_downloads_user_time ON public.video_downloads USING btree (user_id, created_at DESC);


--
-- Name: ix_video_ratings_video_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_video_ratings_video_score ON public.video_ratings USING btree (video_id, score);


--
-- Name: ix_video_reactions_video_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_video_reactions_video_type ON public.video_reactions USING btree (video_id, type);


--
-- Name: ix_video_tags_tag_video; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_video_tags_tag_video ON public.video_tags USING btree (tag_id, video_id);


--
-- Name: ix_videos_channel_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_channel_time ON public.videos USING btree (channel_id, created_at DESC);


--
-- Name: ix_videos_description_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_description_trgm ON public.videos USING gin (description public.gin_trgm_ops);


--
-- Name: ix_videos_moderation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_moderation ON public.videos USING btree (moderation_status, created_at);


--
-- Name: ix_videos_public_category_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_public_category_published ON public.videos USING btree (category_id, published_at DESC) WHERE (((status)::text = 'published'::text) AND ((moderation_status)::text = 'approved'::text) AND ((visibility)::text = 'public'::text));


--
-- Name: ix_videos_public_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_public_published ON public.videos USING btree (published_at DESC) WHERE (((status)::text = 'published'::text) AND ((moderation_status)::text = 'approved'::text) AND ((visibility)::text = 'public'::text));


--
-- Name: ix_videos_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_videos_title_trgm ON public.videos USING gin (title public.gin_trgm_ops);


--
-- Name: ix_viewing_histories_user_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_viewing_histories_user_time ON public.viewing_histories USING btree (user_id, viewed_at DESC);


--
-- Name: ix_viewing_histories_user_video_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_viewing_histories_user_video_time ON public.viewing_histories USING btree (user_id, video_id, viewed_at DESC);


--
-- Name: ix_viewing_histories_video_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_viewing_histories_video_time ON public.viewing_histories USING btree (video_id, viewed_at DESC);


--
-- Name: ux_categories_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_categories_slug ON public.categories USING btree (slug);


--
-- Name: ux_channel_invitations_pending_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_channel_invitations_pending_email ON public.channel_invitations USING btree (channel_id, lower((invited_email)::text)) WHERE (((status)::text = 'pending'::text) AND (invited_email IS NOT NULL));


--
-- Name: ux_channels_handle_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_channels_handle_ci ON public.channels USING btree (lower((handle)::text));


--
-- Name: ux_moderation_cases_report_target; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_moderation_cases_report_target ON public.moderation_cases USING btree (case_type, target_type, target_id) WHERE ((case_type)::text = 'report_case'::text);


--
-- Name: ux_payments_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_payments_idempotency ON public.payments USING btree (user_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: ux_payments_sepay_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_payments_sepay_id ON public.payments USING btree (sepay_transaction_id) WHERE (sepay_transaction_id IS NOT NULL);


--
-- Name: ux_permissions_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_permissions_code ON public.permissions USING btree (code);


--
-- Name: ux_plan_invitation_tokens_member; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_plan_invitation_tokens_member ON public.plan_invitation_tokens USING btree (plan_member_id);


--
-- Name: ux_plan_members_active_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_plan_members_active_email ON public.plan_members USING btree (plan_history_id, lower((member_email)::text)) WHERE ((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying])::text[]));


--
-- Name: ux_plans_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_plans_code ON public.plans USING btree (code);


--
-- Name: ux_recommendation_model_job_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_recommendation_model_job_active ON public.recommendation_jobs USING btree (kind) WHERE ((kind = 'model_update'::text) AND (status = ANY (ARRAY['queued'::text, 'running'::text])));


--
-- Name: ux_reports_user_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_reports_user_idempotency ON public.reports USING btree (user_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: ux_roles_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_roles_code ON public.roles USING btree (code);


--
-- Name: ux_tags_name_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_tags_name_ci ON public.tags USING btree (lower((name)::text));


--
-- Name: ux_users_email_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_email_ci ON public.users USING btree (lower((email)::text));


--
-- Name: ux_users_google_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_google_subject ON public.users USING btree (google_subject) WHERE (google_subject IS NOT NULL);


--
-- Name: ux_users_username_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_users_username_ci ON public.users USING btree (lower((username)::text));


--
-- Name: ux_videos_channel_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_videos_channel_idempotency ON public.videos USING btree (channel_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: login_history FK_login_history_users_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_history
    ADD CONSTRAINT "FK_login_history_users_user_id" FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: appeals appeals_moderation_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT appeals_moderation_case_id_fkey FOREIGN KEY (moderation_case_id) REFERENCES public.moderation_cases(moderation_case_id);


--
-- Name: appeals appeals_strike_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT appeals_strike_id_fkey FOREIGN KEY (strike_id) REFERENCES public.channel_strikes(strike_id);


--
-- Name: audit_logs audit_logs_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: channel_comment_moderators channel_comment_moderators_appointed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_comment_moderators
    ADD CONSTRAINT channel_comment_moderators_appointed_by_user_id_fkey FOREIGN KEY (appointed_by_user_id) REFERENCES public.users(user_id);


--
-- Name: channel_comment_moderators channel_comment_moderators_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_comment_moderators
    ADD CONSTRAINT channel_comment_moderators_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channel_comment_moderators channel_comment_moderators_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_comment_moderators
    ADD CONSTRAINT channel_comment_moderators_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: channel_invitations channel_invitations_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_invitations
    ADD CONSTRAINT channel_invitations_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channel_invitations channel_invitations_invited_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_invitations
    ADD CONSTRAINT channel_invitations_invited_by_user_id_fkey FOREIGN KEY (invited_by_user_id) REFERENCES public.users(user_id);


--
-- Name: channel_invitations channel_invitations_invited_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_invitations
    ADD CONSTRAINT channel_invitations_invited_user_id_fkey FOREIGN KEY (invited_user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: channel_members channel_members_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_members
    ADD CONSTRAINT channel_members_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channel_members channel_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_members
    ADD CONSTRAINT channel_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: channel_strikes channel_strikes_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channel_strikes channel_strikes_revoked_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_revoked_by_user_id_fkey FOREIGN KEY (revoked_by_user_id) REFERENCES public.users(user_id);


--
-- Name: channel_strikes channel_strikes_source_moderation_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_source_moderation_case_id_fkey FOREIGN KEY (source_moderation_case_id) REFERENCES public.moderation_cases(moderation_case_id);


--
-- Name: channel_strikes channel_strikes_source_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_source_report_id_fkey FOREIGN KEY (source_report_id) REFERENCES public.reports(report_id);


--
-- Name: channel_strikes channel_strikes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_strikes
    ADD CONSTRAINT channel_strikes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: comment_moderation_actions comment_moderation_actions_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_moderation_actions
    ADD CONSTRAINT comment_moderation_actions_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(comment_id) ON DELETE CASCADE;


--
-- Name: comment_moderation_actions comment_moderation_actions_moderator_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_moderation_actions
    ADD CONSTRAINT comment_moderation_actions_moderator_user_id_fkey FOREIGN KEY (moderator_user_id) REFERENCES public.users(user_id);


--
-- Name: appeals fk_appeals_resolution; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT fk_appeals_resolution FOREIGN KEY (resolution_id) REFERENCES public.report_resolutions(resolution_id) ON DELETE CASCADE;


--
-- Name: appeals fk_appeals_reviewer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT fk_appeals_reviewer FOREIGN KEY (reviewer_id) REFERENCES public.users(user_id);


--
-- Name: appeals fk_appeals_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appeals
    ADD CONSTRAINT fk_appeals_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: channel_actions fk_channel_actions_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_actions
    ADD CONSTRAINT fk_channel_actions_channel FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channel_actions fk_channel_actions_moderator; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_actions
    ADD CONSTRAINT fk_channel_actions_moderator FOREIGN KEY (moderator_id) REFERENCES public.users(user_id);


--
-- Name: channel_quotas fk_channel_quotas_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_quotas
    ADD CONSTRAINT fk_channel_quotas_channel FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: channels fk_channels_owner; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT fk_channels_owner FOREIGN KEY (owner_user_id) REFERENCES public.users(user_id);


--
-- Name: comment_reactions fk_comment_reactions_comment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT fk_comment_reactions_comment FOREIGN KEY (comment_id) REFERENCES public.comments(comment_id) ON DELETE CASCADE;


--
-- Name: comment_reactions fk_comment_reactions_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reactions
    ADD CONSTRAINT fk_comment_reactions_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: comments fk_comments_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id) REFERENCES public.comments(comment_id);


--
-- Name: comments fk_comments_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: comments fk_comments_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT fk_comments_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: notification_settings fk_notification_settings_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_settings
    ADD CONSTRAINT fk_notification_settings_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: notifications fk_notifications_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: payments fk_payments_history; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_history FOREIGN KEY (plan_history_id) REFERENCES public.plan_histories(plan_history_id) ON DELETE SET NULL;


--
-- Name: payments fk_payments_plan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_plan FOREIGN KEY (plan_id) REFERENCES public.plans(plan_id);


--
-- Name: payments fk_payments_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: plan_histories fk_plan_histories_plan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_histories
    ADD CONSTRAINT fk_plan_histories_plan FOREIGN KEY (plan_id) REFERENCES public.plans(plan_id);


--
-- Name: plan_histories fk_plan_histories_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_histories
    ADD CONSTRAINT fk_plan_histories_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: playlist_videos fk_playlist_videos_playlist; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT fk_playlist_videos_playlist FOREIGN KEY (playlist_id) REFERENCES public.playlists(playlist_id) ON DELETE CASCADE;


--
-- Name: playlist_videos fk_playlist_videos_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlist_videos
    ADD CONSTRAINT fk_playlist_videos_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: playlists fk_playlists_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT fk_playlists_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: recommendation_items fk_recommendation_items_recommendation; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_items
    ADD CONSTRAINT fk_recommendation_items_recommendation FOREIGN KEY (recommendation_id) REFERENCES public.recommendations(recommendation_id) ON DELETE CASCADE;


--
-- Name: recommendation_items fk_recommendation_items_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendation_items
    ADD CONSTRAINT fk_recommendation_items_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: recommendations fk_recommendations_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recommendations
    ADD CONSTRAINT fk_recommendations_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: refresh_tokens fk_refresh_tokens_replaced; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_replaced FOREIGN KEY (replaced_by_token_id) REFERENCES public.refresh_tokens(refresh_token_id);


--
-- Name: refresh_tokens fk_refresh_tokens_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: report_resolutions fk_report_resolutions_report; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_resolutions
    ADD CONSTRAINT fk_report_resolutions_report FOREIGN KEY (report_id) REFERENCES public.reports(report_id) ON DELETE CASCADE;


--
-- Name: report_resolutions fk_report_resolutions_resolver; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_resolutions
    ADD CONSTRAINT fk_report_resolutions_resolver FOREIGN KEY (resolver_id) REFERENCES public.users(user_id);


--
-- Name: report_resolutions fk_report_resolutions_type; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_resolutions
    ADD CONSTRAINT fk_report_resolutions_type FOREIGN KEY (resolution_type_id) REFERENCES public.resolution_types(resolution_type_id);


--
-- Name: reports fk_reports_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_channel FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id);


--
-- Name: reports fk_reports_comment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_comment FOREIGN KEY (comment_id) REFERENCES public.comments(comment_id);


--
-- Name: reports fk_reports_moderation_case; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_moderation_case FOREIGN KEY (moderation_case_id) REFERENCES public.moderation_cases(moderation_case_id) ON DELETE SET NULL;


--
-- Name: reports fk_reports_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: reports fk_reports_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id);


--
-- Name: reports fk_reports_violation_type; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_reports_violation_type FOREIGN KEY (violation_type_id) REFERENCES public.violation_types(violation_type_id);


--
-- Name: role_permissions fk_role_permissions_permission; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: role_permissions fk_role_permissions_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: search_histories fk_search_histories_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_histories
    ADD CONSTRAINT fk_search_histories_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: share_histories fk_share_histories_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.share_histories
    ADD CONSTRAINT fk_share_histories_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: share_histories fk_share_histories_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.share_histories
    ADD CONSTRAINT fk_share_histories_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: subscriptions fk_subscriptions_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_subscriptions_channel FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: subscriptions fk_subscriptions_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: user_permissions fk_user_permissions_permission; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT fk_user_permissions_permission FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id) ON DELETE CASCADE;


--
-- Name: user_permissions fk_user_permissions_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT fk_user_permissions_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: users fk_users_plan; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_plan FOREIGN KEY (plan_id) REFERENCES public.plans(plan_id) ON DELETE SET NULL;


--
-- Name: users fk_users_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES public.roles(role_id);


--
-- Name: video_reactions fk_video_reactions_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_reactions
    ADD CONSTRAINT fk_video_reactions_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: video_reactions fk_video_reactions_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_reactions
    ADD CONSTRAINT fk_video_reactions_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: video_renditions fk_video_renditions_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_renditions
    ADD CONSTRAINT fk_video_renditions_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: video_tags fk_video_tags_tag; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_tags
    ADD CONSTRAINT fk_video_tags_tag FOREIGN KEY (tag_id) REFERENCES public.tags(tag_id) ON DELETE CASCADE;


--
-- Name: video_tags fk_video_tags_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_tags
    ADD CONSTRAINT fk_video_tags_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: videos fk_videos_category; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT fk_videos_category FOREIGN KEY (category_id) REFERENCES public.categories(category_id) ON DELETE SET NULL;


--
-- Name: videos fk_videos_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT fk_videos_channel FOREIGN KEY (channel_id) REFERENCES public.channels(channel_id) ON DELETE CASCADE;


--
-- Name: videos fk_videos_uploaded_by_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.videos
    ADD CONSTRAINT fk_videos_uploaded_by_user FOREIGN KEY (uploaded_by_user_id) REFERENCES public.users(user_id) ON DELETE RESTRICT;


--
-- Name: viewing_histories fk_viewing_histories_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.viewing_histories
    ADD CONSTRAINT fk_viewing_histories_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: viewing_histories fk_viewing_histories_video; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.viewing_histories
    ADD CONSTRAINT fk_viewing_histories_video FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: moderation_cases moderation_cases_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_cases
    ADD CONSTRAINT moderation_cases_report_id_fkey FOREIGN KEY (report_id) REFERENCES public.reports(report_id);


--
-- Name: moderation_cases moderation_cases_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_cases
    ADD CONSTRAINT moderation_cases_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.users(user_id);


--
-- Name: moderation_cases moderation_cases_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_cases
    ADD CONSTRAINT moderation_cases_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.videos(video_id);


--
-- Name: plan_invitation_tokens plan_invitation_tokens_plan_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_invitation_tokens
    ADD CONSTRAINT plan_invitation_tokens_plan_member_id_fkey FOREIGN KEY (plan_member_id) REFERENCES public.plan_members(plan_member_id) ON DELETE CASCADE;


--
-- Name: plan_members plan_members_member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_members
    ADD CONSTRAINT plan_members_member_user_id_fkey FOREIGN KEY (member_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: plan_members plan_members_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_members
    ADD CONSTRAINT plan_members_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: plan_members plan_members_plan_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_members
    ADD CONSTRAINT plan_members_plan_history_id_fkey FOREIGN KEY (plan_history_id) REFERENCES public.plan_histories(plan_history_id) ON DELETE CASCADE;


--
-- Name: reports reports_disposition_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_disposition_by_user_id_fkey FOREIGN KEY (disposition_by_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: video_downloads video_downloads_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_downloads
    ADD CONSTRAINT video_downloads_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: video_downloads video_downloads_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_downloads
    ADD CONSTRAINT video_downloads_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- Name: video_ratings video_ratings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_ratings
    ADD CONSTRAINT video_ratings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: video_ratings video_ratings_video_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_ratings
    ADD CONSTRAINT video_ratings_video_id_fkey FOREIGN KEY (video_id) REFERENCES public.videos(video_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict MPJkUmrjDYS0XmfdoPhPQhUAuQj4PeMW1bq3Ci13jaAWh2jVk0QW4VLZUQdiwS0

