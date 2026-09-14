-- Migration: 20260913_add_policies_table.sql
-- Description: Create policies table, extend moderation_cases, and seed comprehensive 12-pillar policies.
-- Standard PostgreSQL script: compatible with psql, pgAdmin, DBeaver, EF Core, and all migration tools.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

BEGIN;

CREATE TABLE IF NOT EXISTS public.policies (
    policy_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code character varying(100) NOT NULL UNIQUE,
    name character varying(200) NOT NULL,
    "group" character varying(50) NOT NULL DEFAULT 'guidelines',
    content text NOT NULL,
    severity character varying(20) NOT NULL DEFAULT 'medium',
    version character varying(20) NOT NULL DEFAULT '1.0',
    status character varying(20) NOT NULL DEFAULT 'published',
    effective_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_policies_group_status ON public.policies ("group", status);
CREATE INDEX IF NOT EXISTS ix_policies_code ON public.policies (code);

-- Extend moderation_cases safely if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'moderation_cases'
    ) THEN
        ALTER TABLE public.moderation_cases
            ADD COLUMN IF NOT EXISTS policy_code character varying(100),
            ADD COLUMN IF NOT EXISTS policy_version character varying(20),
            ADD COLUMN IF NOT EXISTS decision character varying(50),
            ADD COLUMN IF NOT EXISTS internal_note text,
            ADD COLUMN IF NOT EXISTS risk_level character varying(20) DEFAULT 'normal' NOT NULL;
    END IF;
END $$;

-- Clean up any legacy placeholder IDs
DELETE FROM public.policies WHERE policy_id::text LIKE '10000000-%';

