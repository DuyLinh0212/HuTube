using System.Collections.Concurrent;
using System.Text.Json;
using HuTube.Application.Videos;

namespace HuTube.Api.Services;

public sealed record VideoUploadSessionRequest(Guid UploadId, Guid ChannelId, string FileName,
    string ContentType, long FileSize, int Duration, string SourceQuality);
public sealed record VideoUploadSessionResponse(Guid UploadId, int ChunkSize, int NextChunk, int ChunkProtocol = 2);

// Temporary chunks are actor/channel scoped; finalization still runs the normal
// permission, quota, media inspection and idempotency checks in ContentService.
public sealed class VideoChunkUploadStore : IDisposable
{
    public const int ChunkSize = 8 * 1024 * 1024;
    private static readonly TimeSpan Lifetime = TimeSpan.FromHours(2);
    private readonly string root;
    private readonly ConcurrentDictionary<Guid, Session> sessions = new();
    private readonly object startGate = new();
    private readonly Timer janitor;

    private sealed record SavedSession(Guid ActorId, VideoUploadSessionRequest Request, int NextChunk,
        Guid? CompletedVideoId, DateTimeOffset TouchedAt);

    public VideoChunkUploadStore(string? directory = null)
    {
        root = Path.GetFullPath(directory ?? Path.Combine(Path.GetTempPath(), "hutube-user-video-chunks"));
        Directory.CreateDirectory(root);
        foreach (var path in Directory.EnumerateFiles(root, "*.session.json"))
        {
            try
            {
                var saved = JsonSerializer.Deserialize<SavedSession>(File.ReadAllText(path));
                if (saved == null || !Guid.TryParse(Path.GetFileName(path).Split('.')[0], out var id)
                    || id != saved.Request.UploadId || saved.Request.FileSize <= 0
                    || saved.NextChunk < 0 || saved.NextChunk > (saved.Request.FileSize + ChunkSize - 1) / ChunkSize) continue;
                var source = Path.Combine(root, $"{id:N}.upload");
                if (saved.TouchedAt < DateTimeOffset.UtcNow - Lifetime)
                { Delete(source); Delete(path); continue; }
                var committedBytes = Math.Min(saved.Request.FileSize, (long)saved.NextChunk * ChunkSize);
                if (!saved.CompletedVideoId.HasValue && (!File.Exists(source) || new FileInfo(source).Length < committedBytes)) continue;
                sessions[id] = new(saved.ActorId, saved.Request, source) {
                    NextChunk = saved.NextChunk, CompletedVideoId = saved.CompletedVideoId, TouchedAt = saved.TouchedAt
                };
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { }
        }
        janitor = new Timer(_ => Cleanup(), null, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
    }

    public sealed class Session(Guid actorId, VideoUploadSessionRequest request, string filePath)
    {
        public Guid ActorId { get; } = actorId;
        public VideoUploadSessionRequest Request { get; } = request;
        public string FilePath { get; } = filePath;
        public int NextChunk { get; set; }
        public Guid? CompletedVideoId { get; set; }
        public bool IsCompleting { get; set; }
        public ContentException? CompletionError { get; set; }
        public CancellationTokenSource? CompletionCancellation { get; set; }
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
            var created = new Session(actorId, request, path);
            Persist(created);
            sessions[request.UploadId] = created;
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
            try { Persist(session); }
            catch { session.NextChunk--; throw; }
            return session.NextChunk;
        }
        finally { session.Gate.Release(); }
    }

    public async Task CancelAsync(Guid actorId, Guid uploadId, CancellationToken ct)
    {
        var session = Require(actorId, uploadId);
        await session.Gate.WaitAsync(ct);
        try
        {
            if (session.IsCompleting)
            {
                session.CompletionCancellation?.Cancel();
                return;
            }
            RemoveSession(session);
        }
        finally { session.Gate.Release(); }
    }

    public void RemoveSource(Session session) => Delete(session.FilePath);

    public void Persist(Session session)
    {
        var target = Path.Combine(root, $"{session.Request.UploadId:N}.session.json");
        var temporary = target + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(new SavedSession(session.ActorId, session.Request,
            session.NextChunk, session.CompletedVideoId, session.TouchedAt)));
        File.Move(temporary, target, overwrite: true);
    }

    internal void RemoveSession(Session session)
    {
        // Serialize deletion with Start so reusing an ID cannot delete a new source.
        lock (startGate)
        {
            if (!sessions.TryGetValue(session.Request.UploadId, out var current) || !ReferenceEquals(current, session)) return;
            sessions.TryRemove(session.Request.UploadId, out _);
            Delete(session.FilePath);
            Delete(Path.Combine(root, $"{session.Request.UploadId:N}.session.json"));
        }
    }

    private void Cleanup()
    {
        var cutoff = DateTimeOffset.UtcNow - Lifetime;
        foreach (var pair in sessions)
        {
            var session = pair.Value;
            if (session.TouchedAt >= cutoff || !session.Gate.Wait(0)) continue;
            try
            {
                if (!session.IsCompleting && session.TouchedAt < cutoff && sessions.TryRemove(pair.Key, out _))
                {
                    Delete(session.FilePath);
                    Delete(Path.Combine(root, $"{pair.Key:N}.session.json"));
                }
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
