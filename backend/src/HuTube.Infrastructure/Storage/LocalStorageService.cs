using HuTube.Application.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;

namespace HuTube.Infrastructure.Storage;

public sealed class LocalStorageService(IWebHostEnvironment environment, IHttpContextAccessor httpContextAccessor) : IObjectStorage
{
    private readonly string _uploadRoot = Path.Combine(environment.ContentRootPath, "uploads");

    public async Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default)
    {
        var targetDir = Path.Combine(_uploadRoot, folder);
        Directory.CreateDirectory(targetDir);

        var extension = Path.GetExtension(fileName);
        var uniqueFileName = $"{Guid.NewGuid():N}{extension}";
        var filePath = Path.Combine(targetDir, uniqueFileName);

        await using var outputStream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
        await content.CopyToAsync(outputStream, ct);

        var relativeUrl = $"/uploads/{folder}/{uniqueFileName}";
        var request = httpContextAccessor.HttpContext?.Request;
        return request == null ? relativeUrl : $"{request.Scheme}://{request.Host}{relativeUrl}";
    }

    public Task DeleteFileAsync(string relativePath, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return Task.CompletedTask;
        var clean = relativePath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
        var fullPath = Path.Combine(environment.ContentRootPath, clean);
        if (File.Exists(fullPath))
        {
            try { File.Delete(fullPath); }
            catch { /* ignore cleanup errors */ }
        }
        return Task.CompletedTask;
    }
}
