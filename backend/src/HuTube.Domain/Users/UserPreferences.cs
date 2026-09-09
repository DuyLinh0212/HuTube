namespace HuTube.Domain.Users;

public sealed class UserPreferences
{
    public string Language { get; set; } = "vi";
    public string Theme { get; set; } = "light";
    public bool KeepSubscriptionsPrivate { get; set; } = true;
    public bool KeepPlaylistsPrivate { get; set; } = true;
    public string? Bio { get; set; }
    public string? Location { get; set; } = "Việt Nam";
}
