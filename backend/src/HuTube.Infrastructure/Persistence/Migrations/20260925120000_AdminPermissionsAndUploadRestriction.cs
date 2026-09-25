using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260925120000_AdminPermissionsAndUploadRestriction")]
public sealed class AdminPermissionsAndUploadRestriction : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE public.channel_strikes ADD COLUMN IF NOT EXISTS upload_restricted_until TIMESTAMPTZ;

        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000034', 'role.delete', 'Xóa vai trò', 'Xóa mềm vai trò tùy chỉnh không còn người dùng được gán.', 'active'),
          ('00000000-0000-0001-0000-000000000035', 'report.claim', 'Nhận hồ sơ báo cáo', 'Nhận hoặc trả hồ sơ báo cáo được nhóm theo đối tượng.', 'active'),
          ('00000000-0000-0001-0000-000000000036', 'channel.suspend', 'Tạm ngưng kênh', 'Tạm đình chỉ hoạt động của kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000037', 'channel.ban', 'Cấm kênh', 'Cấm vĩnh viễn hoạt động của kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000038', 'channel.unban', 'Khôi phục kênh', 'Khôi phục hoạt động của kênh đã bị hạn chế.', 'active'),
          ('00000000-0000-0001-0000-000000000039', 'channel.strike', 'Áp dụng gậy kênh', 'Tạo cảnh cáo hoặc gậy phạt cho kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000040', 'channel.remove_strike', 'Thu hồi gậy kênh', 'Thu hồi gậy phạt đã áp dụng cho kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000041', 'channel.delete', 'Xóa kênh', 'Xóa mềm hoặc khôi phục kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000042', 'channel.export', 'Xuất kênh', 'Xuất dữ liệu danh sách kênh.', 'active'),
          ('00000000-0000-0001-0000-000000000043', 'video.view_private', 'Xem video riêng tư', 'Xem video không công khai trong công cụ quản trị.', 'active'),
          ('00000000-0000-0001-0000-000000000044', 'video.edit_metadata', 'Sửa metadata video', 'Sửa tiêu đề, mô tả và danh mục video.', 'active'),
          ('00000000-0000-0001-0000-000000000045', 'video.hide', 'Ẩn video', 'Ẩn video khỏi bề mặt công khai.', 'active'),
          ('00000000-0000-0001-0000-000000000046', 'video.unhide', 'Hiện video', 'Khôi phục khả năng hiển thị của video.', 'active'),
          ('00000000-0000-0001-0000-000000000047', 'video.remove', 'Gỡ video', 'Gỡ video vi phạm khỏi bề mặt công khai.', 'active'),
          ('00000000-0000-0001-0000-000000000048', 'video.restore', 'Khôi phục video', 'Khôi phục video đã bị gỡ.', 'active'),
          ('00000000-0000-0001-0000-000000000049', 'video.strike', 'Áp dụng gậy video', 'Áp dụng cảnh cáo cho chủ video.', 'active'),
          ('00000000-0000-0001-0000-000000000050', 'video.export', 'Xuất video', 'Xuất dữ liệu danh sách video.', 'active')
        ON CONFLICT (permission_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description, status = 'active';

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id
        FROM public.roles r CROSS JOIN public.permissions p
        WHERE r.code IN ('admin','super_admin')
          AND p.code IN ('channel.suspend','channel.ban','channel.unban','channel.strike','channel.remove_strike','channel.delete','channel.export',
            'video.view_private','video.edit_metadata','video.hide','video.unhide','video.remove','video.restore','video.strike','video.export')
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id FROM public.roles r CROSS JOIN public.permissions p
        WHERE r.code = 'super_admin' AND p.code = 'role.delete'
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id FROM public.roles r CROSS JOIN public.permissions p
        WHERE r.code IN ('admin','super_admin','moderator') AND p.code = 'report.claim'
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions rp USING public.permissions p
        WHERE rp.permission_id = p.permission_id AND p.permission_id BETWEEN
          '00000000-0000-0001-0000-000000000034'::uuid AND '00000000-0000-0001-0000-000000000050'::uuid;
        DELETE FROM public.permissions WHERE permission_id BETWEEN
          '00000000-0000-0001-0000-000000000034'::uuid AND '00000000-0000-0001-0000-000000000050'::uuid;
        ALTER TABLE public.channel_strikes DROP COLUMN IF EXISTS upload_restricted_until;
        """);
}
