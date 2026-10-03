using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Videos;

public sealed class StrikePolicySettingsService(HuTubeDbContext db, RbacService rbac)
{
    public async Task<StrikePolicySettingsDto> GetAsync(CancellationToken ct = default)
    {
        var settings = await db.StrikePolicyConfigurations.AsNoTracking()
            .SingleOrDefaultAsync(x => x.Id == StrikePolicyConfiguration.SingletonId, ct);
        return ToDto(settings ?? new StrikePolicyConfiguration());
    }

    public async Task<StrikePolicySettingsDto> UpdateAsync(
        Guid actorId,
        UpdateStrikePolicySettingsRequest request,
        CancellationToken ct = default)
    {
        Validate(request);

        var settings = await db.StrikePolicyConfigurations
            .SingleOrDefaultAsync(x => x.Id == StrikePolicyConfiguration.SingletonId, ct);
        var rejectionThresholdChanged = settings is null || settings.RejectedVideosPerStrike != request.RejectedVideosPerStrike;
        if (settings is null)
        {
            settings = new StrikePolicyConfiguration();
            db.StrikePolicyConfigurations.Add(settings);
        }

        var now = DateTimeOffset.UtcNow;
        settings.RejectedVideosPerStrike = request.RejectedVideosPerStrike;
        settings.FirstStrikeRestrictionDays = request.FirstStrikeRestrictionDays;
        settings.SecondStrikeRestrictionDays = request.SecondStrikeRestrictionDays;
        settings.StrikeExpirationDays = request.StrikeExpirationDays;
        settings.SuspensionStrikeCount = request.SuspensionStrikeCount;
        if (rejectionThresholdChanged) settings.RejectedVideosEffectiveAt = now;
        settings.UpdatedAt = now;
        await db.SaveChangesAsync(ct);

        await rbac.LogAuditAsync(new AuditLogEntry(
            actorId,
            "strike.policy.update",
            "strike_policy_settings",
            null,
            $"Cập nhật quy tắc gậy: {settings.RejectedVideosPerStrike} video bị từ chối / gậy; khóa ở {settings.SuspensionStrikeCount} gậy; hạn chế {settings.FirstStrikeRestrictionDays}/{settings.SecondStrikeRestrictionDays} ngày; hiệu lực {settings.StrikeExpirationDays} ngày."), ct);

        return ToDto(settings);
    }

    public static int RestrictionDaysFor(int strikeNumber, StrikePolicySettingsDto settings) =>
        strikeNumber <= 1 ? settings.FirstStrikeRestrictionDays : settings.SecondStrikeRestrictionDays;

    private static StrikePolicySettingsDto ToDto(StrikePolicyConfiguration settings) => new(
        settings.RejectedVideosPerStrike,
        settings.FirstStrikeRestrictionDays,
        settings.SecondStrikeRestrictionDays,
        settings.StrikeExpirationDays,
        settings.SuspensionStrikeCount,
        settings.RejectedVideosEffectiveAt,
        settings.UpdatedAt);

    private static void Validate(UpdateStrikePolicySettingsRequest request)
    {
        if (request.RejectedVideosPerStrike is < 1 or > 100)
            throw new AuthException(400, "STRIKE_POLICY_INVALID", "Số video bị từ chối cho mỗi gậy phải từ 1 đến 100.");
        if (request.FirstStrikeRestrictionDays is < 0 or > 365)
            throw new AuthException(400, "STRIKE_POLICY_INVALID", "Thời hạn hạn chế của gậy 1 phải từ 0 đến 365 ngày.");
        if (request.SecondStrikeRestrictionDays is < 0 or > 365 || request.SecondStrikeRestrictionDays < request.FirstStrikeRestrictionDays)
            throw new AuthException(400, "STRIKE_POLICY_INVALID", "Thời hạn gậy 2 phải từ thời hạn gậy 1 đến 365 ngày.");
        if (request.StrikeExpirationDays is < 1 or > 3650
            || request.StrikeExpirationDays < request.SecondStrikeRestrictionDays)
            throw new AuthException(400, "STRIKE_POLICY_INVALID", "Thời hạn hiệu lực của gậy phải từ 1 đến 3650 ngày và không ngắn hơn thời hạn hạn chế tải lên.");
        if (request.SuspensionStrikeCount is < 3 or > 10)
            throw new AuthException(400, "STRIKE_POLICY_INVALID", "Ngưỡng khóa kênh phải từ 3 đến 10 gậy đang hiệu lực.");
    }
}
