using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Storage;

/// <summary>
/// Routes images to Cloudinary and videos to R2 while keeping the existing
/// storage abstraction used by the API and application services.
/// </summary>
public sealed class DualObjectStorageService(
    IObjectStorage imageStorage,
    IObjectStorage videoStorage) : IObjectStorage, IDisposable
{
    public Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) =>
        imageStorage.SaveFileAsync(folder, fileName, content, contentType, ct);

    public Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) =>
        videoStorage.SaveVideoAsync(folder, fileName, content, contentType, ct);

    public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default) =>
        IsR2Path(storedPath)
            ? videoStorage.GetReadUrlAsync(storedPath, lifetime, ct)
            : imageStorage.GetReadUrlAsync(storedPath, lifetime, ct);

    public Task DeleteFileAsync(string relativePath, CancellationToken ct = default) =>
        IsR2Path(relativePath)
            ? videoStorage.DeleteFileAsync(relativePath, ct)
            : imageStorage.DeleteFileAsync(relativePath, ct);

    public void Dispose()
    {
        if (imageStorage is IDisposable imageDisposable) imageDisposable.Dispose();
        if (!ReferenceEquals(imageStorage, videoStorage) && videoStorage is IDisposable videoDisposable) videoDisposable.Dispose();
    }

    private static bool IsR2Path(string path) => path.StartsWith("r2://", StringComparison.OrdinalIgnoreCase);
}
