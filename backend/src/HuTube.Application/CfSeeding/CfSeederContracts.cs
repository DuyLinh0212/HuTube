using HuTube.Application.Videos;

namespace HuTube.Application.CfSeeding;

public sealed record CfSeedAccountNameRequest(string Username, string DisplayName, string? ChannelName, string Password);
public sealed record CreateCfSeedAccountsRequest(IReadOnlyList<CfSeedAccountNameRequest> Accounts);
public sealed record CfSeedAccountResponse(Guid UserId, Guid ChannelId, string Username, string DisplayName,
    string ChannelName, string ChannelHandle);
public sealed record CfSeedProvisionResponse(Guid BatchId, IReadOnlyList<CfSeedAccountResponse> Accounts);

public sealed record UploadCfSeedVideoCommand(Guid BatchId, Guid UserId, Guid ChannelId, Guid CategoryId,
    string Title, string Visibility, int Duration, string SourceQuality, long FileSize, string FileName,
    string ContentType, Stream Content, int Sequence, bool UseExistingAccount = false);

public sealed record CfSeedVideoResponse(Guid VideoId, Guid UserId, Guid ChannelId, string Title,
    string Status, string Visibility, long FileSize);

public interface ICfSeederService
{
    Task<IReadOnlyList<CfSeedAccountResponse>> GetExistingAccountsAsync(string? search,
        CancellationToken ct = default);
    Task<CfSeedProvisionResponse> CreateAccountsAsync(Guid adminActorId, CreateCfSeedAccountsRequest request,
        CancellationToken ct = default);
    Task<CfSeedVideoResponse> UploadVideoAsync(Guid adminActorId, UploadCfSeedVideoCommand command,
        CancellationToken ct = default);
}
