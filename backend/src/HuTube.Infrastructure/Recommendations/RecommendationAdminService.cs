using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HuTube.Application.Auth;
using HuTube.Application.Channels;
using HuTube.Application.Videos;
using HuTube.Domain.Rbac;
using HuTube.Domain.Users;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Recommendations;

public sealed record MatrixCounts(int Pairs, int Users, int Videos);
public sealed record MatrixPreviewResponse(string[] Columns, IReadOnlyList<string[]> Rows, int Total);
public sealed record MatrixDiffResponse(string State, string? ModelVersion, string? CsvKey,
    string? CsvSha256, DateTimeOffset? UpdatedAt, MatrixCounts Active, MatrixCounts Current,
    int Added, int Changed, int Removed, double ChangeRate);
public sealed record AdminUserOption(Guid UserId, string Username, string DisplayName, bool IsBot);
public sealed record AdminVideoOption(Guid VideoId, Guid ChannelId, string Title, int Duration);
public sealed record CreateBotsRequest(int Count, string Prefix);
public sealed record SimulatorRequest(IReadOnlyList<Guid> UserIds, IReadOnlyList<Guid> VideoIds,
    string Mode, int ActionsPerUser, int DelayMs, int WatchPercent,
    int ViewRate, int LikeRate, int DislikeRate, int RatingRate, int CommentRate,
    int SubscribeRate, IReadOnlyList<string> CommentTemplates, bool ConfirmRealUsers);
public sealed record ModelManifest(string ModelVersion, string CsvKey, string CsvSha256,
    string ArtifactKey, string ArtifactSha256, DateTimeOffset UpdatedAt);

