namespace HuTube.Application.Videos;

public sealed record TranscodedVideo(string Quality, int Width, int Height, int BitrateKbps, string FilePath, long FileSize);

public interface IVideoTranscoder
{
    Task<IReadOnlyList<TranscodedVideo>> CreateLowerRenditionsAsync(
        string sourceFilePath,
        string sourceQuality,
        string workingDirectory,
        CancellationToken ct = default);

    async Task<TranscodedVideo?> CreateRenditionAsync(
        string sourceFilePath,
        string sourceQuality,
        string quality,
        string workingDirectory,
        CancellationToken ct = default)
    {
        var renditions = await CreateLowerRenditionsAsync(sourceFilePath, sourceQuality, workingDirectory, ct);
        return renditions.FirstOrDefault(x => string.Equals(x.Quality, quality, StringComparison.OrdinalIgnoreCase));
    }

    // Implementations may generate a JPEG preview from the source video. The
    // default keeps lightweight test transcoders and disabled processing modes
    // compatible; uploads can still proceed without an optional thumbnail.
    Task<string?> CreateThumbnailAsync(
        string sourceFilePath,
        string workingDirectory,
        CancellationToken ct = default) => Task.FromResult<string?>(null);
}

public sealed class VideoProcessingOptions
{
    public bool Enabled { get; set; } = true;
    public string FfmpegPath { get; set; } = "ffmpeg";
}

public sealed class FeatureOptions
{
    public bool ModerationEnabled { get; set; }
    public bool PlanEnforcementEnabled { get; set; }
}
