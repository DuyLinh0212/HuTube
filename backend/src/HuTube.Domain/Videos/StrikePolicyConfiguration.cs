namespace HuTube.Domain.Videos;

public sealed class StrikePolicyConfiguration
{
    public const int SingletonId = 1;

    public int Id { get; set; } = SingletonId;
    public int RejectedVideosPerStrike { get; set; } = 5;
    public int FirstStrikeRestrictionDays { get; set; } = 7;
    public int SecondStrikeRestrictionDays { get; set; } = 14;
    public int StrikeExpirationDays { get; set; } = 90;
    public int SuspensionStrikeCount { get; set; } = 3;
    public DateTimeOffset RejectedVideosEffectiveAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
