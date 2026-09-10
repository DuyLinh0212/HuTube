using HuTube.Domain.Rbac;

namespace HuTube.Application.Rbac;

public sealed record PermissionResponse(
    Guid PermissionId,
    string Code,
    string Name,
    string? Description,
    string Status);

public sealed record RoleResponse(
    Guid RoleId,
    string Code,
    string Name,
    string? Description,
    IReadOnlyList<string> Permissions);

public sealed record CreateRoleRequest(
    string Code,
    string Name,
    string? Description,
    IReadOnlyList<string>? PermissionCodes,
    string Reason);

public sealed record UpdateRoleRequest(
    string Name,
    string? Description,
    IReadOnlyList<string>? PermissionCodes,
    string Reason);

public sealed record AuditLogEntry(
    Guid? ActorUserId,
    string Action,
    string? ResourceType = null,
    Guid? ResourceId = null,
    string? Reason = null,
    string? OldValues = null,
    string? NewValues = null,
    string? IpAddress = null,
    string? UserAgent = null);

public sealed record AuditLogResponse(
    Guid AuditLogId,
    Guid? ActorUserId,
    string Action,
    string? ResourceType,
    Guid? ResourceId,
    string? Reason,
    DateTimeOffset CreatedAt);

public sealed record AdminMeResponse(
    Guid UserId,
    string Username,
    string Email,
    string DisplayName,
    bool EmailVerified,
    bool IsAdmin,
    string Role,
    IReadOnlyList<string> Permissions);

public sealed class RbacException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}
