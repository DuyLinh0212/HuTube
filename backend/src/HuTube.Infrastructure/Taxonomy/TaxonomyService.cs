using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using HuTube.Application.Auth;
using HuTube.Application.Rbac;
using HuTube.Application.Serialization;
using HuTube.Application.Taxonomy;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Taxonomy;

public sealed class TaxonomyService(
    HuTubeDbContext db,
    RbacService audit,
    TimeProvider clock)
{
    private DateTimeOffset Now => clock.GetUtcNow();

    public async Task<List<AdminTopicResponse>> GetTopicsAsync(
        string? status = null,
        CancellationToken ct = default)
    {
        var query = db.Categories.AsNoTracking();
        var normalizedStatus = NormalizeStatusFilter(status);
        if (normalizedStatus != null)
            query = query.Where(topic => topic.Status == normalizedStatus);

        return await query
            .OrderBy(topic => topic.Name)
            .Select(topic => new AdminTopicResponse(
                topic.CategoryId,
                topic.Name,
                topic.Slug,
                topic.Description,
                topic.Status,
                db.Videos.Count(video => video.CategoryId == topic.CategoryId),
                topic.CreatedAt,
                topic.UpdatedAt))
            .ToListAsync(ct);
    }

    public async Task<AdminTopicResponse> CreateTopicAsync(
        Guid actorId,
        CreateTopicRequest request,
        CancellationToken ct = default)
    {
        var name = NormalizeTopicName(request.Name);
        var slug = NormalizeSlug(request.Slug, name);
        var status = NormalizeStatus(request.Status);
        var description = NormalizeDescription(request.Description);

        if (await db.Categories.AnyAsync(topic => topic.Slug == slug, ct))
            throw new AuthException(409, "TOPIC_SLUG_EXISTS", "Slug chủ đề đã tồn tại.");

        var now = Now;
        var topic = new Category
        {
            CategoryId = Guid.NewGuid(),
            Name = name,
            Slug = slug,
            Description = description,
            Status = status,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Categories.Add(topic);
        await db.SaveChangesAsync(ct);
        var result = ToTopicResponse(topic, 0);
        await WriteAuditAsync(actorId, "taxonomy.topic_created", topic.CategoryId, result, ct);
        return result;
    }

    public async Task<AdminTopicResponse> UpdateTopicAsync(
        Guid actorId,
        Guid categoryId,
        UpdateTopicRequest request,
        CancellationToken ct = default)
    {
        var topic = await db.Categories.SingleOrDefaultAsync(item => item.CategoryId == categoryId, ct)
            ?? throw new AuthException(404, "TOPIC_NOT_FOUND", "Không tìm thấy chủ đề.");

        var name = NormalizeTopicName(request.Name);
        var slug = NormalizeSlug(request.Slug, name);
        var status = NormalizeStatus(request.Status);
        var description = NormalizeDescription(request.Description);
        if (await db.Categories.AnyAsync(item => item.CategoryId != categoryId && item.Slug == slug, ct))
            throw new AuthException(409, "TOPIC_SLUG_EXISTS", "Slug chủ đề đã tồn tại.");

        var old = ToTopicResponse(topic, await CountVideosAsync(categoryId, ct));
        topic.Name = name;
        topic.Slug = slug;
        topic.Description = description;
        topic.Status = status;
        topic.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);

        var result = ToTopicResponse(topic, old.VideoCount);
        await WriteAuditAsync(actorId, "taxonomy.topic_updated", topic.CategoryId,
            new { old, newValue = result }, ct);
        return result;
    }

    public async Task ArchiveTopicAsync(Guid actorId, Guid categoryId, CancellationToken ct = default)
    {
        var topic = await db.Categories.SingleOrDefaultAsync(item => item.CategoryId == categoryId, ct)
            ?? throw new AuthException(404, "TOPIC_NOT_FOUND", "Không tìm thấy chủ đề.");

        if (topic.Status == "inactive") return;

        topic.Status = "inactive";
        topic.UpdatedAt = Now;
        await db.SaveChangesAsync(ct);
        await WriteAuditAsync(actorId, "taxonomy.topic_archived", topic.CategoryId,
            new { topic.Name, topic.Slug, topic.Status }, ct);
    }

    public async Task<List<AdminTagResponse>> GetTagsAsync(
        string? search = null,
        CancellationToken ct = default)
    {
        var query = db.Tags.AsNoTracking();
        var normalizedSearch = search?.Trim().ToLowerInvariant();
        if (!string.IsNullOrWhiteSpace(normalizedSearch))
            query = query.Where(tag => tag.Name.ToLower().Contains(normalizedSearch));

        return await query
            .OrderBy(tag => tag.Name)
            .Select(tag => new AdminTagResponse(
                tag.TagId,
                tag.Name,
                db.VideoTags.Count(videoTag => videoTag.TagId == tag.TagId),
                tag.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<AdminTagResponse> CreateTagAsync(
        Guid actorId,
        CreateTagRequest request,
        CancellationToken ct = default)
    {
        var name = NormalizeTagName(request.Name);
        if (await db.Tags.AnyAsync(tag => tag.Name.ToLower() == name, ct))
            throw new AuthException(409, "TAG_EXISTS", "Tag đã tồn tại.");

        var tag = new Tag { TagId = Guid.NewGuid(), Name = name, CreatedAt = Now };
        db.Tags.Add(tag);
        await db.SaveChangesAsync(ct);
        var result = new AdminTagResponse(tag.TagId, tag.Name, 0, tag.CreatedAt);
        await WriteAuditAsync(actorId, "taxonomy.tag_created", tag.TagId, result, ct);
        return result;
    }

    public async Task<AdminTagResponse> UpdateTagAsync(
        Guid actorId,
        Guid tagId,
        UpdateTagRequest request,
        CancellationToken ct = default)
    {
        var tag = await db.Tags.SingleOrDefaultAsync(item => item.TagId == tagId, ct)
            ?? throw new AuthException(404, "TAG_NOT_FOUND", "Không tìm thấy tag.");

        var name = NormalizeTagName(request.Name);
        if (await db.Tags.AnyAsync(item => item.TagId != tagId && item.Name.ToLower() == name, ct))
            throw new AuthException(409, "TAG_EXISTS", "Tag đã tồn tại.");

        var old = new AdminTagResponse(tag.TagId, tag.Name, await CountTagUsageAsync(tagId, ct), tag.CreatedAt);
        tag.Name = name;
        await db.SaveChangesAsync(ct);
        var result = new AdminTagResponse(tag.TagId, tag.Name, old.VideoCount, tag.CreatedAt);
        await WriteAuditAsync(actorId, "taxonomy.tag_updated", tag.TagId,
            new { old, newValue = result }, ct);
        return result;
    }

    public async Task DeleteTagAsync(Guid actorId, Guid tagId, CancellationToken ct = default)
    {
        var tag = await db.Tags.SingleOrDefaultAsync(item => item.TagId == tagId, ct)
            ?? throw new AuthException(404, "TAG_NOT_FOUND", "Không tìm thấy tag.");
        var usage = await CountTagUsageAsync(tagId, ct);
        if (usage > 0)
            throw new AuthException(409, "TAG_IN_USE", "Không thể xóa tag đang được dùng bởi video.");

        db.Tags.Remove(tag);
        await db.SaveChangesAsync(ct);
        await WriteAuditAsync(actorId, "taxonomy.tag_deleted", tag.TagId,
            new { tag.Name }, ct);
    }

    private async Task<int> CountVideosAsync(Guid categoryId, CancellationToken ct) =>
        await db.Videos.CountAsync(video => video.CategoryId == categoryId, ct);

    private async Task<int> CountTagUsageAsync(Guid tagId, CancellationToken ct) =>
        await db.VideoTags.CountAsync(videoTag => videoTag.TagId == tagId, ct);

    private async Task WriteAuditAsync(Guid actorId, string action, Guid resourceId, object values, CancellationToken ct) =>
        await audit.LogAuditAsync(new AuditLogEntry(
            actorId,
            action,
            "taxonomy",
            resourceId,
            "Admin quản lý chủ đề và tag",
            NewValues: PersistenceJson.Serialize(values)), ct);

    private static AdminTopicResponse ToTopicResponse(Category topic, int videoCount) => new(
        topic.CategoryId,
        topic.Name,
        topic.Slug,
        topic.Description,
        topic.Status,
        videoCount,
        topic.CreatedAt,
        topic.UpdatedAt);

    private static string NormalizeTopicName(string? value)
    {
        var name = value?.Trim() ?? "";
        if (name.Length is < 1 or > 100)
            throw new AuthException(400, "INVALID_TOPIC_NAME", "Tên chủ đề phải có từ 1 đến 100 ký tự.");
        return name;
    }

    private static string NormalizeTagName(string? value)
    {
        var name = value?.Trim().TrimStart('#').Trim().ToLowerInvariant() ?? "";
        if (name.Length is < 1 or > 80)
            throw new AuthException(400, "INVALID_TAG_NAME", "Tên tag phải có từ 1 đến 80 ký tự.");
        return name;
    }

    private static string? NormalizeDescription(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var description = value.Trim();
        if (description.Length > 1000)
            throw new AuthException(400, "INVALID_TOPIC_DESCRIPTION", "Mô tả chủ đề tối đa 1.000 ký tự.");
        return description;
    }

    private static string NormalizeSlug(string? value, string fallbackName)
    {
        var slug = Slugify(string.IsNullOrWhiteSpace(value) ? fallbackName : value);
        if (slug.Length is < 1 or > 120)
            throw new AuthException(400, "INVALID_TOPIC_SLUG", "Slug chủ đề chỉ gồm chữ thường, số và dấu gạch ngang.");
        return slug;
    }

    private static string? NormalizeStatusFilter(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Trim().Equals("all", StringComparison.OrdinalIgnoreCase))
            return null;
        return NormalizeStatus(value);
    }

    private static string NormalizeStatus(string? value)
    {
        var status = string.IsNullOrWhiteSpace(value) ? "active" : value.Trim().ToLowerInvariant();
        if (status is not ("active" or "inactive"))
            throw new AuthException(400, "INVALID_TOPIC_STATUS", "Trạng thái chủ đề chỉ có active hoặc inactive.");
        return status;
    }

    private static string Slugify(string value)
    {
        var normalized = value.Trim().Replace('đ', 'd').Replace('Đ', 'D').Normalize(NormalizationForm.FormD);
        var withoutMarks = new string(normalized
            .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            .ToArray());
        var ascii = withoutMarks.Normalize(NormalizationForm.FormC).ToLowerInvariant();
        return Regex.Replace(ascii, "[^a-z0-9]+", "-").Trim('-');
    }
}
