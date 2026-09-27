using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Recommendations;

public interface IRecommendationSnapshotStore
{
    Task<byte[]?> ReadOptionalAsync(string key, CancellationToken ct);
    Task WriteAsync(string key, byte[] bytes, string contentType, CancellationToken ct);
}

/// <summary>Reads and writes exact private R2 keys for model snapshots.</summary>
public sealed class RecommendationSnapshotStore(R2Options options) : IRecommendationSnapshotStore, IDisposable
{
    private AmazonS3Client? _client;
    private AmazonS3Client Client => _client ??= CreateClient();

    private AmazonS3Client CreateClient()
    {
        if (string.IsNullOrWhiteSpace(options.AccountId) || string.IsNullOrWhiteSpace(options.AccessKeyId)
            || string.IsNullOrWhiteSpace(options.SecretAccessKey) || string.IsNullOrWhiteSpace(options.BucketName))
            throw new InvalidOperationException("Configure Storage__R2 account, keys and bucket for recommendations.");
        return new AmazonS3Client(new BasicAWSCredentials(options.AccessKeyId, options.SecretAccessKey),
            new AmazonS3Config {
                ServiceURL = $"https://{options.AccountId}.r2.cloudflarestorage.com",
                AuthenticationRegion = "auto", ForcePathStyle = true,
                RequestChecksumCalculation = RequestChecksumCalculation.WHEN_REQUIRED
            });
    }

    public async Task<byte[]?> ReadOptionalAsync(string key, CancellationToken ct)
    {
        try
        {
            using var response = await Client.GetObjectAsync(options.BucketName, key, ct);
            await using var stream = new MemoryStream();
            await response.ResponseStream.CopyToAsync(stream, ct);
            return stream.ToArray();
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound) { return null; }
    }

    public async Task WriteAsync(string key, byte[] bytes, string contentType, CancellationToken ct)
    {
        if (!key.StartsWith("collaborative_cf/", StringComparison.Ordinal) || key.Contains("..", StringComparison.Ordinal))
            throw new ArgumentException("Invalid model object key.", nameof(key));
        await using var stream = new MemoryStream(bytes, writable: false);
        await Client.PutObjectAsync(new PutObjectRequest {
            BucketName = options.BucketName, Key = key, InputStream = stream,
            ContentType = contentType, AutoCloseStream = false,
            DisablePayloadSigning = true, DisableDefaultChecksumValidation = true
        }, ct);
    }

    public void Dispose() => _client?.Dispose();
}
