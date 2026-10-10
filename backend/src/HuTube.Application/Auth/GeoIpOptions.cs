namespace HuTube.Application.Auth;

public sealed class GeoIpOptions
{
    public bool Enabled { get; set; } = true;
    public string Endpoint { get; set; } = "https://ipapi.co";
    public int TimeoutMilliseconds { get; set; } = 800;
}
