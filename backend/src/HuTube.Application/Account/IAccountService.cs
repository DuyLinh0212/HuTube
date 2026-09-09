namespace HuTube.Application.Account;

public interface IAccountService
{
    Task<UserProfileDto> GetProfileAsync(Guid userId, CancellationToken ct = default);
    Task<UserProfileDto> UpdateProfileAsync(Guid userId, UpdateProfileRequest request, CancellationToken ct = default);
    Task ChangePasswordAsync(Guid userId, ChangePasswordRequest request, CancellationToken ct = default);
    Task<NotificationSettingsDto> GetNotificationSettingsAsync(Guid userId, CancellationToken ct = default);
    Task<NotificationSettingsDto> UpdateNotificationSettingsAsync(Guid userId, UpdateNotificationSettingsRequest request, CancellationToken ct = default);
    Task<UserPreferencesDto> GetPreferencesAsync(Guid userId, CancellationToken ct = default);
    Task<UserPreferencesDto> UpdatePreferencesAsync(Guid userId, UpdateUserPreferencesRequest request, CancellationToken ct = default);
}
