namespace HuTube.Domain.Users;

public sealed class NotificationSetting
{
    public Guid NotificationSettingId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public bool InAppEnabled { get; set; } = true;
    public bool EmailEnabled { get; set; } = true;
    public bool NewVideoEnabled { get; set; } = true;
    public bool CommentReplyEnabled { get; set; } = true;
    public bool ReportResultEnabled { get; set; } = true;
    public bool ModerationEnabled { get; set; } = true;
    public bool PlanEnabled { get; set; } = true;
    public bool RecommendationEnabled { get; set; } = true;
    public bool MentionEnabled { get; set; } = true;
    public bool ChannelActivityEnabled { get; set; } = true;
    public bool PaymentEnabled { get; set; } = true;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
