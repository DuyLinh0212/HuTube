namespace HuTube.Application.Taxonomy;

public sealed record AdminTopicResponse(
    Guid CategoryId,
    string Name,
    string Slug,
    string? Description,
    string Status,
    int VideoCount,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record AdminTagResponse(
    Guid TagId,
    string Name,
    int VideoCount,
    DateTimeOffset CreatedAt);

public sealed record CreateTopicRequest(
    string Name,
    string? Slug = null,
    string? Description = null,
    string Status = "active");

public sealed record UpdateTopicRequest(
    string Name,
    string? Slug,
    string? Description,
    string Status);

public sealed record CreateTagRequest(string Name);

public sealed record UpdateTagRequest(string Name);
