using HuTube.Application.Storage;
using HuTube.Infrastructure.Storage;

namespace HuTube.UnitTests;

public sealed class R2StorageTests
{
    [Fact]
    public void LoadDevelopmentFile_ReadsLastBucketScopedCredentialWithoutLoggingSecrets()
    {
        // Arrange
        var directory = Path.Combine(Path.GetTempPath(), "hutube-r2-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, "credentials.txt");
        File.WriteAllText(file, "Access ID key: account-key\nSecret Access Key: account-secret\nBucket Name: all\n\nAccess ID key: bucket-key\nSecret Access Key: bucket-secret\nBucket Name: hutube");
        var options = new R2Options();

        try
        {
            // Act
            R2OptionsLoader.LoadDevelopmentFile(options, directory, file);

            // Assert
            Assert.Equal("bucket-key", options.AccessKeyId);
            Assert.Equal("bucket-secret", options.SecretAccessKey);
            Assert.Equal("hutube", options.BucketName);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Fact]
    public async Task GetReadUrlAsync_ForPrivateR2Object_ReturnsTemporarySignedUrl()
    {
        // Arrange
        using var storage = new R2ObjectStorageService(new R2Options
        {
            AccountId = "0123456789abcdef0123456789abcdef",
            AccessKeyId = "test-access-key",
            SecretAccessKey = "test-secret-key",
            BucketName = "hutube"
        });

        // Act
        var url = await storage.GetReadUrlAsync("r2://hutube/videos/test.mp4", TimeSpan.FromMinutes(5));

        // Assert
        Assert.StartsWith("https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com", url);
        Assert.Contains("X-Amz-Signature=", url);
        Assert.DoesNotContain("test-secret-key", url);
    }
}
