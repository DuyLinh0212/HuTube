using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Domain.Channels;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Channels;

public sealed class ChannelService(HuTubeDbContext db) : IChannelService
{
    public async Task<ChannelDto> CreateChannelAsync(Guid userId, CreateChannelRequest request, CancellationToken ct = default)
    {
        var existing = await db.Channels.SingleOrDefaultAsync(c => c.OwnerUserId == userId && c.Status != "deleted", ct);
        if (existing != null)
            throw new AuthException(409, "USER_ALREADY_HAS_CHANNEL", "Mỗi tài khoản chỉ được tạo tối đa một kênh.");

        if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Trim().Length > 100)
            throw new AuthException(400, "INVALID_CHANNEL_NAME", "Tên kênh không được để trống và tối đa 100 ký tự.");

        if (!Channel.IsValidHandle(request.Handle))
            throw new AuthException(400, "INVALID_HANDLE", "Handle cần 3–50 ký tự, chỉ gồm chữ, số, dấu gạch dưới, gạch ngang hoặc dấu chấm.");

        var normalizedHandle = Channel.NormalizeHandle(request.Handle);
        var handleExists = await db.Channels.AnyAsync(c => c.Handle == normalizedHandle && c.Status != "deleted", ct);
        if (handleExists)
            throw new AuthException(409, "HANDLE_ALREADY_EXISTS", "Handle này đã có người sử dụng. Vui lòng chọn handle khác.");

        var now = DateTimeOffset.UtcNow;
        var channel = new Channel
        {
            ChannelId = Guid.NewGuid(),
            OwnerUserId = userId,
            Name = request.Name.Trim(),
            Handle = normalizedHandle,
            Description = request.Description?.Trim(),
            AvatarUrl = request.AvatarUrl?.Trim(),
            BannerUrl = request.BannerUrl?.Trim(),
            ContactEmail = request.ContactEmail?.Trim(),
            Settings = "{}",
            Status = "active",
            CreatedAt = now,
            UpdatedAt = now
        };

        var quota = new ChannelQuota
        {
            ChannelQuotaId = Guid.NewGuid(),
            ChannelId = channel.ChannelId,
            StorageLimit = 10L * 1024 * 1024 * 1024,
            StorageUsed = 0,
            UpdatedAt = now
        };

        db.Channels.Add(channel);
        db.ChannelQuotas.Add(quota);
        await db.SaveChangesAsync(ct);

