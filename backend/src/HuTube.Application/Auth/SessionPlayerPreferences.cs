using System.ComponentModel.DataAnnotations;
using HuTube.Domain.Users;

namespace HuTube.Application.Auth;

public sealed record SessionPlayerPreferences(decimal Volume = 1m, bool Muted = false);
public sealed record UpdateSessionPlayerPreferencesRequest([Range(0d, 1d)] decimal Volume, bool Muted);

public interface ISessionPlayerPreferencesStore
{
    Task<SessionPlayerPreferences?> GetAsync(UserSession session, CancellationToken ct);
    Task SetAsync(UserSession session, SessionPlayerPreferences preferences, CancellationToken ct);
    Task RemoveAsync(Guid sessionId, CancellationToken ct);
}
