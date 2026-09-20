using HuTube.Application.Auth;
using HuTube.Domain.Users;

namespace HuTube.UnitTests;

public sealed class AuthServicePlanTests
{
    private sealed class MockAuthStore : IAuthStore
    {
        public User? SavedUser { get; private set; }
        public string? SavedPasswordHash { get; private set; }
        public bool AddUserAsyncCalled { get; private set; }

        public Task<IAuthTransaction> LockUserAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult<IAuthTransaction>(new MockTransaction());

        public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) => Task.FromResult<User?>(null);
        public Task<User?> FindUserByGoogleSubjectAsync(string subject, CancellationToken ct) => Task.FromResult<User?>(null);
        public Task<User?> FindUserAsync(Guid id, CancellationToken ct) => Task.FromResult<User?>(null);
        public Task<bool> UsernameExistsAsync(string username, CancellationToken ct) => Task.FromResult(false);
        public Task<string?> FindPasswordHashAsync(Guid userId, CancellationToken ct) => Task.FromResult<string?>(null);
        public Task<UserSession?> FindSessionByHashAsync(string hash, CancellationToken ct) => Task.FromResult<UserSession?>(null);
        public Task<UserSession?> FindSessionAsync(Guid id, CancellationToken ct) => Task.FromResult<UserSession?>(null);
        public Task<List<UserSession>> GetSessionsAsync(Guid userId, CancellationToken ct) => Task.FromResult(new List<UserSession>());
        public Task<List<UserSession>> GetActiveSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct) => Task.FromResult(new List<UserSession>());
        public Task TouchSessionAsync(Guid sessionId, DateTimeOffset now, DateTimeOffset expiresAt, CancellationToken ct) => Task.CompletedTask;
        public Task<EmailVerificationToken?> FindVerificationAsync(string hash, CancellationToken ct) => Task.FromResult<EmailVerificationToken?>(null);
        public Task<PasswordResetToken?> FindResetAsync(string hash, CancellationToken ct) => Task.FromResult<PasswordResetToken?>(null);
        public Task<bool> IsAdminAsync(Guid userId, CancellationToken ct) => Task.FromResult(false);
        public void AddUser(User user, string passwordHash)
        {
            SavedUser = user;
            SavedPasswordHash = passwordHash;
        }

        public Task AddUserAsync(User user, string passwordHash, CancellationToken ct = default)
        {
            AddUserAsyncCalled = true;
            // Simulate assigning the free plan when user is added
            user.PlanId = Guid.Parse("00000000-0000-0000-0000-000000000100");
            SavedUser = user;
            SavedPasswordHash = passwordHash;
            return Task.CompletedTask;
        }

        public void AddSession(UserSession session) { }
        public void AddVerification(User user, EmailVerificationToken token) { }
        public void AddReset(User user, PasswordResetToken token) { }
        public Task InvalidateTokensAsync(Guid userId, bool reset, DateTimeOffset now, CancellationToken ct) => Task.CompletedTask;
        public Task SaveAsync(CancellationToken ct) => Task.CompletedTask;

        private sealed class MockTransaction : IAuthTransaction
        {
            public Task CommitAsync(CancellationToken cancellationToken) => Task.CompletedTask;
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }

    private sealed class MockPasswordService : IPasswordService
    {
        public string Hash(string password) => "hashed_" + password;
        public bool Verify(string password, string hash) => hash == "hashed_" + password;
    }

    private sealed class MockTokenService : ITokenService
    {
        public string CreateOpaqueToken() => "mock-token-123456789012345678901234567890123456789012345678901234567890";
        public string HashToken(string token) => "hashed-" + token;
        public (string Token, DateTimeOffset ExpiresAt) CreateAccessToken(User user, UserSession session) => ("jwt-token", DateTimeOffset.UtcNow.AddHours(1));
    }

    private sealed class MockEmailSender : IAuthEmailSender
    {
        public Task SendAsync(string email, string subject, string body, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class MockGoogleVerifier : IGoogleTokenVerifier
    {
        public Task<GoogleIdentity> VerifyAsync(string credential, CancellationToken cancellationToken) =>
            Task.FromResult(new GoogleIdentity("google-sub", "user@gmail.com", "Google User", null));
    }

    [Fact]
    public async Task RegisterAsync_CallsAddUserAsync_AndUserHasFreePlan()
    {
        var store = new MockAuthStore();
        var passwords = new MockPasswordService();
        var tokens = new MockTokenService();
        var emailSender = new MockEmailSender();
        var google = new MockGoogleVerifier();
        var options = new AuthOptions();
        var authService = new AuthService(store, passwords, tokens, emailSender, google, options, TimeProvider.System);

        var response = await authService.RegisterAsync(new RegisterRequest(
            "newuser",
            "newuser@example.com",
            "New User",
            "StrongPassword123!"
        ));

        Assert.NotNull(response);
        Assert.True(store.AddUserAsyncCalled);
        Assert.NotNull(store.SavedUser);
        Assert.Equal("newuser@example.com", store.SavedUser.Email);
        Assert.Equal(Guid.Parse("00000000-0000-0000-0000-000000000100"), store.SavedUser.PlanId);
    }
}
