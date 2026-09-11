using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Storage;

public static class R2OptionsLoader
{
    public static void LoadDevelopmentFile(R2Options options, string contentRoot, string? configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(options.AccessKeyId) && !string.IsNullOrWhiteSpace(options.SecretAccessKey)) return;
        var path = ResolvePath(contentRoot, configuredPath);
        if (path == null) return;
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in File.ReadLines(path))
        {
            var separator = raw.IndexOf(':');
            if (separator < 0) separator = raw.IndexOf('=');
            if (separator <= 0) continue;
            values[raw[..separator].Trim()] = raw[(separator + 1)..].Trim();
        }
        if (values.TryGetValue("Access ID key", out var access)) options.AccessKeyId = access;
        if (values.TryGetValue("Secret Access Key", out var secret)) options.SecretAccessKey = secret;
        if (values.TryGetValue("Bucket Name", out var bucket) && !string.IsNullOrWhiteSpace(bucket)) options.BucketName = bucket;
    }

    private static string? ResolvePath(string contentRoot, string? configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            var explicitPath = Path.IsPathRooted(configuredPath) ? configuredPath : Path.GetFullPath(configuredPath, contentRoot);
            return File.Exists(explicitPath) ? explicitPath : null;
        }
        var directory = new DirectoryInfo(contentRoot);
        for (var i = 0; i < 6 && directory != null; i++, directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "keyCloudflare.txt");
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}
