using System.ComponentModel.DataAnnotations;

namespace HuTube.Application.Channels;

public sealed record CreateChannelRequest(
    [Required, StringLength(100, MinimumLength = 1)] string Name,
    [Required, RegularExpression(@"^@?[a-zA-Z0-9_.-]{3,50}$")] string Handle,
    [StringLength(1000)] string? Description,
    [StringLength(2048)] string? AvatarUrl = null,
    [StringLength(2048)] string? BannerUrl = null,
    [EmailAddress, StringLength(254)] string? ContactEmail = null);

public sealed record UpdateChannelRequest(
    [StringLength(100, MinimumLength = 1)] string? Name,
    [StringLength(1000)] string? Description,
    [StringLength(2048)] string? AvatarUrl,
    [StringLength(2048)] string? BannerUrl,
    [RegularExpression(@"^@?[a-zA-Z0-9_.-]{3,50}$")] string? Handle = null,
    [EmailAddress, StringLength(254)] string? ContactEmail = null,
    [StringLength(2048)] string? WatermarkUrl = null,
    string? Settings = null);

public sealed record ChannelResponse(
    Guid ChannelId,
    Guid OwnerUserId,
    string Name,
    string Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string? ContactEmail,
    string? WatermarkUrl,
    string Settings,
    string Status,
    long SubscriberCount,
    long VideoCount,
    bool IsOwner,
    string? MyRole,
    IReadOnlyList<string> Permissions,
    DateTimeOffset CreatedAt);

public sealed record CheckHandleResponse(
    string Handle,
    bool IsAvailable,
    string Message);

public sealed record InviteMemberRequest(
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required] string RoleCode);

public sealed record ChangeMemberRoleRequest([Required] string RoleCode);

public sealed record ChannelMemberResponse(
    Guid ChannelMemberId,
    Guid ChannelId,
    Guid UserId,
    string Username,
    string Email,
    string DisplayName,
    string? AvatarUrl,
    string RoleCode,
    IReadOnlyList<string> Permissions,
    string Status,
    DateTimeOffset JoinedAt);

public sealed record ChannelInvitationResponse(
    Guid ChannelInvitationId,
    Guid ChannelId,
    string ChannelName,
    string ChannelHandle,
    Guid? InvitedUserId,
    string? InvitedEmail,
    Guid InvitedByUserId,
    string RoleCode,
    IReadOnlyList<string> Permissions,
    string Status,
    DateTimeOffset ExpiresAt,
    DateTimeOffset CreatedAt);

public sealed record ChannelRoleResponse(
    string Code,
    string Name,
    string Description,
    IReadOnlyList<string> Permissions);

public sealed record SubscriptionResponse(
    Guid SubscriptionId,
    Guid ChannelId,
    Guid UserId,
    DateTimeOffset SubscribedAt,
    bool NotificationsEnabled,
    string Status);

public sealed record SubscribedChannelResponse(
    Guid ChannelId,
    string Name,
    string Handle,
    string? AvatarUrl,
    long SubscriberCount,
    DateTimeOffset SubscribedAt);

public sealed class ChannelException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}
