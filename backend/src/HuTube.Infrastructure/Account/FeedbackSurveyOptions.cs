namespace HuTube.Infrastructure.Account;

public sealed class FeedbackSurveyOptions
{
    public const string PublicFormId = "1FAIpQLSef9jF_PK4qnoEZjPjS7kq1Lk4iQbEtoSXxS8XMkoWcVcoecg";
    public const string FormUrl = "https://docs.google.com/forms/d/e/" + PublicFormId + "/viewform";

    public bool Enabled { get; set; } = true;
    public string TokenEntryId { get; set; } = "";
    public string WebhookSecret { get; set; } = "";

    public bool IsConfigured => WebhookSecret.Length >= 32
        && long.TryParse(TokenEntryId, out var entryId) && entryId > 0;
}
