using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using HuTube.Application.Storage;

namespace HuTube.Infrastructure.Recommendations;

public interface IRecommendationSnapshotStore
{
    Task<byte[]?> ReadOptionalAsync(string key, CancellationToken ct);
    Task WriteAsync(string key, byte[] bytes, string contentType, CancellationToken ct);
    Task DeleteCsvExceptAsync(string keepKey, CancellationToken ct);
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

    public async Task DeleteCsvExceptAsync(string keepKey, CancellationToken ct)
    {
        if (!keepKey.StartsWith("collaborative_cf/", StringComparison.Ordinal)
            || keepKey.Contains("..", StringComparison.Ordinal)
            || !keepKey.EndsWith(".csv", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Invalid model CSV key.", nameof(keepKey));

        var keys = new List<string>();
        string? continuation = null;
        do
        {
            var page = await Client.ListObjectsV2Async(new ListObjectsV2Request
            {
                BucketName = options.BucketName,
                Prefix = "collaborative_cf/",
                ContinuationToken = continuation,
            }, ct);
            keys.AddRange(page.S3Objects
                .Select(item => item.Key)
                .Where(key => key.EndsWith(".csv", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(key, keepKey, StringComparison.Ordinal)));
            continuation = page.IsTruncated == true ? page.NextContinuationToken : null;
        } while (continuation is not null);

        foreach (var batch in keys.Chunk(1000))
        {
            await Client.DeleteObjectsAsync(new DeleteObjectsRequest
            {
                BucketName = options.BucketName,
                Quiet = true,
                Objects = batch.Select(key => new KeyVersion { Key = key }).ToList(),
            }, ct);
        }
    }

    public void Dispose() => _client?.Dispose();
}
