using System.Text.Encodings.Web;
using System.Text.Json;

namespace HuTube.Application.Serialization;

/// <summary>
/// Serializes JSON persisted in PostgreSQL json/jsonb columns.
///
/// PostgreSQL databases configured with the C/SQL_ASCII encoding reject escaped
/// non-ASCII characters such as <c>\u1EDF</c>. Keeping Unicode characters in
/// the payload avoids that incompatibility while still escaping control
/// characters normally.
/// </summary>
public static class PersistenceJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);
}
