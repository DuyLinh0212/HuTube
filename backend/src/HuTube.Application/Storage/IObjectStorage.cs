namespace HuTube.Application.Storage;

public interface IObjectStorage
{
    Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default);
    Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default);
    Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default);
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

public sealed class R2Options
{
    public string AccountId { get; set; } = "";
    public string AccessKeyId { get; set; } = "";
    public string SecretAccessKey { get; set; } = "";
    public string BucketName { get; set; } = "hutube";
    public int ReadUrlMinutes { get; set; } = 60;
}
