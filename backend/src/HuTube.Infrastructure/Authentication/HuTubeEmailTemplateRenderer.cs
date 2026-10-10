using System.Net;
using System.Text;
using HuTube.Application.Auth;

namespace HuTube.Infrastructure.Authentication;

internal static class HuTubeEmailTemplateRenderer
{
    public static string RenderHtml(EmailTemplateMessage message)
    {
        var html = new StringBuilder(8_000);
        var preheader = FirstNonEmpty(message.Paragraphs.FirstOrDefault(), message.Title);

        html.Append("<!doctype html><html lang=\"vi\"><head>");
        html.Append("<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        html.Append("<meta name=\"x-apple-disable-message-reformatting\"><title>");
        html.Append(Html(message.Subject));
        html.Append("</title>");
        html.Append("<style>");
        html.Append("body{margin:0!important;padding:0!important;background:#FAF8F7;color:#111827;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}");
        html.Append("table{border-collapse:collapse;}img{border:0;display:block;max-width:100%;}a{color:#FF2B66;}");
        html.Append(".email-shell{width:620px;max-width:620px;}.email-card{border-radius:26px;}.email-content{padding:42px 46px;}.email-title{font-size:34px;line-height:1.12;}.email-paragraph{font-size:15px;line-height:1.7;}");
        html.Append("@media only screen and (max-width:600px){.email-shell{width:100%!important;}.email-outer{padding:16px 10px!important;}.email-card{border-radius:20px!important;}.email-content{padding:30px 22px!important;}.email-title{font-size:29px!important;}.email-paragraph{font-size:15px!important;}.email-button a{display:block!important;padding:15px 18px!important;}.email-footer{padding:0 18px 18px!important;}}");
        html.Append("</style></head><body>");
        html.Append("<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;\">");
        html.Append(Html(preheader));
        html.Append("</div>");
        html.Append("<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"width:100%;background:#FAF8F7;\">");
        html.Append("<tr><td class=\"email-outer\" align=\"center\" style=\"padding:34px 14px;\">");
        html.Append("<table role=\"presentation\" class=\"email-shell\" width=\"620\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"width:620px;max-width:620px;\">");

        html.Append("<tr><td style=\"padding:0 8px 18px;\">");
        html.Append("<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr>");
        html.Append("<td width=\"44\" height=\"44\" align=\"center\" valign=\"middle\" style=\"width:44px;height:44px;border-radius:14px;background:linear-gradient(135deg,#FF4D80 0%,#FF2B66 52%,#7C3AED 100%);color:#FFFFFF;font-family:Arial,sans-serif;font-size:23px;font-weight:800;line-height:44px;\">H</td>");
        html.Append("<td style=\"padding-left:12px;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:21px;font-weight:800;letter-spacing:-.6px;color:#111827;\">Hu<span style=\"color:#FF2B66;\">Tube</span><div style=\"padding-top:3px;font-size:10px;font-weight:700;letter-spacing:1.5px;color:#9CA3AF;text-transform:uppercase;\">GOOD VIDEOS · BETTER PEOPLE</div></td>");
        html.Append("</tr></table></td></tr>");

        html.Append("<tr><td class=\"email-card\" style=\"overflow:hidden;background:#FFFFFF;border:1px solid #E5E7EB;box-shadow:0 20px 45px -12px rgba(255,43,102,.12),0 8px 20px -4px rgba(17,24,39,.04);\">");
        html.Append("<div style=\"height:6px;background:linear-gradient(135deg,#FF3B69 0%,#FF2B66 50%,#E61952 100%);\"></div>");
        html.Append("<div class=\"email-content\" style=\"padding:42px 46px;\">");
        html.Append("<div style=\"font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:11px;font-weight:800;letter-spacing:1.8px;color:#FF2B66;text-transform:uppercase;\">");
        html.Append(Html(FirstNonEmpty(message.Eyebrow, "THÔNG BÁO TỪ HUTUBE")));
        html.Append("</div>");
        html.Append("<h1 class=\"email-title\" style=\"margin:14px 0 22px;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:34px;line-height:1.12;font-weight:800;letter-spacing:-1.1px;color:#111827;\">");
        html.Append(Html(message.Title));
        html.Append("</h1>");
        html.Append("<div style=\"width:48px;height:4px;border-radius:99px;background:#FF2B66;margin:0 0 26px;\"></div>");

        foreach (var paragraph in message.Paragraphs.Where(paragraph => !string.IsNullOrWhiteSpace(paragraph)))
        {
            html.Append("<p class=\"email-paragraph\" style=\"margin:0 0 16px;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:15px;line-height:1.7;color:#374151;\">");
            html.Append(HtmlWithBreaks(paragraph));
            html.Append("</p>");
        }

        var safeActionUrl = SafeActionUrl(message.ActionUrl);
        if (safeActionUrl is not null)
        {
            var actionUrl = Html(safeActionUrl);
            var actionLabel = Html(FirstNonEmpty(message.ActionLabel, "Mở trên HuTube"));
            html.Append("<table role=\"presentation\" class=\"email-button\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"margin:28px 0 22px;\"><tr><td style=\"border-radius:12px;background:#FF2B66;box-shadow:0 8px 20px -2px rgba(255,43,102,.28);\">");
            html.Append("<a href=\"");
            html.Append(actionUrl);
            html.Append("\" style=\"display:inline-block;padding:14px 22px;border-radius:12px;color:#FFFFFF;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:14px;font-weight:800;line-height:1.2;text-decoration:none;\">");
            html.Append(actionLabel);
            html.Append("</a></td></tr></table>");
        }

        if (!string.IsNullOrWhiteSpace(message.Note))
        {
            html.Append("<div style=\"margin-top:22px;padding:14px 16px;border:1px solid #FCE7EF;border-radius:12px;background:#FFF7FA;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:12px;line-height:1.6;color:#6B7280;\">");
            html.Append(HtmlWithBreaks(message.Note));
            html.Append("</div>");
        }

        html.Append("</div></td></tr>");
        html.Append("<tr><td class=\"email-footer\" align=\"center\" style=\"padding:22px 18px 4px;font-family:'Plus Jakarta Sans',Arial,sans-serif;font-size:11px;line-height:1.6;color:#9CA3AF;\">");
        html.Append("Bạn nhận được email này từ HuTube vì có hoạt động liên quan đến tài khoản của bạn.<br>");
        html.Append("Nếu cần hỗ trợ, hãy trả lời email này hoặc truy cập HuTube.");
        html.Append("</td></tr></table></td></tr></table></body></html>");
        return html.ToString();
    }

    private static string Html(string value) => WebUtility.HtmlEncode(value);

    private static string HtmlWithBreaks(string value) =>
        Html(value).Replace("\n", "<br>", StringComparison.Ordinal);

    private static string FirstNonEmpty(string? value, string fallback) =>
        string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();

    private static string? SafeActionUrl(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri)
            && uri.Scheme is "http" or "https"
            ? uri.AbsoluteUri
            : null;
    }
}
