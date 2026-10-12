namespace HuTube.Application.Payments;

public sealed record AdminPaymentItemResponse(
    Guid PaymentId,
    string TransactionCode,
    Guid UserId,
    string UserName,
    string Email,
    string? AvatarUrl,
    Guid PlanId,
    string PlanName,
    string Type,
    string PaymentMethod,
    decimal Amount,
    string Currency,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? PaidAt,
    DateTimeOffset UpdatedAt,
    DateTimeOffset ExpiresAt,
    long? SepayTransactionId,
    Guid? PlanHistoryId);

public sealed record AdminPaymentStatsResponse(
    decimal RevenueInRange,
    decimal RevenueThisMonth,
    long SuccessfulTransactions,
    long RefundTransactions,
    long PendingTransactions,
    long FailedTransactions);

public sealed record AdminPaymentDailyResponse(DateOnly Date, decimal Revenue, long Transactions);

public sealed record AdminPaymentMethodResponse(string Method, long Transactions, decimal Revenue, double Share);

public sealed record AdminPaymentPageResponse(
    IReadOnlyList<AdminPaymentItemResponse> Items,
    int Page,
    int PageSize,
    long Total,
    bool HasMore,
    AdminPaymentStatsResponse Stats,
    IReadOnlyList<AdminPaymentDailyResponse> Daily,
    IReadOnlyList<AdminPaymentMethodResponse> Methods,
    IReadOnlyList<string> AvailableMethods);

public sealed record AdminPaymentEventResponse(string Status, string Title, string Description, DateTimeOffset OccurredAt);

public sealed record AdminPaymentDetailResponse(
    AdminPaymentItemResponse Transaction,
    IReadOnlyList<AdminPaymentEventResponse> Events);
