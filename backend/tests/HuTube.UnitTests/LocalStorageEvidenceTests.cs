using HuTube.Application.Auth;
using HuTube.Infrastructure.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.FileProviders;

namespace HuTube.UnitTests;

public sealed class LocalStorageEvidenceTests
{
    [Fact]
    public async Task EvidenceDeletedAfterUpload_Returns404WithoutDisclosingStoragePath()
    {
        var directory = Path.Combine(Path.GetTempPath(), "hutube-qc-evidence-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var storage = new LocalStorageService(new TestEnvironment(directory), new HttpContextAccessor());
            var bytes = new byte[] { 137,80,78,71,13,10,26,10 };
            var key = await storage.SaveVideoAsync("appeal-evidence", "proof.png", new MemoryStream(bytes), "image/png");
            await using (var stream = await storage.OpenReadAsync(key))
            {
                using var copy = new MemoryStream();
                await stream.CopyToAsync(copy);
                Assert.Equal(bytes, copy.ToArray());
            }
            await storage.DeleteFileAsync(key);
            var error = await Assert.ThrowsAsync<AuthException>(() => storage.OpenReadAsync(key));
            Assert.Equal(404, error.Status);
            Assert.Equal("APPEAL_EVIDENCE_NOT_FOUND", error.Code);
            Assert.DoesNotContain(directory, error.Message);
        }
        finally { Directory.Delete(directory, true); }
    }

    private sealed class TestEnvironment(string directory) : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "HuTube.QC";
        public string EnvironmentName { get; set; } = "Testing";
        public string ContentRootPath { get; set; } = directory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = directory;
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    }
}
