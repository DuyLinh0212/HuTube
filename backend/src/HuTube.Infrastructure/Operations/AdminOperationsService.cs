using System.Diagnostics;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using HuTube.Application.Storage;
using HuTube.Application.Operations;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using HuTube.Infrastructure.Notifications;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace HuTube.Infrastructure.Operations;

public sealed class AdminOperationsService(
    HuTubeDbContext db,
    IConfiguration configuration,
    IHostEnvironment environment,
    ApiRequestTelemetry telemetry,
    NotificationConnections notificationConnections,
    IObjectStorage objectStorage,
    IHttpClientFactory httpClientFactory)
{
    private static readonly TimeSpan HealthProbeTimeout = TimeSpan.FromSeconds(3);

    public async Task<AdminSystemOverviewResponse> GetSystemOverviewAsync(CancellationToken ct)
    {
        var overviewTimer = Stopwatch.StartNew();
        var now = DateTimeOffset.UtcNow;
        var hourAgo = now.AddHours(-1);
        var dayAgo = now.AddDays(-1);
        var databaseTimer = Stopwatch.StartNew();
        var signupThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:SignupBurstPerHour", 20));
        var reviewThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:PendingReviewThreshold", 50));
        var paymentFailureThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:FailedPaymentsPerDay", 10));
        var apiErrorThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:ApiErrorsPer15Minutes", 5));
        var memoryWarningThreshold = Math.Clamp(configuration.GetValue("SystemAlerts:MemoryWarningPercent", 75), 1, 99);

        var signupsLastHour = await db.Users.AsNoTracking().LongCountAsync(user => user.CreatedAt >= hourAgo && user.CreatedAt < now, ct);
        var lockedAccounts = await db.Users.AsNoTracking().LongCountAsync(user => user.LockedUntil != null && user.LockedUntil > now, ct);
        var abuseReports = await db.Reports.AsNoTracking().LongCountAsync(report => report.AbuseFlag && report.Status == "pending", ct);
        var pendingReviews = await db.ModerationCases.AsNoTracking().LongCountAsync(item =>
            item.CaseType == "upload_review" && item.Status == "pending", ct);
        var failedPayments = await db.Payments.AsNoTracking().LongCountAsync(payment =>
            (payment.Status == "failed" || payment.Status == "cancelled") && payment.UpdatedAt >= dayAgo && payment.UpdatedAt < now, ct);
        var activeSessions = await db.Sessions.AsNoTracking().LongCountAsync(session =>
            session.RevokedAt == null && session.ExpiresAt > now, ct);
        var pendingPayments = db.Payments.AsNoTracking().Where(payment => payment.Status == "pending");
        var pendingPaymentCount = await pendingPayments.LongCountAsync(ct);
        var expiredPendingPayments = await pendingPayments.LongCountAsync(payment => payment.ExpiresAt <= now, ct);
        var processingVideos = await db.Videos.AsNoTracking().LongCountAsync(video => video.Status == "processing", ct);
        var failedVideos = await db.Videos.AsNoTracking().LongCountAsync(video =>
            video.Status == "failed" && video.UpdatedAt >= dayAgo && video.UpdatedAt < now, ct);
        var processingRenditions = await db.VideoRenditions.AsNoTracking().LongCountAsync(rendition => rendition.Status == "processing", ct);
        var failedRenditions = await db.VideoRenditions.AsNoTracking().LongCountAsync(rendition =>
            rendition.Status == "failed" && rendition.UpdatedAt >= dayAgo && rendition.UpdatedAt < now, ct);
        databaseTimer.Stop();

        var apiTraffic = telemetry.Snapshot(now);
        var apiErrors = apiTraffic.ServerErrorsLast15Minutes;

        var (memoryPercent, workingSetBytes, availableBytes) = ReadMemoryUsage();
        var signals = new List<AdminSystemSignal>();
        if (memoryPercent is int currentMemoryPercent)
        {
            var memoryTriggered = currentMemoryPercent >= memoryWarningThreshold;
            signals.Add(new AdminSystemSignal("memory", "runtime",
                memoryTriggered ? (currentMemoryPercent >= 90 ? "critical" : "warning") : "normal",
                "Bộ nhớ tiến trình API", $"Tiến trình API đang sử dụng {currentMemoryPercent}% giới hạn bộ nhớ khả dụng.",
                currentMemoryPercent, "%", memoryWarningThreshold, null, memoryTriggered));
        }
        signals.AddRange(
        [
            new("signup-burst", "security", signupsLastHour >= signupThreshold ? "warning" : "normal",
                "Tốc độ tạo tài khoản", $"Có {signupsLastHour:N0} tài khoản mới trong 60 phút gần nhất.",
                signupsLastHour, "tài khoản/giờ", signupThreshold, "/users", signupsLastHour >= signupThreshold),
            new("locked-accounts", "security", lockedAccounts > 0 ? "warning" : "normal",
                "Tài khoản đang bị khóa đăng nhập", $"Có {lockedAccounts:N0} tài khoản đang trong thời gian khóa đăng nhập.",
                lockedAccounts, "tài khoản", 1, "/users", lockedAccounts > 0),
            new("abuse-reports", "moderation", abuseReports > 0 ? "warning" : "normal",
                "Báo cáo bị đánh dấu lạm dụng", $"Có {abuseReports:N0} báo cáo spam/lạm dụng đang chờ xử lý.",
                abuseReports, "báo cáo", 1, "/moderation/reports", abuseReports > 0),
            new("moderation-backlog", "moderation", pendingReviews >= reviewThreshold ? "warning" : "normal",
                "Hàng đợi kiểm duyệt video", $"Có {pendingReviews:N0} video đang chờ duyệt.",
                pendingReviews, "video", reviewThreshold, "/moderation/videos", pendingReviews >= reviewThreshold),
            new("payment-failures", "payments", failedPayments >= paymentFailureThreshold ? "warning" : "normal",
                "Giao dịch lỗi trong 24 giờ", $"Có {failedPayments:N0} giao dịch thất bại hoặc bị hủy trong 24 giờ gần nhất.",
                failedPayments, "giao dịch/ngày", paymentFailureThreshold, "/payments", failedPayments >= paymentFailureThreshold),
            new("api-errors", "runtime", apiErrors >= apiErrorThreshold ? "warning" : "normal",
                "Lỗi máy chủ API gần đây", $"Có {apiErrors:N0} request API trả về lỗi máy chủ trong 15 phút gần nhất.",
                apiErrors, "lỗi/15 phút", apiErrorThreshold, "/system/logs", apiErrors >= apiErrorThreshold)
        ]);

        var triggered = signals.Where(signal => signal.IsTriggered).ToList();
        var rateLimit = configuration.GetValue("RateLimit:AuthPermitLimit", 60);
        var version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "unknown";
        var settings = new List<AdminSystemRuntimeSetting>
        {
            new("Môi trường ứng dụng", environment.EnvironmentName, "ASPNETCORE_ENVIRONMENT"),
            new("API", "v1", "Định tuyến /api/v1"),
            new("Phiên bản backend", version, "Assembly đang chạy"),
            new("Giới hạn xác thực", $"{rateLimit} yêu cầu/phút/IP", "RateLimit:AuthPermitLimit"),
            new("Ngưỡng cảnh báo đăng ký", $"{signupThreshold} tài khoản/giờ", "SystemAlerts:SignupBurstPerHour"),
            new("Ngưỡng hàng đợi kiểm duyệt", $"{reviewThreshold} video", "SystemAlerts:PendingReviewThreshold"),
            new("Ngưỡng giao dịch lỗi", $"{paymentFailureThreshold} giao dịch/24 giờ", "SystemAlerts:FailedPaymentsPerDay"),
            new("Ngưỡng lỗi API", $"{apiErrorThreshold} lỗi/15 phút", "SystemAlerts:ApiErrorsPer15Minutes"),
            new("Cảnh báo bộ nhớ", $"{memoryWarningThreshold}%", "SystemAlerts:MemoryWarningPercent"),
            new("Bộ nhớ tiến trình", $"{FormatBytes(workingSetBytes)} / {FormatBytes(availableBytes)}", "Process.WorkingSet64 / GC memory limit")
        };

        var liveMetrics = new AdminSystemLiveMetrics(
            activeSessions,
            pendingPaymentCount,
            expiredPendingPayments,
            failedPayments,
            processingVideos,
            failedVideos,
            processingRenditions,
            failedRenditions,
            pendingReviews,
            notificationConnections.Active.Count);
        overviewTimer.Stop();
        var services = await GetServiceStatusesAsync(databaseTimer.Elapsed.TotalMilliseconds,
            overviewTimer.Elapsed.TotalMilliseconds, notificationConnections.Active.Count, ct);

        return new AdminSystemOverviewResponse(now, triggered.Count, triggered.Count(signal => signal.Severity == "critical"),
            signals, settings, apiTraffic, liveMetrics, services);
    }

    private async Task<IReadOnlyList<AdminSystemServiceStatus>> GetServiceStatusesAsync(
        double databaseResponseTimeMs,
        double overviewResponseTimeMs,
        int activeSignalRConnections,
        CancellationToken ct)
    {
        var redisTask = CheckRedisAsync(ct);
        var vercelTask = CheckVercelAsync(ct);
        var r2Task = CheckR2Async(ct);

        return
        [
            new("api", "healthy", "Endpoint giám sát vừa xử lý dữ liệu thành công.", overviewResponseTimeMs),
            new("database", "healthy", "Truy vấn database Neon/PostgreSQL thành công.", databaseResponseTimeMs),
            await redisTask,
            await CheckRenderAsync(overviewResponseTimeMs, ct),
            await vercelTask,
            await r2Task,
            new("signalr", "unmonitored",
                $"Có {activeSignalRConnections:N0} kết nối realtime trên instance này; chưa có phép thử bắt tay SignalR riêng.", null)
        ];
    }

    private async Task<AdminSystemServiceStatus> CheckRedisAsync(CancellationToken ct)
    {
        var endpoint = configuration["UPSTASH_REDIS_REST_URL"] ?? configuration["SystemMonitoring:RedisRestUrl"];
        var token = configuration["UPSTASH_REDIS_REST_TOKEN"] ?? configuration["SystemMonitoring:RedisRestToken"];
        if (string.IsNullOrWhiteSpace(endpoint) || string.IsNullOrWhiteSpace(token))
            return new("redis", "unmonitored",
                "Backend chưa cấu hình URL/token kiểm tra Upstash Redis và hiện không dùng Redis.", null);
        if (!Uri.TryCreate(endpoint.TrimEnd('/') + "/ping", UriKind.Absolute, out var pingUri)
            || pingUri.Scheme != Uri.UriSchemeHttps)
            return new("redis", "error", "URL kiểm tra Upstash Redis không hợp lệ; cần dùng HTTPS.", null);

        var timer = Stopwatch.StartNew();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(HealthProbeTimeout);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, pingUri);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await httpClientFactory.CreateClient().SendAsync(request,
                HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
                return new("redis", "error", $"Upstash Redis trả HTTP {(int)response.StatusCode} khi ping.", timer.Elapsed.TotalMilliseconds);

            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var payload = await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
            var result = payload.RootElement.TryGetProperty("result", out var value) ? value.GetString() : null;
            return string.Equals(result, "PONG", StringComparison.OrdinalIgnoreCase)
                ? new("redis", "healthy", "Upstash Redis phản hồi PONG.", timer.Elapsed.TotalMilliseconds)
                : new("redis", "error", "Upstash Redis không trả kết quả PONG.", timer.Elapsed.TotalMilliseconds);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (OperationCanceledException)
        {
            return new("redis", "error", "Ping Upstash Redis quá thời gian 3 giây.", HealthProbeTimeout.TotalMilliseconds);
        }
        catch (HttpRequestException)
        {
            return new("redis", "error", "Không kết nối được tới Upstash Redis.", timer.Elapsed.TotalMilliseconds);
        }
        catch (JsonException)
        {
            return new("redis", "error", "Upstash Redis trả dữ liệu ping không hợp lệ.", timer.Elapsed.TotalMilliseconds);
        }
    }

    private async Task<AdminSystemServiceStatus> CheckVercelAsync(CancellationToken ct)
    {
        var sites = new[]
        {
            (Name: "admin", Url: configuration["Auth:AdminBaseUrl"]),
            (Name: "user", Url: configuration["Auth:WebBaseUrl"])
        }.Where(item => !string.IsNullOrWhiteSpace(item.Url))
            .DistinctBy(item => item.Url, StringComparer.OrdinalIgnoreCase).ToArray();
        if (sites.Length == 0)
            return new("vercel", "unmonitored", "Chưa cấu hình URL frontend để kiểm tra Vercel.", null);

        var results = await Task.WhenAll(sites.Select(async site =>
            (site.Name, Result: await ProbeHttpAsync(site.Url!, ct))));
        var failed = results.Where(result => !result.Result.IsHealthy).ToArray();
        var detail = string.Join("; ", results.Select(result => result.Result.StatusCode == 0
            ? $"{result.Name}: không kết nối được"
            : $"{result.Name}: HTTP {result.Result.StatusCode}"));
        var status = failed.Length == 0 ? "healthy"
            : failed.Any(result => result.Result.StatusCode >= 500 || result.Result.StatusCode == 0) ? "error" : "warning";
        return new("vercel", status, detail, results.Average(result => result.Result.ResponseTimeMs));
    }

    private Task<AdminSystemServiceStatus> CheckRenderAsync(double responseTimeMs, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var renderUrl = configuration["SystemMonitoring:RenderHealthUrl"]
            ?? configuration["RENDER_EXTERNAL_URL"]
            ?? Environment.GetEnvironmentVariable("RENDER_EXTERNAL_URL");
        if (string.IsNullOrWhiteSpace(renderUrl))
            return Task.FromResult(new AdminSystemServiceStatus("render", "unmonitored",
                "Không phát hiện URL service Render trong môi trường hiện tại.", null));

        return Task.FromResult(new AdminSystemServiceStatus("render", "healthy",
            "Backend trên Render vừa xử lý thành công request giám sát này.", responseTimeMs));
    }

    private async Task<AdminSystemServiceStatus> CheckR2Async(CancellationToken ct)
    {
        var timer = Stopwatch.StartNew();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(HealthProbeTimeout);
        try
        {
            var result = await objectStorage.CheckHealthAsync(timeout.Token);
            return result switch
            {
                true => new("storage", "healthy", "Cloudflare R2 nhận được yêu cầu liệt kê tối đa 1 object.", timer.Elapsed.TotalMilliseconds),
                false => new("storage", "error", "Cloudflare R2 không phản hồi kiểm tra bucket.", timer.Elapsed.TotalMilliseconds),
                _ => new("storage", "unmonitored", "Storage hiện tại không cung cấp phép kiểm tra bucket Cloudflare R2.", null)
            };
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (OperationCanceledException)
        {
            return new("storage", "error", "Kiểm tra Cloudflare R2 quá thời gian 3 giây.", HealthProbeTimeout.TotalMilliseconds);
        }
        catch (Exception)
        {
            return new("storage", "error", "Cloudflare R2 không phản hồi kiểm tra bucket.", timer.Elapsed.TotalMilliseconds);
        }
    }

    private async Task<HttpProbeResult> ProbeHttpAsync(string baseUrl, CancellationToken ct)
    {
        if (!Uri.TryCreate(baseUrl.TrimEnd('/') + "/", UriKind.Absolute, out var uri)
            || (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
                && !string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)))
            return new(false, 0, 0);

        var timer = Stopwatch.StartNew();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(HealthProbeTimeout);
        try
        {
            using var response = await httpClientFactory.CreateClient().GetAsync(uri,
                HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            return new(response.IsSuccessStatusCode, (int)response.StatusCode, timer.Elapsed.TotalMilliseconds);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { return new(false, 0, HealthProbeTimeout.TotalMilliseconds); }
        catch (HttpRequestException) { return new(false, 0, timer.Elapsed.TotalMilliseconds); }
    }

    private sealed record HttpProbeResult(bool IsHealthy, int StatusCode, double ResponseTimeMs);

    public async Task<AdminSystemReportResponse> GetReportAsync(int days, CancellationToken ct)
    {
        days = days is 7 or 30 or 90 ? days : 30;
        var now = DateTimeOffset.UtcNow;
        var start = new DateTimeOffset(now.UtcDateTime.Date.AddDays(1 - days), TimeSpan.Zero);

        var usersQuery = db.Users.AsNoTracking();
        var verifiedUsersQuery = usersQuery.Where(user => user.EmailVerifiedAt != null);
        var videosQuery = db.Videos.AsNoTracking();
        var publishedVideosQuery = videosQuery.Where(video => video.Status == "published");
        var channelsQuery = db.Channels.AsNoTracking().Where(channel => channel.Status != "deleted");
        var viewsQuery = db.ViewingHistories.AsNoTracking();
        var commentsQuery = db.Comments.AsNoTracking();
        var likesQuery = db.VideoReactions.AsNoTracking().Where(reaction => reaction.Type == "like");
        var subscribersQuery = db.Subscriptions.AsNoTracking().Where(subscription => subscription.Status == "active");
        var reportsQuery = db.Reports.AsNoTracking();
        var paymentsQuery = db.Payments.AsNoTracking();

        var userTotal = await usersQuery.LongCountAsync(ct);
        var usersInPeriod = await usersQuery.LongCountAsync(user => user.CreatedAt >= start && user.CreatedAt < now, ct);
        var verifiedTotal = await verifiedUsersQuery.LongCountAsync(ct);
        var verifiedInPeriod = await verifiedUsersQuery.LongCountAsync(user => user.EmailVerifiedAt >= start && user.EmailVerifiedAt < now, ct);
        var videoTotal = await videosQuery.LongCountAsync(ct);
        var videoInPeriod = await videosQuery.LongCountAsync(video => video.CreatedAt >= start && video.CreatedAt < now, ct);
        var publishedTotal = await publishedVideosQuery.LongCountAsync(ct);
        var publishedInPeriod = await publishedVideosQuery.LongCountAsync(video => video.PublishedAt >= start && video.PublishedAt < now, ct);
        var channelTotal = await channelsQuery.LongCountAsync(ct);
        var channelInPeriod = await channelsQuery.LongCountAsync(channel => channel.CreatedAt >= start && channel.CreatedAt < now, ct);
        var viewsTotal = await viewsQuery.LongCountAsync(ct);
        var viewsInPeriod = await viewsQuery.LongCountAsync(view => view.ViewedAt >= start && view.ViewedAt < now, ct);
        var commentsTotal = await commentsQuery.LongCountAsync(ct);
        var commentsInPeriod = await commentsQuery.LongCountAsync(comment => comment.CreatedAt >= start && comment.CreatedAt < now, ct);
        var likesTotal = await likesQuery.LongCountAsync(ct);
        var likesInPeriod = await likesQuery.LongCountAsync(reaction => reaction.CreatedAt >= start && reaction.CreatedAt < now, ct);
        var subscribersTotal = await subscribersQuery.LongCountAsync(ct);
        var subscribersInPeriod = await subscribersQuery.LongCountAsync(subscription => subscription.SubscribedAt >= start && subscription.SubscribedAt < now, ct);
        var reportsTotal = await reportsQuery.LongCountAsync(ct);
        var reportsInPeriod = await reportsQuery.LongCountAsync(report => report.CreatedAt >= start && report.CreatedAt < now, ct);
        var pendingReports = reportsQuery.Where(report => report.Status == "pending");
        var pendingReportsTotal = await pendingReports.LongCountAsync(ct);
        var pendingReportsInPeriod = await pendingReports.LongCountAsync(report => report.CreatedAt >= start && report.CreatedAt < now, ct);
        var pendingReviews = db.ModerationCases.AsNoTracking().Where(item => item.CaseType == "upload_review" && item.Status == "pending");
        var pendingReviewsTotal = await pendingReviews.LongCountAsync(ct);
        var pendingReviewsInPeriod = await pendingReviews.LongCountAsync(item => item.SubmittedAt >= start && item.SubmittedAt < now, ct);
        var pendingAppeals = db.Appeals.AsNoTracking().Where(appeal => appeal.Status == "pending" || appeal.Status == "reviewing");
        var pendingAppealsTotal = await pendingAppeals.LongCountAsync(ct);
        var pendingAppealsInPeriod = await pendingAppeals.LongCountAsync(appeal => appeal.CreatedAt >= start && appeal.CreatedAt < now, ct);
        var activeSessions = db.Sessions.AsNoTracking().Where(session => session.RevokedAt == null && session.ExpiresAt > now);
        var activeSessionsTotal = await activeSessions.LongCountAsync(ct);
        var activeSessionsInPeriod = await activeSessions.LongCountAsync(session => session.IssuedAt >= start, ct);
        var shares = db.ShareHistories.AsNoTracking();
        var sharesTotal = await shares.LongCountAsync(ct);
        var sharesInPeriod = await shares.LongCountAsync(share => share.SharedAt >= start && share.SharedAt < now, ct);

        var paidPayments = paymentsQuery.Where(payment => payment.Status == "paid");
        var totalRevenue = await paidPayments.SumAsync(payment => (decimal?)payment.Amount, ct) ?? 0;
        var transactionsTotal = await paidPayments.LongCountAsync(ct);
        var paidInPeriod = paidPayments.Where(payment => payment.PaidAt >= start && payment.PaidAt < now);
        var periodRevenue = await paidInPeriod.SumAsync(payment => (decimal?)payment.Amount, ct) ?? 0;
        var transactionsInPeriod = await paidInPeriod.LongCountAsync(ct);

        var usersByDay = await usersQuery.Where(user => user.CreatedAt >= start && user.CreatedAt < now)
            .GroupBy(user => new { user.CreatedAt.Year, user.CreatedAt.Month, user.CreatedAt.Day })
            .Select(group => new { group.Key.Year, group.Key.Month, group.Key.Day, Count = group.LongCount() }).ToListAsync(ct);
        var videosByDay = await videosQuery.Where(video => video.CreatedAt >= start && video.CreatedAt < now)
            .GroupBy(video => new { video.CreatedAt.Year, video.CreatedAt.Month, video.CreatedAt.Day })
            .Select(group => new { group.Key.Year, group.Key.Month, group.Key.Day, Count = group.LongCount() }).ToListAsync(ct);
        var viewsByDay = await viewsQuery.Where(view => view.ViewedAt >= start && view.ViewedAt < now)
            .GroupBy(view => new { view.ViewedAt.Year, view.ViewedAt.Month, view.ViewedAt.Day })
            .Select(group => new { group.Key.Year, group.Key.Month, group.Key.Day, Count = group.LongCount() }).ToListAsync(ct);
        var commentsByDay = await commentsQuery.Where(comment => comment.CreatedAt >= start && comment.CreatedAt < now)
            .GroupBy(comment => new { comment.CreatedAt.Year, comment.CreatedAt.Month, comment.CreatedAt.Day })
            .Select(group => new { group.Key.Year, group.Key.Month, group.Key.Day, Count = group.LongCount() }).ToListAsync(ct);
        var revenueByDay = await paidInPeriod.Where(payment => payment.PaidAt != null)
            .GroupBy(payment => new { payment.PaidAt!.Value.Year, payment.PaidAt.Value.Month, payment.PaidAt.Value.Day })
            .Select(group => new { group.Key.Year, group.Key.Month, group.Key.Day, Amount = group.Sum(payment => (decimal?)payment.Amount) ?? 0 })
            .ToListAsync(ct);

        var userLookup = usersByDay.ToDictionary(row => new DateOnly(row.Year, row.Month, row.Day), row => row.Count);
        var videoLookup = videosByDay.ToDictionary(row => new DateOnly(row.Year, row.Month, row.Day), row => row.Count);
        var viewLookup = viewsByDay.ToDictionary(row => new DateOnly(row.Year, row.Month, row.Day), row => row.Count);
        var commentLookup = commentsByDay.ToDictionary(row => new DateOnly(row.Year, row.Month, row.Day), row => row.Count);
        var revenueLookup = revenueByDay.ToDictionary(row => new DateOnly(row.Year, row.Month, row.Day), row => row.Amount);
        var daily = Enumerable.Range(0, days).Select(offset =>
        {
            var date = DateOnly.FromDateTime(start.UtcDateTime.Date.AddDays(offset));
            return new AdminSystemReportDay(date, userLookup.GetValueOrDefault(date), videoLookup.GetValueOrDefault(date),
                viewLookup.GetValueOrDefault(date), commentLookup.GetValueOrDefault(date), revenueLookup.GetValueOrDefault(date));
        }).ToList();

        var videoStatusCounts = await videosQuery.GroupBy(video => video.Status)
            .Select(group => new { Key = group.Key, Count = group.Count() })
            .OrderByDescending(item => item.Count).ToListAsync(ct);
        var videoStatuses = videoStatusCounts
            .Select(item => new AdminSystemReportSlice(item.Key, item.Count)).ToList();
        var reportStatusCounts = await reportsQuery.GroupBy(report => report.Status)
            .Select(group => new { Key = group.Key, Count = group.Count() })
            .OrderByDescending(item => item.Count).ToListAsync(ct);
        var reportStatuses = reportStatusCounts
            .Select(item => new AdminSystemReportSlice(item.Key, item.Count)).ToList();
        var paymentMethodCounts = await paymentsQuery.Where(payment => payment.Status == "paid")
            .GroupBy(payment => payment.PaymentMethod)
            .Select(group => new { Key = group.Key, Count = group.Count() })
            .OrderByDescending(item => item.Count).ToListAsync(ct);
        var paymentMethods = paymentMethodCounts
            .Select(item => new AdminSystemReportSlice(item.Key, item.Count)).ToList();

        return new AdminSystemReportResponse(now, days,
            new(userTotal, usersInPeriod), new(verifiedTotal, verifiedInPeriod),
            new(videoTotal, videoInPeriod), new(publishedTotal, publishedInPeriod), new(channelTotal, channelInPeriod),
            new(viewsTotal, viewsInPeriod), new(commentsTotal, commentsInPeriod), new(likesTotal, likesInPeriod),
            new(subscribersTotal, subscribersInPeriod), new(reportsTotal, reportsInPeriod),
            new(pendingReportsTotal, pendingReportsInPeriod), new(pendingReviewsTotal, pendingReviewsInPeriod),
            new(pendingAppealsTotal, pendingAppealsInPeriod), new(activeSessionsTotal, activeSessionsInPeriod),
            new(sharesTotal, sharesInPeriod), new(totalRevenue, transactionsTotal, periodRevenue, transactionsInPeriod),
            daily, videoStatuses, reportStatuses, paymentMethods);
    }

    public async Task<AdminAuditLogPage> GetAuditLogsAsync(
        int page, int pageSize, string? search, string? action, DateTimeOffset? fromDate, DateTimeOffset? toDate, CancellationToken ct)
    {
        page = Math.Clamp(page, 1, 10_000_000);
        pageSize = Math.Clamp(pageSize, 10, 100);
        var now = DateTimeOffset.UtcNow;
        var since = now.AddHours(-24);
        var allLogs = db.AuditLogs.AsNoTracking();
        var query = from log in allLogs
                    join actor in db.Users.IgnoreQueryFilters().AsNoTracking() on log.ActorUserId equals actor.UserId into actorGroup
                    from actor in actorGroup.DefaultIfEmpty()
                    select new { Log = log, ActorName = actor == null ? null : actor.DisplayName, ActorEmail = actor == null ? null : actor.Email };

        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            var exactIp = System.Net.IPAddress.TryParse(term, out var parsedIp) ? parsedIp.ToString() : null;
            query = query.Where(item => item.Log.Action.Contains(term)
                || (item.Log.ResourceType != null && item.Log.ResourceType.Contains(term))
                || (item.Log.Reason != null && item.Log.Reason.Contains(term))
                || (item.ActorName != null && item.ActorName.Contains(term))
                || (item.ActorEmail != null && item.ActorEmail.Contains(term))
                || (exactIp != null && item.Log.IpAddress == exactIp));
        }
        if (!string.IsNullOrWhiteSpace(action) && action != "all") query = query.Where(item => item.Log.Action == action);
        var fromUtc = fromDate?.ToUniversalTime();
        var toUtc = toDate?.ToUniversalTime();
        if (fromUtc.HasValue) query = query.Where(item => item.Log.CreatedAt >= fromUtc.Value);
        if (toUtc.HasValue) query = query.Where(item => item.Log.CreatedAt < toUtc.Value);

        var total = await query.LongCountAsync(ct);
        var items = await query.OrderByDescending(item => item.Log.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(item => new AdminAuditLogItem(
                item.Log.AuditLogId, item.Log.ActorUserId, item.ActorName, item.ActorEmail,
                item.Log.Action, item.Log.ResourceType, item.Log.ResourceId, item.Log.Reason,
                item.Log.IpAddress, item.Log.UserAgent, item.Log.CreatedAt))
            .ToListAsync(ct);

        var eventsLast24Hours = await allLogs.LongCountAsync(log => log.CreatedAt >= since && log.CreatedAt < now, ct);
        var activeAdministrators = await allLogs.Where(log => log.CreatedAt >= since && log.CreatedAt < now && log.ActorUserId != null)
            .Select(log => log.ActorUserId!.Value).Distinct().LongCountAsync(ct);
        var loginsLast24Hours = await allLogs.LongCountAsync(log => log.CreatedAt >= since && log.CreatedAt < now && log.Action == "admin.login", ct);
        var actions = await allLogs.Select(log => log.Action).Distinct().OrderBy(actionName => actionName).Take(100).ToListAsync(ct);
        var runtimeSettings = BuildRuntimeSettings();
        return new AdminAuditLogPage(page, pageSize, total, eventsLast24Hours, activeAdministrators, loginsLast24Hours,
            actions, runtimeSettings, items);
    }

    private IReadOnlyList<AdminSystemRuntimeSetting> BuildRuntimeSettings()
    {
        var rateLimit = configuration.GetValue("RateLimit:AuthPermitLimit", 60);
        var signupThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:SignupBurstPerHour", 20));
        var reviewThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:PendingReviewThreshold", 50));
        var paymentFailureThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:FailedPaymentsPerDay", 10));
        var apiErrorThreshold = Math.Max(1, configuration.GetValue("SystemAlerts:ApiErrorsPer15Minutes", 5));
        var memoryWarningThreshold = Math.Clamp(configuration.GetValue("SystemAlerts:MemoryWarningPercent", 75), 1, 99);
        var version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "unknown";
        var (memoryPercent, workingSetBytes, availableBytes) = ReadMemoryUsage();
        var memoryDisplay = memoryPercent is int currentMemoryPercent ? $"{currentMemoryPercent}%" : "không có số đo";
        return
        [
            new("Môi trường ứng dụng", environment.EnvironmentName, "ASPNETCORE_ENVIRONMENT"),
            new("API", "v1", "Định tuyến /api/v1"),
            new("Phiên bản backend", version, "Assembly đang chạy"),
            new("Giới hạn xác thực", $"{rateLimit} yêu cầu/phút/IP", "RateLimit:AuthPermitLimit"),
            new("Ngưỡng cảnh báo đăng ký", $"{signupThreshold} tài khoản/giờ", "SystemAlerts:SignupBurstPerHour"),
            new("Ngưỡng hàng đợi kiểm duyệt", $"{reviewThreshold} video", "SystemAlerts:PendingReviewThreshold"),
            new("Ngưỡng giao dịch lỗi", $"{paymentFailureThreshold} giao dịch/24 giờ", "SystemAlerts:FailedPaymentsPerDay"),
            new("Ngưỡng lỗi API", $"{apiErrorThreshold} lỗi/15 phút", "SystemAlerts:ApiErrorsPer15Minutes"),
            new("Cảnh báo bộ nhớ", $"{memoryWarningThreshold}% (hiện tại {memoryDisplay})", "SystemAlerts:MemoryWarningPercent"),
            new("Bộ nhớ tiến trình", $"{FormatBytes(workingSetBytes)} / {FormatBytes(availableBytes)}", "Process.WorkingSet64 / GC memory limit")
        ];
    }

    private static (int? Percent, long? WorkingSet, long? Available) ReadMemoryUsage()
    {
        try
        {
            using var process = Process.GetCurrentProcess();
            var workingSet = process.WorkingSet64;
            var available = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
            if (available <= 0) return (null, workingSet, available);
            return ((int)Math.Clamp(Math.Round(workingSet * 100d / available), 0, 100), workingSet, available);
        }
        catch (Exception) { return (null, null, null); }
    }

    private static string FormatBytes(long? value) => value switch
    {
        null or <= 0 => "không xác định",
        >= 1_073_741_824 => $"{value / 1_073_741_824d:0.0} GB",
        _ => $"{value / 1_048_576d:0} MB"
    };
}
