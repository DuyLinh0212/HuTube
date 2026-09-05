using System.Collections.Concurrent;
using HuTube.Application.Auth;
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

public sealed class AuthApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly string _databaseName = "hutube_test_" + Guid.NewGuid().ToString("N");
    private readonly string _adminConnection = Environment.GetEnvironmentVariable("TEST_DATABASE_CONNECTION")
        ?? throw new InvalidOperationException("TEST_DATABASE_CONNECTION is required. Integration tests always run against a real, isolated PostgreSQL database.");
    public string Connection { get; private set; } = "";
    public TestEmails Emails { get; } = new();
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
        builder.ConfigureServices(services => { services.RemoveAll<IAuthEmailSender>(); services.AddSingleton<IAuthEmailSender>(Emails); });
    }
    async Task IAsyncLifetime.DisposeAsync()
    {
        await base.DisposeAsync();
        NpgsqlConnection.ClearAllPools();
        await using var connection = new NpgsqlConnection(_adminConnection); await connection.OpenAsync();
        await using var command = new NpgsqlCommand($"DROP DATABASE IF EXISTS {_databaseName} WITH (FORCE)", connection); await command.ExecuteNonQueryAsync();
    }
}
