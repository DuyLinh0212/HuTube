namespace HuTube.Infrastructure.Payments;

/// <summary>Server-side VNPay configuration. Keep HashSecret in environment secrets.</summary>
public sealed class VnPayOptions
{
    public string TmnCode { get; set; } = "";
    public string HashSecret { get; set; } = "";
    public string PaymentUrl { get; set; } = "";
    public string ReturnUrl { get; set; } = "";
    public string FrontendReturnUrl { get; set; } = "";
    public int PaymentExpiryMinutes { get; set; } = 30;
}
