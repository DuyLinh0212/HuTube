using System.ComponentModel.DataAnnotations;
using HuTube.Domain.Channels;

namespace HuTube.Application.Channels;

public sealed record CreateChannelRequest(
    [Required, StringLength(100, MinimumLength = 1)] string Name,
    [Required, RegularExpression(@"^[a-zA-Z0-9_.-]{3,50}$")] string Handle,
    [StringLength(1000)] string? Description);

public sealed record UpdateChannelRequest(
    [StringLength(100, MinimumLength = 1)] string? Name,
    [StringLength(1000)] string? Description,
    [StringLength(2048)] string? AvatarUrl,
    [StringLength(2048)] string? BannerUrl);

public sealed record ChannelResponse(
    Guid ChannelId,
    Guid OwnerUserId,
    string Name,
    string Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string Status,
    DateTimeOffset CreatedAt);

public sealed record InviteMemberRequest(
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required] string RoleCode);

public sealed record ChangeMemberRoleRequest(
    [Required] string RoleCode);

public sealed record ChannelMemberResponse(
    Guid ChannelMemberId,
    Guid ChannelId,
    Guid UserId,
    string Username,
    string Email,
    string DisplayName,
    string RoleCode,
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
    string Status,
    DateTimeOffset ExpiresAt,
    DateTimeOffset CreatedAt);

public sealed class ChannelException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}
