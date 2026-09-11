namespace HuTube.Application.Videos;

public sealed record TranscodedVideo(string Quality, int Width, int Height, int BitrateKbps, string FilePath, long FileSize);

public interface IVideoTranscoder
{
    Task<IReadOnlyList<TranscodedVideo>> CreateLowerRenditionsAsync(
        string sourceFilePath,
        string sourceQuality,
        string workingDirectory,
        CancellationToken ct = default);
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
