using HuTube.Domain.Channels;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

internal static class VideoAccessPolicy
{
    public static IQueryable<Video> Catalogue(HuTubeDbContext db) => db.Videos.AsNoTracking().Where(video =>
        video.Status == "published" && video.ModerationStatus == "approved" && video.Visibility == "public"
        && !video.ModerationHidden && !video.RecommendationRestricted && video.MediaPurgedAt == null && video.MediaPurgeStartedAt == null
        && db.Channels.Any(channel => channel.ChannelId == video.ChannelId && channel.Status == "active"));

    public static async Task<bool> CanViewAsync(HuTubeDbContext db, Video video, Guid? viewerId, CancellationToken ct)
    {
        if (video.Status == "deleted" || video.MediaPurgedAt.HasValue || video.MediaPurgeStartedAt.HasValue || video.ModerationHidden) return false;
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(x => x.ChannelId == video.ChannelId, ct);
        if (channel?.Status != "active") return false;
        if (video.Status == "published" && video.ModerationStatus == "approved" && video.Visibility is "public" or "unlisted") return true;
        if (!viewerId.HasValue) return false;
        if (channel.OwnerUserId == viewerId) return true;
        var role = await db.ChannelMembers.AsNoTracking().Where(x => x.ChannelId == video.ChannelId && x.UserId == viewerId && x.Status == "active")
            .Select(x => x.RoleCode).SingleOrDefaultAsync(ct);
        return ChannelPermissions.RoleHas(role, ChannelPermissions.VideoView);
    }
}
