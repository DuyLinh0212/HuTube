namespace HuTube.Application.Recommendations;

public sealed record RecommendedItem(
    Guid VideoId,
    float Score,
    string ModelVersion,
    string Source
);

public sealed record InternalRecommendationRequest(
    string UserId,
    int Limit,
    IReadOnlyList<string> ExcludeItemIds
);

public sealed record InternalRecommendationItemDto(
    string ItemId,
    float Score
);

public sealed record InternalRecommendationResponse(
    IReadOnlyList<InternalRecommendationItemDto> Items,
    string? ModelVersion,
    string? Source
);

public interface IRecommendationClient
{
    bool IsEnabled { get; }
    Task<IReadOnlyList<RecommendedItem>?> GetRecommendationsAsync(
        Guid userId,
        int limit,
        IReadOnlyList<Guid>? excludeVideoIds = null,
        CancellationToken ct = default);
}
