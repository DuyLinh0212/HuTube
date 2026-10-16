namespace HuTube.Application.Account;

public sealed record FeedbackSurveyStatus(bool Enabled, bool HasCompleted, DateTimeOffset? CompletedAt, string? FormUrl);

public sealed record FeedbackSurveySubmission(string FormId, string SurveyToken, string ResponseId, DateTimeOffset SubmittedAt);

public interface IFeedbackSurveyService
{
    Task<FeedbackSurveyStatus> GetStatusAsync(Guid userId, CancellationToken ct = default);
    Task CompleteAsync(FeedbackSurveySubmission submission, CancellationToken ct = default);
}
