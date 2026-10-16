using HuTube.Application.Account;
using HuTube.Application.Auth;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Account;

public sealed class FeedbackSurveyService(HuTubeDbContext db, FeedbackSurveyOptions options, FeedbackSurveySecurity security) : IFeedbackSurveyService
{
    public async Task<FeedbackSurveyStatus> GetStatusAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users.AsNoTracking().Where(x => x.UserId == userId)
            .Select(x => new { x.DisplayName, x.FeedbackSurveyCompletedAt }).SingleOrDefaultAsync(ct)
            ?? throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");
        var completed = user.FeedbackSurveyCompletedAt != null;
        var enabled = options.Enabled && options.IsConfigured;
        var url = enabled && !completed
            ? FeedbackSurveyOptions.FormUrl + "?usp=pp_url&entry." + options.TokenEntryId + "=" + Uri.EscapeDataString(security.CreateToken(userId))
                + "&entry.819508883=" + Uri.EscapeDataString(user.DisplayName)
            : null;
        return new(enabled, completed, user.FeedbackSurveyCompletedAt, url);
    }

    public async Task CompleteAsync(FeedbackSurveySubmission submission, CancellationToken ct = default)
    {
        if (submission.FormId != FeedbackSurveyOptions.PublicFormId
            || string.IsNullOrWhiteSpace(submission.ResponseId) || submission.ResponseId.Length > 512
            || !security.TryReadToken(submission.SurveyToken, out var userId)
            || submission.SubmittedAt == default || submission.SubmittedAt > DateTimeOffset.UtcNow.AddMinutes(5))
            throw new AuthException(400, "INVALID_SURVEY_SUBMISSION", "Xác nhận khảo sát không hợp lệ.");

        var completedAt = submission.SubmittedAt.ToUniversalTime();
        // A retry, duplicate trigger, or edited response must preserve the first completion.
        var changed = await db.Users.Where(x => x.UserId == userId && x.FeedbackSurveyCompletedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.FeedbackSurveyCompletedAt, completedAt), ct);
        if (changed == 0 && !await db.Users.AnyAsync(x => x.UserId == userId, ct))
            throw new AuthException(404, "USER_NOT_FOUND", "Không tìm thấy tài khoản.");
    }
}
