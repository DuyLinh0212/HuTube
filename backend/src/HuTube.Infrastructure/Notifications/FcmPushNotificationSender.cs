using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Google.Apis.Auth.OAuth2;
using HuTube.Application.Notifications;

namespace HuTube.Infrastructure.Notifications;

public sealed class FcmOptions
{
    public bool Enabled { get; set; }
    public string ProjectId { get; set; } = "";
    public string CredentialsPath { get; set; } = "";
}

// Shared across delivery scopes: GoogleCredential caches and refreshes OAuth
// access tokens instead of exchanging a new token for every recipient.
public sealed class FcmCredentialProvider(FcmOptions options) : IDisposable
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private GoogleCredential? credential;

    public async Task<string> GetAccessTokenAsync(CancellationToken ct)
    {
        await gate.WaitAsync(ct);
        try
        {
            credential ??= (await CredentialFactory.FromFileAsync<ServiceAccountCredential>(options.CredentialsPath, ct))
                .ToGoogleCredential().CreateScoped("https://www.googleapis.com/auth/firebase.messaging");
            return await credential.UnderlyingCredential.GetAccessTokenForRequestAsync(cancellationToken: ct);
        }
        finally { gate.Release(); }
    }

    public void Dispose() => gate.Dispose();
}

public sealed class FcmPushNotificationSender(HttpClient http, FcmOptions options, FcmCredentialProvider credentials) : IPushNotificationSender
{
    public bool Enabled => options.Enabled;

    public async Task<bool> SendAsync(string token, NotificationMessage message, Guid notificationId, CancellationToken ct)
    {
        if (!Enabled) return true;
        if (string.IsNullOrWhiteSpace(options.ProjectId) || string.IsNullOrWhiteSpace(options.CredentialsPath))
            throw new InvalidOperationException("FCM project and service-account credential path are required.");
        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"https://fcm.googleapis.com/v1/projects/{Uri.EscapeDataString(options.ProjectId)}/messages:send");
        request.Headers.Authorization = new("Bearer", await credentials.GetAccessTokenAsync(ct));
        request.Content = JsonContent.Create(new { message = new {
            token, notification = new { title = message.Title, body = message.Content },
            data = new Dictionary<string, string> {
                ["notificationId"] = notificationId.ToString(), ["type"] = message.Type,
                ["recipientId"] = message.UserId.ToString(),
                ["actionUrl"] = message.ActionUrl ?? "", ["resourceType"] = message.ResourceType ?? "",
                ["resourceId"] = message.ResourceId?.ToString() ?? ""
            },
            android = new { priority = "high", notification = new { channel_id = "hutube_notifications", tag = notificationId.ToString() } },
            apns = new { headers = new Dictionary<string, string> { ["apns-collapse-id"] = notificationId.ToString() } }
        }});
        using var response = await http.SendAsync(request, ct);
        if (response.IsSuccessStatusCode) return true;
        if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.BadRequest)
        {
            using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            if (payload.RootElement.TryGetProperty("error", out var error) && error.TryGetProperty("details", out var details)
                && details.ValueKind == JsonValueKind.Array && details.EnumerateArray().Any(detail =>
                    detail.TryGetProperty("errorCode", out var code) && code.GetString() == "UNREGISTERED")) return false;
        }
        // Status only: registration tokens and provider response bodies stay out of logs.
        throw new HttpRequestException($"FCM delivery returned HTTP {(int)response.StatusCode}.", null, response.StatusCode);
    }
}
