namespace HuTube.Application.Storage;

public interface IObjectStorage
{
    Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default);
    Task DeleteFileAsync(string relativePath, CancellationToken ct = default);
}

public sealed class ObjectStorageException(string message, Exception? innerException = null)
    : Exception(message, innerException)
{
}

public sealed class StorageOptions
{
    public string Provider { get; set; } = "Cloudinary";
    public string CloudName { get; set; } = "";
    public string ApiKey { get; set; } = "";
    public string ApiSecret { get; set; } = "";
}
