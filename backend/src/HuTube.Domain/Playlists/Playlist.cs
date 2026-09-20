namespace HuTube.Domain.Playlists;

public sealed class Playlist
{
    public Guid PlaylistId { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public string? Description { get; set; }
    public string Visibility { get; set; } = "private";
    public string PlaylistType { get; set; } = "personal";
    public string Status { get; set; } = "active";
    public DateTimeOffset? DeletedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PlaylistVideo
{
    public Guid PlaylistVideoId { get; set; } = Guid.NewGuid();
    public Guid PlaylistId { get; set; }
    public Guid VideoId { get; set; }
    public int Position { get; set; }
    public DateTimeOffset AddedAt { get; set; } = DateTimeOffset.UtcNow;
}