        return ToDto(channel);
    }

    public async Task<ChannelDetailDto?> GetMyChannelAsync(Guid userId, CancellationToken ct = default)
    {
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(c => c.OwnerUserId == userId && c.Status != "deleted", ct);
        return channel == null ? null : ToDetailDto(channel, true);
    }

    public async Task<ChannelDetailDto> GetChannelByHandleAsync(string handle, Guid? currentUserId = null, CancellationToken ct = default)
    {
        var normalized = Channel.NormalizeHandle(handle);
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(c => c.Handle == normalized && c.Status != "deleted", ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh yêu cầu.");

        var isOwner = currentUserId.HasValue && channel.OwnerUserId == currentUserId.Value;
        return ToDetailDto(channel, isOwner);
    }

    public async Task<ChannelDetailDto> GetChannelByIdAsync(Guid channelId, Guid? currentUserId = null, CancellationToken ct = default)
    {
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(c => c.ChannelId == channelId && c.Status != "deleted", ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh yêu cầu.");

        var isOwner = currentUserId.HasValue && channel.OwnerUserId == currentUserId.Value;
        return ToDetailDto(channel, isOwner);
    }

    public async Task<ChannelDto> UpdateChannelAsync(Guid userId, Guid channelId, UpdateChannelRequest request, CancellationToken ct = default)
    {
        var channel = await db.Channels.SingleOrDefaultAsync(c => c.ChannelId == channelId && c.Status != "deleted", ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh yêu cầu.");

        if (channel.OwnerUserId != userId)
            throw new AuthException(403, "NOT_CHANNEL_OWNER", "Chỉ chủ sở hữu mới có quyền tùy chỉnh kênh.");

        if (request.Name is not null)
        {
            var trimmed = request.Name.Trim();
            if (trimmed.Length is < 1 or > 100)
                throw new AuthException(400, "INVALID_CHANNEL_NAME", "Tên kênh không được để trống và tối đa 100 ký tự.");
            channel.Name = trimmed;
        }

        if (request.Handle is not null)
        {
            if (!Channel.IsValidHandle(request.Handle))
                throw new AuthException(400, "INVALID_HANDLE", "Handle cần 3–50 ký tự, chỉ gồm chữ, số, dấu gạch dưới, gạch ngang hoặc dấu chấm.");

            var normalized = Channel.NormalizeHandle(request.Handle);
            if (normalized != channel.Handle)
            {
                var handleExists = await db.Channels.AnyAsync(c => c.Handle == normalized && c.ChannelId != channelId && c.Status != "deleted", ct);
                if (handleExists)
                    throw new AuthException(409, "HANDLE_ALREADY_EXISTS", "Handle này đã có người sử dụng. Vui lòng chọn handle khác.");
                channel.Handle = normalized;
            }
        }

        if (request.Description is not null) channel.Description = request.Description.Trim();
        if (request.AvatarUrl is not null) channel.AvatarUrl = request.AvatarUrl.Trim();
        if (request.BannerUrl is not null) channel.BannerUrl = request.BannerUrl.Trim();
        if (request.ContactEmail is not null) channel.ContactEmail = request.ContactEmail.Trim();
        if (request.WatermarkUrl is not null) channel.WatermarkUrl = request.WatermarkUrl.Trim();
        if (request.Settings is not null) channel.Settings = request.Settings.Trim();

        channel.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return ToDto(channel);
    }

    public async Task DeleteChannelAsync(Guid userId, Guid channelId, CancellationToken ct = default)
    {
        var channel = await db.Channels.SingleOrDefaultAsync(c => c.ChannelId == channelId && c.Status != "deleted", ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh yêu cầu.");

        if (channel.OwnerUserId != userId)
            throw new AuthException(403, "NOT_CHANNEL_OWNER", "Chỉ chủ sở hữu kênh mới có quyền xóa kênh.");

        channel.SoftDelete(DateTimeOffset.UtcNow);
        await db.SaveChangesAsync(ct);
    }

    public async Task<CheckHandleResponse> CheckHandleAsync(string handle, Guid? currentChannelId = null, CancellationToken ct = default)
    {
        if (!Channel.IsValidHandle(handle))
            return new CheckHandleResponse(handle, false, "Handle không hợp lệ (3–50 ký tự: chữ cái, số, _, -, .).");

        var normalized = Channel.NormalizeHandle(handle);
        var exists = await db.Channels.AnyAsync(c => c.Handle == normalized && (!currentChannelId.HasValue || c.ChannelId != currentChannelId.Value) && c.Status != "deleted", ct);
        return new CheckHandleResponse(normalized, !exists, exists ? "Handle này đã có người sử dụng." : "Handle khả dụng.");
    }

    private static ChannelDto ToDto(Channel c) => new(
        c.ChannelId,
        c.OwnerUserId,
        c.Name,
        c.Handle,
        c.Description,
        c.AvatarUrl,
        c.BannerUrl,
        c.ContactEmail,
        c.WatermarkUrl,
        c.Status,
        c.CreatedAt
    );

    private static ChannelDetailDto ToDetailDto(Channel c, bool isOwner) => new(
        c.ChannelId,
        c.OwnerUserId,
        c.Name,
        c.Handle,
        c.Description,
        c.AvatarUrl,
        c.BannerUrl,
        c.ContactEmail,
        c.WatermarkUrl,
        c.Settings,
        c.Status,
        SubscriberCount: 0,
        VideoCount: 0,
        isOwner,
        c.CreatedAt
    );
}
