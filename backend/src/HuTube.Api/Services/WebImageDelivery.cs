using System.Text.Json.Serialization.Metadata;

namespace HuTube.Api.Services;

// Delivery-only conversion: original uploads and stored URLs remain unchanged.
// All API clients receive the same optimized image URLs, including older records.
internal static class WebImageDelivery
{
    private static readonly HashSet<string> ImageProperties = new(StringComparer.OrdinalIgnoreCase)
    {
        "avatarUrl", "channelAvatarUrl", "authorAvatarUrl", "ownerAvatarUrl", "thumbnailUrl",
        "targetThumbnailUrl", "coverUrl", "bannerUrl", "watermarkUrl", "channelWatermarkUrl",
        "logoUrl", "iconUrl", "imageUrl", "posterUrl"
    };

    public static DefaultJsonTypeInfoResolver CreateResolver()
    {
        var resolver = new DefaultJsonTypeInfoResolver();
        resolver.Modifiers.Add(info =>
        {
            if (info.Kind != JsonTypeInfoKind.Object) return;
            foreach (var property in info.Properties)
            {
                if (property.PropertyType != typeof(string) || !ImageProperties.Contains(property.Name) || property.Get is not { } get) continue;
                property.Get = instance => get(instance) is string value ? Optimize(value) : null;
            }
        });
        return resolver;
    }

    internal static string Optimize(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https"
            || !uri.Host.Equals("res.cloudinary.com", StringComparison.OrdinalIgnoreCase)
            || uri.Query.Length != 0 || uri.Fragment.Length != 0 || uri.UserInfo.Length != 0) return value;
        const string marker = "/image/upload/";
        var path = uri.AbsolutePath;
        var index = path.IndexOf(marker, StringComparison.Ordinal);
        if (index <= 1) return value;
        var start = index + marker.Length;
        var tail = path[start..];
        if (tail.Length == 0 || tail.Split('/').Any(segment => segment.StartsWith("s--", StringComparison.Ordinal))) return value;
        // Preserve explicitly configured formats and transformations (and avoid duplicate variants).
        if (tail.Split(['/', ',']).Any(segment => segment.StartsWith("f_", StringComparison.Ordinal))) return value;
        var format = path.EndsWith(".gif", StringComparison.OrdinalIgnoreCase) ? "f_webp,fl_awebp,q_auto/" : "f_webp,q_auto/";
        return uri.GetLeftPart(UriPartial.Authority) + path.Insert(start, format);
    }
}
