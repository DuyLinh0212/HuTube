using System.Collections.Concurrent;
using HuTube.Application.Videos;

namespace HuTube.Api.Services;

public sealed record VideoUploadSessionRequest(Guid UploadId, Guid ChannelId, string FileName,
    string ContentType, long FileSize, int Duration, string SourceQuality);
public sealed record VideoUploadSessionResponse(Guid UploadId, int ChunkSize, int NextChunk);

// Temporary chunks are actor/channel scoped; finalization still runs the normal
// permission, quota, media inspection and idempotency checks in ContentService.
public sealed class VideoChunkUploadStore : IDisposable
{
    public const int ChunkSize = 8 * 1024 * 1024;
    private static readonly TimeSpan Lifetime = TimeSpan.FromHours(2);
    private readonly string root = Path.Combine(Path.GetTempPath(), "hutube-user-video-chunks");
    private readonly ConcurrentDictionary<Guid, Session> sessions = new();
    private readonly object startGate = new();
    private readonly Timer janitor;

    public VideoChunkUploadStore()
    {
        Directory.CreateDirectory(root);
        janitor = new Timer(_ => Cleanup(), null, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
    }

    public sealed class Session(Guid actorId, VideoUploadSessionRequest request, string filePath)
    {
        public Guid ActorId { get; } = actorId;
        public VideoUploadSessionRequest Request { get; } = request;
        public string FilePath { get; } = filePath;
        public int NextChunk { get; set; }
        public Guid? CompletedVideoId { get; set; }
        public DateTimeOffset TouchedAt { get; set; } = DateTimeOffset.UtcNow;
        public SemaphoreSlim Gate { get; } = new(1, 1);
    }

    public VideoUploadSessionResponse Start(Guid actorId, VideoUploadSessionRequest request)
    {
        if (request.UploadId == Guid.Empty || request.FileSize <= 0 || request.FileSize > 256L * 1024 * 1024 * 1024)
            throw Error(400, "UPLOAD_INVALID_SESSION", "Thông tin phiên tải video không hợp lệ.");
        if (string.IsNullOrWhiteSpace(request.FileName) || request.FileName.Length > 255)
            throw Error(400, "UPLOAD_INVALID_FILE", "Tên file video không hợp lệ.");
        request = request with { FileName = Path.GetFileName(request.FileName) };
        lock (startGate)
        {
            Cleanup();
            if (sessions.TryGetValue(request.UploadId, out var existing))
            {
                if (existing.ActorId != actorId || existing.Request != request)
                    throw Error(409, "UPLOAD_SESSION_CONFLICT", "Phiên tải lên đã được dùng cho file khác.");
                existing.TouchedAt = DateTimeOffset.UtcNow;
                return new(request.UploadId, ChunkSize, existing.NextChunk);
            }
            if (sessions.Values.Count(s => s.ActorId == actorId && s.CompletedVideoId == null) >= 2)
                throw Error(409, "UPLOAD_SESSION_LIMIT", "Hãy hoàn tất hoặc hủy phiên tải video trước.");
            var reserved = sessions.Values.Where(s => s.CompletedVideoId == null).Sum(s => s.Request.FileSize);
            var free = new DriveInfo(Path.GetPathRoot(root)!).AvailableFreeSpace;
            // Finalization copies the source into the existing media workspace.
            if (2 * (reserved + request.FileSize) > free - 256L * 1024 * 1024)
                throw Error(507, "UPLOAD_TEMP_STORAGE_FULL", "Máy chủ không còn đủ dung lượng tạm. Vui lòng thử lại sau.");
            var path = Path.Combine(root, $"{request.UploadId:N}.upload");
            using (File.Create(path)) { }
            sessions[request.UploadId] = new(actorId, request, path);
            return new(request.UploadId, ChunkSize, 0);
        }
    }

    public Session Require(Guid actorId, Guid uploadId)
    {
        if (!sessions.TryGetValue(uploadId, out var session) || session.ActorId != actorId)
            throw Error(404, "UPLOAD_SESSION_NOT_FOUND", "Phiên tải video đã hết hạn hoặc máy chủ vừa khởi động lại. Hãy tải lại video.");
        return session;
    }

    public VideoUploadSessionResponse? TryResume(Guid actorId, VideoUploadSessionRequest request)
    {
        lock (startGate)
        {
            if (!sessions.TryGetValue(request.UploadId, out var session)) return null;
            if (session.ActorId != actorId || session.Request != (request with { FileName = Path.GetFileName(request.FileName) }))
                throw Error(409, "UPLOAD_SESSION_CONFLICT", "Phiên tải lên đã được dùng cho file khác.");
            session.TouchedAt = DateTimeOffset.UtcNow;
            return new(request.UploadId, ChunkSize, session.NextChunk);
        }
    }

    public async Task<int> AppendAsync(Guid actorId, Guid uploadId, int index, IFormFile chunk, CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            if (session.CompletedVideoId.HasValue) return session.NextChunk;
            var total = (int)((session.Request.FileSize + ChunkSize - 1) / ChunkSize);
            if (index < 0 || index >= total) throw Error(400, "UPLOAD_CHUNK_INDEX", "Phần video không hợp lệ.");
            if (index < session.NextChunk) return session.NextChunk;
            if (index != session.NextChunk) throw Error(409, "UPLOAD_CHUNK_ORDER", "Thứ tự phần video không đúng.");
            var expected = Math.Min(ChunkSize, session.Request.FileSize - (long)index * ChunkSize);
            if (chunk.Length != expected) throw Error(400, "UPLOAD_CHUNK_SIZE", "Dung lượng phần video không đúng.");
            await using var output = new FileStream(session.FilePath, FileMode.Open, FileAccess.Write,
                FileShare.None, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            output.SetLength((long)index * ChunkSize);
            output.Position = output.Length;
            await using var input = chunk.OpenReadStream();
            await input.CopyToAsync(output, ct);
            await output.FlushAsync(ct);
            session.NextChunk++;
            session.TouchedAt = DateTimeOffset.UtcNow;
            return session.NextChunk;
        }
        finally { session.Gate.Release(); }
    }

    public async Task CancelAsync(Guid actorId, Guid uploadId, CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try { sessions.TryRemove(uploadId, out _); Delete(session.FilePath); }
        finally { session.Gate.Release(); }
    }

    public void RemoveSource(Session session) => Delete(session.FilePath);

    private void Cleanup()
    {
        var cutoff = DateTimeOffset.UtcNow - Lifetime;
        foreach (var pair in sessions)
        {
            var session = pair.Value;
            if (session.TouchedAt >= cutoff || !session.Gate.Wait(0)) continue;
            try
            {
                if (session.TouchedAt < cutoff && sessions.TryRemove(pair.Key, out _)) Delete(session.FilePath);
            }
            finally { session.Gate.Release(); }
        }
        // Render can restart between chunks; remove abandoned source files later.
        try
        {
            foreach (var path in Directory.EnumerateFiles(root, "*.upload"))
                if (Guid.TryParse(Path.GetFileNameWithoutExtension(path), out var id)
                    && !sessions.ContainsKey(id) && File.GetLastWriteTimeUtc(path) < cutoff.UtcDateTime) Delete(path);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void Delete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static ContentException Error(int status, string code, string message) => new(status, code, message);
    public void Dispose() => janitor.Dispose();
}
