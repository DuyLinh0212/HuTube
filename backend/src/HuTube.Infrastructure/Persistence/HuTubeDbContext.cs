using HuTube.Domain.Channels;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Persistence;

public sealed class HuTubeDbContext(DbContextOptions<HuTubeDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Role> Roles => Set<Role>();
    public DbSet<UserSession> Sessions => Set<UserSession>();
    public DbSet<Channel> Channels => Set<Channel>();
    public DbSet<ChannelMember> ChannelMembers => Set<ChannelMember>();
    public DbSet<ChannelInvitation> ChannelInvitations => Set<ChannelInvitation>();
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder) =>
        optionsBuilder.ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.RelationalEventId.PendingModelChangesWarning));

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema("public");
        model.HasPostgresExtension("citext");
        model.Entity<User>(b => {
            b.ToTable("users"); b.HasKey(x => x.UserId); b.Ignore(x => x.IsBlocked);
            b.HasQueryFilter(x => x.DeletedAt == null);
            b.Property(x => x.Email).HasColumnType("citext"); b.Property(x => x.Username).HasColumnType("citext");
            b.Property(x => x.UserId).HasColumnName("user_id"); b.Property(x => x.PasswordHash).HasColumnName("password_hash");
            b.Property(x => x.GoogleSubject).HasColumnName("google_subject");
            b.Property(x => x.DisplayName).HasColumnName("display_name"); b.Property(x => x.RoleId).HasColumnName("role_id");
            b.Property(x => x.Status).HasColumnName("status"); b.Property(x => x.EmailVerifiedAt).HasColumnName("email_verified_at");
            b.Property(x => x.LastLoginAt).HasColumnName("last_login_at"); b.Property(x => x.FailedLoginAttempts).HasColumnName("failed_login_attempts");
            b.Property(x => x.LockedUntil).HasColumnName("locked_until"); b.Property(x => x.CreatedAt).HasColumnName("created_at");
            b.Property(x => x.UpdatedAt).HasColumnName("updated_at"); b.Property(x => x.DeletedAt).HasColumnName("deleted_at");
            b.Property(x => x.EmailVerificationTokenHash).HasColumnName("email_verification_token_hash");
            b.Property(x => x.EmailVerificationCreatedAt).HasColumnName("email_verification_created_at");
            b.Property(x => x.EmailVerificationExpiresAt).HasColumnName("email_verification_expires_at");
            b.Property(x => x.EmailVerificationUsedAt).HasColumnName("email_verification_used_at");
            b.Property(x => x.PasswordResetTokenHash).HasColumnName("password_reset_token_hash");
            b.Property(x => x.PasswordResetCreatedAt).HasColumnName("password_reset_created_at");
            b.Property(x => x.PasswordResetExpiresAt).HasColumnName("password_reset_expires_at");
            b.Property(x => x.PasswordResetUsedAt).HasColumnName("password_reset_used_at");
            b.HasIndex(x => x.Email).IsUnique().HasDatabaseName("ux_users_email_ci");
            b.HasIndex(x => x.Username).IsUnique().HasDatabaseName("ux_users_username_ci");
            b.HasIndex(x => x.GoogleSubject).IsUnique().HasDatabaseName("ux_users_google_subject");
        });
        model.Entity<Role>(b => { b.ToTable("roles"); b.HasKey(x => x.RoleId); b.Property(x => x.RoleId).HasColumnName("role_id"); b.Property(x => x.Code).HasColumnName("code"); b.Property(x => x.Status).HasColumnName("status"); });
        model.Entity<UserSession>(b => {
            b.ToTable("refresh_tokens"); b.HasKey(x => x.SessionId);
            b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId);
            b.Property(x => x.SessionId).HasColumnName("refresh_token_id"); b.Property(x => x.UserId).HasColumnName("user_id");
            b.Property(x => x.RefreshTokenHash).HasColumnName("token_hash"); b.Property(x => x.Jti).HasColumnName("jti");
            b.Property(x => x.DeviceName).HasColumnName("device_name"); b.Property(x => x.Platform).HasColumnName("platform");
            b.Property(x => x.IssuedAt).HasColumnName("issued_at"); b.Property(x => x.ExpiresAt).HasColumnName("expires_at");
            b.Property(x => x.LastActiveAt).HasColumnName("last_active_at"); b.Property(x => x.RevokedAt).HasColumnName("revoked_at");
            b.Property(x => x.RevokeReason).HasColumnName("revoke_reason"); b.Property(x => x.ReplacedBySessionId).HasColumnName("replaced_by_token_id");
            b.HasOne<UserSession>().WithMany().HasForeignKey(x => x.ReplacedBySessionId).OnDelete(DeleteBehavior.SetNull);
            b.HasIndex(x => x.RefreshTokenHash).IsUnique(); b.HasIndex(x => x.Jti).IsUnique();
        });
        model.Entity<Channel>(b => {
            b.ToTable("channels"); b.HasKey(x => x.ChannelId); b.Ignore(x => x.IsActive);
            b.HasQueryFilter(x => x.Status != "deleted");
            b.Property(x => x.Handle).HasColumnType("citext");
        });
        model.Entity<ChannelMember>(b => {
            b.ToTable("channel_members"); b.HasKey(x => x.ChannelMemberId);
            b.HasIndex(x => new { x.ChannelId, x.UserId }).IsUnique();
        });
        model.Entity<ChannelInvitation>(b => {
            b.ToTable("channel_invitations"); b.HasKey(x => x.ChannelInvitationId);
            b.Property(x => x.InvitedEmail).HasColumnType("citext");
        });
        model.Entity<Permission>(b => {
            b.ToTable("permissions"); b.HasKey(x => x.PermissionId);
            b.HasIndex(x => x.Code).IsUnique();
        });
        model.Entity<RolePermission>(b => {
            b.ToTable("role_permissions"); b.HasKey(x => x.RolePermissionId);
            b.HasIndex(x => new { x.RoleId, x.PermissionId }).IsUnique();
        });
        model.Entity<AuditLog>(b => {
            b.ToTable("audit_logs"); b.HasKey(x => x.AuditLogId);
            b.Property(x => x.OldValues).HasColumnType("jsonb");
            b.Property(x => x.NewValues).HasColumnType("jsonb");
            b.Property(x => x.IpAddress)
                .HasConversion(
                    v => string.IsNullOrWhiteSpace(v) ? null : System.Net.IPAddress.Parse(v),
                    v => v == null ? null : v.ToString())
                .HasColumnType("inet");
        });
        foreach (var entity in model.Model.GetEntityTypes())
            foreach (var property in entity.GetProperties())
                property.SetColumnName(System.Text.RegularExpressions.Regex.Replace(property.Name, "([a-z0-9])([A-Z])", "$1_$2").ToLowerInvariant());
        model.Entity<UserSession>().Property(x => x.SessionId).HasColumnName("refresh_token_id");
        model.Entity<UserSession>().Property(x => x.RefreshTokenHash).HasColumnName("token_hash");
        model.Entity<UserSession>().Property(x => x.ReplacedBySessionId).HasColumnName("replaced_by_token_id");
    }
}
