using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using Xunit;

namespace HuTube.UnitTests;

public sealed class RbacTests
{
    private sealed class FakeRbacStore : IRbacStore
    {
        public Dictionary<Guid, List<string>> UserPermissions { get; } = [];
        public Dictionary<Guid, (string? Code, string? Name)> UserRoles { get; } = [];
        public List<AuditLog> AuditLogs { get; } = [];
        public List<Role> Roles { get; } = [];
        public List<Permission> Permissions { get; } = AdminPermissions.All
            .Select(code => new Permission { PermissionId = Guid.NewGuid(), Code = code, Name = code, Status = "active" })
            .ToList();
        public Dictionary<Guid, List<Guid>> RolePermissionIds { get; } = [];

        public Task<List<string>> GetUserPermissionsAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(UserPermissions.TryGetValue(userId, out var list) ? list : []);

        public Task<(string? RoleCode, string? RoleName)> GetUserRoleAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(UserRoles.TryGetValue(userId, out var role) ? role : (null, null));

        public Task<bool> HasPermissionAsync(Guid userId, string permissionCode, CancellationToken ct) =>
            Task.FromResult(UserPermissions.TryGetValue(userId, out var list) && list.Contains(permissionCode, StringComparer.OrdinalIgnoreCase));

        public Task<List<Permission>> GetAllPermissionsAsync(CancellationToken ct) =>
            Task.FromResult(Permissions.ToList());

        public Task<List<RoleWithPermissions>> GetAllRolesWithPermissionsAsync(CancellationToken ct) =>
            Task.FromResult(Roles.Select(role => new RoleWithPermissions(
                role.RoleId,
                role.Code,
                role.Name,
                role.Description,
                RolePermissionIds.TryGetValue(role.RoleId, out var ids)
                    ? Permissions.Where(permission => ids.Contains(permission.PermissionId)).Select(permission => permission.Code).ToList()
                    : [])).ToList());

        public Task<Role?> FindRoleAsync(Guid roleId, CancellationToken ct) =>
            Task.FromResult(Roles.SingleOrDefault(role => role.RoleId == roleId));
        public Task<bool> RoleCodeExistsAsync(string code, CancellationToken ct) =>
            Task.FromResult(Roles.Any(role => role.Code == code));
        public Task<List<Permission>> GetActivePermissionsByCodesAsync(IReadOnlyCollection<string> codes, CancellationToken ct) =>
            Task.FromResult(Permissions.Where(permission => permission.Status == "active" && codes.Contains(permission.Code)).ToList());
        public void AddRole(Role role) => Roles.Add(role);
        public Task ReplaceRolePermissionsAsync(Guid roleId, IReadOnlyCollection<Guid> permissionIds, CancellationToken ct)
        {
            RolePermissionIds[roleId] = permissionIds.Distinct().ToList();
            return Task.CompletedTask;
        }
        public void AddAuditLog(AuditLog log) => AuditLogs.Add(log);
        public Task<List<AuditLog>> GetAuditLogsAsync(int limit, CancellationToken ct) =>
            Task.FromResult(AuditLogs.OrderByDescending(a => a.CreatedAt).Take(limit).ToList());
        public Task SaveAsync(CancellationToken ct) => Task.CompletedTask;
    }

    private sealed class FakeAuthStore : IAuthStore
    {
        public Dictionary<Guid, User> Users { get; } = [];
        public HashSet<Guid> AdminUserIds { get; } = [];

        public Task<User?> FindUserAsync(Guid id, CancellationToken ct) =>
            Task.FromResult(Users.TryGetValue(id, out var user) ? user : null);

        public Task<bool> IsAdminAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(AdminUserIds.Contains(userId));

        public Task<IAuthTransaction> LockUserAsync(Guid userId, CancellationToken ct) => throw new NotImplementedException();
        public Task<User?> FindUserByEmailAsync(string email, CancellationToken ct) => throw new NotImplementedException();
        public Task<User?> FindUserByGoogleSubjectAsync(string subject, CancellationToken ct) => throw new NotImplementedException();
        public Task<bool> UsernameExistsAsync(string username, CancellationToken ct) => throw new NotImplementedException();
        public Task<string?> FindPasswordHashAsync(Guid userId, CancellationToken ct) => throw new NotImplementedException();
        public Task<UserSession?> FindSessionByHashAsync(string hash, CancellationToken ct) => throw new NotImplementedException();
        public Task<UserSession?> FindSessionAsync(Guid id, CancellationToken ct) => throw new NotImplementedException();
        public Task<List<UserSession>> GetSessionsAsync(Guid userId, CancellationToken ct) => throw new NotImplementedException();
        public Task<List<UserSession>> GetActiveSessionsAsync(Guid userId, DateTimeOffset now, CancellationToken ct) => throw new NotImplementedException();
        public Task TouchSessionAsync(Guid sessionId, DateTimeOffset now, CancellationToken ct) => throw new NotImplementedException();
        public Task<EmailVerificationToken?> FindVerificationAsync(string hash, CancellationToken ct) => throw new NotImplementedException();
        public Task<PasswordResetToken?> FindResetAsync(string hash, CancellationToken ct) => throw new NotImplementedException();
        public void AddUser(User user, string passwordHash) => throw new NotImplementedException();
        public void AddSession(UserSession session) => throw new NotImplementedException();
        public void AddVerification(User user, EmailVerificationToken token) => throw new NotImplementedException();
        public void AddReset(User user, PasswordResetToken token) => throw new NotImplementedException();
        public Task InvalidateTokensAsync(Guid userId, bool reset, DateTimeOffset now, CancellationToken ct) => throw new NotImplementedException();
        public Task SaveAsync(CancellationToken ct) => Task.CompletedTask;
    }