public sealed class RecommendationAdminService(
    HuTubeDbContext db, IRecommendationSnapshotStore snapshots,
    IHttpClientFactory clients, RecommendationOptions options,
    IPasswordService passwords, IContentService content, ChannelService channels,
    ILogger<RecommendationAdminService> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static ContentException Error(int status, string code, string message) => new(status, code, message);
    private static string Serialize(object value) => JsonSerializer.Serialize(value, JsonOptions);

    private sealed class Signal(Guid userId, Guid videoId)
    {
        public Guid UserId { get; } = userId;
        public Guid VideoId { get; } = videoId;
        public decimal WatchRatio { get; set; }
        public bool Like { get; set; }
        public bool Dislike { get; set; }
        public short? Rating { get; set; }
        public int Comments { get; set; }
        public bool Subscribed { get; set; }
        public decimal Score => Rating.HasValue ? Rating.Value : Math.Clamp(
            (Dislike ? 1.5m : Like ? 4.5m : WatchRatio >= .8m ? 4m :
                WatchRatio >= .5m ? 3.5m : WatchRatio >= .2m ? 3m : 2.5m)
            + (Comments > 0 && !Dislike ? .3m : 0m) + (Subscribed ? .4m : 0m), 1m, 5m);
        public string CsvLine => string.Join(",", new[] { UserId.ToString(), VideoId.ToString(),
            WatchRatio.ToString("0.####", CultureInfo.InvariantCulture),
            Like ? "1" : "0", Dislike ? "1" : "0", Rating?.ToString(CultureInfo.InvariantCulture) ?? "",
            Comments.ToString(CultureInfo.InvariantCulture), Subscribed ? "1" : "0",
            Score.ToString("0.####", CultureInfo.InvariantCulture) });
    }

    private async Task<List<Signal>> BuildMatrixAsync(CancellationToken ct)
    {
        var userIds = (await db.Users.AsNoTracking().Where(x => x.Status == "active")
            .Select(x => x.UserId).ToListAsync(ct)).ToHashSet();
        var videos = await db.Videos.AsNoTracking()
            .Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public")
            .Select(x => new { x.VideoId, x.ChannelId }).ToListAsync(ct);
        var videoIds = videos.Select(x => x.VideoId).ToHashSet();
        var pairs = new Dictionary<(Guid, Guid), Signal>();
        Signal? Get(Guid userId, Guid videoId)
        {
            if (!userIds.Contains(userId) || !videoIds.Contains(videoId)) return null;
            var key = (userId, videoId);
            if (!pairs.TryGetValue(key, out var signal))
                pairs[key] = signal = new Signal(userId, videoId);
            return signal;
        }
        var histories = await db.ViewingHistories.AsNoTracking().Where(x => x.WatchDuration > 0)
            .Select(x => new { x.UserId, x.VideoId, x.Progress }).ToListAsync(ct);
        foreach (var h in histories)
        {
            var row = Get(h.UserId, h.VideoId);
            if (row != null) row.WatchRatio = Math.Max(row.WatchRatio, Math.Clamp(h.Progress / 100m, 0, 1));
        }
        var reactions = await db.VideoReactions.AsNoTracking()
            .Select(x => new { x.UserId, x.VideoId, x.Type }).ToListAsync(ct);
        foreach (var r in reactions)
        {
            var row = Get(r.UserId, r.VideoId);
            if (row == null) continue;
            row.Like = r.Type == "like";
            row.Dislike = r.Type == "dislike";
        }
        var ratings = await db.VideoRatings.AsNoTracking()
            .Select(x => new { x.UserId, x.VideoId, x.Score }).ToListAsync(ct);
        foreach (var r in ratings)
        {
            var row = Get(r.UserId, r.VideoId);
            if (row != null) row.Rating = r.Score;
        }
        var comments = await db.Comments.AsNoTracking().Where(x => x.Status == "visible")
            .GroupBy(x => new { x.UserId, x.VideoId })
            .Select(x => new { x.Key.UserId, x.Key.VideoId, Count = x.Count() }).ToListAsync(ct);
        foreach (var c in comments)
        {
            var row = Get(c.UserId, c.VideoId);
            if (row != null) row.Comments = c.Count;
        }
        var subscriptions = await db.Subscriptions.AsNoTracking().Where(x => x.Status == "active")
            .Select(x => new { x.UserId, x.ChannelId }).ToListAsync(ct);
        var channelByVideo = videos.ToDictionary(x => x.VideoId, x => x.ChannelId);
        var subscribedChannels = subscriptions.Select(x => (x.UserId, x.ChannelId)).ToHashSet();
        // Channel subscriptions enrich video interactions already present. Creating a
        // pair for every video in a subscribed channel would mark unseen videos as seen.
        foreach (var row in pairs.Values)
            row.Subscribed = subscribedChannels.Contains((row.UserId, channelByVideo[row.VideoId]));
        return pairs.Values.OrderBy(x => x.UserId).ThenBy(x => x.VideoId).ToList();
    }

    private static byte[] ToCsv(IReadOnlyList<Signal> rows)
    {
        var builder = new StringBuilder("user_id,video_id,watch_ratio,like,dislike,rating,comment_count,subscribed,score\n");
        foreach (var row in rows) builder.Append(row.CsvLine).Append('\n');
        return Encoding.UTF8.GetBytes(builder.ToString());
    }

    private async Task<ModelManifest?> ActiveAsync(CancellationToken ct)
    {
        var bytes = await snapshots.ReadOptionalAsync("collaborative_cf/active.json", ct);
        return bytes == null ? null : JsonSerializer.Deserialize<ModelManifest>(bytes, JsonOptions);
    }

    public async Task<MatrixDiffResponse> DiffAsync(CancellationToken ct)
    {
        var rows = await BuildMatrixAsync(ct);
        var current = Count(rows.Select(x => x.CsvLine));
        var active = await ActiveAsync(ct);
        if (active == null)
            return new("uninitialized", null, null, null, null,
                new MatrixCounts(0, 0, 0), current, rows.Count, 0, 0, 0);
        var oldBytes = await snapshots.ReadOptionalAsync(active.CsvKey, ct)
            ?? throw Error(503, "ACTIVE_CSV_MISSING", "CSV của model đang hoạt động không còn trên R2.");
        if (!string.Equals(Convert.ToHexString(SHA256.HashData(oldBytes)), active.CsvSha256, StringComparison.OrdinalIgnoreCase))
            throw Error(503, "ACTIVE_CSV_INVALID", "Hash CSV của model đang hoạt động không khớp.");
        var oldLines = Encoding.UTF8.GetString(oldBytes).Split('\n', StringSplitOptions.RemoveEmptyEntries).Skip(1)
            .Select(x => x.TrimEnd('\r')).ToList();
        static string Key(string line) { var cols = line.Split(',', 3); return cols[0] + "," + cols[1]; }
        var oldMap = oldLines.ToDictionary(Key, x => x, StringComparer.Ordinal);
        var newMap = rows.ToDictionary(x => $"{x.UserId},{x.VideoId}", x => x.CsvLine, StringComparer.Ordinal);
        var added = newMap.Keys.Count(x => !oldMap.ContainsKey(x));
        var removed = oldMap.Keys.Count(x => !newMap.ContainsKey(x));
        var changed = newMap.Count(x => oldMap.TryGetValue(x.Key, out var old) && old != x.Value);
        return new("ready", active.ModelVersion, active.CsvKey, active.CsvSha256, active.UpdatedAt,
            Count(oldLines), current, added, changed, removed,
            oldMap.Count == 0 ? 0 : (double)(added + changed + removed) / oldMap.Count);
    }

    private static MatrixCounts Count(IEnumerable<string> lines)
    {
        var values = lines.Select(x => x.Split(',', 3)).ToList();
        return new(values.Count, values.Select(x => x[0]).Distinct().Count(),
            values.Select(x => x[1]).Distinct().Count());
    }

    public async Task<byte[]> ExportMatrixAsync(CancellationToken ct) => ToCsv(await BuildMatrixAsync(ct));

    public async Task<MatrixPreviewResponse> PreviewMatrixAsync(CancellationToken ct)
    {
        var rows = await BuildMatrixAsync(ct);
        return new MatrixPreviewResponse(
            ["user_id", "video_id", "watch_ratio", "like", "dislike", "rating",
                "comment_count", "subscribed", "score"],
            rows.Take(20).Select(x => x.CsvLine.Split(',')).ToList(), rows.Count);
    }

    public async Task<RecommendationJob> QueueModelAsync(Guid actorId, CancellationToken ct)
    {
        if (await db.RecommendationJobs.AnyAsync(x => x.Kind == "model_update" && (x.Status == "queued" || x.Status == "running"), ct))
            throw Error(409, "MODEL_UPDATE_RUNNING", "Một lượt cập nhật model đang chạy.");
        var job = new RecommendationJob { ActorUserId = actorId, Kind = "model_update" };
        db.RecommendationJobs.Add(job);
        await db.SaveChangesAsync(ct);
        return job;
    }

    public async Task<IReadOnlyList<AdminUserOption>> UsersAsync(string? search, CancellationToken ct)
    {
        var query = db.Users.AsNoTracking().Where(x => x.Status == "active");
        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(x => x.Username.Contains(search.Trim()) || x.DisplayName.Contains(search.Trim()));
        var users = await query.OrderBy(x => x.Username).Take(200)
            .Select(x => new { x.UserId, x.Username, x.DisplayName, x.Email }).ToListAsync(ct);
        return users.Select(x => new AdminUserOption(x.UserId, x.Username, x.DisplayName,
            x.Email.EndsWith(".hutube.invalid", StringComparison.OrdinalIgnoreCase))).ToList();
    }

    public async Task<IReadOnlyList<AdminVideoOption>> VideosAsync(string? search, CancellationToken ct)
    {
        var query = db.Videos.AsNoTracking().Where(x => x.Status == "published" && x.ModerationStatus == "approved" && x.Visibility == "public");
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => x.Title.Contains(search.Trim()));
        return await query.OrderByDescending(x => x.PublishedAt).Take(200)
            .Select(x => new AdminVideoOption(x.VideoId, x.ChannelId, x.Title, x.Duration)).ToListAsync(ct);
    }

    public async Task<IReadOnlyList<AdminUserOption>> CreateBotsAsync(Guid actorId, CreateBotsRequest request, CancellationToken ct)
    {
        if (request.Count is < 1 or > 100 || string.IsNullOrWhiteSpace(request.Prefix)
            || !System.Text.RegularExpressions.Regex.IsMatch(request.Prefix, "^[A-Za-z][A-Za-z0-9_-]{1,20}$"))
            throw Error(400, "INVALID_BOT_REQUEST", "Tạo 1–100 bot với tiền tố gồm 2–21 ký tự chữ, số, _ hoặc -.");
        var now = DateTimeOffset.UtcNow;
        var bots = new List<User>();
        for (var i = 0; i < request.Count; i++)
        {
            var suffix = Guid.NewGuid().ToString("N")[..12];
            var username = $"{request.Prefix}_{suffix}";
            bots.Add(new User { UserId = Guid.NewGuid(), Username = username,
                DisplayName = $"Bot {i + 1}", Email = $"{username}@bot.hutube.invalid",
                PasswordHash = passwords.Hash(Convert.ToBase64String(RandomNumberGenerator.GetBytes(48))),
                RoleId = UserRoles.User, Status = "active", EmailVerifiedAt = now,
                CreatedAt = now, UpdatedAt = now });
        }
        db.Users.AddRange(bots);
        db.AuditLogs.Add(new AuditLog { ActorUserId = actorId, Action = "recommendations.bots_created",
            ResourceType = "recommendation_bot", NewValues = Serialize(new { users = bots.Select(x => x.UserId) }), CreatedAt = now });
        await db.SaveChangesAsync(ct);
        return bots.Select(x => new AdminUserOption(x.UserId, x.Username, x.DisplayName, true)).ToList();
    }

    public async Task<RecommendationJob> QueueSimulatorAsync(Guid actorId, SimulatorRequest request, CancellationToken ct)
    {
        if (request.UserIds is not { Count: >= 1 and <= 200 } || request.VideoIds is not { Count: >= 1 and <= 200 }
            || request.ActionsPerUser is < 1 or > 1000 || request.UserIds.Count * request.ActionsPerUser > 10000
            || request.DelayMs is < 0 or > 5000 || request.WatchPercent is < 1 or > 100
            || request.Mode is not ("target" or "cluster") || request.CommentTemplates is null
            || request.CommentTemplates.Count > 100
            || request.CommentTemplates.Any(x => x is null || x.Length is < 3 or > 5000))
            throw Error(400, "INVALID_SIMULATION", "Cấu hình mô phỏng không hợp lệ.");
        if (new[] { request.ViewRate, request.LikeRate, request.DislikeRate, request.RatingRate,
                request.CommentRate, request.SubscribeRate }.Any(x => x is < 0 or > 100))
            throw Error(400, "INVALID_SIMULATION_RATE", "Tỷ lệ hành vi phải từ 0 đến 100.");
        if (request.LikeRate + request.DislikeRate > 100)
            throw Error(400, "INVALID_REACTION_RATE", "Tổng tỷ lệ thích và không thích không được vượt 100%.");
        var users = await db.Users.AsNoTracking().Where(x => request.UserIds.Contains(x.UserId) && x.Status == "active")
            .Select(x => new { x.UserId, x.Email }).ToListAsync(ct);
        if (users.Count != request.UserIds.Distinct().Count())
            throw Error(400, "USER_NOT_ACTIVE", "Danh sách có user không hoạt động hoặc không tồn tại.");
        var videos = await db.Videos.AsNoTracking().Where(x => request.VideoIds.Contains(x.VideoId)
                && x.Status == "published" && x.ModerationStatus == "approved"
                && x.Visibility == "public" && x.Duration > 0)
            .Select(x => x.VideoId).ToListAsync(ct);
        if (videos.Count != request.VideoIds.Distinct().Count())
            throw Error(400, "VIDEO_NOT_PUBLIC", "Danh sách có video không công khai hoặc không tồn tại.");
        if (users.Any(x => !x.Email.EndsWith(".hutube.invalid", StringComparison.OrdinalIgnoreCase)) && !request.ConfirmRealUsers)
            throw Error(400, "CONFIRM_REAL_USERS", "Cần xác nhận rõ khi mô phỏng trên tài khoản thật.");
        var job = new RecommendationJob { ActorUserId = actorId, Kind = "simulation",
            PayloadJson = Serialize(request), Total = request.UserIds.Count * request.ActionsPerUser };
        db.RecommendationJobs.Add(job);
        db.AuditLogs.Add(new AuditLog { ActorUserId = actorId, Action = "recommendations.simulation_queued",
            ResourceType = "recommendation_job", ResourceId = job.JobId,
            NewValues = Serialize(new { users = request.UserIds, videos = request.VideoIds,
                request.Mode, request.ActionsPerUser }), CreatedAt = DateTimeOffset.UtcNow });
        await db.SaveChangesAsync(ct);
        return job;
    }

    public async Task<RecommendationJob> JobAsync(Guid id, CancellationToken ct) =>
        await db.RecommendationJobs.AsNoTracking().SingleOrDefaultAsync(x => x.JobId == id, ct)
        ?? throw Error(404, "JOB_NOT_FOUND", "Không tìm thấy job.");

    public async Task StopAsync(Guid id, CancellationToken ct)
    {
        var job = await db.RecommendationJobs.SingleOrDefaultAsync(x => x.JobId == id && x.Kind == "simulation", ct)
            ?? throw Error(404, "JOB_NOT_FOUND", "Không tìm thấy job mô phỏng.");
        if (job.Status is "queued" or "running")
        { job.Status = "cancelling"; job.UpdatedAt = DateTimeOffset.UtcNow; await db.SaveChangesAsync(ct); }
    }

    public async Task ProcessAsync(RecommendationJob job, CancellationToken ct)
    {
        try
        {
            if (job.Kind == "model_update") await ProcessModelAsync(job, ct);
            else await ProcessSimulatorAsync(job, ct);
            job.Status = job.Status == "cancelling" ? "cancelled" : "completed";
            job.Step = job.Status;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Recommendation job {JobId} failed at {Step}", job.JobId, job.Step);
            job.Status = "failed"; job.Error = $"{job.Step}: {ex.Message}";
        }
        job.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(CancellationToken.None);
    }

    private async Task ProcessModelAsync(RecommendationJob job, CancellationToken ct)
    {
        job.Step = "matrix"; await db.SaveChangesAsync(ct);
        var rows = await BuildMatrixAsync(ct);
        if (rows.Count < 3 || rows.Select(x => x.UserId).Distinct().Count() < 2 || rows.Select(x => x.VideoId).Distinct().Count() < 2)
            throw Error(422, "MATRIX_TOO_SMALL", "CF cần ít nhất 2 user, 2 video và 3 cặp tương tác.");
        var bytes = ToCsv(rows);
        if (bytes.Length > 32 * 1024 * 1024)
            throw Error(422, "MATRIX_TOO_LARGE", "CSV vượt giới hạn 32 MiB của Render Free.");
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var now = DateTimeOffset.UtcNow;
        var key = $"collaborative_cf/{now:yyyy/MM/dd}/interactions_{now:yyyyMMddTHHmmssZ}_{hash[..12]}.csv";
        job.Step = "upload_csv"; await db.SaveChangesAsync(ct);
        await snapshots.WriteAsync(key, bytes, "text/csv", ct);
        job.Step = "train_model"; await db.SaveChangesAsync(ct);
        if (string.IsNullOrWhiteSpace(options.ServiceUrl) || string.IsNullOrWhiteSpace(options.AdminToken))
            throw new InvalidOperationException("Recommendation Service URL/AdminToken is not configured.");
        using var client = clients.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(30);
        using var request = new HttpRequestMessage(HttpMethod.Post, options.ServiceUrl.TrimEnd('/') + "/internal/model/train") {
            Content = System.Net.Http.Json.JsonContent.Create(new { csvKey = key, csvSha256 = hash }) };
        request.Headers.Add("X-Model-Admin-Token", options.AdminToken);
        using var response = await client.SendAsync(request, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"Recommendation Service returned {(int)response.StatusCode}: {body[..Math.Min(500, body.Length)]}");
        using var submitted = JsonDocument.Parse(body);
        var serviceJobId = submitted.RootElement.GetProperty("jobId").GetString()
            ?? throw new InvalidOperationException("Recommendation Service did not return a job ID.");
        var deadline = DateTimeOffset.UtcNow.AddMinutes(20);
        while (DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(TimeSpan.FromSeconds(3), ct);
            using var poll = new HttpRequestMessage(HttpMethod.Get,
                options.ServiceUrl.TrimEnd('/') + "/internal/model/jobs/" + Uri.EscapeDataString(serviceJobId));
            poll.Headers.Add("X-Model-Admin-Token", options.AdminToken);
            using var progress = await client.SendAsync(poll, ct);
            var progressBody = await progress.Content.ReadAsStringAsync(ct);
            if (!progress.IsSuccessStatusCode)
                throw new InvalidOperationException($"Model job polling returned {(int)progress.StatusCode}: {progressBody[..Math.Min(500, progressBody.Length)]}");
            using var progressJson = JsonDocument.Parse(progressBody);
            var state = progressJson.RootElement.GetProperty("status").GetString();
            if (state == "completed") break;
            if (state == "failed")
                throw new InvalidOperationException(progressJson.RootElement.GetProperty("error").GetString() ?? "Model training failed.");
        }
        if (DateTimeOffset.UtcNow >= deadline)
            throw new TimeoutException("Model training exceeded the 20-minute job limit.");
        job.Step = "verify_manifest"; await db.SaveChangesAsync(ct);
        var active = await ActiveAsync(ct);
        if (active == null || active.CsvKey != key || !string.Equals(active.CsvSha256, hash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Recommendation Service did not publish the requested CSV manifest.");
        job.LogsJson = Serialize(new[] { $"Model {active.ModelVersion} đang hoạt động.", $"CSV: {key}", $"SHA-256: {hash}" });
    }

    private async Task ProcessSimulatorAsync(RecommendationJob job, CancellationToken ct)
    {
        var request = JsonSerializer.Deserialize<SimulatorRequest>(job.PayloadJson, JsonOptions)
            ?? throw new InvalidOperationException("Invalid simulation payload.");
        var videos = await db.Videos.AsNoTracking().Where(x => request.VideoIds.Contains(x.VideoId))
            .Select(x => new { x.VideoId, x.ChannelId, x.Duration }).ToListAsync(ct);
        var videosById = videos.ToDictionary(x => x.VideoId);
        var logs = new List<string>();
        job.Step = "interactions"; await db.SaveChangesAsync(ct);
        foreach (var userId in request.UserIds)
        for (var i = 0; i < request.ActionsPerUser; i++)
        {
            await db.Entry(job).ReloadAsync(ct);
            if (job.Status == "cancelling") return;
            var video = request.Mode == "target"
                ? videosById[request.VideoIds[i % request.VideoIds.Count]]
                : videos[Random.Shared.Next(videos.Count)];
            async Task Act(string behavior, Func<Task> action)
            {
                try
                {
                    await action();
                    db.AuditLogs.Add(new AuditLog { ActorUserId = job.ActorUserId,
                        Action = "recommendations.simulated_" + behavior,
                        ResourceType = "video", ResourceId = video.VideoId,
                        NewValues = Serialize(new { targetUserId = userId, videoId = video.VideoId, behavior, jobId = job.JobId }),
                        CreatedAt = DateTimeOffset.UtcNow });
                    logs.Add($"{DateTimeOffset.UtcNow:HH:mm:ss} {userId} {behavior} {video.VideoId}");
                }
                catch (Exception ex)
                {
                    logs.Add($"{DateTimeOffset.UtcNow:HH:mm:ss} {userId} {behavior}: {ex.Message}");
                }
            }
            if (Hit(request.ViewRate)) await Act("view", async () => {
                await content.SaveProgressAsync(userId, video.VideoId,
                    new WatchProgressRequest(Math.Clamp(
                        (int)Math.Round(video.Duration * request.WatchPercent / 100.0), 1, video.Duration),
                        true, true), ct);
            });
            var reactionRoll = Random.Shared.Next(100);
            if (reactionRoll < request.LikeRate) await Act("like", async () => { await content.SetVideoReactionAsync(userId, video.VideoId, "like", ct); });
            else if (reactionRoll < request.LikeRate + request.DislikeRate) await Act("dislike", async () => { await content.SetVideoReactionAsync(userId, video.VideoId, "dislike", ct); });
            if (Hit(request.RatingRate)) await Act("rating", async () => { await content.SetRatingAsync(userId, video.VideoId, Random.Shared.Next(1, 6), ct); });
            if (Hit(request.CommentRate) && request.CommentTemplates.Count > 0)
                await Act("comment", async () => { await content.CreateCommentAsync(userId, video.VideoId,
                    new CreateCommentRequest(request.CommentTemplates[Random.Shared.Next(request.CommentTemplates.Count)], null), ct); });
            if (Hit(request.SubscribeRate)) await Act("subscribe", async () => { await channels.SubscribeAsync(video.ChannelId, userId, ct); });
            job.Completed++;
            job.LogsJson = Serialize(logs.TakeLast(500).ToArray());
            job.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            if (request.DelayMs > 0) await Task.Delay(request.DelayMs, ct);
        }
    }

    private static bool Hit(int rate) => rate > 0 && Random.Shared.Next(100) < rate;
}
