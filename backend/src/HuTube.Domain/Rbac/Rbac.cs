namespace HuTube.Domain.Rbac;

public static class SystemRoles
{
    public static readonly Guid User = Guid.Parse("00000000-0000-0000-0000-000000000001");
    public static readonly Guid Admin = Guid.Parse("00000000-0000-0000-0000-000000000002");
    public static readonly Guid SuperAdmin = Guid.Parse("00000000-0000-0000-0000-000000000003");
    public static readonly Guid Moderator = Guid.Parse("00000000-0000-0000-0000-000000000004");
}

public static class AdminPermissions
{
    public const string DashboardView = "dashboard.view";
    public const string UserView = "user.view";
    public const string UserEdit = "user.edit";
    public const string UserBan = "user.ban";
    public const string RoleView = "role.view";
    public const string RoleEdit = "role.edit";
    public const string RoleDelete = "role.delete";
    public const string ChannelView = "channel.view";
    public const string ChannelEdit = "channel.edit";
    public const string ChannelSuspend = "channel.suspend";
    public const string ChannelBan = "channel.ban";
    public const string ChannelUnban = "channel.unban";
    public const string ChannelStrike = "channel.strike";
    public const string ChannelRemoveStrike = "channel.remove_strike";
    public const string ChannelDelete = "channel.delete";
    public const string ChannelExport = "channel.export";
    public const string VideoView = "video.view";
    public const string VideoViewPrivate = "video.view_private";
    public const string VideoEditMetadata = "video.edit_metadata";
    public const string VideoHide = "video.hide";
    public const string VideoUnhide = "video.unhide";
    public const string VideoRemove = "video.remove";
    public const string VideoRestore = "video.restore";
    public const string VideoStrike = "video.strike";
    public const string VideoExport = "video.export";
    public const string ModerationViewQueue = "moderation.view_queue";
    public const string ModerationClaim = "moderation.claim";
    public const string ModerationReview = "moderation.review";
    public const string ModerationApprove = "moderation.approve";
    public const string ModerationReject = "moderation.reject";
    public const string AuditView = "audit.view";
    public const string SystemViewSetting = "system.view_setting";
    public const string SystemEditSetting = "system.edit_setting";
    public const string TaxonomyManage = "taxonomy.manage";
    public const string CfSeedManage = "cf_seed.manage";
    public const string PlanView = "plan.view";
    public const string PlanCreate = "plan.create";
    public const string PlanEdit = "plan.edit";
    public const string PlanArchive = "plan.archive";
    public const string PolicyView = "policy.view";
    public const string PolicyManage = "policy.manage";
    public const string ReportView = "report.view";
    public const string ReportClaim = "report.claim";
    public const string ReportResolve = "report.resolve";
    public const string AppealView = "appeal.view";
    public const string AppealResolve = "appeal.resolve";
    public const string StrikeView = "strike.view";
    public const string StrikeManage = "strike.manage";
    public const string ChannelLock = "channel.lock";

    public static readonly IReadOnlyList<string> All = [
        DashboardView,
        UserView, UserEdit, UserBan,
        RoleView, RoleEdit, RoleDelete,
        ChannelView, ChannelEdit, ChannelSuspend, ChannelBan, ChannelUnban, ChannelStrike,
        ChannelRemoveStrike, ChannelDelete, ChannelExport, ChannelLock,
        VideoView, VideoViewPrivate, VideoEditMetadata, VideoHide, VideoUnhide, VideoRemove,
        VideoRestore, VideoStrike, VideoExport,
        ModerationViewQueue, ModerationClaim, ModerationReview, ModerationApprove, ModerationReject,
        ReportView, ReportClaim, ReportResolve,
        AppealView, AppealResolve,
        StrikeView, StrikeManage,
        PolicyView, PolicyManage,
        AuditView,
        SystemViewSetting, SystemEditSetting,
        TaxonomyManage, CfSeedManage,
        PlanView, PlanCreate, PlanEdit, PlanArchive
    ];
}

public sealed class Permission
{
    public Guid PermissionId { get; set; } = Guid.NewGuid();
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Description { get; set; }
    public string Status { get; set; } = "active";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class RolePermission
{
    public Guid RolePermissionId { get; set; } = Guid.NewGuid();
    public Guid RoleId { get; set; }
    public Guid PermissionId { get; set; }
    public DateTimeOffset AssignedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class AuditLog
{
    public Guid AuditLogId { get; set; } = Guid.NewGuid();
    public Guid? ActorUserId { get; set; }
    public string Action { get; set; } = "";
    public string? ResourceType { get; set; }
    public Guid? ResourceId { get; set; }
    public string? Reason { get; set; }
    public string? OldValues { get; set; }
    public string? NewValues { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