-- Seed comprehensive 12-pillar policies with standard PostgreSQL UUIDs (policy_id auto-generated via gen_random_uuid())
INSERT INTO public.policies (code, name, "group", content, severity, version, status)
VALUES
-- 1. Community Guidelines: Community Safety
(
    'CHILD_SAFETY',
    'An toàn cho trẻ em',
    'guidelines',
    'Tuyệt đối không khoan nhượng với hành vi bóc lột, lạm dụng tình dục hoặc đưa trẻ em vào tình huống nguy hiểm. Cấm CSAM/CSAE, cấm lôi kéo vào thử thách đe dọa thể xác và tâm lý.',
    'critical',
    '1.0',
    'published'
),
(
    'SEXUAL_CONTENT',
    'Nội dung tình dục và ảnh khỏa thân',
    'guidelines',
    'Nghiêm cấm nội dung khiêu dâm, hành vi tình dục rõ ràng hoặc khỏa thân không phù hợp với không gian chung. Cho phép ngoại lệ tác phẩm điêu khắc, hội họa hoặc giáo dục giới tính có ngữ cảnh.',
    'critical',
    '1.0',
    'published'
),
(
    'SELF_HARM',
    'Nội dung tự làm hại bản thân và tự tử',
    'guidelines',
    'Cấm khuyến khích, hướng dẫn hoặc cổ xúy các hành vi tự tử và tự gây thương tích, thử thách bỏ đói hoặc rối loạn ăn uống cực đoan.',
    'critical',
    '1.0',
    'published'
),
(
    'VIOLENCE',
    'Nội dung bạo lực hoặc đẫm máu',
    'guidelines',
    'Cấm video bạo lực đồ họa tàn bạo, khủng bố, hoặc kích động bạo lực trong thế giới thực. Tư liệu lịch sử hoặc phóng sự báo chí bắt buộc phải có cảnh báo đầu video.',
    'critical',
    '1.0',
    'published'
),
(
    'ANIMAL_ABUSE',
    'Ngược đãi động vật',
    'guidelines',
    'Nghiêm cấm hành hạ, đánh đập, giết hại dã man động vật hoặc dàn dựng giải cứu động vật giả để câu view.',
    'high',
    '1.0',
    'published'
),
(
    'HATE_SPEECH',
    'Nội dung kích động thù địch',
    'guidelines',
    'Cấm ngôn từ thù hận, miệt thị dựa trên chủng tộc, tôn giáo, giới tính, khuynh hướng tính dục hoặc tình trạng khuyết tật.',
    'high',
    '1.0',
    'published'
),
(
    'HARASSMENT',
    'Hành vi quấy rối và đe dọa bắt nạt',
    'guidelines',
    'Cấm đe dọa vũ lực, sỉ nhục ngoại hình lặp đi lặp lại nhằm quấy nhiễu đời tư hoặc triệt hạ nhân phẩm cá nhân.',
    'high',
    '1.0',
    'published'
),
(
    'DANGEROUS_ACTIVITIES',
    'Hoạt động nguy hiểm hoặc có hại',
    'guidelines',
    'Cấm các thử thách viral liều lĩnh có nguy cơ gây thương tật nặng hoặc tử vong, cấm hướng dẫn chế tạo vũ khí, chất nổ hoặc độc dược.',
    'high',
    '1.0',
    'published'
),
-- 2. Community Guidelines: Integrity & Deception
(
    'SPAM_SCAM',
    'Nội dung rác và hành vi lừa đảo',
    'guidelines',
    'Bảo vệ khán giả khỏi bình luận rác hàng loạt, lừa đảo đa cấp tài chính, tiền ảo không rõ nguồn gốc hoặc cam kết lợi nhuận phi thực tế.',
    'high',
    '1.0',
    'published'
),
(
    'IMPERSONATION',
    'Hành vi mạo danh',
    'guidelines',
    'Cấm tạo kênh giả mạo người nổi tiếng, cơ quan chức năng hoặc thương hiệu để gây nhầm lẫn và trục lợi.',
    'high',
    '1.0',
    'published'
),
(
    'FAKE_ENGAGEMENT',
    'Tương tác ảo và thao túng nền tảng',
    'guidelines',
    'Cấm dùng bot, dịch vụ cày view hoặc mua bán sub/like ảo. HuTube tự động trừ bỏ và đóng băng các kênh vi phạm thao túng số liệu.',
    'high',
    '1.0',
    'published'
),
(
    'MISLEADING_METADATA',
    'Metadata sai lệch và clickbait lừa dối',
    'guidelines',
    'Tiêu đề, ảnh thu nhỏ (thumbnail) và mô tả phải phản ánh đúng nội dung thực tế của video.',
    'medium',
    '1.0',
    'published'
),
(
    'EXTERNAL_LINKS',
    'Liên kết ngoài độc hại',
    'guidelines',
    'Cấm đính kèm đường link dẫn tới trang web lừa đảo, phát tán mã độc hoặc nội dung cấm.',
    'critical',
    '1.0',
    'published'
),
(
    'MISINFORMATION_SYNTHETIC',
    'Thông tin sai lệch và nội dung AI / Deepfake',
    'guidelines',
    'Ngăn chặn tin giả nguy hại và kiểm soát tính minh bạch của nội dung AI. Bắt buộc gắn cờ Nội dung AI đối với video mô phỏng người thật.',
    'high',
    '1.0',
    'published'
),
(
    'REGULATED_GOODS',
    'Hàng hóa và dịch vụ bị kiểm soát đặc biệt',
    'guidelines',
    'Tuân thủ pháp luật về hàng cấm, vũ khí, chất ma túy và dịch vụ cờ bạc online, cá cược thể thao.',
    'critical',
    '1.0',
    'published'
),
(
    'CONTENT_SURFACES',
    'Phạm vi áp dụng trên toàn bộ nền tảng',
    'guidelines',
    'Quy tắc cộng đồng áp dụng đồng bộ trên video dài, Shorts, livestream, thumbnail, bình luận và danh sách phát.',
    'info',
    '1.0',
    'published'
),
-- 3. Privacy & Data Protection
(
    'DOXXING_PRIVACY',
    'Chống công khai dữ liệu cá nhân (Doxxing)',
    'privacy',
    'Tuyệt đối cấm phát tán thông tin riêng tư (địa chỉ nhà, số điện thoại, biển số xe) của người khác nhằm mục đích quấy rối.',
    'critical',
    '1.0',
    'published'
),
(
    'PERSONAL_DOCUMENTS',
    'Bảo vệ giấy tờ định danh và dữ liệu nhạy cảm',
    'privacy',
    'Không hiển thị số CCCD, hộ chiếu, thông tin tài khoản ngân hàng trong video mà không che mờ.',
    'high',
    '1.0',
    'published'
),
(
    'NON_CONSENSUAL',
    'Nội dung không có sự đồng thuận',
    'privacy',
    'Nghiêm cấm phát tán hình ảnh hoặc video nhạy cảm khi chưa được sự đồng thuận rõ ràng của người trong cuộc.',
    'critical',
    '1.0',
    'published'
),
(
    'MINOR_DATA_PROTECTION',
    'Quyền riêng tư của trẻ em và thanh thiếu niên',
    'privacy',
    'Thiết lập bảo vệ tối đa cho tài khoản người dùng dưới 16 tuổi theo Nghị định 13/2023/NĐ-CP.',
    'critical',
    '1.0',
    'published'
),
(
    'SECURITY_ENCRYPTION',
    'Tiêu chuẩn bảo mật TLS 1.3 và lưu trữ AES-256',
    'privacy',
    'Toàn bộ dữ liệu truyền tải và lưu trữ được bảo vệ theo các chuẩn mã hóa hàng đầu tại Data Center Việt Nam.',
    'info',
    '1.0',
    'published'
),
-- 4. Terms of Service & Legal
(
    'TERMS_ACCEPTANCE',
    'Chấp thuận điều khoản và phạm vi dịch vụ',
    'terms',
    'Quy định pháp lý ràng buộc khi truy cập và sử dụng dịch vụ trên nền tảng mạng xã hội video HuTube.',
    'info',
    '1.0',
    'published'
),
(
    'USER_ACCOUNTS',
    'Quyền và trách nhiệm tài khoản người dùng',
    'terms',
    'Bảo mật thông tin đăng nhập, xác thực 2 bước và chịu trách nhiệm về mọi hoạt động diễn ra dưới tài khoản.',
    'high',
    '1.0',
    'published'
),
(
    'COPYRIGHT_UGC',
    'Bản quyền nội dung tải lên và giấy phép cấp cho HuTube',
    'terms',
    'Tác giả giữ toàn quyền sở hữu tác phẩm và cấp phép phát sóng cho HuTube. Nghiêm cấm vi phạm bản quyền bên thứ ba.',
    'high',
    '1.0',
    'published'
),
(
    'SERVICE_TERMINATION',
    'Chấm dứt dịch vụ và đóng tài khoản',
    'terms',
    'HuTube có quyền ngưng cung cấp dịch vụ hoặc xóa tài khoản đối với các hành vi vi phạm nghiêm trọng hoặc tái phạm nhiều lần.',
    'critical',
    '1.0',
    'published'
),
(
    'LIABILITY_LIMITATION',
    'Giới hạn trách nhiệm pháp lý',
    'terms',
    'Phạm vi trách nhiệm pháp lý của HuTube đối với các nội dung do bên thứ ba hoặc người dùng tải lên.',
    'info',
    '1.0',
    'published'
),
-- 5. Monetization & Partner
(
    'PARTNER_ELIGIBILITY',
    'Điều kiện tham gia Chương trình Đối tác HuTube',
    'monetization',
    'Ngưỡng điều kiện người đăng ký, giờ xem công khai hợp lệ và kênh không có gậy cảnh cáo vi phạm còn hiệu lực.',
    'high',
    '1.0',
    'published'
),
(
    'AD_SUITABILITY_GUIDE',
    'Tiêu chuẩn nội dung thân thiện với nhà quảng cáo',
    'monetization',
    'Hệ thống đánh giá tính phù hợp hiển thị quảng cáo: Biểu tượng Xanh (Bật đầy đủ), Vàng (Hạn chế), Đỏ (Không quảng cáo).',
    'medium',
    '1.0',
    'published'
),
(
    'REVENUE_PAYOUTS',
    'Chia sẻ doanh thu và nghĩa vụ thuế',
    'monetization',
    'Quy trình quyết toán định kỳ hàng tháng qua tài khoản ngân hàng chính chủ và khấu trừ thuế theo quy định pháp luật Việt Nam.',
    'info',
    '1.0',
    'published'
),
-- 6. Enforcement & Appeals
(
    'STRIKES_WARNING',
    'Hệ thống cảnh báo và gậy vi phạm',
    'enforcement',
    'Cơ chế xử phạt lũy tiến: Nhắc nhở (Warning), Gậy 1 (khóa 7 ngày), Gậy 2 (khóa 14 ngày), Gậy 3 (chấm dứt kênh vĩnh viễn).',
    'high',
    '1.0',
    'published'
),
(
    'EDSA_EXCEPTIONS',
    'Nguyên tắc xem xét ngoại lệ EDSA',
    'enforcement',
    'Xem xét ngữ cảnh đặc biệt đối với nội dung Giáo dục (E), Tài liệu (D), Khoa học (S), Nghệ thuật (A) và Lợi ích công chúng.',
    'info',
    '1.0',
    'published'
),
(
    'APPEALS_PROCESS',
    'Quy trình khiếu nại minh bạch',
    'enforcement',
    'Quyền khiếu nại quyết định kiểm duyệt trong vòng 30 ngày; chuyên viên con người phản hồi và xử lý trong 48 giờ.',
    'info',
    '1.0',
    'published'
),
(
    'MODERATION_INFRASTRUCTURE',
    'Hạ tầng kiểm duyệt kết hợp AI và chuyên viên con người',
    'enforcement',
    'Hệ sinh thái kiểm duyệt đa tầng: AI quét tự động đa phương thức kết hợp đội ngũ kiểm duyệt viên bản địa thẩm định.',
    'info',
    '1.0',
    'published'
)
ON CONFLICT (code) DO NOTHING;

-- Grant Administrator role permission safely if both role and permission exist
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.roles WHERE role_id = '00000000-0000-0000-0000-000000000002'
    ) AND EXISTS (
        SELECT 1 FROM public.permissions WHERE permission_id = '00000000-0000-0001-0000-000000000017'
    ) THEN
        INSERT INTO public.role_permissions (role_permission_id, role_id, permission_id)
        VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000002', '00000000-0000-0001-0000-000000000017')
        ON CONFLICT (role_id, permission_id) DO NOTHING;
    END IF;
END $$;

COMMIT;
