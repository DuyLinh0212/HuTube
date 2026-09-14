using HuTube.Application.Policies;
using HuTube.Infrastructure.Policies;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/policies")]
public sealed class PolicyController(PolicyService policyService) : ControllerBase
{
    [HttpGet]
    public Task<List<PolicyDto>> GetPublicPoliciesAsync([FromQuery] string? group = null, CancellationToken ct = default) =>
        policyService.GetPublicPoliciesAsync(group, ct);
}
