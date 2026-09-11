import { Injectable, signal } from '@angular/core';

export type AppLang = 'vi' | 'en';

const DICTIONARY: Record<AppLang, Record<string, string>> = {
  vi: {
    // Common
    'common.save': 'Lưu thay đổi',
    'common.saving': 'Đang lưu...',
    'common.cancel': 'Hủy',
    'common.delete': 'Xóa',
    'common.edit': 'Chỉnh sửa',
    'common.back': 'Quay lại',
    'common.close': 'Đóng',
    'common.loading': 'Đang tải dữ liệu...',
    'common.search': 'Tìm kiếm',
    'common.actions': 'Thao tác',
    'common.status': 'Trạng thái',
    'common.filter': 'Bộ lọc',
    'common.all': 'Tất cả',
    'common.active': 'Hoạt động',
    'common.inactive': 'Không hoạt động',
    'common.banned': 'Bị khóa',
    'common.success': 'Thành công',
    'common.error': 'Đã có lỗi xảy ra',
    'common.confirm': 'Xác nhận',

    // Topbar
    'topbar.searchPlaceholder': 'Tìm hồ sơ, video, người dùng, kênh…',
    'topbar.dateRange': '30 ngày gần nhất',
    'topbar.notifications': 'thông báo',
    'topbar.adminRole': 'Quản trị viên',
    'topbar.theme': 'Giao diện',
    'topbar.themeLight': 'Chế độ Sáng',
    'topbar.themeDark': 'Chế độ Tối',
    'topbar.language': 'Ngôn ngữ',

    // Navigation Groups & Items
    'nav.expand': 'Mở rộng sidebar',
    'nav.collapse': 'Thu gọn sidebar',
    'nav.closeMenu': 'Đóng menu',
    'nav.openMenu': 'Mở menu',
    'nav.dashboard': 'Tổng quan',
    'nav.groupUser': 'Người dùng',
    'nav.userList': 'Danh sách người dùng',
    'nav.roleList': 'Nhóm quyền & vai trò',
    'nav.groupContent': 'Nội dung',
    'nav.channels': 'Kênh',
    'nav.videos': 'Video',
    'nav.topics': 'Chủ đề & tag',
    'nav.groupModeration': 'Kiểm duyệt',
    'nav.videoQueue': 'Hàng đợi video',
    'nav.reports': 'Báo cáo vi phạm',
    'nav.appeals': 'Khiếu nại',
    'nav.warnings': 'Warning & strike',
    'nav.groupBusiness': 'Kinh doanh',
    'nav.plans': 'Gói dịch vụ (Plan)',
    'nav.subscriptions': 'Thuê bao (Subscription)',
    'nav.payments': 'Doanh thu & Thanh toán',
    'nav.groupSystem': 'Hệ thống',
    'nav.notificationsNav': 'Thông báo hệ thống',
    'nav.statistics': 'Thống kê & Báo cáo',
    'nav.systemLogs': 'Nhật ký & cấu hình',

    // Admin Users Page
    'users.title': 'Quản lý người dùng',
    'users.subtitle': 'Xem, tìm kiếm, phân quyền và quản lý trạng thái tài khoản người dùng HuTube',
    'users.search': 'Tìm theo email, tên hiển thị hoặc username...',
    'users.filterRole': 'Lọc theo vai trò',
    'users.filterStatus': 'Lọc theo trạng thái',
    'users.colUser': 'Người dùng',
    'users.colRole': 'Vai trò',
    'users.colStatus': 'Trạng thái',
    'users.colEmailVerified': 'Xác minh Email',
    'users.colCreatedAt': 'Ngày tham gia',
    'users.colActions': 'Hành động',
    'users.verified': 'Đã xác minh',
    'users.unverified': 'Chưa xác minh',
    'users.actionBan': 'Khóa tài khoản',
    'users.actionUnban': 'Mở khóa tài khoản',
    'users.actionEditRole': 'Đổi vai trò',
    'users.empty': 'Không tìm thấy người dùng nào phù hợp.',

    // Admin RBAC Page
    'rbac.title': 'Nhóm quyền & vai trò (RBAC)',
    'rbac.subtitle': 'Thiết lập danh mục quyền hạn chi tiết cho từng nhóm quản trị viên và người dùng',
    'rbac.rolesTitle': 'Danh sách vai trò',
    'rbac.createRole': 'Tạo vai trò mới',
    'rbac.permissionsMatrix': 'Ma trận phân quyền',
    'rbac.saveMatrix': 'Lưu thay đổi ma trận quyền',
    'rbac.roleName': 'Tên vai trò',
    'rbac.roleDescription': 'Mô tả',
    'rbac.userCount': 'Số người dùng',
    'rbac.permission': 'Quyền hạn',

    // Account & Profile
    'account.title': 'Tài khoản quản trị',
    'account.tabProfile': 'Thông tin cá nhân',
    'account.tabPassword': 'Mật khẩu & Bảo mật',
    'account.tabPreferences': 'Giao diện & Cài đặt',
    'account.tabSessions': 'Phiên đăng nhập',
    'account.themeLabel': 'Giao diện hiển thị (Chế độ màu)',
    'account.themeLight': 'Nền sáng (Mặc định)',
    'account.themeDark': 'Nền tối (Dịu mắt)',
    'account.langLabel': 'Ngôn ngữ quản trị',

    // Forbidden Page
    'forbidden.title': 'Truy cập bị từ chối (403)',
    'forbidden.desc': 'Tài khoản của bạn không có đủ quyền hạn để truy cập vào khu vực này.',
    'forbidden.back': 'Quay về trang quản trị',

    // Auth
    'auth.loginTitle': 'Đăng nhập HuTube Quản trị',
    'auth.email': 'Email quản trị',
    'auth.password': 'Mật khẩu',
    'auth.loginBtn': 'Đăng nhập vào hệ thống',
    'auth.logout': 'Đăng xuất'
  },

  en: {
    // Common
    'common.save': 'Save changes',
    'common.saving': 'Saving...',
    'common.cancel': 'Cancel',
    'common.delete': 'Delete',
    'common.edit': 'Edit',
    'common.back': 'Back',
    'common.close': 'Close',
    'common.loading': 'Loading data...',
    'common.search': 'Search',
    'common.actions': 'Actions',
    'common.status': 'Status',
    'common.filter': 'Filter',
    'common.all': 'All',
    'common.active': 'Active',
    'common.inactive': 'Inactive',
    'common.banned': 'Banned',
    'common.success': 'Success',
    'common.error': 'An error occurred',
    'common.confirm': 'Confirm',

    // Topbar
    'topbar.searchPlaceholder': 'Search records, videos, users, channels...',
    'topbar.dateRange': 'Last 30 days',
    'topbar.notifications': 'notifications',
    'topbar.adminRole': 'Administrator',
    'topbar.theme': 'Appearance',
    'topbar.themeLight': 'Light Mode',
    'topbar.themeDark': 'Dark Mode',
    'topbar.language': 'Language',

    // Navigation Groups & Items
    'nav.expand': 'Expand sidebar',
    'nav.collapse': 'Collapse sidebar',
    'nav.closeMenu': 'Close menu',
    'nav.openMenu': 'Open menu',
    'nav.dashboard': 'Overview',
    'nav.groupUser': 'Users',
    'nav.userList': 'User Directory',
    'nav.roleList': 'Roles & Permissions',
    'nav.groupContent': 'Content',
    'nav.channels': 'Channels',
    'nav.videos': 'Videos',
    'nav.topics': 'Topics & Tags',
    'nav.groupModeration': 'Moderation',
    'nav.videoQueue': 'Video Queue',
    'nav.reports': 'Violation Reports',
    'nav.appeals': 'Appeals',
    'nav.warnings': 'Warnings & Strikes',
    'nav.groupBusiness': 'Commercial',
    'nav.plans': 'Plans',
    'nav.subscriptions': 'Subscriptions',
    'nav.payments': 'Revenue & Billing',
    'nav.groupSystem': 'System',
    'nav.notificationsNav': 'System Broadcasts',
    'nav.statistics': 'Analytics & Reports',
    'nav.systemLogs': 'Logs & Configuration',

    // Admin Users Page
    'users.title': 'User Management',
    'users.subtitle': 'Inspect, search, assign roles and manage HuTube user accounts',
    'users.search': 'Search by email, display name or username...',
    'users.filterRole': 'Filter by role',
    'users.filterStatus': 'Filter by status',
    'users.colUser': 'User',
    'users.colRole': 'Role',
    'users.colStatus': 'Status',
    'users.colEmailVerified': 'Email Verified',
    'users.colCreatedAt': 'Joined Date',
    'users.colActions': 'Actions',
    'users.verified': 'Verified',
    'users.unverified': 'Unverified',
    'users.actionBan': 'Suspend account',
    'users.actionUnban': 'Reactivate account',
    'users.actionEditRole': 'Change role',
    'users.empty': 'No matching users found.',

    // Admin RBAC Page
    'rbac.title': 'Roles & Permissions (RBAC)',
    'rbac.subtitle': 'Configure granular permission matrices for administrative and platform roles',
    'rbac.rolesTitle': 'Role List',
    'rbac.createRole': 'Create new role',
    'rbac.permissionsMatrix': 'Permission Matrix',
    'rbac.saveMatrix': 'Save matrix changes',
    'rbac.roleName': 'Role Name',
    'rbac.roleDescription': 'Description',
    'rbac.userCount': 'User count',
    'rbac.permission': 'Permission',

    // Account & Profile
    'account.title': 'Admin Account',
    'account.tabProfile': 'Personal Profile',
    'account.tabPassword': 'Password & Security',
    'account.tabPreferences': 'Appearance & Settings',
    'account.tabSessions': 'Active Sessions',
    'account.themeLabel': 'Display Appearance (Color Mode)',
    'account.themeLight': 'Light Mode (Default)',
    'account.themeDark': 'Dark Mode (Comfortable)',
    'account.langLabel': 'Admin Language',

    // Forbidden Page
    'forbidden.title': 'Access Denied (403)',
    'forbidden.desc': 'Your account lacks sufficient permissions to access this administrative section.',
    'forbidden.back': 'Back to Admin Portal',

    // Auth
    'auth.loginTitle': 'Sign in to HuTube Admin',
    'auth.email': 'Admin Email',
    'auth.password': 'Password',
    'auth.loginBtn': 'Sign In to Portal',
    'auth.logout': 'Sign Out'
  }
};

@Injectable({
  providedIn: 'root'
})
export class I18nService {
  private readonly STORAGE_KEY = 'hutube_admin_lang';
  readonly currentLang = signal<AppLang>('vi');

  constructor() {
    const saved = localStorage.getItem(this.STORAGE_KEY) as AppLang | null;
    const globalSaved = localStorage.getItem('hutube_lang') as AppLang | null;
    const initial = saved || globalSaved;

    if (initial === 'vi' || initial === 'en') {
      this.currentLang.set(initial);
    }
  }

  setLang(lang: AppLang): void {
    if (lang === 'vi' || lang === 'en') {
      this.currentLang.set(lang);
      localStorage.setItem(this.STORAGE_KEY, lang);
      localStorage.setItem('hutube_lang', lang);
    }
  }

  t(key: string, params?: Record<string, string>): string {
    const lang = this.currentLang();
    let text = DICTIONARY[lang]?.[key] ?? DICTIONARY['vi']?.[key] ?? key;
    if (params) {
      for (const [k, v] of Object.entries(params)) {
        text = text.replace(new RegExp(`{${k}}`, 'g'), v);
      }
    }
    return text;
  }
}
