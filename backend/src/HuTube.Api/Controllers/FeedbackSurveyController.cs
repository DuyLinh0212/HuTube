using System.Security.Claims;
using System.Text;
using System.Text.Json;
using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Infrastructure.Account;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/feedback-survey")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class FeedbackSurveyController(IFeedbackSurveyService surveys, FeedbackSurveySecurity security) : ControllerBase
{
    [Authorize, HttpGet]
    public Task<FeedbackSurveyStatus> GetStatusAsync(CancellationToken ct)
    {
        var userId = Guid.Parse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? throw new AuthException(401, "UNAUTHORIZED", "Vui lòng đăng nhập."));
        return surveys.GetStatusAsync(userId, ct);
    }

    [AllowAnonymous, HttpPost("google-form-submission"), RequestSizeLimit(4096), EnableRateLimiting("feedback-survey-webhook")]
    public async Task<IActionResult> GoogleFormSubmissionAsync(CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var body = await reader.ReadToEndAsync(ct);
        if (!security.VerifyWebhook(body, Request.Headers["X-HuTube-Survey-Timestamp"], Request.Headers["X-HuTube-Survey-Signature"]))
            throw new AuthException(401, "INVALID_SURVEY_SIGNATURE", "Chữ ký xác nhận khảo sát không hợp lệ.");
        FeedbackSurveySubmission? submission;
        try { submission = JsonSerializer.Deserialize<FeedbackSurveySubmission>(body, new JsonSerializerOptions(JsonSerializerDefaults.Web)); }
        catch (JsonException) { throw new AuthException(400, "INVALID_SURVEY_SUBMISSION", "Dữ liệu xác nhận khảo sát không hợp lệ."); }
        if (submission is null) throw new AuthException(400, "INVALID_SURVEY_SUBMISSION", "Thiếu dữ liệu xác nhận khảo sát.");
        await surveys.CompleteAsync(submission, ct);
        return NoContent();
    }
}
