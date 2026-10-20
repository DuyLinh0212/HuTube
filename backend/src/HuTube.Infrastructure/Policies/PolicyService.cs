using HuTube.Application.Auth;
using HuTube.Application.Policies;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HuTube.Infrastructure.Policies;

public sealed class PolicyService(HuTubeDbContext db)
{
    public async Task<List<PolicyDto>> GetPublicPoliciesAsync(string? group = null, CancellationToken ct = default)
    {
        var query = db.Policies
            .AsNoTracking()
            .Where(p => p.Status == "published" && p.EffectiveAt <= DateTimeOffset.UtcNow
                && !db.Policies.Any(newer => newer.Code == p.Code && newer.Status == "published"
                    && newer.EffectiveAt <= DateTimeOffset.UtcNow && newer.EffectiveAt > p.EffectiveAt));

        if (!string.IsNullOrWhiteSpace(group))
        {
            var g = group.Trim().ToLowerInvariant();
            query = query.Where(p => p.Group == g);
        }

        return await query
            .OrderBy(p => p.Group)
            .ThenBy(p => p.Code)
            .Select(p => new PolicyDto(
                p.PolicyId,
                p.Code,
                p.Name,
                p.Group,
                p.Content,
                p.Severity,
                p.Version,
                p.Status,
                p.EffectiveAt
            ))
            .ToListAsync(ct);
    }

    public async Task<List<PolicyDto>> GetAdminPoliciesAsync(string? group = null, string? status = null, CancellationToken ct = default)
    {
        var query = db.Policies.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(group))
        {
            var g = group.Trim().ToLowerInvariant();
            query = query.Where(p => p.Group == g);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim().ToLowerInvariant();
            query = query.Where(p => p.Status == s);
        }

        return await query
            .OrderBy(p => p.Group)
            .ThenBy(p => p.Code)
            .Select(p => new PolicyDto(
                p.PolicyId,
                p.Code,
                p.Name,
                p.Group,
                p.Content,
                p.Severity,
                p.Version,
                p.Status,
                p.EffectiveAt
            ))
            .ToListAsync(ct);
    }

    public async Task<PolicyDto> CreatePolicyAsync(Guid actorId, CreatePolicyRequest request, CancellationToken ct = default)
    {
        var code = request.Code.Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Content))
            throw new AuthException(400, "VALIDATION_ERROR", "Mã, tên và nội dung chính sách không được để trống.");

        var existing = await db.Policies.FirstOrDefaultAsync(p => p.Code == code, ct);
        if (existing != null)
            throw new AuthException(409, "POLICY_CODE_EXISTS", $"Chính sách với mã {code} đã tồn tại.");

        var now = DateTimeOffset.UtcNow;
        var policy = new Policy
        {
            Code = code,
            Name = request.Name.Trim(),
            Group = string.IsNullOrWhiteSpace(request.Group) ? "content" : request.Group.Trim().ToLowerInvariant(),
            Content = request.Content.Trim(),
            Severity = string.IsNullOrWhiteSpace(request.Severity) ? "medium" : request.Severity.Trim().ToLowerInvariant(),
            Version = string.IsNullOrWhiteSpace(request.Version) ? "1.0" : request.Version.Trim(),
            Status = string.IsNullOrWhiteSpace(request.Status) ? "published" : request.Status.Trim().ToLowerInvariant(),
            EffectiveAt = now,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Policies.Add(policy);
        await db.SaveChangesAsync(ct);

        return new PolicyDto(
            policy.PolicyId,
            policy.Code,
            policy.Name,
            policy.Group,
            policy.Content,
            policy.Severity,
            policy.Version,
            policy.Status,
            policy.EffectiveAt
        );
    }

    public async Task<PolicyDto> PublishPolicyVersionAsync(Guid actorId, Guid policyId, UpdatePolicyRequest? request = null, CancellationToken ct = default)
    {
        var policy = await db.Policies.FirstOrDefaultAsync(p => p.PolicyId == policyId, ct)
            ?? throw new AuthException(404, "POLICY_NOT_FOUND", "Không tìm thấy chính sách.");

        // Published records are referenced by moderation evidence. Keep their
        // identity and content intact when publishing the next version.
        if (policy.Status == "published")
        {
            var version = request?.Version?.Trim();
            if (string.IsNullOrWhiteSpace(version) || version == policy.Version)
                throw new AuthException(409, "POLICY_VERSION_REQUIRED", "Phiên bản đã công bố không thể sửa. Hãy chọn phiên bản mới.");
            if (await db.Policies.AnyAsync(p => p.Code == policy.Code && p.Version == version, ct))
                throw new AuthException(409, "POLICY_VERSION_EXISTS", "Phiên bản chính sách đã tồn tại.");
            policy = new Policy
            {
                Code = policy.Code, Name = policy.Name, Group = policy.Group,
                Content = policy.Content, Severity = policy.Severity,
                Version = version, CreatedAt = DateTimeOffset.UtcNow
            };
            db.Policies.Add(policy);
        }

        if (request != null)
        {
            if (!string.IsNullOrWhiteSpace(request.Name)) policy.Name = request.Name.Trim();
            if (!string.IsNullOrWhiteSpace(request.Content)) policy.Content = request.Content.Trim();
            if (!string.IsNullOrWhiteSpace(request.Severity)) policy.Severity = request.Severity.Trim().ToLowerInvariant();
            if (!string.IsNullOrWhiteSpace(request.Version)) policy.Version = request.Version.Trim();
        }

        policy.Status = "published";
        policy.EffectiveAt = DateTimeOffset.UtcNow;
        policy.UpdatedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        return new PolicyDto(
            policy.PolicyId,
            policy.Code,
            policy.Name,
            policy.Group,
            policy.Content,
            policy.Severity,
            policy.Version,
            policy.Status,
            policy.EffectiveAt
        );
    }
}
