namespace HuTube.Application.Auth;

public sealed record ClientLocation(
    string? CountryCode,
    string? Region,
    string? City,
    double? Latitude,
    double? Longitude);

public interface IClientLocationResolver
{
    Task<ClientLocation?> ResolveAsync(string? ipAddress, CancellationToken ct = default);
}
