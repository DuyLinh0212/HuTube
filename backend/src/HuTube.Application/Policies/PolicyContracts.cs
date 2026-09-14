namespace HuTube.Application.Policies;

public sealed record PolicyDto(
    Guid PolicyId,
    string Code,
    string Name,
    string Group,
    string Content,
    string Severity,
    string Version,
    string Status,
    DateTimeOffset EffectiveAt
);

public sealed record CreatePolicyRequest(
    string Code,
    string Name,
    string Group,
    string Content,
    string Severity,
    string Version = "1.0",
    string Status = "published"
);

public sealed record UpdatePolicyRequest(
    string Name,
    string Group,
    string Content,
    string Severity,
    string Status,
    string? Version = null
);
