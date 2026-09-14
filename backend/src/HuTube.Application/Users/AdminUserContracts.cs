namespace HuTube.Application.Users;

public sealed record AdminUserListItem(
    Guid UserId,
    string DisplayName,
    string Username,
    string Email,
    string? AvatarUrl,
    string RoleCode,
    string RoleName,
    string? PlanCode,
    string? PlanName,
    int ChannelCount,
    int WarningCount,
    DateTimeOffset? LastLoginAt,
    DateTimeOffset CreatedAt,
    string Status,
    bool EmailVerified,
    DateTimeOffset? LockedUntil);

public sealed record AdminUserStats(
    int Total,
    int Active,
    int Blocked,
    int CreatorPro);

public sealed record AdminUserListResponse(
    IReadOnlyList<AdminUserListItem> Items,
    int Page,
    int PageSize,
    int Total,
    bool HasMore,
    AdminUserStats Stats);

public sealed record AdminUserAuditItem(
    string Action,
    string? Reason,
    DateTimeOffset CreatedAt);

public sealed record AdminUserChannelItem(
    Guid ChannelId,
    string Name,
    string Handle,
    string Status);

public sealed record AdminUserDetailResponse(
    Guid UserId,
    string DisplayName,
    string Username,
    string Email,
    string? AvatarUrl,
    string RoleCode,
    string RoleName,
    string? PlanCode,
    string? PlanName,
    string Status,
    bool EmailVerified,
    DateTimeOffset? LastLoginAt,
    DateTimeOffset CreatedAt,
    DateTimeOffset? LockedUntil,
    IReadOnlyList<string> Permissions,
    IReadOnlyList<AdminUserAuditItem> AuditHistory,
    IReadOnlyList<AdminUserChannelItem> Channels);

public sealed record AdminUserActionRequest(string Reason, bool Notify = true);

public sealed record UpdateAdminUserRoleRequest(string RoleCode, string Reason);
