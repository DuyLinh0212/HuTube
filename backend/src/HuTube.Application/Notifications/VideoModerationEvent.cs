namespace HuTube.Application.Notifications;

// One small event per decision. Recipient discovery belongs to the worker.
public sealed record VideoModerationEvent(
    Guid EventId, Guid ModerationCaseId, Guid VideoId, Guid ChannelId,
    string ChannelName, string VideoTitle, string Decision, bool NotifySubscribers,
    DateTimeOffset OccurredAt, IReadOnlyList<NotificationMessage> OwnerNotifications)
{
    public string EventType => Decision is "approve" or "age_restricted" or "recommendation_restricted"
        ? "video.approved.v1" : "video.moderated.v1";
}
