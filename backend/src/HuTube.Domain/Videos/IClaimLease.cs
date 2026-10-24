namespace HuTube.Domain.Videos;

public interface IClaimLease
{
    Guid? ReviewerId { get; set; }
    string Status { get; set; }
    DateTimeOffset? ClaimedAt { get; set; }
    Guid? ClaimId { get; set; }
    DateTimeOffset? ClaimExpiresAt { get; set; }
}
