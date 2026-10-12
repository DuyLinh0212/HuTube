using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace HuTube.Infrastructure.Payments;

public sealed record VnPayResponse(
    string TransactionReference,
    long AmountMinor,
    string ResponseCode,
    string TransactionStatus,
    string TransactionNo,
    IReadOnlyDictionary<string, string> Parameters);

/// <summary>Creates and verifies VNPay v2.1.0 payment URLs and callback signatures.</summary>
public sealed class VnPayGateway(VnPayOptions options)
{
    private const string Version = "2.1.0";
    private const string PaymentCommand = "pay";

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(options.TmnCode)
        && options.TmnCode.Length == 8 && options.TmnCode.All(char.IsAsciiLetterOrDigit)
        && !string.IsNullOrWhiteSpace(options.HashSecret)
        && IsVnPayPaymentUrl(options.PaymentUrl)
        && IsHttpsOrLocalHttp(options.ReturnUrl)
        && IsHttpsOrLocalHttp(options.FrontendReturnUrl);

    public string CreatePaymentUrl(string transactionReference, decimal amount, string clientIp, DateTimeOffset now)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("VNPAY payment configuration is incomplete.");
        if (amount <= 0 || amount > 9_999_999_999m || amount != decimal.Truncate(amount))
            throw new InvalidOperationException("VNPAY requires a positive whole-VND amount.");

        var amountMinor = checked((long)(amount * 100m));
        if (amountMinor > 999_999_999_999L)
            throw new InvalidOperationException("VNPAY amount exceeds the supported limit.");

        var localTime = now.ToOffset(TimeSpan.FromHours(7));
        var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["vnp_Version"] = Version,
            ["vnp_Command"] = PaymentCommand,
            ["vnp_TmnCode"] = options.TmnCode,
            ["vnp_Amount"] = amountMinor.ToString(CultureInfo.InvariantCulture),
            ["vnp_CurrCode"] = "VND",
            ["vnp_CreateDate"] = localTime.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture),
            ["vnp_ExpireDate"] = localTime.AddMinutes(options.PaymentExpiryMinutes)
                .ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture),
            ["vnp_IpAddr"] = NormalizeIpAddress(clientIp),
            ["vnp_Locale"] = "vn",
            ["vnp_OrderInfo"] = "Thanh toan goi dich vu HuTube " + transactionReference,
            ["vnp_OrderType"] = "other",
            ["vnp_ReturnUrl"] = options.ReturnUrl,
            ["vnp_TxnRef"] = transactionReference,
        };

        var signedData = BuildCanonicalQuery(parameters);
        var signature = ComputeSignature(signedData);
        return options.PaymentUrl + "?" + signedData + "&vnp_SecureHash=" + signature;
    }

    public bool TryValidateResponse(IReadOnlyDictionary<string, string> parameters, out VnPayResponse? response)
    {
        response = null;
        if (string.IsNullOrWhiteSpace(options.HashSecret) || string.IsNullOrWhiteSpace(options.TmnCode)
            || !parameters.TryGetValue("vnp_SecureHash", out var suppliedHash)
            || !parameters.TryGetValue("vnp_TmnCode", out var tmnCode)
            || !string.Equals(tmnCode, options.TmnCode, StringComparison.Ordinal)
            || !parameters.TryGetValue("vnp_TxnRef", out var transactionReference)
            || transactionReference.Length is < 1 or > 100
            || !parameters.TryGetValue("vnp_Amount", out var rawAmount)
            || !long.TryParse(rawAmount, NumberStyles.None, CultureInfo.InvariantCulture, out var amountMinor)
            || amountMinor <= 0
            || !parameters.TryGetValue("vnp_ResponseCode", out var responseCode)
            || responseCode.Length != 2
            || !parameters.TryGetValue("vnp_TransactionStatus", out var transactionStatus)
            || transactionStatus.Length != 2)
            return false;

        var signedParameters = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in parameters)
        {
            if (!key.StartsWith("vnp_", StringComparison.Ordinal)
                || key is "vnp_SecureHash" or "vnp_SecureHashType"
                || string.IsNullOrEmpty(value))
                continue;
            signedParameters[key] = value;
        }

        var expectedHash = ComputeSignature(BuildCanonicalQuery(signedParameters));
        if (!FixedTimeHexEquals(expectedHash, suppliedHash))
            return false;

        var transactionNo = parameters.GetValueOrDefault("vnp_TransactionNo", "");
        if (responseCode == "00" && transactionStatus == "00"
            && (transactionNo.Length is < 1 or > 15 || transactionNo.Any(c => c is < '0' or > '9')))
            return false;

        response = new VnPayResponse(transactionReference, amountMinor, responseCode, transactionStatus,
            transactionNo, parameters);
        return true;
    }

    private string ComputeSignature(string data)
    {
        using var hmac = new HMACSHA512(Encoding.UTF8.GetBytes(options.HashSecret));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(data))).ToLowerInvariant();
    }

    private static string BuildCanonicalQuery(IEnumerable<KeyValuePair<string, string>> parameters) =>
        string.Join("&", parameters.Select(parameter =>
            $"{WebUtility.UrlEncode(parameter.Key)}={WebUtility.UrlEncode(parameter.Value)}"));

    private static bool FixedTimeHexEquals(string expected, string supplied)
    {
        if (supplied.Length != expected.Length) return false;
        try
        {
            var expectedBytes = Convert.FromHexString(expected);
            var suppliedBytes = Convert.FromHexString(supplied);
            return CryptographicOperations.FixedTimeEquals(expectedBytes, suppliedBytes);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static bool IsHttpsOrLocalHttp(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.UserInfo.Length > 0
            || uri.Query.Length > 0 || uri.Fragment.Length > 0)
            return false;
        return uri.Scheme == Uri.UriSchemeHttps
            || (uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback);
    }

    private static bool IsVnPayPaymentUrl(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps
            || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0)
            return false;
        var host = uri.Host;
        return host.Equals("vnpayment.vn", StringComparison.OrdinalIgnoreCase)
            || host.EndsWith(".vnpayment.vn", StringComparison.OrdinalIgnoreCase)
            || host.Equals("vnpay.vn", StringComparison.OrdinalIgnoreCase)
            || host.EndsWith(".vnpay.vn", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeIpAddress(string value)
    {
        if (!IPAddress.TryParse(value, out var address)) return "127.0.0.1";
        return address.IsIPv4MappedToIPv6 ? address.MapToIPv4().ToString() : address.ToString();
    }
}
