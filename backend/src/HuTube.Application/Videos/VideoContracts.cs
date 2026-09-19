using HuTube.Domain.Videos;

namespace HuTube.Application.Videos;

public sealed class ContentException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public sealed record PageResult<T>(IReadOnlyList<T> Items, int Page, int PageSize, int Total);
public sealed record CategoryResponse(Guid CategoryId, string Name, string Slug, string? Description);
public sealed record ChapterRequest(int StartSeconds, string Title);
public sealed record RenditionResponse(string Quality, int Width, int Height, long FileSize, string Url);
public sealed record VideoStatsResponse(long Views, long Likes, long Dislikes, int Comments, decimal? AverageRating, int RatingCount, long Shares);
public sealed record VideoViewerStateResponse(string? Reaction, int? Rating, int ResumeAtSeconds, decimal Progress);
public sealed record VideoCardResponse(Guid VideoId, Guid ChannelId, string ChannelName, string ChannelHandle, string Title,
    string? ThumbnailUrl, int Duration, string Visibility, DateTimeOffset? PublishedAt, long Views);
public sealed record LibraryVideoResponse(Guid VideoId, Guid ChannelId, string ChannelName, string ChannelHandle, string Title,
    string? ThumbnailUrl, int Duration, string Visibility, DateTimeOffset? PublishedAt, long Views, long Likes,
    long Dislikes, decimal? AverageRating, int RatingCount, int? MyRating, int WatchedSeconds, decimal Progress,
    DateTimeOffset ActivityAt);
public sealed record VideoResponse(Guid VideoId, Guid ChannelId, string ChannelName, string ChannelHandle, Guid? CategoryId,
    string Title, string? Description, string VideoUrl, string? ThumbnailUrl, int Duration, long FileSize,
    string Visibility, string Status, string ModerationStatus, string? LanguageCode, bool AgeRestricted,
    DateTimeOffset? PublishedAt, DateTimeOffset CreatedAt, IReadOnlyList<string> Tags,
    IReadOnlyList<VideoChapter> Chapters, VideoStatsResponse Stats, VideoViewerStateResponse? ViewerState);
public sealed record PlaybackResponse(Guid VideoId, string Title, string Visibility, int Duration,
    IReadOnlyList<RenditionResponse> Renditions, int ResumeAtSeconds, decimal Progress);

public sealed record CreateVideoCommand(Guid ChannelId, string Title, string? Description, Guid? CategoryId,
    string? LanguageCode, string Visibility, bool AgeRestricted, int Duration, string SourceQuality, long FileSize,
    string FileName, string ContentType, Stream Content, string? ThumbnailFileName,
    string? ThumbnailContentType, Stream? ThumbnailContent, IReadOnlyList<string> Tags,
    IReadOnlyList<ChapterRequest> Chapters, string? IdempotencyKey = null,
    bool GenerateLowerRenditions = true, bool DeferLowerRenditions = false);
public sealed record UpdateVideoRequest(string? Title, string? Description, Guid? CategoryId, bool ClearCategory,
    string? LanguageCode, string? Visibility, bool? AgeRestricted, string? ThumbnailUrl,
    IReadOnlyList<string>? Tags, IReadOnlyList<ChapterRequest>? Chapters);
public sealed record WatchProgressRequest(int WatchedSeconds, bool SaveHistory = true);
public sealed record WatchProgressResponse(int WatchedSeconds, decimal Progress, DateTimeOffset ViewedAt);
public sealed record ReactionRequest(string Type);
public sealed record ReactionResponse(string? MyReaction, long Likes, long Dislikes);
public sealed record RatingRequest(int Score);
public sealed record RatingResponse(int? MyRating, decimal? Average, int Count);
public sealed record ShareRequest(string? Method);
public sealed record ShareResponse(string Url, long ShareCount);
public sealed record CreateCommentRequest(string Content, Guid? ParentCommentId);
public sealed record UpdateCommentRequest(string Content);
public sealed record CommentResponse(Guid CommentId, Guid VideoId, Guid UserId, string DisplayName, Guid? ParentCommentId,
    string Content, string Status, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, long Likes, long Dislikes,
    string? MyReaction, int ReplyCount);
public sealed record ReportCommentRequest(Guid ViolationTypeId, string Description);
public sealed record ReportResponse(Guid ReportId, string Status, DateTimeOffset CreatedAt);
public sealed record ViolationTypeResponse(Guid ViolationTypeId, string Code, string Name, string? Description);
public sealed record CreateDownloadRequest(string Quality);
public sealed record DownloadResponse(Guid VideoDownloadId, Guid VideoId, string Title, string Quality,
    string FileUrl, long FileSize, string Status, DateTimeOffset CreatedAt);
public sealed record UploadPreflightRequest(Guid ChannelId, long FileSize, int Duration, string ContentType, string SourceQuality);
public sealed record UploadPreflightResponse(bool Allowed, long MaxUploadSize, int MaxDuration, string MaxQuality,
    long StorageLimit, long StorageUsed, long StorageRemaining);

