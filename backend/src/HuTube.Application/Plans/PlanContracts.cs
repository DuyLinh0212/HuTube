namespace HuTube.Application.Plans;

public sealed record PlanResponse(
    Guid PlanId,
    string Code,
    string Name,
    string? Description,
    decimal Price,
    int DurationDays,
    long StorageLimit,
    long MaxUploadSize,
    int MaxVideoDuration,
    string? MaxVideoQuality,
    int MaxMembers,
    string Status,
    IReadOnlyDictionary<string, bool>? Features = null,
    int DisplayOrder = 0,
    string? MaxDownloadQuality = null);

public sealed record PlanMemberResponse(
    Guid PlanMemberId,
    Guid PlanId,
    Guid OwnerUserId,
    string MemberEmail,
    Guid? MemberUserId,
    string Status,
    DateTimeOffset InvitedAt,
    DateTimeOffset? AcceptedAt,
    DateTimeOffset? RevokedAt,
    long? AllocatedStorage = null,
    long StorageUsed = 0);

public sealed record PlanShareResponse(
    Guid PlanId,
    string Code,
    string Name,
    string? Description,
    string ShareUrl,
    string Status,
    IReadOnlyDictionary<string, bool>? Features = null);

public sealed record PlanSubscriptionInfo(
    Guid PlanHistoryId,
    DateTimeOffset StartedAt,
    DateTimeOffset? EndedAt,
    bool AutoRenew,
    bool IsExpired);

public sealed record PlanDetailResponse(
    Guid? PlanId,
    string? Code,
    string? Name,
    long StorageLimit,
    long UsedStorage,
    long RemainingStorage,
    long MaxUploadSize,
    string? MaxVideoQuality,
    int MaxMembers,
    IReadOnlyList<PlanMemberResponse> Members,
    PlanSubscriptionInfo? Subscription = null,
    bool IsSharedMember = false,
    decimal Price = 0,
    IReadOnlyList<Guid>? ActivePaidPlanIds = null,
    IReadOnlyDictionary<string, bool>? Features = null,
    int DurationDays = 0,
    int MaxVideoDuration = 0,
    string? Description = null,
    string? Status = null,
    string? MaxDownloadQuality = null,
    long? OwnerAllocatedStorage = null);

public sealed record PlanSubscriptionRequest(
    string? PaymentMethod = null,
    bool AutoRenew = false);

public sealed record CreatePlanRequest(
    string Code,
    string Name,
    string? Description,
    decimal Price,
    int DurationDays,
    long StorageLimit,
    long MaxUploadSize,
    int MaxVideoDuration,
    string MaxVideoQuality,
    int MaxMembers,
    string? Features = null,
    int DisplayOrder = 0,
    string? MaxDownloadQuality = null);

public sealed record UpdatePlanRequest(
    string Name,
    string? Description,
    decimal Price,
    int DurationDays,
    long StorageLimit,
    long MaxUploadSize,
    int MaxVideoDuration,
    string MaxVideoQuality,
    int MaxMembers,
    string Status,
    string? Features = null,
    int DisplayOrder = 0,
    string? MaxDownloadQuality = null);

public sealed record PlanInviteRequest(
    string Email,
    long? AllocatedStorage = null);

public sealed record UpdatePlanMemberStorageRequest(
    long? AllocatedStorage);

public sealed record UpdateOwnerStorageRequest(
    long? AllocatedStorage);

public sealed record PlanAcceptInvitationRequest(
    string Token);

public sealed class PlanException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public interface IPlanService
{
    Task<IReadOnlyList<PlanResponse>> GetPlansAsync(CancellationToken ct = default);
    Task<IReadOnlyList<PlanResponse>> GetAdminPlansAsync(CancellationToken ct = default);
    Task<PlanResponse> CreatePlanAsync(Guid actorUserId, CreatePlanRequest request, CancellationToken ct = default);
    Task<PlanResponse> UpdatePlanAsync(Guid actorUserId, Guid planId, UpdatePlanRequest request, CancellationToken ct = default);
    Task ArchivePlanAsync(Guid actorUserId, Guid planId, CancellationToken ct = default);
    Task<PlanResponse> GetPlanByIdAsync(Guid planId, CancellationToken ct = default);
    Task<PlanShareResponse> GetPlanShareAsync(Guid planId, CancellationToken ct = default);
    Task<PlanDetailResponse?> GetMyPlanAsync(Guid userId, CancellationToken ct = default);
    Task<long?> GetEffectiveStorageLimitAsync(Guid userId, CancellationToken ct = default);
    Task<PlanResponse> SubscribeAsync(Guid userId, Guid planId, PlanSubscriptionRequest request, CancellationToken ct = default);

    /// <summary>
    /// Kích hoạt gói trả phí sau khi thanh toán được xác nhận qua webhook SePay.
    /// Trả về PlanHistoryId của bản ghi vừa tạo.
    /// </summary>
    Task<Guid> ActivatePaidPlanAsync(Guid userId, Guid planId, Guid paymentId, bool autoRenew, CancellationToken ct = default);

    Task<PlanMemberResponse> InviteMemberAsync(Guid ownerUserId, string email, long? allocatedStorage, CancellationToken ct = default);
    Task<PlanMemberResponse> AcceptInvitationAsync(Guid userId, Guid memberId, string token, CancellationToken ct = default);
    Task RemoveMemberAsync(Guid ownerUserId, Guid memberId, CancellationToken ct = default);
    Task<PlanMemberResponse> UpdateMemberStorageAsync(Guid ownerUserId, Guid memberId, long? allocatedStorage, CancellationToken ct = default);
    Task UpdateOwnerStorageAsync(Guid ownerUserId, long? allocatedStorage, CancellationToken ct = default);
}
