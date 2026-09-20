using System.Security.Claims;
using HuTube.Application.Playlists;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HuTube.Api.Controllers;

[ApiController, Route("api/v1/playlists")]
public sealed class PlaylistController(IPlaylistService playlists) : ControllerBase
{
    private Guid UserId => Guid.TryParse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : throw new PlaylistException(401, "UNAUTHORIZED", "Vui long dang nhap de tiep tuc.");
    private Guid? ViewerId => Guid.TryParse(User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id) ? id : null;

    [Authorize, HttpGet]
    public Task<IReadOnlyList<PlaylistSummaryResponse>> MineAsync(CancellationToken ct) => playlists.GetMineAsync(UserId, ct);

    [AllowAnonymous, HttpGet("channel/{channelId:guid}")]
    public Task<IReadOnlyList<PlaylistSummaryResponse>> PublicByChannelAsync(Guid channelId, CancellationToken ct) =>
        playlists.GetPublicByChannelAsync(channelId, ct);

    [Authorize, HttpGet("channel/{channelId:guid}/mine")]
    public Task<IReadOnlyList<PlaylistSummaryResponse>> ChannelMineAsync(Guid channelId, CancellationToken ct) =>
        playlists.GetChannelMineAsync(UserId, channelId, ct);

    [AllowAnonymous, HttpGet("{id:guid}")]
    public Task<PlaylistResponse> GetAsync(Guid id, CancellationToken ct) => playlists.GetAsync(id, ViewerId, ct);

    [Authorize, HttpPost]
    public async Task<ActionResult<PlaylistResponse>> CreateAsync(CreatePlaylistRequest request, CancellationToken ct)
        => Ok(await playlists.CreateAsync(UserId, request, ct));

    [Authorize, HttpPost("save")]
    public Task<PlaylistResponse> SaveVideoAsync(SaveVideoRequest request, CancellationToken ct) =>
        playlists.SaveVideoAsync(UserId, request, ct);

    [Authorize, HttpPatch("{id:guid}")]
    public Task<PlaylistResponse> UpdateAsync(Guid id, UpdatePlaylistRequest request, CancellationToken ct) => playlists.UpdateAsync(UserId, id, request, ct);

    [Authorize, HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteAsync(Guid id, CancellationToken ct) { await playlists.DeleteAsync(UserId, id, ct); return NoContent(); }

    [Authorize, HttpPost("{id:guid}/videos")]
    public Task<PlaylistResponse> AddVideoAsync(Guid id, AddPlaylistVideoRequest request, CancellationToken ct) => playlists.AddVideoAsync(UserId, id, request, ct);

    [Authorize, HttpDelete("{id:guid}/videos/{videoId:guid}")]
    public async Task<IActionResult> RemoveVideoAsync(Guid id, Guid videoId, CancellationToken ct) { await playlists.RemoveVideoAsync(UserId, id, videoId, ct); return NoContent(); }

    [Authorize, HttpPut("{id:guid}/order")]
    public Task<PlaylistResponse> ReorderAsync(Guid id, ReorderPlaylistRequest request, CancellationToken ct) => playlists.ReorderAsync(UserId, id, request, ct);
}
