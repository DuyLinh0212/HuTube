using CloudinaryDotNet;
using CloudinaryDotNet.Actions;
using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Storage;

public sealed class CloudinaryStorageService : IObjectStorage
{
    private readonly Cloudinary _cloudinary;

    public CloudinaryStorageService(StorageOptions options)
    {
        if (string.IsNullOrWhiteSpace(options.CloudName)
            || string.IsNullOrWhiteSpace(options.ApiKey)
            || string.IsNullOrWhiteSpace(options.ApiSecret))
            throw new InvalidOperationException("Storage__CloudName, Storage__ApiKey and Storage__ApiSecret are required for Cloudinary.");

        _cloudinary = new Cloudinary(new CloudinaryDotNet.Account(options.CloudName, options.ApiKey, options.ApiSecret))
        {
            Api = { Secure = true }
        };
    }

    public async Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default)
    {
        var normalizedFolder = "hutube/" + folder.Trim().Trim('/').Replace('\\', '/');
        var parameters = new ImageUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = normalizedFolder,
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };

        ImageUploadResult result;
        try
        {
            result = await _cloudinary.UploadAsync(parameters, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new ObjectStorageException("Dịch vụ lưu trữ ảnh tạm thời không khả dụng.", ex);
        }
        if (result.Error != null || result.SecureUrl == null)
            throw new ObjectStorageException("Dịch vụ lưu trữ ảnh từ chối yêu cầu tải lên.");

        return result.SecureUrl.AbsoluteUri;
    }

    public async Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default)
    {
        var parameters = new VideoUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = "hutube/" + folder.Trim().Trim('/').Replace('\\', '/'),
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };
        try
        {
            var result = await _cloudinary.UploadAsync(parameters, ct);
            if (result.Error != null || result.SecureUrl == null)
                throw new ObjectStorageException("Dịch vụ lưu trữ video từ chối yêu cầu tải lên.");
            return result.SecureUrl.AbsoluteUri;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (ObjectStorageException) { throw; }
        catch (Exception ex) { throw new ObjectStorageException("Dịch vụ lưu trữ video tạm thời không khả dụng.", ex); }
    }

    public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default) => Task.FromResult(storedPath);

    public Task DeleteFileAsync(string relativePath, CancellationToken ct = default)
    {
        // Stored records currently contain delivery URLs only. Asset deletion will be wired to
        // persisted public IDs when the Sprint 9 data-lifecycle workflow is implemented.
        return Task.CompletedTask;
    }
}
