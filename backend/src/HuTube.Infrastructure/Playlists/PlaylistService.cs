using HuTube.Application.Playlists;
using HuTube.Application.Storage;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Playlists;

public sealed class PlaylistService(HuTubeDbContext db, IObjectStorage storage, TimeProvider clock) : IPlaylistService
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<IReadOnlyList<PlaylistSummaryResponse>> GetMineAsync(Guid userId, CancellationToken ct = default) =>
        await db.Playlists.AsNoTracking().Where(x => x.UserId == userId)
            .OrderByDescending(x => x.UpdatedAt)
            .Select(x => new PlaylistSummaryResponse(x.PlaylistId, x.UserId, x.Name, x.Description, x.Visibility,
                db.PlaylistVideos.Count(v => v.PlaylistId == x.PlaylistId), x.UpdatedAt))
            .ToListAsync(ct);

    public async Task<IReadOnlyList<PlaylistSummaryResponse>> GetPublicByChannelAsync(Guid channelId, CancellationToken ct = default)
    {
        var ownerUserId = await db.Channels.AsNoTracking()
            .Where(x => x.ChannelId == channelId && x.Status == "active")
            .Select(x => (Guid?)x.OwnerUserId)
            .SingleOrDefaultAsync(ct)
            ?? throw Error(404, "CHANNEL_NOT_FOUND", "Khong tim thay kenh.");

        return await db.Playlists.AsNoTracking()
            .Where(x => x.UserId == ownerUserId && x.Visibility == "public")
            .OrderByDescending(x => x.UpdatedAt)
            .Select(x => new PlaylistSummaryResponse(x.PlaylistId, x.UserId, x.Name, x.Description, x.Visibility,
                db.PlaylistVideos.Count(v => v.PlaylistId == x.PlaylistId), x.UpdatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<PlaylistSummaryResponse>> GetChannelMineAsync(Guid userId, Guid channelId, CancellationToken ct = default)
    {
        var ownsChannel = await db.Channels.AsNoTracking().AnyAsync(x => x.ChannelId == channelId && x.OwnerUserId == userId && x.Status == "active", ct);
        if (!ownsChannel) throw Error(403, "CHANNEL_OWNER_REQUIRED", "Chi chu kenh moi duoc xem playlist kenh.");
        return await db.Playlists.AsNoTracking()
            .Where(x => x.UserId == userId)
            .OrderByDescending(x => x.UpdatedAt)
            .Select(x => new PlaylistSummaryResponse(x.PlaylistId, x.UserId, x.Name, x.Description, x.Visibility,
                db.PlaylistVideos.Count(v => v.PlaylistId == x.PlaylistId), x.UpdatedAt))
            .ToListAsync(ct);
    }

    public async Task<PlaylistResponse> GetAsync(Guid playlistId, Guid? viewerId, CancellationToken ct = default)
    {
        var playlist = await db.Playlists.AsNoTracking().SingleOrDefaultAsync(x => x.PlaylistId == playlistId, ct)
            ?? throw Error(404, "PLAYLIST_NOT_FOUND", "Khong tim thay playlist.");
        if (playlist.Visibility == "private" && playlist.UserId != viewerId)
            throw Error(viewerId.HasValue ? 403 : 404, "PLAYLIST_NOT_PUBLIC", "Playlist nay khong duoc cong khai.");

        var rows = await (from item in db.PlaylistVideos.AsNoTracking()
                          join video in db.Videos.AsNoTracking() on item.VideoId equals video.VideoId into videos
                          from video in videos.DefaultIfEmpty()
                          where item.PlaylistId == playlistId
                          orderby item.Position
                          select new { Item = item, Video = video }).ToListAsync(ct);
        var items = new List<PlaylistItemResponse>(rows.Count);
        foreach (var row in rows)
        {
            var video = row.Video;
            var available = video != null && video.Status == "published" && (video.Visibility is "public" or "unlisted")
                && video.ModerationStatus == "approved";
            var reason = video == null || video.Status == "deleted" ? "deleted" : available ? null
                : video.Visibility == "private" ? "private"
                : video.ModerationStatus is "rejected" or "removed" ? "removed"
                : "unavailable";
            items.Add(new(row.Item.PlaylistVideoId, row.Item.VideoId, row.Item.Position,
                video?.Title, video?.ThumbnailUrl == null ? null : await storage.GetReadUrlAsync(video.ThumbnailUrl, TimeSpan.FromMinutes(60), ct),
                video?.Duration ?? 0, video?.Visibility, video?.Status, video?.ModerationStatus, available, reason));
        }
        return new(playlist.PlaylistId, playlist.UserId, playlist.Name, playlist.Description, playlist.Visibility,
            playlist.CreatedAt, playlist.UpdatedAt, items);
    }

    public async Task<PlaylistResponse> CreateAsync(Guid userId, CreatePlaylistRequest request, CancellationToken ct = default)
    {
        var name = request.Name.Trim();
        var visibility = NormalizeVisibility(request.Visibility);
        if (name.Length is 0 or > 150) throw Error(400, "INVALID_PLAYLIST_NAME", "Ten playlist khong hop le.");
        var playlist = new HuTube.Domain.Playlists.Playlist { UserId = userId, Name = name, Description = Clean(request.Description), Visibility = visibility, CreatedAt = Now, UpdatedAt = Now };
        db.Playlists.Add(playlist);
        await db.SaveChangesAsync(ct);
        return await GetAsync(playlist.PlaylistId, userId, ct);
    }

    public async Task<PlaylistResponse> SaveVideoAsync(Guid userId, SaveVideoRequest request, CancellationToken ct = default)
    {
        var playlist = await db.Playlists.SingleOrDefaultAsync(x => x.UserId == userId && x.Name == "Video đã lưu", ct);
        if (playlist == null)
        {
            playlist = new HuTube.Domain.Playlists.Playlist { UserId = userId, Name = "Video đã lưu", Visibility = "private", CreatedAt = Now, UpdatedAt = Now };
            db.Playlists.Add(playlist);
            await db.SaveChangesAsync(ct);
        }
        return await AddVideoAsync(userId, playlist.PlaylistId, new AddPlaylistVideoRequest(request.VideoId), ct);
    }

    public async Task<PlaylistResponse> UpdateAsync(Guid userId, Guid playlistId, UpdatePlaylistRequest request, CancellationToken ct = default)
    {
        var playlist = await OwnedAsync(userId, playlistId, ct);
        var name = request.Name.Trim();
        if (name.Length is 0 or > 150) throw Error(400, "INVALID_PLAYLIST_NAME", "Ten playlist khong hop le.");
        playlist.Name = name; playlist.Description = Clean(request.Description); playlist.Visibility = NormalizeVisibility(request.Visibility); playlist.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        return await GetAsync(playlistId, userId, ct);
    }

    public async Task DeleteAsync(Guid userId, Guid playlistId, CancellationToken ct = default)
    {
        var playlist = await OwnedAsync(userId, playlistId, ct);
        var items = await db.PlaylistVideos.Where(x => x.PlaylistId == playlistId).ToListAsync(ct);
        db.PlaylistVideos.RemoveRange(items);
        db.Playlists.Remove(playlist);
        await db.SaveChangesAsync(ct);
    }

    public async Task<PlaylistResponse> AddVideoAsync(Guid userId, Guid playlistId, AddPlaylistVideoRequest request, CancellationToken ct = default)
    {
        var playlist = await OwnedAsync(userId, playlistId, ct);
        var video = await db.Videos.AsNoTracking().SingleOrDefaultAsync(x => x.VideoId == request.VideoId && x.Status != "deleted", ct)
            ?? throw Error(404, "VIDEO_NOT_FOUND", "Khong tim thay video.");
        if (video.Status != "published" || video.ModerationStatus != "approved" || video.Visibility != "public")
            throw Error(403, "VIDEO_NOT_SAVABLE", "Chi co the luu video dang cong khai.");
        if (await db.PlaylistVideos.AnyAsync(x => x.PlaylistId == playlistId && x.VideoId == request.VideoId, ct))
            throw Error(409, "PLAYLIST_VIDEO_EXISTS", "Video da co trong playlist.");
        var position = (await db.PlaylistVideos.Where(x => x.PlaylistId == playlistId).Select(x => (int?)x.Position).MaxAsync(ct) ?? 0) + 1;
        db.PlaylistVideos.Add(new HuTube.Domain.Playlists.PlaylistVideo { PlaylistId = playlistId, VideoId = video.VideoId, Position = position, AddedAt = Now });
        playlist.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        return await GetAsync(playlistId, userId, ct);
    }

    public async Task RemoveVideoAsync(Guid userId, Guid playlistId, Guid videoId, CancellationToken ct = default)
    {
        var playlist = await OwnedAsync(userId, playlistId, ct);
        var item = await db.PlaylistVideos.SingleOrDefaultAsync(x => x.PlaylistId == playlistId && x.VideoId == videoId, ct)
            ?? throw Error(404, "PLAYLIST_VIDEO_NOT_FOUND", "Video khong co trong playlist.");
        db.PlaylistVideos.Remove(item); playlist.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        var rest = await db.PlaylistVideos.Where(x => x.PlaylistId == playlistId).OrderBy(x => x.Position).ToListAsync(ct);
        for (var i = 0; i < rest.Count; i++) rest[i].Position = i + 1;
        await db.SaveChangesAsync(ct);
    }

    public async Task<PlaylistResponse> ReorderAsync(Guid userId, Guid playlistId, ReorderPlaylistRequest request, CancellationToken ct = default)
    {
        var playlist = await OwnedAsync(userId, playlistId, ct);
        var items = await db.PlaylistVideos.Where(x => x.PlaylistId == playlistId).ToListAsync(ct);
        if (request.VideoIds.Count != items.Count || request.VideoIds.Distinct().Count() != items.Count || items.Any(x => !request.VideoIds.Contains(x.VideoId)))
            throw Error(400, "INVALID_PLAYLIST_ORDER", "Thu tu playlist khong hop le.");
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        try
        {
            var lookup = items.ToDictionary(x => x.VideoId);
            var offset = items.Count + 1;
            for (var i = 0; i < request.VideoIds.Count; i++) lookup[request.VideoIds[i]].Position = offset + i;
            await db.SaveChangesAsync(ct);

            for (var i = 0; i < request.VideoIds.Count; i++) lookup[request.VideoIds[i]].Position = i + 1;
            playlist.UpdatedAt = Now;
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        return await GetAsync(playlistId, userId, ct);
    }

    private async Task<HuTube.Domain.Playlists.Playlist> OwnedAsync(Guid userId, Guid playlistId, CancellationToken ct) =>
        await db.Playlists.SingleOrDefaultAsync(x => x.PlaylistId == playlistId && x.UserId == userId, ct)
        ?? throw Error(403, "PLAYLIST_OWNER_REQUIRED", "Chi chu playlist moi duoc thao tac.");
    private static string NormalizeVisibility(string value) => value.Trim().ToLowerInvariant() switch { "public" => "public", "unlisted" => "unlisted", _ => "private" };
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static PlaylistException Error(int status, string code, string message) => new(status, code, message);
}
