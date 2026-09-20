namespace HuTube.Application.Playlists;

public sealed record PlaylistItemResponse(Guid PlaylistVideoId, Guid VideoId, int Position, string? Title, string? ThumbnailUrl,
    int Duration, string? Visibility, string? Status, string? ModerationStatus, bool Available, string? UnavailableReason);
public sealed record PlaylistResponse(Guid PlaylistId, Guid UserId, string Name, string? Description, string Visibility,
    string PlaylistType, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, IReadOnlyList<PlaylistItemResponse> Items);
public sealed record PlaylistSummaryResponse(Guid PlaylistId, Guid UserId, string Name, string? Description, string Visibility,
    string PlaylistType, int ItemCount, DateTimeOffset UpdatedAt);
public sealed record CreatePlaylistRequest(string Name, string? Description = null, string Visibility = "private", string PlaylistType = "personal");
public sealed record UpdatePlaylistRequest(string Name, string? Description, string Visibility);
public sealed record AddPlaylistVideoRequest(Guid VideoId);
public sealed record SaveVideoRequest(Guid VideoId);
public sealed record ReorderPlaylistRequest(IReadOnlyList<Guid> VideoIds);

public sealed class PlaylistException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public interface IPlaylistService
{
    Task<IReadOnlyList<PlaylistSummaryResponse>> GetMineAsync(Guid userId, CancellationToken ct = default);
    Task<IReadOnlyList<PlaylistSummaryResponse>> GetPublicByChannelAsync(Guid channelId, CancellationToken ct = default);
    Task<IReadOnlyList<PlaylistSummaryResponse>> GetChannelMineAsync(Guid userId, Guid channelId, CancellationToken ct = default);
    Task<PlaylistResponse> GetAsync(Guid playlistId, Guid? viewerId, CancellationToken ct = default);
    Task<PlaylistResponse> CreateAsync(Guid userId, CreatePlaylistRequest request, CancellationToken ct = default);
    Task<PlaylistResponse> SaveVideoAsync(Guid userId, SaveVideoRequest request, CancellationToken ct = default);
    Task<PlaylistResponse> UpdateAsync(Guid userId, Guid playlistId, UpdatePlaylistRequest request, CancellationToken ct = default);
    Task DeleteAsync(Guid userId, Guid playlistId, CancellationToken ct = default);
    Task<PlaylistResponse> AddVideoAsync(Guid userId, Guid playlistId, AddPlaylistVideoRequest request, CancellationToken ct = default);
    Task RemoveVideoAsync(Guid userId, Guid playlistId, Guid videoId, CancellationToken ct = default);
    Task<PlaylistResponse> ReorderAsync(Guid userId, Guid playlistId, ReorderPlaylistRequest request, CancellationToken ct = default);
}
