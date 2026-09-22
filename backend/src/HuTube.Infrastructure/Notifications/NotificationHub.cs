using System.Security.Claims;
using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Notifications;

[Authorize]
public sealed class NotificationHub : Hub;

public sealed class NotificationUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection) =>
        connection.User?.FindFirst("sub")?.Value ?? connection.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
}

public sealed class NotificationService(
    HuTubeDbContext db,
    IHubContext<NotificationHub> hub,
    IAuthEmailSender emailSender,
    TimeProvider clock) : INotificationService
{
    public async Task<NotificationPage> GetAsync(Guid userId, int page = 1, int pageSize = 5, CancellationToken ct = default)
    {
        page = Math.Max(1, page); pageSize = Math.Clamp(pageSize, 1, 25);
        var query = db.Notifications.AsNoTracking().Where(x => x.UserId == userId);
        var total = await query.CountAsync(ct);
        var unread = await query.CountAsync(x => !x.IsRead, ct);
        var rows = await query.OrderByDescending(x => x.CreatedAt).ThenByDescending(x => x.NotificationId)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        return new(rows.Select(ToResponse).ToArray(), page, pageSize, total, unread, page * pageSize < total);
    }

    public async Task MarkReadAsync(Guid userId, Guid notificationId, CancellationToken ct = default)
    {
        var changed = await db.Notifications.Where(x => x.UserId == userId && x.NotificationId == notificationId && !x.IsRead)
            .ExecuteUpdateAsync(update => update.SetProperty(x => x.IsRead, true).SetProperty(x => x.ReadAt, clock.GetUtcNow()), ct);
        if (changed == 0 && !await db.Notifications.AnyAsync(x => x.UserId == userId && x.NotificationId == notificationId, ct))
            throw new ContentException(404, "NOTIFICATION_NOT_FOUND", "Không tìm thấy thông báo.");
        await hub.Clients.User(userId.ToString()).SendAsync("UnreadCountChanged", await UnreadAsync(userId, ct), ct);
    }

    public async Task MarkAllReadAsync(Guid userId, CancellationToken ct = default)
    {
        await db.Notifications.Where(x => x.UserId == userId && !x.IsRead)
            .ExecuteUpdateAsync(update => update.SetProperty(x => x.IsRead, true).SetProperty(x => x.ReadAt, clock.GetUtcNow()), ct);
        await hub.Clients.User(userId.ToString()).SendAsync("UnreadCountChanged", 0, ct);
    }

    public Task PublishInAppAsync(Guid userId, string type, string title, string content, string? actionUrl,
        string? resourceType, Guid? resourceId, CancellationToken ct = default) =>
        PublishInternalAsync(userId, type, title, content, actionUrl, resourceType, resourceId, false, ct);

    public Task PublishAsync(Guid userId, string type, string title, string content, string? actionUrl,
        string? resourceType, Guid? resourceId, CancellationToken ct = default) =>
        PublishInternalAsync(userId, type, title, content, actionUrl, resourceType, resourceId, true, ct);

    public async Task PublishInvitationAsync(Guid userId, InvitationSignal invitation, CancellationToken ct = default)
    {
        await PublishInAppAsync(userId, "channel_invitation", $"Lời mời tham gia kênh {invitation.ChannelName}",
            $"Bạn được mời tham gia với vai trò {invitation.RoleCode}.", $"/channel-invitations?invitation={invitation.InvitationId}",
            "channel_invitation", invitation.InvitationId, ct);
        await hub.Clients.User(userId.ToString()).SendAsync("InvitationReceived", invitation, ct);
    }

    private async Task PublishInternalAsync(Guid userId, string type, string title, string content, string? actionUrl,
        string? resourceType, Guid? resourceId, bool sendEmail, CancellationToken ct)
    {
        var mandatoryInApp = type == "channel_invitation";
        var setting = await db.NotificationSettings.AsNoTracking().SingleOrDefaultAsync(x => x.UserId == userId, ct);
        var categoryEnabled = type switch
        {
            "comment_reply" or "video_comment" => setting?.CommentReplyEnabled ?? true,
            "mention" => setting?.MentionEnabled ?? true,
            "new_video" => setting?.NewVideoEnabled ?? true,
            "report_result" => setting?.ReportResultEnabled ?? true,
            "moderation" => setting?.ModerationEnabled ?? true,
            "channel_activity" or "video_like" or "video_dislike" or "comment_like" => setting?.ChannelActivityEnabled ?? true,
            _ => true
        };
        if (!categoryEnabled) return;

        if (mandatoryInApp || (setting?.InAppEnabled ?? true))
        {
            var row = new HuTube.Domain.Videos.Notification { UserId = userId, Type = type, Title = title, Content = content,
                ActionUrl = actionUrl, ResourceType = resourceType, ResourceId = resourceId, CreatedAt = clock.GetUtcNow() };
            db.Notifications.Add(row); await db.SaveChangesAsync(ct);
            await hub.Clients.User(userId.ToString()).SendAsync("NotificationReceived", ToResponse(row), ct);
            await hub.Clients.User(userId.ToString()).SendAsync("UnreadCountChanged", await UnreadAsync(userId, ct), ct);
        }
        if (sendEmail && (setting?.EmailEnabled ?? true))
        {
            var address = await db.Users.AsNoTracking().Where(x => x.UserId == userId).Select(x => x.Email).SingleAsync(ct);
            await emailSender.SendAsync(address, title, content, ct);
        }
    }

    private Task<int> UnreadAsync(Guid userId, CancellationToken ct) => db.Notifications.CountAsync(x => x.UserId == userId && !x.IsRead, ct);
    private static NotificationResponse ToResponse(HuTube.Domain.Videos.Notification row) => new(row.NotificationId, row.Type,
        row.Title, row.Content, row.ActionUrl, row.IsRead, row.CreatedAt, row.ResourceType, row.ResourceId);
}
