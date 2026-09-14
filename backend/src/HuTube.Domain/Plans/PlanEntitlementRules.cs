using System.Text.Json;

namespace HuTube.Domain.Plans;

public static class PlanEntitlementRules
{
    public const string Download = "download";
    public const string BackgroundPlay = "background_play";
    public const string PictureInPicture = "pip";

    public static IReadOnlyDictionary<string, bool> ReadFlags(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                return new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

            var flags = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in document.RootElement.EnumerateObject())
                if (property.Value.ValueKind is JsonValueKind.True or JsonValueKind.False)
                    flags[property.Name.Trim().ToLowerInvariant()] = property.Value.GetBoolean();
            return flags;
        }
        catch (JsonException)
        {
            return new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        }
    }

    public static bool IsEnabled(string? json, string key) =>
        ReadFlags(json).TryGetValue(key, out var enabled) && enabled;
}
