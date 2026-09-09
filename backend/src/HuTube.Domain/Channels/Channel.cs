using System.Text.RegularExpressions;

namespace HuTube.Domain.Channels;

public static class ChannelRoles
{
    public const string Owner = "owner";
    public const string Manager = "manager";
    public const string Editor = "editor";
    public const string Moderator = "moderator";
    public const string Viewer = "viewer";

    public static readonly IReadOnlyList<string> AssignableMemberRoles = [Manager, Editor, Moderator, Viewer];
    public static readonly IReadOnlyList<string> AllRoles = [Owner, Manager, Editor, Moderator, Viewer];
}

public static class ChannelPermissions
{
    public const string ViewDashboard = "channel.view_dashboard";
    public const string EditProfile = "channel.edit_profile";
    public const string EditBranding = "channel.edit_branding";
    public const string VideoView = "video.view";
    public const string VideoUpload = "video.upload";
    public const string VideoEdit = "video.edit";
    public const string VideoDelete = "video.delete";
    public const string PlaylistManage = "playlist.manage";
    public const string CommentManage = "comment.manage";
    public const string AnalyticsView = "analytics.view";
    public const string CopyrightView = "copyright.view";
    public const string CopyrightSubmit = "copyright.submit";
    public const string MemberView = "member.view";
    public const string MemberInvite = "member.invite";
    public const string MemberChangeRole = "member.change_role";
    public const string MemberRemove = "member.remove";
    public const string SettingView = "channel.setting.view";
    public const string SettingEdit = "channel.setting.edit";
    public const string Delete = "channel.delete";

    public static readonly IReadOnlyList<string> All =
    [
        ViewDashboard, EditProfile, EditBranding,
        VideoView, VideoUpload, VideoEdit, VideoDelete,
        PlaylistManage, CommentManage, AnalyticsView,
        CopyrightView, CopyrightSubmit,
        MemberView, MemberInvite, MemberChangeRole, MemberRemove,
        SettingView, SettingEdit, Delete
    ];

    private static readonly IReadOnlyDictionary<string, IReadOnlySet<string>> ByRole =
        new Dictionary<string, IReadOnlySet<string>>(StringComparer.OrdinalIgnoreCase)
        {
            [ChannelRoles.Owner] = new HashSet<string>(All, StringComparer.OrdinalIgnoreCase),
            [ChannelRoles.Manager] = new HashSet<string>(
            [
                ViewDashboard, EditProfile, EditBranding,
                VideoView, VideoUpload, VideoEdit, VideoDelete,
                PlaylistManage, CommentManage, AnalyticsView,
                CopyrightView, CopyrightSubmit,
                MemberView, MemberInvite, MemberChangeRole, MemberRemove,
                SettingView, SettingEdit
            ], StringComparer.OrdinalIgnoreCase),
            [ChannelRoles.Editor] = new HashSet<string>(
            [
                ViewDashboard, VideoView, VideoUpload, VideoEdit,
                PlaylistManage, AnalyticsView, CopyrightView, MemberView
            ], StringComparer.OrdinalIgnoreCase),
            [ChannelRoles.Moderator] = new HashSet<string>(
            [ViewDashboard, CommentManage, MemberView], StringComparer.OrdinalIgnoreCase),
            [ChannelRoles.Viewer] = new HashSet<string>(
            [ViewDashboard, VideoView, CopyrightView, MemberView], StringComparer.OrdinalIgnoreCase)
        };

    public static IReadOnlyList<string> ForRole(string? roleCode) =>
        roleCode != null && ByRole.TryGetValue(roleCode, out var permissions)
            ? permissions.Order(StringComparer.Ordinal).ToArray()
            : [];

    public static bool RoleHas(string? roleCode, string permission) =>
        roleCode != null && ByRole.TryGetValue(roleCode, out var permissions) && permissions.Contains(permission);
}

public sealed class Channel
{
    private static readonly Regex HandlePattern = new(@"^[A-Za-z0-9_.-]{3,50}$", RegexOptions.Compiled);

    public Guid ChannelId { get; set; } = Guid.NewGuid();
    public Guid OwnerUserId { get; set; }
    public string Name { get; set; } = "";
    public string Handle { get; set; } = "";
    public string? Description { get; set; }
    public string? AvatarUrl { get; set; }
    public string? BannerUrl { get; set; }
    public string? ContactEmail { get; set; }
    public string? WatermarkUrl { get; set; }
    public string Settings { get; set; } = "{}";
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public bool IsActive => Status == "active";

    public static bool IsValidHandle(string? handle)
    {
        if (string.IsNullOrWhiteSpace(handle)) return false;
        var clean = handle.StartsWith('@') ? handle[1..] : handle;
        return HandlePattern.IsMatch(clean);
    }

    public static string NormalizeHandle(string handle)
    {
        var clean = handle.Trim();
        if (clean.StartsWith('@')) clean = clean[1..];
        return clean.ToLowerInvariant();
    }

    public void SoftDelete(DateTimeOffset now)
    {
        Status = "deleted";
        UpdatedAt = now;
    }
}

public sealed class ChannelMember
{
    public Guid ChannelMemberId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public Guid UserId { get; set; }
    public string RoleCode { get; set; } = ChannelRoles.Viewer;
    public string Status { get; set; } = "active";
    public DateTimeOffset JoinedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class ChannelInvitation
{
    public Guid ChannelInvitationId { get; set; } = Guid.NewGuid();
    public Guid ChannelId { get; set; }
    public Guid? InvitedUserId { get; set; }
    public string? InvitedEmail { get; set; }
    public Guid InvitedByUserId { get; set; }
    public string RoleCode { get; set; } = ChannelRoles.Viewer;
    public string? TokenHash { get; set; }
    public string Status { get; set; } = "pending";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RespondedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public bool IsPending(DateTimeOffset now) => Status == "pending" && ExpiresAt > now;
}
