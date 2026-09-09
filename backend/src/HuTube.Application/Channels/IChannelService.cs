namespace HuTube.Application.Channels;

public interface IChannelService
{
    Task<ChannelDto> CreateChannelAsync(Guid userId, CreateChannelRequest request, CancellationToken ct = default);
    Task<ChannelDetailDto?> GetMyChannelAsync(Guid userId, CancellationToken ct = default);
    Task<ChannelDetailDto> GetChannelByHandleAsync(string handle, Guid? currentUserId = null, CancellationToken ct = default);
    Task<ChannelDetailDto> GetChannelByIdAsync(Guid channelId, Guid? currentUserId = null, CancellationToken ct = default);
    Task<ChannelDto> UpdateChannelAsync(Guid userId, Guid channelId, UpdateChannelRequest request, CancellationToken ct = default);
    Task DeleteChannelAsync(Guid userId, Guid channelId, CancellationToken ct = default);
    Task<CheckHandleResponse> CheckHandleAsync(string handle, Guid? currentChannelId = null, CancellationToken ct = default);
}
