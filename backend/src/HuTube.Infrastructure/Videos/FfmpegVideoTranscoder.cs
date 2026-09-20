using System.Diagnostics;
using HuTube.Application.Videos;
using HuTube.Domain.Videos;

namespace HuTube.Infrastructure.Videos;

public sealed class FfmpegVideoTranscoder(VideoProcessingOptions options) : IVideoTranscoder
{
    private static readonly IReadOnlyDictionary<int, int> Bitrates = new Dictionary<int, int>
    {
        [2160] = 12000, [1440] = 8000, [1080] = 5000, [720] = 2800, [480] = 1400, [360] = 800
    };

    public async Task<IReadOnlyList<TranscodedVideo>> CreateLowerRenditionsAsync(
        string sourceFilePath,
        string sourceQuality,
        string workingDirectory,
        CancellationToken ct = default)
    {
        if (!options.Enabled) return [];
        var results = new List<TranscodedVideo>();
        foreach (var quality in VideoRules.LowerQualities(sourceQuality))
        {
            var rendition = await CreateRenditionAsync(sourceFilePath, sourceQuality, quality, workingDirectory, ct);
            if (rendition != null) results.Add(rendition);
        }
        return results;
    }

    public async Task<TranscodedVideo?> CreateRenditionAsync(
        string sourceFilePath,
        string sourceQuality,
        string quality,
        string workingDirectory,
        CancellationToken ct = default)
    {
        if (!options.Enabled) return null;
        if (!VideoRules.LowerQualities(sourceQuality).Contains(quality, StringComparer.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Quality {quality} không thấp hơn source {sourceQuality}.");

        Directory.CreateDirectory(workingDirectory);
        var height = VideoRules.QualityHeight(quality);
        var width = height * 16 / 9;
        if (width % 2 != 0) width--;
        var bitrate = Bitrates[height];
        var output = Path.Combine(workingDirectory, $"{quality}.mp4");
        if (File.Exists(output) && new FileInfo(output).Length > 0)
        {
            // A previous worker may have completed this rendition before the
            // process was restarted. Reuse it instead of encoding the same
            // quality again.
            return new(quality, width, height, bitrate, output, new FileInfo(output).Length);
        }

        var start = new ProcessStartInfo
        {
            FileName = options.FfmpegPath,
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        };
        foreach (var argument in new[]
        {
            "-hide_banner", "-loglevel", "error", "-y", "-i", sourceFilePath,
            "-vf", $"scale=-2:{height}", "-c:v", "libx264", "-preset", "veryfast",
            "-b:v", $"{bitrate}k", "-maxrate", $"{bitrate}k", "-bufsize", $"{bitrate * 2}k",
            "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", output
        }) start.ArgumentList.Add(argument);

        using var process = Process.Start(start) ?? throw new InvalidOperationException("Không thể khởi động FFmpeg.");
        var stderr = process.StandardError.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);
        var error = await stderr;
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"FFmpeg không tạo được {quality}: {error.Trim()}");
        var info = new FileInfo(output);
        if (!info.Exists || info.Length == 0)
            throw new InvalidOperationException($"FFmpeg không tạo ra file {quality} hợp lệ.");
        return new(quality, width, height, bitrate, output, info.Length);
    }

    public async Task<string?> CreateThumbnailAsync(
        string sourceFilePath,
        string workingDirectory,
        CancellationToken ct = default)
    {
        if (!options.Enabled) return null;
        Directory.CreateDirectory(workingDirectory);
        var output = Path.Combine(workingDirectory, "thumbnail.jpg");
        var start = new ProcessStartInfo
        {
            FileName = options.FfmpegPath,
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        };
        foreach (var argument in new[]
        {
            "-hide_banner", "-loglevel", "error", "-y", "-ss", "00:00:01",
            "-i", sourceFilePath, "-frames:v", "1", "-vf", "scale='min(1280,iw)':-2",
            "-q:v", "3", "-f", "image2", output
        }) start.ArgumentList.Add(argument);

        using var process = Process.Start(start) ?? throw new InvalidOperationException("Không thể khởi động FFmpeg để tạo thumbnail.");
        var stderr = process.StandardError.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);
        var error = await stderr;
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"FFmpeg không tạo được thumbnail: {error.Trim()}");
        if (!File.Exists(output) || new FileInfo(output).Length == 0)
            throw new InvalidOperationException("FFmpeg không tạo ra file thumbnail hợp lệ.");
        return output;
    }
}
