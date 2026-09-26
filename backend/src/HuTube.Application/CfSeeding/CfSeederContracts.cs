using HuTube.Application.Videos;

namespace HuTube.Application.CfSeeding;

public sealed record CfSeedAccountNameRequest(string Username, string DisplayName, string? ChannelName, string Password);
public sealed record CreateCfSeedAccountsRequest(IReadOnlyList<CfSeedAccountNameRequest> Accounts);
public sealed record CfSeedAccountResponse(Guid UserId, Guid ChannelId, string Username, string DisplayName,
    string ChannelName, string ChannelHandle);
public sealed record CfSeedProvisionResponse(Guid BatchId, IReadOnlyList<CfSeedAccountResponse> Accounts);

public sealed record UploadCfSeedVideoCommand(Guid BatchId, Guid UserId, Guid ChannelId, Guid CategoryId,
    string Title, string Visibility, int Duration, string SourceQuality, long FileSize, string FileName,
    string ContentType, Stream Content, int Sequence, bool UseExistingAccount = false,
    int SourceWidth = 0, int SourceHeight = 0, string? Description = null);

public sealed record UploadCfSeedRenditionCommand(Guid VideoId, string Quality, int Width, int Height,
    int? BitrateKbps, string? Codec, long FileSize, string FileName, string ContentType, Stream Content);
public sealed record CfSeedRenditionResponse(Guid VideoId, string Quality, int Width, int Height,
    long FileSize, string Status);

public sealed record CfSeedVideoResponse(Guid VideoId, Guid UserId, Guid ChannelId, string Title,
    string Status, string Visibility, long FileSize);
public sealed record CfSeedVideoProcessingResponse(Guid VideoId, int TotalRenditions, int ReadyRenditions,
    int ProcessingRenditions, int FailedRenditions)
{
    public bool IsComplete => ProcessingRenditions == 0;
    public bool IsSuccessful => IsComplete && FailedRenditions == 0 && ReadyRenditions == TotalRenditions;
}

public interface ICfSeederService
{
    Task<IReadOnlyList<CfSeedAccountResponse>> GetExistingAccountsAsync(string? search,
        CancellationToken ct = default);
    Task<CfSeedProvisionResponse> CreateAccountsAsync(Guid adminActorId, CreateCfSeedAccountsRequest request,
        CancellationToken ct = default);
    Task<IReadOnlyList<CfSeedViewerAccountResponse>> CreateViewerAccountsAsync(CreateCfSeedViewersRequest request,
        CancellationToken ct = default);
    Task<IReadOnlyList<CfSeedViewerAccountResponse>> GetViewerAccountsAsync(string? search,
        int limit = 100, CancellationToken ct = default);
    Task<CfSeedVideoResponse> UploadVideoAsync(Guid adminActorId, UploadCfSeedVideoCommand command,
        CancellationToken ct = default);
    Task<CfSeedRenditionResponse> UploadRenditionAsync(Guid adminActorId,
        UploadCfSeedRenditionCommand command, CancellationToken ct = default);
    Task<CfSeedVideoProcessingResponse> GetVideoProcessingAsync(Guid videoId, CancellationToken ct = default);
}

public sealed record CfSeedViewerAccountRequest(string Username, string DisplayName, string? Email, string Password);
public sealed record CreateCfSeedViewersRequest(IReadOnlyList<CfSeedViewerAccountRequest> Accounts);
public sealed record CfSeedViewerAccountResponse(Guid UserId, string Username, string DisplayName, string Email);
