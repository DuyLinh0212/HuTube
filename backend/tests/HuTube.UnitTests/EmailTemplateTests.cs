using HuTube.Application.Auth;
using HuTube.Infrastructure.Authentication;
using MailKit.Net.Smtp;
using Microsoft.Extensions.Logging.Abstractions;
using MimeKit;

namespace HuTube.UnitTests;

public sealed class EmailTemplateTests
{
    [Fact]
    public async Task AuthEmailSender_WritesOneBrandedHtmlTemplateWithPlainTextFallback()
    {
        var pickupDirectory = Path.Combine(Path.GetTempPath(), "hutube-email-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(pickupDirectory);

        try
        {
            var sender = new AuthEmailSender(
                new EmailOptions { Mode = "Pickup", PickupDirectory = pickupDirectory, From = "noreply@hutube.local" },
                NullLogger<AuthEmailSender>.Instance,
                new TestHttpClientFactory());
            var template = new EmailTemplateMessage(
                "Đặt lại mật khẩu Dalitu",
                "BẢO MẬT TÀI KHOẢN",
                "Đặt lại mật khẩu Dalitu",
                ["Chúng tôi nhận được yêu cầu đặt lại mật khẩu."],
                "Đặt lại mật khẩu",
                "https://hutube.example/reset-password?token=abc123",
                "Liên kết có hiệu lực trong 30 phút.");

            await sender.SendTemplateAsync("user@example.com", template, CancellationToken.None);

            var message = MimeMessage.Load(Directory.GetFiles(pickupDirectory).Single());
            var alternatives = Assert.IsType<MultipartAlternative>(message.Body);
            var plainText = Assert.Single(alternatives.OfType<TextPart>(), part => part.ContentType.MediaSubtype == "plain");
            var related = Assert.IsType<MultipartRelated>(alternatives[1]);
            var html = Assert.IsType<TextPart>(related[0]);
            var logo = Assert.IsType<MimePart>(related[1]);

            Assert.Contains("https://hutube.example/reset-password?token=abc123", plainText.Text);
            Assert.Contains("Đặt lại mật khẩu Dalitu", html.Text);
            Assert.Contains("href=\"https://hutube.example/reset-password?token=abc123\"", html.Text);
            Assert.Contains("src=\"cid:dalitu-email-logo\"", html.Text);
            Assert.Equal("dalitu-email-logo", logo.ContentId);
            Assert.Equal("image", logo.ContentType.MediaType);
            Assert.Equal("png", logo.ContentType.MediaSubtype);
            Assert.Contains("#FF2B66", html.Text);
        }
        finally
        {
            Directory.Delete(pickupDirectory, recursive: true);
        }
    }

    private sealed class TestHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new();
    }
}
