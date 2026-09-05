using HuTube.Application.Auth;
using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

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
}
public sealed class AuthEmailSender(EmailOptions options) : IAuthEmailSender
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
            using var client = new SmtpClient();
            await client.ConnectAsync(options.Host, options.Port, options.Port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls, ct);
            if (!string.IsNullOrEmpty(options.Username)) await client.AuthenticateAsync(options.Username, options.Password, ct);
            await client.SendAsync(message, ct); await client.DisconnectAsync(true, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            throw new AuthException(503, "EMAIL_DELIVERY_UNAVAILABLE", "Chưa thể gửi email. Vui lòng thử lại sau.");
        }
    }
}
