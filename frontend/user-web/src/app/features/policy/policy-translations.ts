import type { AppLang } from '../../core/i18n.service';

// Loaded with the policy and moderation screens instead of the initial application bundle.
export const POLICY_CENTER_TRANSLATIONS: Record<AppLang, Record<string, string>> = {
  "vi": {
    "policies.all": "Tất cả chính sách",
    "policies.compactTitle": "Chính sách Dalitu",
    "policies.compactDescription": "Tra cứu quy định, quyền riêng tư và hướng dẫn xử lý vi phạm.",
    "policies.tab.all.title": "Tất cả chính sách",
    "policies.tab.all.desc": "Toàn bộ quy định, quyền lợi và trách nhiệm khi sử dụng Dalitu. Chọn một nhóm hoặc tìm kiếm để tra cứu nhanh.",
    "policies.directory": "DANH MỤC CHÍNH SÁCH",
    "policies.collectionCount": "{count} chính sách · 4 nhóm nội dung",
    "policies.exportHint": "Bản PDF bao gồm toàn bộ chính sách, không phụ thuộc bộ lọc.",
    "policies.needHelp": "Bạn cần tìm hiểu cách xử lý vi phạm?",
    "policies.helpDesc": "Xem quy trình cảnh cáo và hướng dẫn gửi kháng nghị.",
    "policies.loading": "Đang tải chính sách mới nhất…",
    "policies.exporting": "Đang tạo PDF…",
    "policies.loadError": "Chưa tải được chính sách mới nhất. Nội dung hướng dẫn vẫn hiển thị; hãy thử lại trước khi tải PDF.",
    "policies.retry": "Thử lại",
    "report.stepProgress": "Bước {step} / 2",
    "report.stepReason": "Chọn lý do",
    "report.stepDetails": "Bổ sung thông tin",
    "report.policyLink": "Xem chính sách cộng đồng",
    "report.selectedReason": "Lý do đã chọn",
    "report.detailsLabel": "Thông tin bổ sung (không bắt buộc)",
    "studio.viewPolicies": "Tra cứu chính sách"
  },
  "en": {
    "policies.all": "All policies",
    "policies.compactTitle": "Dalitu policies",
    "policies.compactDescription": "Find guidelines, privacy rules and help with moderation decisions.",
    "policies.tab.all.title": "All policies",
    "policies.tab.all.desc": "Every rule, right and responsibility for using Dalitu. Choose a category or search to find what you need.",
    "policies.directory": "POLICY DIRECTORY",
    "policies.collectionCount": "{count} policies · 4 categories",
    "policies.exportHint": "The PDF includes all policies, regardless of filters.",
    "policies.needHelp": "Need help with a moderation decision?",
    "policies.helpDesc": "Understand warnings, strikes and how to submit an appeal.",
    "policies.loading": "Loading the latest policies…",
    "policies.exporting": "Creating PDF…",
    "policies.loadError": "The latest policies could not be loaded. Reference guidance remains available; please retry before downloading a PDF.",
    "policies.retry": "Retry",
    "report.stepProgress": "Step {step} / 2",
    "report.stepReason": "Choose a reason",
    "report.stepDetails": "Add details",
    "report.policyLink": "Read community guidelines",
    "report.selectedReason": "Selected reason",
    "report.detailsLabel": "Additional details (optional)",
    "studio.viewPolicies": "Browse policies"
  }
};
