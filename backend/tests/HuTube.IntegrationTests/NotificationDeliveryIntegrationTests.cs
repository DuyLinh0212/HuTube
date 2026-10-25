using HuTube.Application.Auth;
using HuTube.Application.Notifications;
using HuTube.Application.Serialization;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Notifications;
using HuTube.Infrastructure.Persistence;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HuTube.IntegrationTests;

public sealed class NotificationDeliveryIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Emails : IAuthEmailSender
    {
        public bool Fail { get; set; }
        public int Sent { get; set; }
        public Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken)
        { if (Fail) throw new IOException("Simulated mail outage"); Sent++; return Task.CompletedTask; }
    }
    private sealed class Push : IPushNotificationSender
    {
        public bool Enabled => true;
        public List<string> Tokens { get; } = [];
        public Task<bool> SendAsync(string token, NotificationMessage message, Guid notificationId, CancellationToken ct)
        { Tokens.Add(token); return Task.FromResult(token != "invalid-token"); }
    }
    private sealed class Hub : IHubContext<NotificationHub>, IHubClients, IClientProxy
    {
        public List<(string User, string Method)> Calls { get; } = [];
        private string user = "";
        public IHubClients Clients => this;
        public IGroupManager Groups => throw new NotSupportedException();
        public IClientProxy User(string userId) { user = userId; return this; }
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
        { Calls.Add((user, method)); return Task.CompletedTask; }
        public IClientProxy All => throw new NotSupportedException();
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
        public IClientProxy Client(string connectionId) => throw new NotSupportedException();
        IClientProxy IHubClients<IClientProxy>.Clients(IReadOnlyList<string> connectionIds) => throw new NotSupportedException();
        public IClientProxy Group(string groupName) => throw new NotSupportedException();
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
        IClientProxy IHubClients<IClientProxy>.Groups(IReadOnlyList<string> groupNames) => throw new NotSupportedException();
        public IClientProxy Users(IReadOnlyList<string> userIds) => throw new NotSupportedException();
    }
    private async Task<(User User, UserSession Session)> PersonAsync()
    {
        await using var db = factory.CreateDb();
        var user = new User { Username = "delivery_" + Guid.NewGuid().ToString("N")[..10], Email = $"{Guid.NewGuid():N}@example.test",
            DisplayName = "Delivery fixture", PasswordHash = "fixture", RoleId = UserRoles.User, Status = "active" };
        db.Users.Add(user); await db.SaveChangesAsync();
        var session = new UserSession { UserId = user.UserId, RefreshTokenHash = Guid.NewGuid().ToString("N"), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1) };
        db.Sessions.Add(session); await db.SaveChangesAsync();
        return (user, session);
    }
    private async Task<Guid> SeedDeliveryAsync(Guid userId)
    {
        await using var db = factory.CreateDb();
        var row = new Notification { UserId = userId, Type = "video_approved", Title = "Video approved", Content = "Ready", ActionUrl = "/studio", CreatedAt = DateTimeOffset.UtcNow };
        db.Notifications.Add(row);
        var delivery = new NotificationDelivery { DeliveryId = Guid.NewGuid(), EventId = Guid.NewGuid(), UserId = userId,
            NotificationId = row.NotificationId, Type = row.Type, AvailableAt = DateTimeOffset.UtcNow,
            Payload = PersistenceJson.Serialize(new NotificationMessage(userId, row.Type, row.Title, row.Content, row.ActionUrl, "video", Guid.NewGuid())) };
        db.NotificationDeliveries.Add(delivery); await db.SaveChangesAsync(); return delivery.DeliveryId;
    }
    private async Task DeliverAsync(Hub hub, Emails emails, Push push, Clock clock)
    {
        await using var db = factory.CreateDb();
        await new NotificationDeliveryProcessor(db, hub, emails, push, new AuthOptions { WebBaseUrl = "https://dalitu.app" }, clock,
            NullLogger<NotificationDeliveryProcessor>.Instance).DeliverNextAsync();
    }

    [Fact]
    public async Task DeliveryRetriesOnlyFailedChannels_AndIgnoresLoggedOutDevices()
    {
        var (user, session) = await PersonAsync(); var id = await SeedDeliveryAsync(user.UserId);
        await using (var db = factory.CreateDb())
        {
            var revoked = new UserSession { UserId = user.UserId, RefreshTokenHash = Guid.NewGuid().ToString("N"), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1), RevokedAt = DateTimeOffset.UtcNow };
            db.Sessions.Add(revoked); await db.SaveChangesAsync();
            db.PushDevices.AddRange(
                new PushDevice { UserId = user.UserId, SessionId = session.SessionId, Token = "valid-token", TokenHash = Guid.NewGuid().ToString("N"), UpdatedAt = DateTimeOffset.UtcNow },
                new PushDevice { UserId = user.UserId, SessionId = session.SessionId, Token = "invalid-token", TokenHash = Guid.NewGuid().ToString("N"), UpdatedAt = DateTimeOffset.UtcNow },
                new PushDevice { UserId = user.UserId, SessionId = revoked.SessionId, Token = "revoked-token", TokenHash = Guid.NewGuid().ToString("N"), UpdatedAt = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        }
        var hub = new Hub(); var emails = new Emails { Fail = true }; var push = new Push(); var clock = new Clock();
        await DeliverAsync(hub, emails, push, clock);
        await using (var db = factory.CreateDb())
        {
            var pending = (await db.NotificationDeliveries.FindAsync(id))!;
            Assert.Null(pending.CompletedAt); Assert.True(pending.RealtimeDone); Assert.True(pending.PushDone); Assert.False(pending.EmailDone);
            Assert.Equal(1, pending.Attempts);
            Assert.False(await db.PushDevices.AnyAsync(device => device.UserId == user.UserId && device.Token == "invalid-token"));
        }
        Assert.Equal(2, hub.Calls.Count); Assert.All(hub.Calls, call => Assert.Equal(user.UserId.ToString(), call.User));
        Assert.Equal(2, push.Tokens.Count); Assert.DoesNotContain("revoked-token", push.Tokens);
        emails.Fail = false; clock.Now = clock.Now.AddMinutes(10);
        await DeliverAsync(hub, emails, push, clock);
        Assert.Equal(1, emails.Sent); Assert.Equal(2, hub.Calls.Count); Assert.Equal(2, push.Tokens.Count);
        await using var check = factory.CreateDb();
        Assert.NotNull((await check.NotificationDeliveries.FindAsync(id))!.CompletedAt);
    }

    [Fact]
    public async Task DeviceRegistrationRebindsToCurrentSession_AndOtherUsersCannotRemoveIt()
    {
        var first = await PersonAsync(); var second = await PersonAsync(); const string token = "a-device-registration-token";
        await using var db = factory.CreateDb(); var service = new PushDeviceService(db, TimeProvider.System);
        await service.RegisterAsync(first.User.UserId, first.Session.SessionId, new(token, "android"), CancellationToken.None);
        await service.RegisterAsync(second.User.UserId, second.Session.SessionId, new(token, "android"), CancellationToken.None);
        await service.RemoveAsync(first.User.UserId, first.Session.SessionId, token, CancellationToken.None);
        var row = await db.PushDevices.AsNoTracking().SingleAsync(device => device.Token == token);
        Assert.Equal(second.User.UserId, row.UserId); Assert.Equal(second.Session.SessionId, row.SessionId);
        await db.Sessions.Where(session => session.SessionId == second.Session.SessionId).ExecuteUpdateAsync(set => set.SetProperty(session => session.RevokedAt, DateTimeOffset.UtcNow));
        var error = await Assert.ThrowsAsync<AuthException>(() => service.RegisterAsync(second.User.UserId, second.Session.SessionId, new(token, "android"), CancellationToken.None));
        Assert.Equal(401, error.Status);
    }
}