public interface IContentService
{
    Task<IReadOnlyList<CategoryResponse>> GetCategoriesAsync(CancellationToken ct = default);
    Task<PageResult<VideoCardResponse>> GetFeedAsync(string feed, string? sort, Guid? categoryId, string? tag, int page, int pageSize, CancellationToken ct = default);
    Task<PageResult<LibraryVideoResponse>> GetWatchHistoryAsync(Guid userId, int page, int pageSize, CancellationToken ct = default);
    Task<PageResult<LibraryVideoResponse>> GetLikedVideosAsync(Guid userId, int? rating, int page, int pageSize, CancellationToken ct = default);
    Task<VideoResponse> GetVideoAsync(Guid videoId, Guid? viewerId, CancellationToken ct = default);
    Task<PlaybackResponse> GetPlaybackAsync(Guid videoId, Guid? viewerId, CancellationToken ct = default);
    Task<VideoResponse> CreateVideoAsync(Guid actorId, CreateVideoCommand command, CancellationToken ct = default);
    Task<UploadPreflightResponse> PreflightAsync(Guid actorId, UploadPreflightRequest request, CancellationToken ct = default);
    Task<PageResult<VideoResponse>> GetManagedVideosAsync(Guid actorId, Guid channelId, string? status, string? visibility,
        string? search, Guid? categoryId, string? tag, int page, int pageSize, CancellationToken ct = default);
    Task<VideoResponse> UpdateVideoAsync(Guid actorId, Guid videoId, UpdateVideoRequest request, CancellationToken ct = default);
    Task DeleteVideoAsync(Guid actorId, Guid videoId, CancellationToken ct = default);
    Task<VideoResponse> SubmitModerationAsync(Guid actorId, Guid videoId, CancellationToken ct = default);
    Task<VideoResponse> PublishAsync(Guid actorId, Guid videoId, CancellationToken ct = default);
    Task CancelUploadAsync(Guid actorId, Guid videoId, CancellationToken ct = default);
    Task<VideoResponse> RetryProcessingAsync(Guid actorId, Guid videoId, CancellationToken ct = default);
    Task<WatchProgressResponse> SaveProgressAsync(Guid userId, Guid videoId, WatchProgressRequest request, CancellationToken ct = default);
    Task<ReactionResponse> SetVideoReactionAsync(Guid userId, Guid videoId, string? reaction, CancellationToken ct = default);
    Task<RatingResponse> SetRatingAsync(Guid userId, Guid videoId, int? score, CancellationToken ct = default);
    Task<ShareResponse> ShareAsync(Guid userId, Guid videoId, string? method, CancellationToken ct = default);
    Task<PageResult<CommentResponse>> GetCommentsAsync(Guid videoId, Guid? viewerId, string sort, int page, int pageSize, CancellationToken ct = default);
    Task<PageResult<CommentResponse>> GetRepliesAsync(Guid commentId, Guid? viewerId, int page, int pageSize, CancellationToken ct = default);
    Task<PageResult<CommentResponse>> GetManagedCommentsAsync(Guid actorId, Guid channelId, string? status, int page, int pageSize, CancellationToken ct = default);
    Task<IReadOnlyList<ViolationTypeResponse>> GetViolationTypesAsync(CancellationToken ct = default);
    Task<CommentResponse> CreateCommentAsync(Guid userId, Guid videoId, CreateCommentRequest request, CancellationToken ct = default);
    Task<CommentResponse> UpdateCommentAsync(Guid userId, Guid commentId, UpdateCommentRequest request, CancellationToken ct = default);
    Task DeleteCommentAsync(Guid userId, Guid commentId, CancellationToken ct = default);
    Task<ReactionResponse> SetCommentReactionAsync(Guid userId, Guid commentId, string? reaction, CancellationToken ct = default);
    Task<ReportResponse> ReportCommentAsync(Guid userId, Guid commentId, ReportCommentRequest request, CancellationToken ct = default);
    Task<CommentResponse> SetCommentHiddenAsync(Guid actorId, Guid commentId, bool hidden, string? reason, CancellationToken ct = default);
    Task<IReadOnlyList<RenditionResponse>> GetDownloadOptionsAsync(Guid userId, Guid videoId, CancellationToken ct = default);
    Task<DownloadResponse> CreateDownloadAsync(Guid userId, Guid videoId, string quality, CancellationToken ct = default);
    Task<IReadOnlyList<DownloadResponse>> GetDownloadsAsync(Guid userId, CancellationToken ct = default);
    Task DeleteDownloadAsync(Guid userId, Guid downloadId, CancellationToken ct = default);
    Task<DownloadResponse> SetDownloadStateAsync(Guid userId, Guid downloadId, string action, CancellationToken ct = default);
    Task DeleteDownloadsAsync(Guid userId, IReadOnlyList<Guid> downloadIds, CancellationToken ct = default);
}