    [Fact]
    public async Task GetAdminMe_WhenNotAdmin_Throws403()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);

        var user = new User { UserId = Guid.NewGuid(), Email = "user@example.com", Status = "active" };
        authStore.Users[user.UserId] = user;
        // Not in AdminUserIds

        var ex = await Assert.ThrowsAsync<RbacException>(() => service.GetAdminMeAsync(user.UserId));
        Assert.Equal(403, ex.Status);
        Assert.Equal("ADMIN_ACCESS_DENIED", ex.Code);
    }

    [Fact]
    public async Task GetAdminMe_WhenAdmin_ReturnsRoleAndPermissions()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);

        var adminUser = new User
        {
            UserId = Guid.NewGuid(),
            Email = "admin@example.com",
            Username = "adminuser",
            DisplayName = "Admin User",
            Status = "active",
            EmailVerifiedAt = DateTimeOffset.UtcNow
        };
        authStore.Users[adminUser.UserId] = adminUser;
        authStore.AdminUserIds.Add(adminUser.UserId);
        rbacStore.UserRoles[adminUser.UserId] = ("moderator", "Moderator");
        rbacStore.UserPermissions[adminUser.UserId] = [AdminPermissions.ModerationViewQueue, AdminPermissions.ModerationReview];

        var response = await service.GetAdminMeAsync(adminUser.UserId);

        Assert.Equal("moderator", response.Role);
        Assert.True(response.IsAdmin);
        Assert.Equal(2, response.Permissions.Count);
        Assert.Contains(AdminPermissions.ModerationViewQueue, response.Permissions);
    }

    [Fact]
    public async Task HasPermission_ResolvesCorrectly()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);
        var userId = Guid.NewGuid();

        rbacStore.UserPermissions[userId] = [AdminPermissions.ModerationViewQueue];

        Assert.True(await service.HasPermissionAsync(userId, AdminPermissions.ModerationViewQueue));
        Assert.False(await service.HasPermissionAsync(userId, AdminPermissions.ModerationApprove));
    }

    [Fact]
    public async Task LogAudit_CreatesEntry()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);
        var actorId = Guid.NewGuid();

        await service.LogAuditAsync(new(actorId, "admin.login", "user", actorId, "Standard login"));

        Assert.Single(rbacStore.AuditLogs);
        Assert.Equal("admin.login", rbacStore.AuditLogs[0].Action);
        Assert.Equal(actorId, rbacStore.AuditLogs[0].ActorUserId);
    }

    [Fact]
    public async Task CreateRole_AsSuperAdmin_CreatesPermissionsAndAuditEntry()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);
        var actorId = Guid.NewGuid();
        rbacStore.UserRoles[actorId] = ("super_admin", "Super Administrator");

        var result = await service.CreateRoleAsync(actorId, new CreateRoleRequest(
            "content_reviewer",
            "Content reviewer",
            "Review flagged content",
            [AdminPermissions.ModerationViewQueue, AdminPermissions.ModerationReview],
            "Thiết lập vai trò kiểm duyệt nội dung"));

        Assert.Equal("content_reviewer", result.Code);
        Assert.Equal(2, result.Permissions.Count);
        Assert.Single(rbacStore.Roles);
        Assert.Equal(2, rbacStore.RolePermissionIds[result.RoleId].Count);
        Assert.Contains(rbacStore.AuditLogs, entry => entry.Action == "rbac.role_created" && entry.ActorUserId == actorId);
    }

    [Fact]
    public async Task UpdateRole_RejectsPermissionBeyondActorDelegation()
    {
        var rbacStore = new FakeRbacStore();
        var authStore = new FakeAuthStore();
        var service = new RbacService(rbacStore, authStore);
        var actorId = Guid.NewGuid();
        var role = new Role { RoleId = Guid.NewGuid(), Code = "moderator", Name = "Moderator", Status = "active" };
        rbacStore.Roles.Add(role);
        rbacStore.UserRoles[actorId] = ("role_manager", "Role manager");
        rbacStore.UserPermissions[actorId] = [AdminPermissions.RoleEdit];

        var exception = await Assert.ThrowsAsync<RbacException>(() => service.UpdateRoleAsync(actorId, role.RoleId, new UpdateRoleRequest(
            "Moderator",
            "Kiểm duyệt",
            [AdminPermissions.UserBan],
            "Thử gán quyền vượt quá phạm vi")));

        Assert.Equal(403, exception.Status);
        Assert.Equal("PERMISSION_DELEGATION_DENIED", exception.Code);
    }
}
