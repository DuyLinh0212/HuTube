using System.Net.Mail;

namespace HuTube.Application.Auth;

public static class AuthRules
{
    public static string NormalizeEmail(string email)
    {
        var value = email?.Trim().ToLowerInvariant() ?? "";
        if (value.Length > 254 || !MailAddress.TryCreate(value, out var address) || address.Address != value || !value.Contains('.'))
            throw new AuthException(400, "INVALID_EMAIL", "Địa chỉ email không hợp lệ.");
        return value;
    }
    public static void ValidatePassword(string password)
    {
        if (password is null || password.Length is < 10 or > 128 || !password.Any(char.IsUpper)
            || !password.Any(char.IsLower) || !password.Any(char.IsDigit))
            throw new AuthException(400, "INVALID_PASSWORD", "Mật khẩu cần 10–128 ký tự, gồm chữ hoa, chữ thường và số.");
    }
}
