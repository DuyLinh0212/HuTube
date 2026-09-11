using System.Collections.Concurrent;
using HuTube.Application.Auth;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;

namespace HuTube.IntegrationTests;

public sealed class TestEmails : IAuthEmailSender
{
    public ConcurrentDictionary<string, string> Bodies { get; } = new();
    public Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken) { Bodies[email] = body; return Task.CompletedTask; }
    public string Token(string email) => Uri.UnescapeDataString(Bodies[email].Split("?token=")[1]);
}
public sealed class TestGoogleTokenVerifier : IGoogleTokenVerifier
{
    public Task<GoogleIdentity> VerifyAsync(string credential, CancellationToken cancellationToken) => credential == "valid-google-token-123"
        ? Task.FromResult(new GoogleIdentity("google-subject-123", "google.user@example.com", "Google User", null))
        : throw new AuthException(401, "INVALID_GOOGLE_TOKEN", "Google token không hợp lệ.");
}
public sealed class TestObjectStorage : IObjectStorage
{
    public ConcurrentDictionary<string, byte[]> Objects { get; } = new();
    public Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) => SaveAsync(folder, fileName, content, ct);
    public Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) => SaveAsync(folder, fileName, content, ct);
    private async Task<string> SaveAsync(string folder, string fileName, Stream content, CancellationToken ct)
    {
        var path = $"test://{folder}/{Guid.NewGuid():N}{Path.GetExtension(fileName)}";
        using var buffer = new MemoryStream(); await content.CopyToAsync(buffer, ct); Objects[path] = buffer.ToArray(); return path;
    }
    public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default) => Task.FromResult(storedPath.Replace("test://", "https://storage.test/"));
    public Task DeleteFileAsync(string relativePath, CancellationToken ct = default) { Objects.TryRemove(relativePath, out _); return Task.CompletedTask; }
}

public sealed class TestVideoTranscoder : IVideoTranscoder
{
    public async Task<IReadOnlyList<TranscodedVideo>> CreateLowerRenditionsAsync(string sourceFilePath, string sourceQuality, string workingDirectory, CancellationToken ct = default)
    {
        var result = new List<TranscodedVideo>();
        foreach (var quality in HuTube.Domain.Videos.VideoRules.LowerQualities(sourceQuality))
        {
            var height = HuTube.Domain.Videos.VideoRules.QualityHeight(quality);
            var output = Path.Combine(workingDirectory, quality + ".mp4");
            await using var source = File.OpenRead(sourceFilePath);
            await using var target = File.Create(output);
            await source.CopyToAsync(target, ct);
            result.Add(new(quality, height * 16 / 9, height, 1000, output, source.Length));
        }
        return result;
    }
}

public class AuthApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly string _databaseName = "hutube_test_" + Guid.NewGuid().ToString("N");
    private readonly string _adminConnection = Environment.GetEnvironmentVariable("TEST_DATABASE_CONNECTION")
        ?? throw new InvalidOperationException("TEST_DATABASE_CONNECTION is required. Integration tests always run against a real, isolated PostgreSQL database.");
    public string Connection { get; private set; } = "";
    public TestEmails Emails { get; } = new();
    public TestObjectStorage Storage { get; } = new();
    public async Task InitializeAsync()
    {
        await using var connection = new NpgsqlConnection(_adminConnection); await connection.OpenAsync();
        await using var command = new NpgsqlCommand($"CREATE DATABASE {_databaseName}", connection); await command.ExecuteNonQueryAsync();
        var builder = new NpgsqlConnectionStringBuilder(_adminConnection) { Database = _databaseName };
        Connection = builder.ConnectionString;
        await using var db = CreateDb(); await db.Database.MigrateAsync();
        // Migration creates citext after Npgsql first loads types. Production migrates in a
        // separate process; this fixture hosts both steps and must refresh its type cache.
        await db.Database.OpenConnectionAsync();
        await ((NpgsqlConnection)db.Database.GetDbConnection()).ReloadTypesAsync();
        await db.Database.CloseConnectionAsync();
    }
    public HuTubeDbContext CreateDb() => new(new DbContextOptionsBuilder<HuTubeDbContext>().UseNpgsql(Connection).Options);
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("ConnectionStrings:Database", Connection);
        builder.UseSetting("Jwt:SigningKey", new string('t', 80));
        builder.UseSetting("Email:Mode", "Pickup");
        builder.UseSetting("RateLimit:AuthPermitLimit", "10000");
        builder.UseSetting("Auth:WebBaseUrl", "http://localhost:4200");
        builder.UseSetting("Auth:AdminBaseUrl", "http://localhost:4201");
        builder.UseSetting("Auth:AllowedOrigins:0", "");
        builder.UseSetting("Auth:AllowedOrigins:1", "");
        builder.UseSetting("Features:ModerationEnabled", "true");
        builder.UseSetting("Features:PlanEnforcementEnabled", "true");
        builder.ConfigureServices(services => { services.RemoveAll<IAuthEmailSender>(); services.RemoveAll<IGoogleTokenVerifier>(); services.RemoveAll<IObjectStorage>(); services.RemoveAll<IVideoTranscoder>(); services.AddSingleton<IAuthEmailSender>(Emails); services.AddSingleton<IGoogleTokenVerifier, TestGoogleTokenVerifier>(); services.AddSingleton<IObjectStorage>(Storage); services.AddSingleton<IVideoTranscoder, TestVideoTranscoder>(); });
    }
    async Task IAsyncLifetime.DisposeAsync()
    {
        await base.DisposeAsync();
        NpgsqlConnection.ClearAllPools();
        await using var connection = new NpgsqlConnection(_adminConnection); await connection.OpenAsync();
        await using var command = new NpgsqlCommand($"DROP DATABASE IF EXISTS {_databaseName} WITH (FORCE)", connection); await command.ExecuteNonQueryAsync();
    }
}
