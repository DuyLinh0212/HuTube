using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Storage;

public sealed class R2ObjectStorageService : IObjectStorage, IDisposable
{
    private readonly R2Options _options;
    private readonly AmazonS3Client _client;

    public R2ObjectStorageService(R2Options options)
    {
        _options = options;
        if (string.IsNullOrWhiteSpace(options.AccountId) || string.IsNullOrWhiteSpace(options.AccessKeyId)
            || string.IsNullOrWhiteSpace(options.SecretAccessKey) || string.IsNullOrWhiteSpace(options.BucketName))
            throw new InvalidOperationException("Storage__R2__AccountId, AccessKeyId, SecretAccessKey và BucketName là bắt buộc.");
        var config = new AmazonS3Config
        {
            ServiceURL = $"https://{options.AccountId}.r2.cloudflarestorage.com",
            AuthenticationRegion = "auto",
            ForcePathStyle = true
        };
        _client = new AmazonS3Client(new BasicAWSCredentials(options.AccessKeyId, options.SecretAccessKey), config);
    }

    public Task<string> SaveFileAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) =>
        UploadAsync(folder, fileName, content, contentType, ct);

    public Task<string> SaveVideoAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct = default) =>
        UploadAsync(folder, fileName, content, contentType, ct);

    private async Task<string> UploadAsync(string folder, string fileName, Stream content, string contentType, CancellationToken ct)
    {
        var extension = Path.GetExtension(fileName).ToLowerInvariant();
        var key = $"{folder.Trim().Trim('/', '\\').Replace('\\', '/')}/{DateTime.UtcNow:yyyy/MM}/{Guid.NewGuid():N}{extension}";
        try
        {
            await _client.PutObjectAsync(new PutObjectRequest
            {
                BucketName = _options.BucketName,
                Key = key,
                InputStream = content,
                ContentType = contentType,
                AutoCloseStream = false,
                DisablePayloadSigning = true,
                DisableDefaultChecksumValidation = true
            }, ct);
            return $"r2://{_options.BucketName}/{key}";
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception ex) { throw new ObjectStorageException("Không thể lưu tệp lên Cloudflare R2.", ex); }
    }

    public Task<string> GetReadUrlAsync(string storedPath, TimeSpan lifetime, CancellationToken ct = default)
    {
        if (!TryObjectKey(storedPath, out var key)) return Task.FromResult(storedPath);
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _options.BucketName,
            Key = key,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(lifetime)
        };
        return Task.FromResult(_client.GetPreSignedURL(request));
    }

    public async Task DeleteFileAsync(string relativePath, CancellationToken ct = default)
    {
        if (!TryObjectKey(relativePath, out var key)) return;
        try { await _client.DeleteObjectAsync(_options.BucketName, key, ct); }
        catch (Exception ex) { throw new ObjectStorageException("Không thể xóa tệp trên Cloudflare R2.", ex); }
    }

    private bool TryObjectKey(string value, out string key)
    {
        var prefix = $"r2://{_options.BucketName}/";
        key = value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? value[prefix.Length..] : "";
        return key.Length > 0;
    }

    public void Dispose() => _client.Dispose();
}
