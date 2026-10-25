using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Rbac;
using HuTube.Application.Users;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace HuTube.IntegrationTests;

public sealed class RoleDeletionIntegrationTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private async Task<(HttpClient Client, User User)> CreateUserAsync(Guid? roleId = null)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var suffix = Guid.NewGuid().ToString("N");
        var email = $"role_{suffix}@example.test";
        (await client.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest("role_" + suffix[..14], email, "Role test", "Password123!"))).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/auth/verify-email", new TokenRequest(factory.Emails.Token(email)))).EnsureSuccessStatusCode();
        await using var db = factory.CreateDb();
        var user = await db.Users.SingleAsync(u => u.Email == email);
        if (roleId.HasValue) { user.RoleId = roleId; await db.SaveChangesAsync(); }
        var admin = roleId.HasValue && roleId != UserRoles.User;
        if (admin) client.DefaultRequestHeaders.Add("X-HuTube-App", "admin");
        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(email, "Password123!", admin ? "admin" : "web", "Role test"));
        login.EnsureSuccessStatusCode();
        var body = (await login.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", body.AccessToken);
        return (client, user);
    }

    private static async Task<RoleResponse> CreateRoleAsync(HttpClient admin)
    {
        var result = await admin.PostAsJsonAsync("/api/v1/admin/roles", new CreateRoleRequest(
            "custom_" + Guid.NewGuid().ToString("N")[..10], "Custom role", null,
            [AdminPermissions.RoleView, AdminPermissions.UserView], "Role deletion test"));
        result.EnsureSuccessStatusCode();
        return (await result.Content.ReadFromJsonAsync<RoleResponse>(JsonOptions))!;
    }

    private static Task<HttpResponseMessage> DeleteAsync(HttpClient client, Guid roleId, string reason = "Remove custom role") =>
        client.DeleteAsync($"/api/v1/admin/roles/{roleId}?reason={Uri.EscapeDataString(reason)}");

    [Fact]
    public async Task DeletingAssignedRole_UnassignsAllUsers_RevokesAdminAccess_KeepsAccounts_AndAllowsReassignment()
    {
        var (admin, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var role = await CreateRoleAsync(admin);
        var (member, user) = await CreateUserAsync(role.RoleId);
        var (_, blockedUser) = await CreateUserAsync(role.RoleId);
        var (_, unrelatedUser) = await CreateUserAsync();
        await using (var db = factory.CreateDb())
        {
            var blocked = await db.Users.SingleAsync(u => u.UserId == blockedUser.UserId);
            blocked.Status = "banned";
            blocked.DeletedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.OK, (await member.GetAsync("/api/v1/admin/users")).StatusCode);
        var web = factory.CreateClient();
        web.DefaultRequestHeaders.Add("X-HuTube-Client", "web");
        var webLogin = await web.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(user.Email, "Password123!", "web", "Viewer session"));
        webLogin.EnsureSuccessStatusCode();
        web.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", (await webLogin.Content.ReadFromJsonAsync<LoginResponse>(JsonOptions))!.AccessToken);
        (await web.PostAsJsonAsync("/api/v1/channels", new CreateChannelRequest("Kept channel", "kept_" + Guid.NewGuid().ToString("N")[..12], null))).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.NoContent, (await DeleteAsync(admin, role.RoleId)).StatusCode);
        await using (var db = factory.CreateDb())
        {
            Assert.Equal("deleted", (await db.Roles.SingleAsync(r => r.RoleId == role.RoleId)).Status);
            var kept = await db.Users.SingleAsync(u => u.UserId == user.UserId);
            Assert.Null(kept.RoleId);
            Assert.Equal("active", kept.Status);
            Assert.Equal(user.Email, kept.Email);
            var blocked = await db.Users.IgnoreQueryFilters().SingleAsync(u => u.UserId == blockedUser.UserId);
            Assert.Null(blocked.RoleId);
            Assert.Equal("banned", blocked.Status);
            Assert.NotNull(blocked.DeletedAt);
            Assert.Equal(UserRoles.User, (await db.Users.SingleAsync(u => u.UserId == unrelatedUser.UserId)).RoleId);
            var audit = await db.AuditLogs.SingleAsync(a => a.ResourceId == role.RoleId && a.Action == "rbac.role_deleted");
            Assert.Equal(2, JsonDocument.Parse(audit.NewValues!).RootElement.GetProperty("removedUserCount").GetInt32());
        }
        Assert.Contains((await member.GetAsync("/api/v1/admin/users")).StatusCode, new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden });
        var me = await web.GetFromJsonAsync<UserResponse>("/api/v1/auth/me", JsonOptions);
        Assert.False(me!.IsAdmin);
        Assert.Equal(HttpStatusCode.OK, (await web.GetAsync("/api/v1/channels/me")).StatusCode);
        var detail = (await admin.GetFromJsonAsync<AdminUserDetailResponse>($"/api/v1/admin/users/{user.UserId}", JsonOptions))!;
        Assert.Null(detail.RoleCode);
        Assert.Null(detail.RoleName);
        Assert.Empty(detail.Permissions);
        var list = (await admin.GetFromJsonAsync<AdminUserListResponse>($"/api/v1/admin/users?role=__unassigned&search={Uri.EscapeDataString(user.Email)}", JsonOptions))!;
        Assert.Equal(user.UserId, Assert.Single(list.Items).UserId);
        Assert.DoesNotContain((await admin.GetFromJsonAsync<List<RoleResponse>>("/api/v1/admin/roles", JsonOptions))!, r => r.RoleId == role.RoleId);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.PutAsJsonAsync($"/api/v1/admin/users/{user.UserId}/role", new UpdateAdminUserRoleRequest(role.Code, "Cannot use deleted role"))).StatusCode);
        (await admin.PutAsJsonAsync($"/api/v1/admin/users/{user.UserId}/role", new UpdateAdminUserRoleRequest("moderator", "Assign another role"))).EnsureSuccessStatusCode();
        detail = (await admin.GetFromJsonAsync<AdminUserDetailResponse>($"/api/v1/admin/users/{user.UserId}", JsonOptions))!;
        Assert.Equal("moderator", detail.RoleCode);
    }

    [Theory]
    [InlineData("user")]
    [InlineData("admin")]
    [InlineData("super_admin")]
    [InlineData("moderator")]
    public async Task SystemRolesRemainProtected(string code)
    {
        var (admin, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        await using var db = factory.CreateDb();
        var role = await db.Roles.SingleAsync(r => r.Code == code);
        var count = await db.Users.IgnoreQueryFilters().CountAsync(u => u.RoleId == role.RoleId);
        Assert.Equal(HttpStatusCode.Forbidden, (await DeleteAsync(admin, role.RoleId)).StatusCode);
        await db.Entry(role).ReloadAsync();
        Assert.Equal("active", role.Status);
        Assert.Equal(count, await db.Users.IgnoreQueryFilters().CountAsync(u => u.RoleId == role.RoleId));
    }

    [Fact]
    public async Task UserRole_IsOnlyVisibleAndAssignableToSuperAdmin()
    {
        var (super, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var (admin, _) = await CreateUserAsync(UserRoles.Admin);
        var (_, target) = await CreateUserAsync(SystemRoles.Moderator);
        Assert.Contains((await super.GetFromJsonAsync<List<RoleResponse>>("/api/v1/admin/roles", JsonOptions))!, r => r.Code == "user");
        Assert.DoesNotContain((await admin.GetFromJsonAsync<List<RoleResponse>>("/api/v1/admin/roles", JsonOptions))!, r => r.Code == "user");
        Assert.Equal(HttpStatusCode.Forbidden, (await admin.PutAsJsonAsync($"/api/v1/admin/users/{target.UserId}/role", new UpdateAdminUserRoleRequest("user", "Not allowed for admin"))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await super.PutAsJsonAsync($"/api/v1/admin/users/{target.UserId}/role", new UpdateAdminUserRoleRequest("user", "Allowed for super admin"))).StatusCode);
    }

    [Fact]
    public async Task DeletionRequiresPermissionAndValidReason()
    {
        var (super, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var role = await CreateRoleAsync(super);
        var (member, _) = await CreateUserAsync(role.RoleId);
        Assert.Equal(HttpStatusCode.Forbidden, (await DeleteAsync(member, role.RoleId)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await DeleteAsync(super, role.RoleId, "x")).StatusCode);
        await using var db = factory.CreateDb();
        Assert.Equal("active", (await db.Roles.SingleAsync(r => r.RoleId == role.RoleId)).Status);
        Assert.Equal(1, await db.Users.CountAsync(u => u.RoleId == role.RoleId));
    }

    [Fact]
    public async Task ConcurrentAssignmentAndDeletion_CannotLeaveUserAssignedToDeletedRole()
    {
        var (super, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var role = await CreateRoleAsync(super);
        var (_, target) = await CreateUserAsync();
        var delete = DeleteAsync(super, role.RoleId);
        var assign = super.PutAsJsonAsync($"/api/v1/admin/users/{target.UserId}/role", new UpdateAdminUserRoleRequest(role.Code, "Concurrent assignment"));
        var responses = await Task.WhenAll(delete, assign);
        Assert.Equal(HttpStatusCode.NoContent, responses[0].StatusCode);
        Assert.Contains(responses[1].StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.NotFound });
        await using var db = factory.CreateDb();
        Assert.NotEqual(role.RoleId, (await db.Users.SingleAsync(u => u.UserId == target.UserId)).RoleId);
    }

    private sealed class RejectSave : SaveChangesInterceptor
    {
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken ct = default) => throw new InvalidOperationException("Test save failure");
    }

    [Fact]
    public async Task UnassignedFilterDoesNotShadowACustomRoleNamedNone()
    {
        var (super, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var response = await super.PostAsJsonAsync("/api/v1/admin/roles", new CreateRoleRequest(
            "none", "Role named none", null, [AdminPermissions.UserView], "Verify role filter"));
        response.EnsureSuccessStatusCode();
        var role = (await response.Content.ReadFromJsonAsync<RoleResponse>(JsonOptions))!;
        var (_, member) = await CreateUserAsync(role.RoleId);
        var search = Uri.EscapeDataString(member.Email);
        var assigned = (await super.GetFromJsonAsync<AdminUserListResponse>($"/api/v1/admin/users?role=none&search={search}", JsonOptions))!;
        Assert.Equal(member.UserId, Assert.Single(assigned.Items).UserId);
        var unassigned = (await super.GetFromJsonAsync<AdminUserListResponse>($"/api/v1/admin/users?role=__unassigned&search={search}", JsonOptions))!;
        Assert.Empty(unassigned.Items);
    }

    [Fact]
    public async Task SaveFailureRollsBackBothDeletionAndUserRemoval()
    {
        var (super, _) = await CreateUserAsync(SystemRoles.SuperAdmin);
        var role = await CreateRoleAsync(super);
        var (_, member) = await CreateUserAsync(role.RoleId);
        await using (var db = new HuTubeDbContext(new DbContextOptionsBuilder<HuTubeDbContext>().UseNpgsql(factory.Connection).AddInterceptors(new RejectSave()).Options))
        {
            var stored = await db.Roles.SingleAsync(r => r.RoleId == role.RoleId);
            await Assert.ThrowsAsync<InvalidOperationException>(() => new RbacStore(db).SoftDeleteRoleAsync(stored,
                new AuditLog { Action = "rbac.role_deleted", ResourceType = "role", ResourceId = role.RoleId, CreatedAt = DateTimeOffset.UtcNow }, default));
        }
        await using var verify = factory.CreateDb();
        Assert.Equal("active", (await verify.Roles.SingleAsync(r => r.RoleId == role.RoleId)).Status);
        Assert.Equal(role.RoleId, (await verify.Users.SingleAsync(u => u.UserId == member.UserId)).RoleId);
        Assert.False(await verify.AuditLogs.AnyAsync(a => a.ResourceId == role.RoleId && a.Action == "rbac.role_deleted"));
    }
}
