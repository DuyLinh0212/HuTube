using HuTube.Domain.Users;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Persistence;

public sealed class HuTubeDbContext(DbContextOptions<HuTubeDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<AuthIdentity> Identities => Set<AuthIdentity>();
    public DbSet<UserSession> Sessions => Set<UserSession>();
    public DbSet<EmailVerificationToken> VerificationTokens => Set<EmailVerificationToken>();
    public DbSet<PasswordResetToken> ResetTokens => Set<PasswordResetToken>();
    public DbSet<AdminAccount> AdminAccounts => Set<AdminAccount>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema("hutube");
        model.HasPostgresExtension("citext");
        model.Entity<User>(b => {
            b.ToTable("users"); b.HasKey(x => x.UserId); b.Ignore(x => x.IsBlocked);
            b.HasQueryFilter(x => x.DeletedAt == null);
            b.Property(x => x.Email).HasColumnType("citext"); b.Property(x => x.Username).HasColumnType("citext");
            b.HasIndex(x => x.Email).IsUnique().HasFilter("deleted_at IS NULL").HasDatabaseName("ux_users_email_active");
            b.HasIndex(x => x.Username).IsUnique().HasFilter("deleted_at IS NULL").HasDatabaseName("ux_users_username_active");
        });
        model.Entity<AuthIdentity>(b => { b.ToTable("auth_identities"); b.HasKey(x => x.AuthIdentityId); b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId); });
        model.Entity<UserSession>(b => {
            b.ToTable("user_sessions"); b.HasKey(x => x.SessionId);
            b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId);
            b.HasOne<UserSession>().WithMany().HasForeignKey(x => x.ReplacedBySessionId).OnDelete(DeleteBehavior.SetNull);
            b.HasIndex(x => x.RefreshTokenHash).IsUnique(); b.HasIndex(x => x.Jti).IsUnique();
        });
        model.Entity<EmailVerificationToken>(b => { b.ToTable("email_verification_tokens"); b.HasKey(x => x.EmailVerificationTokenId); b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId); });
        model.Entity<PasswordResetToken>(b => { b.ToTable("password_reset_tokens"); b.HasKey(x => x.PasswordResetTokenId); b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId); });
        model.Entity<AdminAccount>(b => { b.ToTable("admin_accounts"); b.HasKey(x => x.AdminAccountId); b.HasOne<User>().WithMany().HasForeignKey(x => x.UserId); });
        foreach (var entity in model.Model.GetEntityTypes())
            foreach (var property in entity.GetProperties())
                property.SetColumnName(System.Text.RegularExpressions.Regex.Replace(property.Name, "([a-z0-9])([A-Z])", "$1_$2").ToLowerInvariant());
    }
}
