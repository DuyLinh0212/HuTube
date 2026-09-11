using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Account;

public sealed class AccountService(
    HuTubeDbContext db,
    IPasswordService passwordService) : IAccountService
{
    public async Task<UserProfileDto> GetProfileAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(u => u.UserId == userId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy thông tin tài khoản.");

        var prefs = await GetPreferencesAsync(userId, ct);

        return new UserProfileDto(
            user.UserId,
            user.Username,
            user.Email,
            user.DisplayName,
            user.AvatarUrl,
            prefs.Location != null ? user.Bio ?? "" : user.Bio,
            user.EmailVerifiedAt != null,
            user.CreatedAt
        );
    }

    public async Task<UserProfileDto> UpdateProfileAsync(Guid userId, UpdateProfileRequest request, CancellationToken ct = default)
    {
        var user = await db.Users.SingleOrDefaultAsync(u => u.UserId == userId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy thông tin tài khoản.");

        if (request.DisplayName is not null)
        {
            var trimmedName = request.DisplayName.Trim();
            if (trimmedName.Length is < 1 or > 120)
                throw new AuthException(400, "INVALID_DISPLAY_NAME", "Tên hiển thị cần từ 1 đến 120 ký tự.");
            user.DisplayName = trimmedName;
        }

        if (request.AvatarUrl is not null)
        {
            user.AvatarUrl = request.AvatarUrl.Trim();
        }

        if (request.Bio is not null)
        {
            user.Bio = request.Bio.Trim();
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return await GetProfileAsync(userId, ct);
    }

    public async Task ChangePasswordAsync(Guid userId, ChangePasswordRequest request, CancellationToken ct = default)
    {
        var user = await db.Users.SingleOrDefaultAsync(u => u.UserId == userId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy thông tin tài khoản.");

        if (string.IsNullOrWhiteSpace(request.CurrentPassword))
            throw new AuthException(400, "CURRENT_PASSWORD_REQUIRED", "Vui lòng nhập mật khẩu hiện tại.");

        if (!passwordService.Verify(request.CurrentPassword, user.PasswordHash))
            throw new AuthException(400, "INVALID_CURRENT_PASSWORD", "Mật khẩu hiện tại chưa chính xác.");

        AuthRules.ValidatePassword(request.NewPassword);

        if (request.CurrentPassword == request.NewPassword)
            throw new AuthException(400, "SAME_PASSWORD", "Mật khẩu mới không được trùng với mật khẩu hiện tại.");

        user.PasswordHash = passwordService.Hash(request.NewPassword);
        user.UpdatedAt = DateTimeOffset.UtcNow;

        // Revoke all refresh tokens for security
        var now = DateTimeOffset.UtcNow;
        var activeSessions = await db.Sessions
            .Where(s => s.UserId == userId && s.RevokedAt == null && s.ExpiresAt > now)
            .ToListAsync(ct);

        foreach (var session in activeSessions)
        {
            session.Revoke(now, "Password changed");
        }

        await db.SaveChangesAsync(ct);
    }

    public async Task<NotificationSettingsDto> GetNotificationSettingsAsync(Guid userId, CancellationToken ct = default)
    {
        var settings = await db.NotificationSettings.AsNoTracking().SingleOrDefaultAsync(n => n.UserId == userId, ct);
        if (settings == null)
        {
            return new NotificationSettingsDto(
                InAppEnabled: true,
                EmailEnabled: true,
                NewVideoEnabled: true,
                CommentReplyEnabled: true,
                ReportResultEnabled: true,
                ModerationEnabled: true,
                PlanEnabled: true,
                RecommendationEnabled: true,
                MentionEnabled: true,
                ChannelActivityEnabled: true,
                PaymentEnabled: true
            );
        }

        return new NotificationSettingsDto(
            settings.InAppEnabled,
            settings.EmailEnabled,
            settings.NewVideoEnabled,
            settings.CommentReplyEnabled,
            settings.ReportResultEnabled,
            settings.ModerationEnabled,
            settings.PlanEnabled,
            settings.RecommendationEnabled,
            settings.MentionEnabled,
            settings.ChannelActivityEnabled,
            settings.PaymentEnabled
        );
    }

    public async Task<NotificationSettingsDto> UpdateNotificationSettingsAsync(Guid userId, UpdateNotificationSettingsRequest request, CancellationToken ct = default)
    {
        var settings = await db.NotificationSettings.SingleOrDefaultAsync(n => n.UserId == userId, ct);
        if (settings == null)
        {
            settings = new NotificationSetting { UserId = userId };
            db.NotificationSettings.Add(settings);
        }

        settings.InAppEnabled = request.InAppEnabled;
        settings.EmailEnabled = request.EmailEnabled;
        settings.NewVideoEnabled = request.NewVideoEnabled;
        settings.CommentReplyEnabled = request.CommentReplyEnabled;
        settings.ReportResultEnabled = request.ReportResultEnabled;
        settings.ModerationEnabled = request.ModerationEnabled;
        settings.PlanEnabled = request.PlanEnabled;
        settings.RecommendationEnabled = request.RecommendationEnabled;
        settings.MentionEnabled = request.MentionEnabled;
        settings.ChannelActivityEnabled = request.ChannelActivityEnabled;
        settings.PaymentEnabled = request.PaymentEnabled;
        settings.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        return new NotificationSettingsDto(
            settings.InAppEnabled,
            settings.EmailEnabled,
            settings.NewVideoEnabled,
            settings.CommentReplyEnabled,
            settings.ReportResultEnabled,
            settings.ModerationEnabled,
            settings.PlanEnabled,
            settings.RecommendationEnabled,
            settings.MentionEnabled,
            settings.ChannelActivityEnabled,
            settings.PaymentEnabled
        );
    }

    public async Task<UserPreferencesDto> GetPreferencesAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.UserId == userId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy thông tin tài khoản.");
        return new(user.PreferredLanguage, user.Theme, user.KeepSubscriptionsPrivate, user.KeepPlaylistsPrivate, user.Location);
    }

    public async Task<UserPreferencesDto> UpdatePreferencesAsync(Guid userId, UpdateUserPreferencesRequest request, CancellationToken ct = default)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.UserId == userId, ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy thông tin tài khoản.");
        if (request.Language != null && request.Language is not ("vi" or "en"))
            throw new AuthException(400, "INVALID_LANGUAGE", "Ngôn ngữ chỉ hỗ trợ vi hoặc en.");
        if (request.Theme != null && request.Theme is not ("light" or "dark" or "system"))
            throw new AuthException(400, "INVALID_THEME", "Giao diện chỉ hỗ trợ light, dark hoặc system.");
        user.PreferredLanguage = request.Language ?? user.PreferredLanguage;
        user.Theme = request.Theme ?? user.Theme;
        user.KeepSubscriptionsPrivate = request.KeepSubscriptionsPrivate ?? user.KeepSubscriptionsPrivate;
        user.KeepPlaylistsPrivate = request.KeepPlaylistsPrivate ?? user.KeepPlaylistsPrivate;
        user.Location = request.Location == null ? user.Location : string.IsNullOrWhiteSpace(request.Location) ? null : request.Location.Trim();
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return new(user.PreferredLanguage, user.Theme, user.KeepSubscriptionsPrivate, user.KeepPlaylistsPrivate, user.Location);
    }
}
