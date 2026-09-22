using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public sealed class StrikeService(
    HuTubeDbContext db,
    RbacService rbac,
    INotificationService notifications)
{
    public async Task<ChannelStrikeStatusResponse> GetChannelStrikeStatusAsync(Guid channelId, CancellationToken ct = default)
    {
        var channel = await db.Channels.AsNoTracking().FirstOrDefaultAsync(c => c.ChannelId == channelId, ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var now = DateTimeOffset.UtcNow;
        var strikes = await db.ChannelStrikes.AsNoTracking()
            .Where(s => s.ChannelId == channelId)
            .OrderByDescending(s => s.CreatedAt)
            .ToListAsync(ct);

        var activeStrikes = strikes.Where(s => s.IsActive(now)).ToList();
        var activeCount = activeStrikes.Count;
        var hasWarning = strikes.Any(s => s.Severity == StrikeSeverities.Low || s.StrikeNumber == 0);

        DateTimeOffset? uploadRestrictedUntil = null;
        if (channel.Status == "suspended")
        {
            uploadRestrictedUntil = DateTimeOffset.MaxValue;
        }
        else if (activeStrikes.Count > 0)
        {
            var newestActive = activeStrikes[0];
            var days = newestActive.StrikeNumber >= 2 ? 14 : 7;
            var restrictionEnd = newestActive.CreatedAt.AddDays(days);
            if (restrictionEnd > now)
            {
                uploadRestrictedUntil = restrictionEnd;
            }
        }

        var dtos = strikes.Select(s => new ChannelStrikeDto(
            s.StrikeId,
            s.ChannelId,
            channel.Name,
            s.UserId,
            s.StrikeNumber,
            s.Severity,
            s.PolicyCode,
            s.Reason,
            s.InternalNote,
            s.ExpiresAt <= now && s.Status == StrikeStatuses.Active ? StrikeStatuses.Expired : s.Status,
            s.ExpiresAt,
            s.CreatedAt,
            s.RevokedAt,
            s.RevokedByUserId,
            s.RevocationReason,
            channel.Handle,
            channel.Status
        )).ToList();

        return new ChannelStrikeStatusResponse(
            channelId,
            activeCount,
            hasWarning,
            channel.Status == "suspended",
            uploadRestrictedUntil,
            dtos
        );
    }

    public async Task<List<ChannelStrikeDto>> GetAdminStrikesAsync(
        Guid? channelId = null,
        string? status = null,
        int page = 1,
        int pageSize = 50,
        CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var now = DateTimeOffset.UtcNow;
        var query = db.ChannelStrikes.AsNoTracking();

        if (channelId.HasValue)
        {
            query = query.Where(s => s.ChannelId == channelId.Value);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim().ToLowerInvariant();
            query = s switch
            {
                "active" => query.Where(x => x.Status == StrikeStatuses.Active && x.ExpiresAt > now),
                "expired" => query.Where(x => x.Status == StrikeStatuses.Expired || (x.Status == StrikeStatuses.Active && x.ExpiresAt <= now)),
                "revoked" => query.Where(x => x.Status == StrikeStatuses.Revoked),
                _ => query
            };
        }

        var strikes = await query
            .OrderByDescending(s => s.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        if (strikes.Count == 0) return [];

        var channelIds = strikes.Select(s => s.ChannelId).Distinct().ToList();
        var channels = await db.Channels.AsNoTracking()
            .Where(c => channelIds.Contains(c.ChannelId))
            .ToDictionaryAsync(c => c.ChannelId, c => new { c.Name, c.Handle, c.Status }, ct);

        return strikes.Select(s =>
        {
            channels.TryGetValue(s.ChannelId, out var ch);
            return new ChannelStrikeDto(
                s.StrikeId,
                s.ChannelId,
                ch?.Name ?? "Kênh không xác định",
                s.UserId,
                s.StrikeNumber,
                s.Severity,
                s.PolicyCode,
                s.Reason,
                s.InternalNote,
                s.ExpiresAt <= now && s.Status == StrikeStatuses.Active ? StrikeStatuses.Expired : s.Status,
                s.ExpiresAt,
                s.CreatedAt,
                s.RevokedAt,
                s.RevokedByUserId,
                s.RevocationReason,
                ch?.Handle,
                ch?.Status
            );
        }).ToList();
    }

    public async Task<ChannelStrikeDto> CreateManualStrikeAsync(Guid actorId, CreateStrikeRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(request.Reason))
            throw new AuthException(400, "REASON_REQUIRED", "Bắt buộc nhập lý do áp dụng gậy/cảnh cáo.");

        var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == request.ChannelId, ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh cần xử lý.");

        var now = DateTimeOffset.UtcNow;
        var activeStrikesCount = await db.ChannelStrikes
            .CountAsync(s => s.ChannelId == request.ChannelId && s.Status == StrikeStatuses.Active && s.ExpiresAt > now, ct);

        var nextStrikeNumber = activeStrikesCount + 1;
        var severity = string.IsNullOrWhiteSpace(request.Severity) ? StrikeSeverities.High : request.Severity.Trim().ToLowerInvariant();

        var strike = new ChannelStrike
        {
            ChannelId = channel.ChannelId,
            UserId = channel.OwnerUserId,
            StrikeNumber = nextStrikeNumber,
            Severity = severity,
            PolicyCode = request.PolicyCode?.Trim(),
            Reason = request.Reason.Trim(),
            InternalNote = request.InternalNote?.Trim(),
            Status = StrikeStatuses.Active,
            ExpiresAt = now.AddDays(90),
            CreatedAt = now
        };

        db.ChannelStrikes.Add(strike);

        if (nextStrikeNumber >= 3)
        {
            channel.Status = "suspended";
            channel.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            "strike.create",
            "channel",
            channel.ChannelId,
            $"Áp dụng Strike {nextStrikeNumber} ({severity}) cho kênh '{channel.Name}'. Lý do: {request.Reason}"
        ), ct);

        await notifications.PublishAsync(
            channel.OwnerUserId,
            "channel_strike",
            $"Kênh nhận Gậy phạt {nextStrikeNumber}",
            $"Kênh '{channel.Name}' vừa nhận Gậy phạt {nextStrikeNumber} do vi phạm chính sách {request.PolicyCode ?? ""}. Lý do: {request.Reason}",
            "/studio",
            "channel",
            channel.ChannelId,
            ct
        );

        return new ChannelStrikeDto(
            strike.StrikeId,
            strike.ChannelId,
            channel.Name,
            strike.UserId,
            strike.StrikeNumber,
            strike.Severity,
            strike.PolicyCode,
            strike.Reason,
            strike.InternalNote,
            strike.Status,
            strike.ExpiresAt,
            strike.CreatedAt,
            strike.RevokedAt,
            strike.RevokedByUserId,
            strike.RevocationReason,
            channel.Handle,
            channel.Status
        );
    }

    public async Task<ChannelStrikeDto> RevokeStrikeAsync(Guid actorId, Guid strikeId, RevokeStrikeRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(request.Reason))
            throw new AuthException(400, "REASON_REQUIRED", "Bắt buộc nhập lý do thu hồi gậy.");

        var strike = await db.ChannelStrikes.FirstOrDefaultAsync(s => s.StrikeId == strikeId, ct)
            ?? throw new AuthException(404, "STRIKE_NOT_FOUND", "Không tìm thấy bản ghi gậy phạt.");

        if (strike.Status == StrikeStatuses.Revoked)
            throw new AuthException(409, "STRIKE_ALREADY_REVOKED", "Gậy này đã được thu hồi trước đó.");

        var now = DateTimeOffset.UtcNow;
        strike.Status = StrikeStatuses.Revoked;
        strike.RevokedAt = now;
        strike.RevokedByUserId = actorId;
        strike.RevocationReason = request.Reason.Trim();

        var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == strike.ChannelId, ct);
        if (channel != null && channel.Status == "suspended")
        {
            // If channel was suspended, check remaining active strikes
            var remainingActive = await db.ChannelStrikes
                .CountAsync(s => s.ChannelId == channel.ChannelId && s.StrikeId != strikeId && s.Status == StrikeStatuses.Active && s.ExpiresAt > now, ct);

            if (remainingActive < 3)
            {
                channel.Status = "active";
                channel.UpdatedAt = now;
            }
        }

        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            "strike.revoke",
            "channel_strike",
            strike.StrikeId,
            $"Thu hồi Strike {strike.StrikeNumber} của kênh {strike.ChannelId}. Lý do: {request.Reason}"
        ), ct);

        if (channel != null)
        {
            await notifications.PublishAsync(
                channel.OwnerUserId,
                "strike_revoked",
                "Gậy phạt đã được thu hồi",
                $"Gậy phạt vi phạm chính sách của kênh '{channel.Name}' đã được xem xét và thu hồi thành công.",
                "/studio",
                "channel",
                channel.ChannelId,
                ct
            );
        }

        return new ChannelStrikeDto(
            strike.StrikeId,
            strike.ChannelId,
            channel?.Name ?? "Kênh không xác định",
            strike.UserId,
            strike.StrikeNumber,
            strike.Severity,
            strike.PolicyCode,
            strike.Reason,
            strike.InternalNote,
            strike.Status,
            strike.ExpiresAt,
            strike.CreatedAt,
            strike.RevokedAt,
            strike.RevokedByUserId,
            strike.RevocationReason,
            channel?.Handle,
            channel?.Status
        );
    }

    public async Task<bool> SetChannelLockAsync(Guid actorId, Guid channelId, bool lockChannel, string reason, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(reason))
            throw new AuthException(400, "REASON_REQUIRED", "Bắt buộc nhập lý do khóa hoặc mở khóa kênh.");

        var channel = await db.Channels.FirstOrDefaultAsync(c => c.ChannelId == channelId, ct)
            ?? throw new AuthException(404, "CHANNEL_NOT_FOUND", "Không tìm thấy kênh.");

        var now = DateTimeOffset.UtcNow;
        channel.Status = lockChannel ? "suspended" : "active";
        channel.UpdatedAt = now;

        await db.SaveChangesAsync(ct);

        var action = lockChannel ? "channel.lock" : "channel.unlock";
        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            action,
            "channel",
            channel.ChannelId,
            $"{(lockChannel ? "Khóa" : "Mở khóa")} kênh '{channel.Name}'. Lý do: {reason}"
        ), ct);

        await notifications.PublishAsync(
            channel.OwnerUserId,
            lockChannel ? "channel_suspended" : "channel_restored",
            lockChannel ? "Kênh của bạn đã bị khóa" : "Kênh của bạn đã được mở khóa",
            lockChannel
                ? $"Kênh '{channel.Name}' đã bị tạm ngưng hoạt động. Lý do: {reason}"
                : $"Kênh '{channel.Name}' đã được khôi phục hoạt động bình thường.",
            "/studio",
            "channel",
            channel.ChannelId,
            ct
        );

        return true;
    }
}
