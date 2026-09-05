using HuTube.Application.Auth;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Authentication;

public sealed class EmailOptions
{
    public string Mode { get; set; } = "Smtp";
    public string PickupDirectory { get; set; } = ".work/mail";
    public string From { get; set; } = "noreply@hutube.local";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 587;
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public GmailEmailOptions Gmail { get; set; } = new();
}

public sealed class GmailEmailOptions
{
    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public string TokenEndpoint { get; set; } = "https://oauth2.googleapis.com/token";
    public string ApiEndpoint { get; set; } = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";
}

public sealed class AuthEmailSender(
    EmailOptions options,
    ILogger<AuthEmailSender> logger,
    IHttpClientFactory httpClientFactory) : IAuthEmailSender
{
    public async Task SendAsync(string email, string subject, string body, CancellationToken ct)
    {
        var message = new MimeMessage();
        message.From.Add(MailboxAddress.Parse(options.From)); message.To.Add(MailboxAddress.Parse(email));
        message.Subject = subject; message.Body = new TextPart("plain") { Text = body };
        try
        {
            if (options.Mode == "Pickup")
            {
                Directory.CreateDirectory(options.PickupDirectory);
                await message.WriteToAsync(Path.Combine(options.PickupDirectory, $"{Guid.NewGuid():N}.eml"), ct);
                return;
            }

            if (options.Mode == "GmailApi")
            {
                await SendViaGmailApiAsync(message, ct);
                return;
            }

            using var client = new SmtpClient { Timeout = 15_000 };
            await client.ConnectAsync(options.Host, options.Port, options.Port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls, ct);
            var username = options.Username.Trim();
            var password = options.Password.Replace(" ", "", StringComparison.Ordinal);
            if (!string.IsNullOrEmpty(username)) await client.AuthenticateAsync(username, password, ct);
            await client.SendAsync(message, ct); await client.DisconnectAsync(true, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException && ex is not AuthException)
        {
            logger.LogError(ex, "SMTP email delivery failed for {Recipient}", email);
            throw new AuthException(503, "EMAIL_DELIVERY_UNAVAILABLE", "Chưa thể gửi email. Vui lòng thử lại sau.");
        }
    }

    private async Task SendViaGmailApiAsync(MimeMessage message, CancellationToken ct)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        var cancellationToken = timeout.Token;
        var client = httpClientFactory.CreateClient();

        try
        {
            using var tokenRequest = new HttpRequestMessage(HttpMethod.Post, options.Gmail.TokenEndpoint)
            {
                Content = new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["client_id"] = options.Gmail.ClientId,
                    ["client_secret"] = options.Gmail.ClientSecret,
                    ["refresh_token"] = options.Gmail.RefreshToken,
                    ["grant_type"] = "refresh_token"
                })
            };
            using var tokenResponse = await client.SendAsync(tokenRequest, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            var tokenBody = await tokenResponse.Content.ReadAsStringAsync(cancellationToken);
            if (!tokenResponse.IsSuccessStatusCode)
                throw new InvalidOperationException($"Gmail OAuth token request failed ({(int)tokenResponse.StatusCode}): {tokenBody}");

            var token = System.Text.Json.JsonSerializer.Deserialize<GmailTokenResponse>(tokenBody)
                ?? throw new InvalidOperationException("Gmail OAuth token response was empty.");
            if (string.IsNullOrWhiteSpace(token.AccessToken))
                throw new InvalidOperationException("Gmail OAuth token response did not contain an access token.");

            await using var stream = new MemoryStream();
            await message.WriteToAsync(stream, cancellationToken);
            var raw = Convert.ToBase64String(stream.ToArray())
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');

            using var sendRequest = new HttpRequestMessage(HttpMethod.Post, options.Gmail.ApiEndpoint);
            sendRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.AccessToken);
            sendRequest.Content = JsonContent.Create(new { raw });
            using var sendResponse = await client.SendAsync(sendRequest, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            var sendBody = await sendResponse.Content.ReadAsStringAsync(cancellationToken);
            if (!sendResponse.IsSuccessStatusCode)
                throw new InvalidOperationException($"Gmail API send failed ({(int)sendResponse.StatusCode}): {sendBody}");
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            logger.LogError("Gmail API email delivery timed out.");
            throw new TimeoutException("Gmail API request timed out.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Gmail API email delivery failed");
            throw new AuthException(503, "EMAIL_DELIVERY_UNAVAILABLE", "Chưa thể gửi email. Vui lòng thử lại sau.");
        }
    }

    private sealed record GmailTokenResponse(
        [property: JsonPropertyName("access_token")] string AccessToken,
        [property: JsonPropertyName("expires_in")] int ExpiresIn,
        [property: JsonPropertyName("token_type")] string TokenType);
}
