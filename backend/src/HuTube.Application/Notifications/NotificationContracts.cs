namespace HuTube.Application.Notifications;

public sealed record NotificationResponse(Guid NotificationId, string Type, string Title, string Content,
    string? ActionUrl, bool IsRead, DateTimeOffset CreatedAt, string? ResourceType, Guid? ResourceId);

public sealed record NotificationPage(IReadOnlyList<NotificationResponse> Items, int Page, int PageSize, int Total, int UnreadCount, bool HasMore);

public sealed record InvitationSignal(Guid InvitationId, Guid ChannelId, string ChannelName, string RoleCode, DateTimeOffset ExpiresAt);

public sealed record NotificationMessage(Guid UserId, string Type, string Title, string Content,
    string? ActionUrl, string? ResourceType, Guid? ResourceId, bool SendEmail = true);

public interface INotificationService
{
    // Persist inside the caller's transaction; deliver external effects only after commit.
    async Task<Func<CancellationToken, Task>> PrepareBatchAsync(IReadOnlyList<NotificationMessage> messages, CancellationToken ct = default)
    {
        foreach (var message in messages)
        {
            if (message.SendEmail)
                await PublishAsync(message.UserId, message.Type, message.Title, message.Content, message.ActionUrl, message.ResourceType, message.ResourceId, ct);
            else
                await PublishInAppAsync(message.UserId, message.Type, message.Title, message.Content, message.ActionUrl, message.ResourceType, message.ResourceId, ct);
        }
        return _ => Task.CompletedTask;
    }
    Task<NotificationPage> GetAsync(Guid userId, int page = 1, int pageSize = 5, CancellationToken ct = default);
    Task MarkReadAsync(Guid userId, Guid notificationId, CancellationToken ct = default);
    Task MarkAllReadAsync(Guid userId, CancellationToken ct = default);
    Task PublishInAppAsync(Guid userId, string type, string title, string content, string? actionUrl,
        string? resourceType, Guid? resourceId, CancellationToken ct = default);
    Task PublishAsync(Guid userId, string type, string title, string content, string? actionUrl,
        string? resourceType, Guid? resourceId, CancellationToken ct = default);
    Task PublishInvitationAsync(Guid userId, InvitationSignal invitation, CancellationToken ct = default);
}
