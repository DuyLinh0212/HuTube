using System.Text.Json;
using System.Text.RegularExpressions;
using HuTube.Application.Auth;
using HuTube.Application.CfSeeding;
using HuTube.Application.Serialization;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.CfSeeding;

public sealed class CfSeederService(
    HuTubeDbContext db,
    IPasswordService passwords,
    IContentService content,
    TimeProvider clock) : ICfSeederService
{
    private static readonly Regex UsernamePattern = new("^[A-Za-z0-9_.-]{3,50}$", RegexOptions.Compiled);
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<IReadOnlyList<CfSeedAccountResponse>> GetExistingAccountsAsync(
        string? search, CancellationToken ct = default)
    {
        var normalizedSearch = string.IsNullOrWhiteSpace(search) ? null : search.Trim();
        var query =
            from user in db.Users.AsNoTracking()
            join channel in db.Channels.AsNoTracking() on user.UserId equals channel.OwnerUserId
            where user.Status == "active"
                && user.RoleId == UserRoles.User
                && channel.Status == "active"
            select new { user, channel };

        if (normalizedSearch != null)
        {
            query = query.Where(row => row.user.Username.Contains(normalizedSearch)
                || row.user.DisplayName.Contains(normalizedSearch)
                || row.channel.Name.Contains(normalizedSearch)
                || row.channel.Handle.Contains(normalizedSearch));
        }

        return await query
            .OrderBy(row => row.user.Username)
            .Take(100)
            .Select(row => new CfSeedAccountResponse(
                row.user.UserId,
                row.channel.ChannelId,
                row.user.Username,
                row.user.DisplayName,
                row.channel.Name,
                row.channel.Handle))
            .ToListAsync(ct);
    }

    public async Task<CfSeedProvisionResponse> CreateAccountsAsync(Guid adminActorId,
        CreateCfSeedAccountsRequest request, CancellationToken ct = default)
    {
        if (request.Accounts is not { Count: >= 1 and <= 100 })
            throw Error(400, "CF_SEED_ACCOUNT_COUNT", "Mỗi lượt chỉ được tạo từ 1 đến 100 tài khoản seed.");

        var normalized = request.Accounts.Select((item, index) => NormalizeAccount(item, index)).ToArray();
        var duplicate = normalized.GroupBy(x => x.Username, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate != null)
            throw Error(400, "CF_SEED_DUPLICATE_USERNAME", $"Username '{duplicate.Key}' bị lặp trong file JSON.");

        var usernames = normalized.Select(x => x.Username).ToArray();
        var conflicts = await db.Users.AsNoTracking().Where(x => usernames.Contains(x.Username))
            .Select(x => x.Username).ToListAsync(ct);
        if (conflicts.Count > 0)
            throw Error(409, "CF_SEED_USERNAME_CONFLICT",
                $"Username đã tồn tại: {string.Join(", ", conflicts.Take(8))}{(conflicts.Count > 8 ? "…" : "")}");

        var batchId = Guid.NewGuid();
        var batchCode = batchId.ToString("N")[..8];
        var existingHandles = new HashSet<string>(
            await db.Channels.AsNoTracking().Select(x => x.Handle).ToListAsync(ct),
            StringComparer.OrdinalIgnoreCase);
        // Seeder accounts need enough quota for the admin-selected quality. Use the
        // largest active plan so normal upload validation remains in force.
        var seedPlan = await db.Plans.AsNoTracking().Where(x => x.Status == "active")
            .OrderByDescending(x => x.StorageLimit).ThenByDescending(x => x.MaxUploadSize).FirstOrDefaultAsync(ct);
        var now = Now;
        var rows = new List<(User User, Channel Channel)>();

        for (var index = 0; index < normalized.Length; index++)
        {
            var account = normalized[index];
            var user = new User
            {
                Username = account.Username,
                DisplayName = account.DisplayName,
                Email = $"cfseed-{batchCode}-{index + 1}@seed.hutube.invalid",
                PasswordHash = passwords.Hash(account.Password),
                RoleId = UserRoles.User,
                PlanId = seedPlan?.PlanId,
                Status = "active",
                EmailVerifiedAt = now,
                CreatedAt = now,
                UpdatedAt = now
            };
            var handle = UniqueHandle(account.Username, batchCode, index + 1, existingHandles);
            existingHandles.Add(handle);
            var channel = new Channel
            {
                OwnerUserId = user.UserId,
                Name = account.ChannelName,
                Handle = handle,
                Settings = PersistenceJson.Serialize(new { source = "cf-data-seeder", batchId }),
                Status = "active",
                CreatedAt = now,
                UpdatedAt = now
            };
            rows.Add((user, channel));
        }

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        db.Users.AddRange(rows.Select(x => x.User));
        // The EF model intentionally keeps these aggregates as scalar FK-only
        // entities, so PostgreSQL FK ordering is not inferred from AddRange order.
        // Persist each dependency layer explicitly while the whole operation is
        // still protected by one transaction.
        await db.SaveChangesAsync(ct);

        db.Channels.AddRange(rows.Select(x => x.Channel));
        await db.SaveChangesAsync(ct);

        if (seedPlan != null)
            db.PlanHistories.AddRange(rows.Select(x => new PlanHistory
            {
                UserId = x.User.UserId,
                PlanId = seedPlan.PlanId,
                OwnerUserId = x.User.UserId,
                Status = "active",
                StartedAt = now,
                EndedAt = now.AddDays(seedPlan.DurationDays),
                AutoRenew = false,
                CreatedAt = now
            }));
        db.ChannelQuotas.AddRange(rows.Select(x => new ChannelQuota
        {
            ChannelId = x.Channel.ChannelId,
            StorageLimit = seedPlan?.StorageLimit ?? ChannelQuotaRules.DefaultStorageLimit,
            UpdatedAt = now
        }));
        db.AuditLogs.Add(new AuditLog
        {
            ActorUserId = adminActorId,
            Action = "cf_seed.accounts_created",
            ResourceType = "cf_seed_batch",
            ResourceId = batchId,
            NewValues = PersistenceJson.Serialize(new
            {
                count = rows.Count,
                users = rows.Select(x => new { x.User.UserId, x.User.Username, x.Channel.ChannelId })
            }),
            CreatedAt = now
        });
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return new CfSeedProvisionResponse(batchId, rows.Select(x => new CfSeedAccountResponse(
            x.User.UserId, x.Channel.ChannelId, x.User.Username, x.User.DisplayName,
            x.Channel.Name, x.Channel.Handle)).ToArray());
    }

    public async Task<CfSeedVideoResponse> UploadVideoAsync(Guid adminActorId,
        UploadCfSeedVideoCommand command, CancellationToken ct = default)
    {
        if (command.Sequence < 1) throw Error(400, "CF_SEED_SEQUENCE", "Số thứ tự video không hợp lệ.");
        var channel = await db.Channels.AsNoTracking().SingleOrDefaultAsync(x => x.ChannelId == command.ChannelId, ct)
            ?? throw Error(404, "CF_SEED_CHANNEL_NOT_FOUND", "Không tìm thấy kênh seed.");
        if (channel.OwnerUserId != command.UserId || channel.Status != "active")
            throw Error(403, "CF_SEED_CHANNEL_MISMATCH", "Kênh không thuộc tài khoản hoặc lượt seed hiện tại.");
        if (!command.UseExistingAccount && !BelongsToBatch(channel.Settings, command.BatchId))
            throw Error(403, "CF_SEED_CHANNEL_MISMATCH", "Kênh không thuộc tài khoản hoặc lượt seed hiện tại.");
        if (command.UseExistingAccount)
        {
            var existingUser = await db.Users.AsNoTracking().SingleOrDefaultAsync(
                x => x.UserId == command.UserId && x.Status == "active" && x.RoleId == UserRoles.User, ct);
            if (existingUser == null)
                throw Error(403, "CF_SEED_EXISTING_USER_INVALID", "Chỉ có thể seed vào user thường đang hoạt động.");
        }

        var created = await content.CreateVideoAsync(command.UserId, new CreateVideoCommand(
            command.ChannelId,
            command.Title,
            "Video dữ liệu được tạo bởi CF Data Seeder.",
            command.CategoryId,
            "vi",
            "private",
            false,
            command.Duration,
            command.SourceQuality,
            command.FileSize,
            command.FileName,
            command.ContentType,
            command.Content,
            null,
            null,
            null,
            [],
            [],
            $"cf:{command.BatchId:N}:{command.Sequence}",
            true,
            true), ct);

        var video = await db.Videos.SingleAsync(x => x.VideoId == created.VideoId, ct);
        video.Visibility = NormalizeVisibility(command.Visibility);
        video.Status = "published";
        video.ModerationStatus = video.Visibility == "private" ? "not_submitted" : "approved";
        video.PublishedAt = Now;
        video.UpdatedAt = Now;
        video.Metadata = PersistenceJson.Serialize(new
        {
            chapters = Array.Empty<object>(),
            cfSeed = new { command.BatchId, command.Sequence, adminActorId }
        });
        await db.SaveChangesAsync(ct);

        return new CfSeedVideoResponse(video.VideoId, command.UserId, video.ChannelId, video.Title,
            video.Status, video.Visibility, video.FileSize);
    }

    private static (string Username, string DisplayName, string ChannelName, string Password) NormalizeAccount(
        CfSeedAccountNameRequest account, int index)
    {
        var username = account.Username?.Trim() ?? "";
        var displayName = account.DisplayName?.Trim() ?? "";
        var channelName = string.IsNullOrWhiteSpace(account.ChannelName) ? displayName : account.ChannelName.Trim();
        var password = account.Password ?? "";
        if (!UsernamePattern.IsMatch(username))
            throw Error(400, "CF_SEED_INVALID_USERNAME",
                $"Account #{index + 1}: username phải có 3–50 ký tự gồm chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.");
        if (displayName.Length is < 1 or > 120)
            throw Error(400, "CF_SEED_INVALID_DISPLAY_NAME", $"Account #{index + 1}: tên hiển thị phải có 1–120 ký tự.");
        if (channelName.Length is < 1 or > 100)
            throw Error(400, "CF_SEED_INVALID_CHANNEL_NAME", $"Account #{index + 1}: tên kênh phải có 1–100 ký tự.");
        if (password.Length is < 10 or > 128 || !password.Any(char.IsUpper)
            || !password.Any(char.IsLower) || !password.Any(char.IsDigit))
            throw Error(400, "CF_SEED_INVALID_PASSWORD",
                $"Account #{index + 1}: mật khẩu cần 10–128 ký tự, gồm chữ hoa, chữ thường và số.");
        return (username, displayName, channelName, password);
    }

    private static string UniqueHandle(string username, string batchCode, int index, ISet<string> existing)
    {
        var clean = Channel.NormalizeHandle(username);
        if (!existing.Contains(clean)) return clean;
        var suffix = $"-{batchCode}-{index}";
        var prefix = clean[..Math.Min(clean.Length, 50 - suffix.Length)];
        return prefix + suffix;
    }

    private static bool BelongsToBatch(string settings, Guid batchId)
    {
        try
        {
            using var json = JsonDocument.Parse(settings);
            return json.RootElement.TryGetProperty("source", out var source)
                && source.GetString() == "cf-data-seeder"
                && json.RootElement.TryGetProperty("batchId", out var batch)
                && batch.TryGetGuid(out var parsed)
                && parsed == batchId;
        }
        catch (JsonException) { return false; }
    }

    private static string NormalizeVisibility(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        if (!HuTube.Domain.Videos.VideoRules.Visibilities.Contains(normalized))
            throw Error(400, "INVALID_VISIBILITY", "Chế độ hiển thị không hợp lệ.");
        return normalized;
    }

    private static ContentException Error(int status, string code, string message) => new(status, code, message);
}
