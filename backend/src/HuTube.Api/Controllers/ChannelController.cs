using HuTube.Application.Channels;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/channels")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class ChannelController(ChannelService channelService) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirst("sub")!.Value);

    [Authorize, HttpPost]
    public async Task<ActionResult<ChannelResponse>> CreateAsync(CreateChannelRequest request, CancellationToken ct)
    {
        var result = await channelService.CreateChannelAsync(UserId, request, ct);
        return StatusCode(201, result);
    }

    [HttpGet("{id:guid}")]
    public Task<ChannelResponse> GetByIdAsync(Guid id, CancellationToken ct) =>
        channelService.GetChannelAsync(id, ct);

    [HttpGet("handle/{handle}")]
    public Task<ChannelResponse> GetByHandleAsync(string handle, CancellationToken ct) =>
        channelService.GetChannelByHandleAsync(handle, ct);

    [Authorize, HttpPatch("{id:guid}")]
    public Task<ChannelResponse> UpdateAsync(Guid id, UpdateChannelRequest request, CancellationToken ct) =>
        channelService.UpdateChannelAsync(id, UserId, request, ct);

    [Authorize, HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken ct)
    {
        await channelService.DeleteChannelAsync(id, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpPost("{id:guid}/members/invite")]
    public async Task<ActionResult<ChannelInvitationResponse>> InviteMemberAsync(Guid id, InviteMemberRequest request, CancellationToken ct)
    {
        var result = await channelService.InviteMemberAsync(id, UserId, request, ct);
        return StatusCode(201, result);
    }

    [Authorize, HttpGet("{id:guid}/invitations")]
    public Task<List<ChannelInvitationResponse>> GetPendingInvitationsAsync(Guid id, CancellationToken ct) =>
        channelService.GetPendingInvitationsAsync(id, UserId, ct);

    [Authorize, HttpDelete("{id:guid}/invitations/{invitationId:guid}")]
    public async Task<IActionResult> RevokeInvitationAsync(Guid id, Guid invitationId, CancellationToken ct)
    {
        await channelService.RevokeInvitationAsync(id, invitationId, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpGet("invitations/me")]
    public Task<List<ChannelInvitationResponse>> GetMyInvitationsAsync(CancellationToken ct) =>
        channelService.GetMyInvitationsAsync(UserId, ct);

    [Authorize, HttpPost("invitations/{invitationId:guid}/accept")]
    public Task<ChannelMemberResponse> AcceptInvitationAsync(Guid invitationId, CancellationToken ct) =>
        channelService.AcceptInvitationAsync(invitationId, UserId, ct);

    [Authorize, HttpPost("invitations/{invitationId:guid}/decline")]
    public async Task<IActionResult> DeclineInvitationAsync(Guid invitationId, CancellationToken ct)
    {
        await channelService.DeclineInvitationAsync(invitationId, UserId, ct);
        return NoContent();
    }

    [Authorize, HttpGet("{id:guid}/members")]
    public Task<List<ChannelMemberResponse>> GetMembersAsync(Guid id, CancellationToken ct) =>
        channelService.GetMembersAsync(id, UserId, ct);

    [Authorize, HttpPatch("{id:guid}/members/{targetUserId:guid}/role")]
    public Task<ChannelMemberResponse> ChangeMemberRoleAsync(Guid id, Guid targetUserId, ChangeMemberRoleRequest request, CancellationToken ct) =>
        channelService.ChangeMemberRoleAsync(id, targetUserId, UserId, request, ct);

    [Authorize, HttpDelete("{id:guid}/members/{targetUserId:guid}")]
    public async Task<IActionResult> RemoveMemberAsync(Guid id, Guid targetUserId, CancellationToken ct)
    {
        await channelService.RemoveMemberAsync(id, targetUserId, UserId, ct);
        return NoContent();
    }
}
