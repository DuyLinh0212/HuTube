using Google.Apis.Auth;
using HuTube.Application.Auth;
using Microsoft.Extensions.Logging;

namespace HuTube.Infrastructure.Authentication;

public sealed class GoogleTokenVerifier(GoogleOptions options, ILogger<GoogleTokenVerifier> logger) : IGoogleTokenVerifier
{
    public async Task<GoogleIdentity> VerifyAsync(string credential, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ClientId))
            throw new AuthException(503, "GOOGLE_LOGIN_NOT_CONFIGURED", "Đăng nhập Google chưa được cấu hình.");

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var payload = await GoogleJsonWebSignature.ValidateAsync(credential,
                new GoogleJsonWebSignature.ValidationSettings { Audience = [options.ClientId] });
            if (string.IsNullOrWhiteSpace(payload.Subject) || string.IsNullOrWhiteSpace(payload.Email) || payload.EmailVerified != true)
                throw new AuthException(401, "INVALID_GOOGLE_TOKEN", "Google chưa xác minh địa chỉ email này.");
            return new GoogleIdentity(payload.Subject, payload.Email, payload.Name ?? payload.Email.Split('@')[0], payload.Picture);
        }
        catch (AuthException) { throw; }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (InvalidJwtException ex)
        {
            // Log only a fixed diagnostic label, never the credential or exception
            // message, which may contain claims from an untrusted token.
            var message = ex.Message;
            var reason = message.Contains("audience", StringComparison.OrdinalIgnoreCase) || message.Contains("'aud'", StringComparison.OrdinalIgnoreCase) ? "audience_mismatch"
                : message.Contains("expired", StringComparison.OrdinalIgnoreCase) ? "token_expired"
                : message.Contains("future", StringComparison.OrdinalIgnoreCase) || message.Contains("early", StringComparison.OrdinalIgnoreCase) || message.Contains("not yet valid", StringComparison.OrdinalIgnoreCase) ? "token_not_yet_valid_check_server_clock"
                : message.Contains("issuer", StringComparison.OrdinalIgnoreCase) ? "issuer_invalid"
                : message.Contains("signature", StringComparison.OrdinalIgnoreCase) ? "signature_invalid"
                : "malformed_or_invalid_token";
            logger.LogWarning("Google token validation failed: {Reason}. Server UTC: {ServerUtc}", reason, DateTimeOffset.UtcNow);
            throw new AuthException(401, "INVALID_GOOGLE_TOKEN", "Không thể xác thực thông tin đăng nhập Google.");
        }
        catch (Exception ex)
        {
            logger.LogError("Google verification unavailable. Exception type: {ExceptionType}; inner type: {InnerType}. Server UTC: {ServerUtc}",
                ex.GetType().FullName, ex.InnerException?.GetType().FullName, DateTimeOffset.UtcNow);
            throw new AuthException(503, "GOOGLE_VERIFICATION_UNAVAILABLE", "Chưa thể kết nối hoặc xử lý xác thực Google. Vui lòng thử lại sau.");
        }
    }
}
