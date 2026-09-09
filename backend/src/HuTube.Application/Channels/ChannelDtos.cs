namespace HuTube.Application.Channels;

public sealed record CreateChannelRequest(
    string Name,
    string Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string? ContactEmail
);

public sealed record UpdateChannelRequest(
    string? Name,
    string? Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string? ContactEmail,
    string? WatermarkUrl,
    string? Settings
);

public sealed record ChannelDto(
    Guid ChannelId,
    Guid OwnerUserId,
    string Name,
    string Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string? ContactEmail,
    string? WatermarkUrl,
    string Status,
    DateTimeOffset CreatedAt
);

public sealed record ChannelDetailDto(
    Guid ChannelId,
    Guid OwnerUserId,
    string Name,
    string Handle,
    string? Description,
    string? AvatarUrl,
    string? BannerUrl,
    string? ContactEmail,
    string? WatermarkUrl,
    string Settings,
    string Status,
    long SubscriberCount,
    long VideoCount,
    bool IsOwner,
    DateTimeOffset CreatedAt
);

public sealed record CheckHandleResponse(
    string Handle,
    bool IsAvailable,
    string Message
);
