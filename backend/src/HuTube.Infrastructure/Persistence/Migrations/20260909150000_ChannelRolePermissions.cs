using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260909150000_ChannelRolePermissions")]
public sealed class ChannelRolePermissions : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.channel_invitations
        SET role_code = 'moderator'
        WHERE role_code = 'comment_moderator';

        ALTER TABLE public.channel_members DROP CONSTRAINT IF EXISTS ck_channel_members_role;
        ALTER TABLE public.channel_members
          ADD CONSTRAINT ck_channel_members_role
          CHECK (role_code IN ('manager', 'editor', 'moderator', 'viewer'));

        ALTER TABLE public.channel_invitations DROP CONSTRAINT IF EXISTS ck_channel_invitations_role;
        ALTER TABLE public.channel_invitations
          ADD CONSTRAINT ck_channel_invitations_role
          CHECK (role_code IN ('manager', 'editor', 'moderator', 'viewer'));

        CREATE UNIQUE INDEX IF NOT EXISTS ux_channel_invitations_pending_email
          ON public.channel_invitations(channel_id, lower(invited_email::text))
          WHERE status = 'pending' AND invited_email IS NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS public.ux_channel_invitations_pending_email;

        UPDATE public.channel_members
        SET role_code = 'viewer'
        WHERE role_code = 'moderator';

        UPDATE public.channel_invitations
        SET role_code = 'comment_moderator'
        WHERE role_code = 'moderator';

        ALTER TABLE public.channel_members DROP CONSTRAINT IF EXISTS ck_channel_members_role;
        ALTER TABLE public.channel_members
          ADD CONSTRAINT ck_channel_members_role
          CHECK (role_code IN ('manager', 'editor', 'viewer'));

        ALTER TABLE public.channel_invitations DROP CONSTRAINT IF EXISTS ck_channel_invitations_role;
        ALTER TABLE public.channel_invitations
          ADD CONSTRAINT ck_channel_invitations_role
          CHECK (role_code IN ('manager', 'editor', 'viewer', 'comment_moderator'));
        """);
}
