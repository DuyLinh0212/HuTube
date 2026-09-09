namespace HuTube.Application.Storage;

public interface IObjectStorage
{
    Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default);
    Task DeleteFileAsync(string relativePath, CancellationToken ct = default);
}
