using HuTube.Application.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;

namespace HuTube.Infrastructure.Storage;

public sealed class LocalStorageService(IWebHostEnvironment environment, IHttpContextAccessor httpContextAccessor) : IObjectStorage
{
    private readonly string _uploadRoot = Path.Combine(environment.ContentRootPath, "uploads");
    private readonly string _privateUploadRoot = Path.Combine(environment.ContentRootPath, ".private_uploads");

    public async Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default)
    {
        if (folder.Equals("appeal-evidence", StringComparison.OrdinalIgnoreCase))
        {
            Directory.CreateDirectory(_privateUploadRoot);
            var privateExtension = Path.GetExtension(fileName).ToLowerInvariant();
            var privateFileName = $"{Guid.NewGuid():N}{privateExtension}";
            var privatePath = Path.Combine(_privateUploadRoot, privateFileName);
            await using var privateStream = new FileStream(privatePath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            await content.CopyToAsync(privateStream, ct);
            return $"local-private://{privateFileName}";
        }
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

    public Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) =>
        SaveFileAsync(folder, fileName, content, contentType, ct);

    public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default) => Task.FromResult(storedPath);

    public Task<Stream> OpenReadAsync(string storedPath, CancellationToken ct = default)
    {
        const string prefix = "local-private://";
        if (!storedPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new FileNotFoundException("Không tìm thấy bằng chứng.");
        var fileName = Path.GetFileName(storedPath[prefix.Length..]);
        if (string.IsNullOrWhiteSpace(fileName)) throw new FileNotFoundException("Không tìm thấy bằng chứng.");
        Stream stream = new FileStream(Path.Combine(_privateUploadRoot, fileName), FileMode.Open, FileAccess.Read, FileShare.Read);
        return Task.FromResult(stream);
    }

    public Task DeleteFileAsync(string relativePath, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return Task.CompletedTask;
        const string privatePrefix = "local-private://";
        if (relativePath.StartsWith(privatePrefix, StringComparison.OrdinalIgnoreCase))
        {
            var privateName = Path.GetFileName(relativePath[privatePrefix.Length..]);
            var privatePath = Path.Combine(_privateUploadRoot, privateName);
            if (File.Exists(privatePath)) File.Delete(privatePath);
            return Task.CompletedTask;
        }
        var localPath = relativePath;
        if (Uri.TryCreate(relativePath, UriKind.Absolute, out var uri))
            localPath = Uri.UnescapeDataString(uri.AbsolutePath);

        const string uploadsPrefix = "/uploads/";
        if (localPath.StartsWith(uploadsPrefix, StringComparison.OrdinalIgnoreCase))
            localPath = localPath[1..];
        localPath = localPath.TrimStart('/', '\\').Replace('/', Path.DirectorySeparatorChar);
        var uploadSegment = "uploads" + Path.DirectorySeparatorChar;
        if (!localPath.StartsWith(uploadSegment, StringComparison.OrdinalIgnoreCase)) return Task.CompletedTask;

        var uploadRoot = Path.GetFullPath(_uploadRoot);
        var uploadRootPrefix = uploadRoot.EndsWith(Path.DirectorySeparatorChar) ? uploadRoot : uploadRoot + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(Path.Combine(Path.GetFullPath(environment.ContentRootPath), localPath));
        if (!fullPath.StartsWith(uploadRootPrefix, StringComparison.OrdinalIgnoreCase)) return Task.CompletedTask;
        if (File.Exists(fullPath))
        {
            try { File.Delete(fullPath); }
            catch { /* ignore cleanup errors */ }
        }
        return Task.CompletedTask;
    }
}
