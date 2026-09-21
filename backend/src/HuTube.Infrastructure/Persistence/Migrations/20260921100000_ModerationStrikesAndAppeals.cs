using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20260921100000_ModerationStrikesAndAppeals")]
public sealed class ModerationStrikesAndAppeals : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        -- 1. Create channel_strikes table
        CREATE TABLE IF NOT EXISTS public.channel_strikes (
            strike_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            channel_id UUID NOT NULL REFERENCES public.channels(channel_id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
            strike_number INT NOT NULL DEFAULT 1,
            severity VARCHAR(20) NOT NULL DEFAULT 'high',
            policy_code VARCHAR(100),
            reason TEXT NOT NULL,
            internal_note TEXT,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            expires_at TIMESTAMPTZ NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
            revoked_at TIMESTAMPTZ,
            revoked_by_user_id UUID REFERENCES public.users(user_id),
            revocation_reason TEXT,
            source_moderation_case_id UUID REFERENCES public.moderation_cases(moderation_case_id),
            source_report_id UUID REFERENCES public.reports(report_id)
        );

        CREATE INDEX IF NOT EXISTS ix_channel_strikes_channel_status ON public.channel_strikes (channel_id, status);
        CREATE INDEX IF NOT EXISTS ix_channel_strikes_user_status ON public.channel_strikes (user_id, status);

        -- 2. Enhance appeals table
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appeals') THEN
                ALTER TABLE public.appeals
                    ADD COLUMN IF NOT EXISTS target_type VARCHAR(30) NOT NULL DEFAULT 'video',
                    ADD COLUMN IF NOT EXISTS target_id UUID,
                    ADD COLUMN IF NOT EXISTS moderation_case_id UUID REFERENCES public.moderation_cases(moderation_case_id),
                    ADD COLUMN IF NOT EXISTS strike_id UUID REFERENCES public.channel_strikes(strike_id),
                    ADD COLUMN IF NOT EXISTS evidence_url TEXT,
                    ADD COLUMN IF NOT EXISTS evidence_note TEXT,
                    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

                ALTER TABLE public.appeals ALTER COLUMN resolution_id DROP NOT NULL;
            END IF;
        END $$;

        -- 3. Seed new permissions
        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000025', 'policy.view', 'Xem Chính sách', 'Tra cứu danh mục và điều khoản chính sách kiểm duyệt', 'active'),
          ('00000000-0000-0001-0000-000000000026', 'policy.manage', 'Quản lý Chính sách', 'Tạo, sửa, công bố hoặc lưu trữ điều khoản', 'active'),
          ('00000000-0000-0001-0000-000000000027', 'report.view', 'Xem Báo cáo', 'Xem danh sách và chi tiết các báo cáo vi phạm', 'active'),
          ('00000000-0000-0001-0000-000000000028', 'report.resolve', 'Xử lý Báo cáo', 'Bác bỏ, cảnh cáo, đánh gậy, ẩn/gỡ nội dung bị báo cáo', 'active'),
          ('00000000-0000-0001-0000-000000000029', 'appeal.view', 'Xem Khiếu nại', 'Xem danh sách và chi tiết đơn khiếu nại', 'active'),
          ('00000000-0000-0001-0000-000000000030', 'appeal.resolve', 'Xử lý Khiếu nại', 'Chấp thuận (khôi phục/gỡ gậy) hoặc bác bỏ khiếu nại', 'active'),
          ('00000000-0000-0001-0000-000000000031', 'strike.view', 'Xem Warning & Strike', 'Tra cứu lịch sử gậy và cảnh cáo của các kênh', 'active'),
          ('00000000-0000-0001-0000-000000000032', 'strike.manage', 'Quản lý Strike', 'Đánh gậy thủ công, thu hồi gậy, gỡ phạt', 'active'),
          ('00000000-0000-0001-0000-000000000033', 'channel.lock', 'Khóa/Mở khóa Kênh', 'Khóa đình chỉ hoặc khôi phục hoạt động của kênh', 'active')
        ON CONFLICT (permission_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description;

        -- 4. Assign permissions to roles
        -- Super Admin: gets all new permissions
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000003'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code IN (
            'policy.view', 'policy.manage',
            'report.view', 'report.resolve',
            'appeal.view', 'appeal.resolve',
            'strike.view', 'strike.manage',
            'channel.lock'
        )
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- Admin: gets all new permissions
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000002'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code IN (
            'policy.view', 'policy.manage',
            'report.view', 'report.resolve',
            'appeal.view', 'appeal.resolve',
            'strike.view', 'strike.manage',
            'channel.lock'
        )
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- Moderator: gets view & resolve permissions, but NOT strike.manage, channel.lock, or policy.manage
        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT '00000000-0000-0000-0000-000000000004'::uuid, p.permission_id
        FROM public.permissions p
        WHERE p.code IN (
            'policy.view',
            'report.view', 'report.resolve',
            'appeal.view', 'appeal.resolve',
            'strike.view'
        )
        ON CONFLICT (role_id, permission_id) DO NOTHING;

        -- 5. Seed standard violation_types
        INSERT INTO public.violation_types (violation_type_id, code, name, description, status, created_at, updated_at)
        VALUES
          ('00000000-0000-0002-0000-000000000001', 'sexual', 'Nội dung khiêu dâm', 'Hình ảnh, video hoặc nội dung khiêu dâm, không phù hợp thuần phong mỹ tục.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000002', 'violent', 'Nội dung bạo lực hoặc phản cảm', 'Bạo lực, đẫm máu, gây sốc hoặc phản cảm.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000003', 'hate', 'Nội dung lăng mạ hoặc kích động thù hận', 'Xúc phạm danh dự, kỳ thị hoặc kích động thù địch.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000004', 'harassment', 'Nội dung quấy rối hoặc bắt nạt', 'Đe dọa, quấy rối, bắt nạt trực tuyến.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000005', 'harmful', 'Hành động gây hại hoặc nguy hiểm', 'Hành vi khuyến khích nguy hiểm hoặc tự gây hại.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000006', 'spam', 'Spam hoặc thông tin sai lệch', 'Lừa đảo, tin giả, quảng cáo rác hoặc thao túng người xem.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000007', 'copyright', 'Vi phạm bản quyền', 'Sử dụng tác phẩm không có bản quyền hoặc quyền sở hữu hợp pháp.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          ('00000000-0000-0002-0000-000000000008', 'other', 'Vi phạm khác', 'Các hành vi vi phạm điều khoản dịch vụ hoặc tiêu chuẩn cộng đồng khác.', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (violation_type_id) DO UPDATE SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE permission_id >= '00000000-0000-0001-0000-000000000025'::uuid
          AND permission_id <= '00000000-0000-0001-0000-000000000033'::uuid;

        DELETE FROM public.permissions
        WHERE permission_id >= '00000000-0000-0001-0000-000000000025'::uuid
          AND permission_id <= '00000000-0000-0001-0000-000000000033'::uuid;

        DROP TABLE IF EXISTS public.channel_strikes;
        """);
}
