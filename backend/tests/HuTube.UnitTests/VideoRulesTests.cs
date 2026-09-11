using HuTube.Domain.Videos;

namespace HuTube.UnitTests;

public sealed class VideoRulesTests
{
    [Theory]
    [InlineData("2160p", new[] { "1440p", "1080p", "720p", "480p", "360p" })]
    [InlineData("1080p", new[] { "720p", "480p", "360p" })]
    [InlineData("720p", new[] { "480p", "360p" })]
    [InlineData("360p", new string[0])]
    public void LowerQualities_ReturnsOnlyRenditionsBelowSource(string source, string[] expected)
    {
        Assert.Equal(expected, VideoRules.LowerQualities(source));
    }

    [Theory]
    [InlineData("public")]
    [InlineData("unlisted")]
    [InlineData("private")]
    public void ValidateVisibility_WithSupportedValue_DoesNotThrow(string value)
    {
        // Arrange / Act
        var exception = Record.Exception(() => VideoRules.ValidateVisibility(value));

        // Assert
        Assert.Null(exception);
    }

    [Fact]
    public void ValidateVisibility_WithUnsupportedValue_Throws()
    {
        // Arrange / Act / Assert
        Assert.Throws<VideoValidationException>(() => VideoRules.ValidateVisibility("members"));
    }

    [Theory]
    [InlineData("video/mp4")]
    [InlineData("video/webm")]
    [InlineData("video/quicktime")]
    public void ValidateUpload_WithSupportedContentType_DoesNotThrow(string contentType)
    {
        // Arrange / Act
        var exception = Record.Exception(() => VideoRules.ValidateUpload(contentType, 100, 200));

        // Assert
        Assert.Null(exception);
    }

    [Fact]
    public void ValidateUpload_WhenFileExceedsLimit_Throws()
    {
        // Arrange / Act / Assert
        var exception = Assert.Throws<VideoValidationException>(() =>
            VideoRules.ValidateUpload("video/mp4", 201, 200));
        Assert.Equal("FILE_TOO_LARGE", exception.Code);
    }

    [Fact]
    public void ValidateChapters_WithIncreasingTimeline_ReturnsNormalizedChapters()
    {
        // Arrange
        var chapters = new[] { new VideoChapter(0, "Mở đầu"), new VideoChapter(65, "Nội dung") };

        // Act
        var result = VideoRules.ValidateChapters(chapters, 120);

        // Assert
        Assert.Equal(2, result.Count);
        Assert.Equal("Nội dung", result[1].Title);
    }

    [Fact]
    public void ValidateChapters_WhenTimelineIsNotIncreasing_Throws()
    {
        // Arrange
        var chapters = new[] { new VideoChapter(10, "Một"), new VideoChapter(10, "Hai") };

        // Act / Assert
        Assert.Throws<VideoValidationException>(() => VideoRules.ValidateChapters(chapters, 120));
    }

    [Theory]
    [InlineData(30, 120, 25)]
    [InlineData(999, 120, 100)]
    public void CalculateProgress_ClampsAndCalculatesPercentage(int watched, int duration, decimal expected)
    {
        // Arrange / Act
        var result = VideoRules.CalculateProgress(watched, duration);

        // Assert
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("ok")]
    [InlineData("")]
    [InlineData("   ")]
    public void ValidateComment_WithInvalidContent_Throws(string content)
    {
        // Arrange / Act / Assert
        Assert.Throws<VideoValidationException>(() => VideoRules.ValidateComment(content));
    }

    [Fact]
    public void ValidateRating_WithScoreOutsideOneToFive_Throws()
    {
        // Arrange / Act / Assert
        Assert.Throws<VideoValidationException>(() => VideoRules.ValidateRating(6));
    }
}
