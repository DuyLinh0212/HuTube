using Google.Apis.Auth;
using HuTube.Application.Auth;

namespace HuTube.Infrastructure.Authentication;

public sealed class GoogleTokenVerifier(GoogleOptions options) : IGoogleTokenVerifier
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
        catch (Exception)
        {
            throw new AuthException(401, "INVALID_GOOGLE_TOKEN", "Không thể xác thực thông tin đăng nhập Google.");
        }
    }
}
