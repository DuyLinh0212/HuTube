namespace HuTube.Application.Plans;

public sealed record AdminSubscriptionPaymentResponse(
    Guid PaymentId,
    Guid PlanId,
    string PlanName,
    string TransactionCode,
    decimal Amount,
    string Currency,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? PaidAt);

public sealed record AdminSubscriptionItemResponse(
    Guid PlanHistoryId,
    Guid UserId,
    string UserName,
    string Email,
    string? AvatarUrl,
    Guid PlanId,
    string PlanCode,
    string PlanName,
    decimal Price,
    int DurationDays,
    string Cycle,
    string Status,
    DateTimeOffset StartedAt,
    DateTimeOffset? ExpiresAt,
    bool AutoRenew,
    DateTimeOffset? LastPaymentAt,
    decimal? LastPaymentAmount,
    string? LastPaymentStatus,
    bool IsStorageOverLimit);

public sealed record AdminSubscriptionStatsResponse(
    int TotalSubscriptions,
    int ActiveSubscriptions,
    int ExpiringSubscriptions,
    int ExpiredSubscriptions,
    int AutoRenewSubscriptions,
    int PendingPayments,
    decimal PaidRevenueThisMonth,
    int PaidTransactionsThisMonth,
    int FailedPayments,
    int NewSubscriptionsThisMonth);

public sealed record AdminSubscriptionPageResponse(
    IReadOnlyList<AdminSubscriptionItemResponse> Items,
    int Page,
    int PageSize,
    int Total,
    bool HasMore,
    AdminSubscriptionStatsResponse Stats);

public sealed record AdminSubscriptionDetailResponse(
    AdminSubscriptionItemResponse Subscription,
    IReadOnlyList<AdminSubscriptionPaymentResponse> Payments);

public sealed record AdminSubscriptionAutoRenewRequest(bool AutoRenew);

public sealed record AdminSubscriptionSwitchPlanRequest(Guid PlanId);
