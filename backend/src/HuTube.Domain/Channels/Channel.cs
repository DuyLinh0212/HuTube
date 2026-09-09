using System.Text.RegularExpressions;

namespace HuTube.Domain.Channels;

public sealed class Channel
{
    private static readonly Regex HandlePattern = new(@"^[A-Za-z0-9_.-]{3,50}$", RegexOptions.Compiled);

    public Guid ChannelId { get; set; } = Guid.NewGuid();
    public Guid OwnerUserId { get; set; }
    public string Name { get; set; } = "";
    public string Handle { get; set; } = "";
    public string? Description { get; set; }
    public string? AvatarUrl { get; set; }
    public string? BannerUrl { get; set; }
    public string? ContactEmail { get; set; }
    public string? WatermarkUrl { get; set; }
    public string Settings { get; set; } = "{}";
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public bool IsActive => Status == "active";

    public static bool IsValidHandle(string? handle)
    {
        if (string.IsNullOrWhiteSpace(handle)) return false;
        var clean = handle.StartsWith('@') ? handle[1..] : handle;
        return HandlePattern.IsMatch(clean);
    }

    public static string NormalizeHandle(string handle)
    {
        var clean = handle.Trim();
        if (clean.StartsWith('@')) clean = clean[1..];
        return clean.ToLowerInvariant();
    }

    public void SoftDelete(DateTimeOffset now)
    {
        Status = "deleted";
        UpdatedAt = now;
    }
}
