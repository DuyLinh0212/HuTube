using HuTube.Application.Auth;
using HuTube.Infrastructure.Authentication;
using MailKit.Net.Smtp;
using Microsoft.Extensions.Logging.Abstractions;
using MimeKit;

namespace HuTube.UnitTests;

public sealed class EmailTemplateTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not-a-url")]
    [InlineData("javascript:alert(1)")]
    [InlineData("ftp://dalitu.app")]
    [InlineData("https://user:password@dalitu.app")]
    [InlineData("https://dalitu.app?preview=1")]
    [InlineData("https://dalitu.app#preview")]
    public async Task AuthEmailSender_WithoutValidWebUrl_EmbedsLogoAndPlainTextFallback(string? webBaseUrl)
    {
        var pickupDirectory = Path.Combine(Path.GetTempPath(), "hutube-email-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(pickupDirectory);

        try
        {
            var sender = new AuthEmailSender(
                new EmailOptions { Mode = "Pickup", PickupDirectory = pickupDirectory, From = "noreply@hutube.local" },
                NullLogger<AuthEmailSender>.Instance,
                new TestHttpClientFactory(),
                webBaseUrl is null ? null : new AuthOptions { WebBaseUrl = webBaseUrl });
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

    [Theory]
    [InlineData("https://dalitu.app/", "https://dalitu.app/assets/logo.svg")]
    [InlineData("https://dalitu.app/a&b/", "https://dalitu.app/a&amp;b/assets/logo.svg")]
    public async Task AuthEmailSender_WithWebUrl_UsesEncodedSvgLogo(string webBaseUrl, string expectedLogoUrl)
    {
        // Arrange
        var pickupDirectory = Path.Combine(Path.GetTempPath(), "dalitu-email-" + Guid.NewGuid().ToString("N"));
        var sender = new AuthEmailSender(
            new EmailOptions { Mode = "Pickup", PickupDirectory = pickupDirectory, From = "noreply@dalitu.app" },
            NullLogger<AuthEmailSender>.Instance,
            new TestHttpClientFactory(),
            new AuthOptions { WebBaseUrl = webBaseUrl });
        var template = EmailTemplateMessage.FromPlainText("Dalitu", "Email content");

        try
        {
            // Act
            await sender.SendTemplateAsync("user@example.com", template, CancellationToken.None);
            var message = MimeMessage.Load(Directory.GetFiles(pickupDirectory).Single());

            // Assert
            Assert.Contains($"src=\"{expectedLogoUrl}\"", message.HtmlBody);
            Assert.Contains($"href=\"{expectedLogoUrl}\"", message.HtmlBody);
            Assert.Contains("alt=\"Dalitu\"", message.HtmlBody);
            Assert.DoesNotContain("cid:dalitu-email-logo", message.HtmlBody);
            Assert.DoesNotContain(message.BodyParts.OfType<MimePart>(), part => part.ContentType.MediaType == "image");
            Assert.Contains("Email content", message.TextBody);
        }
        finally
        {
            if (Directory.Exists(pickupDirectory)) Directory.Delete(pickupDirectory, recursive: true);
        }
    }

    private sealed class TestHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new();
    }
}
