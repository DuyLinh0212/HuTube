namespace HuTube.Domain.Plans;

public sealed class PlanHistory
{
    public Guid PlanHistoryId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid PlanId { get; set; }
    public Guid? OwnerUserId { get; set; }
    public string Status { get; set; } = "active";
    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? EndedAt { get; set; }
    public bool AutoRenew { get; set; }
    public string? PaymentReference { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PlanMember
{
    public Guid PlanMemberId { get; set; } = Guid.NewGuid();
    public Guid PlanHistoryId { get; set; }
    public Guid OwnerUserId { get; set; }
    public string MemberEmail { get; set; } = "";
    public Guid? MemberUserId { get; set; }
    public string Status { get; set; } = "pending";
    public DateTimeOffset InvitedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? AcceptedAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}

public sealed class PlanInvitationToken
{
    public Guid PlanInvitationTokenId { get; set; } = Guid.NewGuid();
    public Guid PlanMemberId { get; set; }
    public string Token { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
