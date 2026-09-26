using System.Data;
using System.Text.Json;
using System.Text.RegularExpressions;
using HuTube.Application.Auth;
using HuTube.Application.CfSeeding;
using HuTube.Application.Serialization;
using HuTube.Application.Storage;
using HuTube.Application.Videos;
using HuTube.Domain.Channels;
using HuTube.Domain.Plans;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.CfSeeding;

public sealed class CfSeederService(
    HuTubeDbContext db,
    IPasswordService passwords,
    IContentService content,
    IObjectStorage storage,
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

    public async Task<IReadOnlyList<CfSeedViewerAccountResponse>> CreateViewerAccountsAsync(
        CreateCfSeedViewersRequest request, CancellationToken ct = default)
    {
        if (request.Accounts is not { Count: >= 1 and <= 200 })
            throw Error(400, "CF_SEED_VIEWER_COUNT", "Mỗi lượt chỉ được tạo từ 1 đến 200 tài khoản người xem.");

        var now = Now;
        var results = new List<CfSeedViewerAccountResponse>();
        var newUsers = new List<User>();

        var usernames = request.Accounts.Select(x => x.Username.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var existingUsers = await db.Users.Where(x => usernames.Contains(x.Username)).ToDictionaryAsync(x => x.Username, StringComparer.OrdinalIgnoreCase, ct);

        foreach (var account in request.Accounts)
        {
            var username = account.Username.Trim();
            var displayName = string.IsNullOrWhiteSpace(account.DisplayName) ? username : account.DisplayName.Trim();
            var email = string.IsNullOrWhiteSpace(account.Email)
                ? $"{username.ToLowerInvariant()}@viewer.hutube.invalid"
                : account.Email.Trim().ToLowerInvariant();
            var password = string.IsNullOrWhiteSpace(account.Password) ? "HuTube@123456" : account.Password;

            if (existingUsers.TryGetValue(username, out var existing))
            {
                existing.PasswordHash = passwords.Hash(password);
                existing.Status = "active";
                existing.EmailVerifiedAt ??= now;
                existing.UpdatedAt = now;
                results.Add(new CfSeedViewerAccountResponse(existing.UserId, existing.Username, existing.DisplayName, existing.Email));
            }
            else
            {
                var user = new User
                {
                    UserId = Guid.NewGuid(),
                    Username = username,
                    DisplayName = displayName,
                    Email = email,
                    PasswordHash = passwords.Hash(password),
                    RoleId = UserRoles.User,
                    Status = "active",
                    EmailVerifiedAt = now,
                    CreatedAt = now,
                    UpdatedAt = now
                };
                newUsers.Add(user);
                results.Add(new CfSeedViewerAccountResponse(user.UserId, user.Username, user.DisplayName, user.Email));
            }
        }

        if (newUsers.Count > 0)
        {
            db.Users.AddRange(newUsers);
        }

        await db.SaveChangesAsync(ct);
        return results;
    }

    public async Task<IReadOnlyList<CfSeedViewerAccountResponse>> GetViewerAccountsAsync(
        string? search, int limit = 100, CancellationToken ct = default)
    {
        var query = db.Users.AsNoTracking().Where(u => u.Status == "active");
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            query = query.Where(u => u.Username.Contains(s) || u.DisplayName.Contains(s));
        }

        return await query
            .OrderByDescending(u => u.CreatedAt)
            .Take(Math.Clamp(limit, 1, 200))
            .Select(u => new CfSeedViewerAccountResponse(u.UserId, u.Username, u.DisplayName, u.Email))
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
            command.Description,
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
            false,
            false), ct);

        var video = await db.Videos.SingleAsync(x => x.VideoId == created.VideoId, ct);
        if (command.SourceWidth > 0 && command.SourceHeight > 0)
        {
            var sourceRendition = await db.VideoRenditions.SingleOrDefaultAsync(
                x => x.VideoId == video.VideoId && x.QualityLabel == command.SourceQuality.ToLowerInvariant(), ct);
            if (sourceRendition != null)
            {
                sourceRendition.Width = command.SourceWidth;
                sourceRendition.Height = command.SourceHeight;
            }
        }
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

    public async Task<CfSeedRenditionResponse> UploadRenditionAsync(Guid adminActorId,
        UploadCfSeedRenditionCommand command, CancellationToken ct = default)
    {
        var quality = command.Quality.Trim().ToLowerInvariant();
        var qualityHeight = VideoRules.QualityHeight(quality);
        if (qualityHeight == 0 || command.Width <= 0 || command.Height <= 0 || command.Height > 2160
            || QualityForHeight(command.Height) != quality)
            throw Error(400, "CF_SEED_RENDITION_QUALITY", "Độ phân giải rendition không hợp lệ hoặc không khớp metadata video.");
        if (command.BitrateKbps is < 0 or > 2_000_000)
            throw Error(400, "CF_SEED_RENDITION_BITRATE", "Bitrate rendition không hợp lệ.");
        if (string.IsNullOrWhiteSpace(command.FileName))
            throw Error(400, "CF_SEED_RENDITION_FILENAME", "Tên file rendition không hợp lệ.");
        try { VideoRules.ValidateUpload(command.ContentType, command.FileSize, long.MaxValue); }
        catch (VideoValidationException ex) { throw Error(400, ex.Code, ex.Message); }

        var video = await db.Videos.SingleOrDefaultAsync(x => x.VideoId == command.VideoId, ct)
            ?? throw Error(404, "CF_SEED_VIDEO_NOT_FOUND", "Không tìm thấy video seed.");
        if (!IsCfSeedVideo(video.Metadata))
            throw Error(403, "CF_SEED_VIDEO_REQUIRED", "Rendition này không thuộc video được tạo bởi CF Data Seeder.");

        var existing = await db.VideoRenditions.SingleOrDefaultAsync(
            x => x.VideoId == command.VideoId && x.QualityLabel == quality, ct);
        if (existing?.Status == "ready")
            return new(video.VideoId, quality, existing.Width, existing.Height, existing.FileSize, existing.Status);

        var extension = Path.GetExtension(command.FileName).ToLowerInvariant();
        if (extension is not (".mp4" or ".mov" or ".webm" or ".mkv")) extension = ".mp4";
        var storedPath = await storage.SaveVideoAsync(
            $"video-renditions/{video.VideoId:N}", $"{quality}{extension}", command.Content,
            command.ContentType, ct);
        var objectStored = true;
        try
        {
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var current = await db.VideoRenditions.SingleOrDefaultAsync(
                x => x.VideoId == command.VideoId && x.QualityLabel == quality, ct);
            if (current?.Status == "ready")
            {
                await transaction.RollbackAsync(CancellationToken.None);
                await storage.DeleteFileAsync(storedPath, CancellationToken.None);
                objectStored = false;
                return new(video.VideoId, quality, current.Width, current.Height, current.FileSize, current.Status);
            }

            var quota = await db.ChannelQuotas.SingleOrDefaultAsync(x => x.ChannelId == video.ChannelId, ct);
            if (quota != null)
            {
                if (!ChannelQuotaRules.CanReserve(quota.StorageUsed, command.FileSize, quota.StorageLimit))
                    throw Error(409, "CHANNEL_QUOTA_EXCEEDED", "Kênh không còn đủ dung lượng lưu trữ cho rendition.");
                quota.StorageUsed += command.FileSize;
                quota.UpdatedAt = Now;
            }

            if (current == null)
            {
                current = new VideoRendition { VideoId = video.VideoId, QualityLabel = quality, CreatedAt = Now };
                db.VideoRenditions.Add(current);
            }
            current.Width = command.Width;
            current.Height = command.Height;
            current.BitrateKbps = command.BitrateKbps;
            current.Codec = string.IsNullOrWhiteSpace(command.Codec) ? null : command.Codec.Trim();
            current.FileUrl = storedPath;
            current.FileSize = command.FileSize;
            current.Status = "ready";
            current.UpdatedAt = Now;
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            objectStored = false;

            return new(video.VideoId, quality, current.Width, current.Height, current.FileSize, current.Status);
        }
        catch
        {
            if (objectStored) await storage.DeleteFileAsync(storedPath, CancellationToken.None);
            throw;
        }
    }

    public async Task<CfSeedVideoProcessingResponse> GetVideoProcessingAsync(Guid videoId,
        CancellationToken ct = default)
    {
        var exists = await db.Videos.AsNoTracking().AnyAsync(x => x.VideoId == videoId, ct);
        if (!exists) throw Error(404, "CF_SEED_VIDEO_NOT_FOUND", "Không tìm thấy video seed.");

        var renditions = await db.VideoRenditions.AsNoTracking()
            .Where(x => x.VideoId == videoId)
            .Select(x => x.Status)
            .ToListAsync(ct);
        var ready = renditions.Count(status => status == "ready");
        var processing = renditions.Count(status => status == "processing");
        var failed = renditions.Count(status => status == "failed");
        return new CfSeedVideoProcessingResponse(videoId, renditions.Count, ready, processing, failed);
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

    private static bool IsCfSeedVideo(string metadata)
    {
        try
        {
            using var json = JsonDocument.Parse(metadata);
            return json.RootElement.TryGetProperty("cfSeed", out var marker)
                && marker.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException) { return false; }
    }

    private static string? QualityForHeight(int height) =>
        VideoRules.Qualities.Select(quality => (Quality: quality, Height: VideoRules.QualityHeight(quality)))
            .Where(item => item.Height <= height)
            .OrderByDescending(item => item.Height)
            .Select(item => item.Quality)
            .FirstOrDefault();

    private static string NormalizeVisibility(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        if (!HuTube.Domain.Videos.VideoRules.Visibilities.Contains(normalized))
            throw Error(400, "INVALID_VISIBILITY", "Chế độ hiển thị không hợp lệ.");
        return normalized;
    }

    private static ContentException Error(int status, string code, string message) => new(status, code, message);
}
