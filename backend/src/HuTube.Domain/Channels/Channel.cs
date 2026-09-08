namespace HuTube.Domain.Channels;

public static class ChannelRoles
{
    public const string Owner = "owner";
    public const string Manager = "manager";
    public const string Editor = "editor";
    public const string Viewer = "viewer";
    public const string CommentModerator = "comment_moderator";

    public static readonly IReadOnlyList<string> AssignableMemberRoles = [Manager, Editor, Viewer];
    public static readonly IReadOnlyList<string> AllRoles = [Owner, Manager, Editor, Viewer, CommentModerator];
}

public sealed class Channel
{
    public Guid ChannelId { get; set; } = Guid.NewGuid();
    public Guid OwnerUserId { get; set; }
    public string Name { get; set; } = "";
    public string Handle { get; set; } = "";
    public string? Description { get; set; }
    public string? AvatarUrl { get; set; }
    public string? BannerUrl { get; set; }
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public bool IsActive => Status == "active";
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
