import 'package:flutter/widgets.dart';

class AppStrings {
  static final ValueNotifier<String> currentLang = ValueNotifier<String>('vi');

  static void setLanguage(String lang) {
    if (lang == 'vi' || lang == 'en') {
      currentLang.value = lang;
    }
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      // Common
      'common.save': 'Lưu thay đổi',
      'common.saving': 'Đang lưu...',
      'common.cancel': 'Hủy',
      'common.delete': 'Xóa',
      'common.edit': 'Chỉnh sửa',
      'common.back': 'Quay lại',
      'common.close': 'Đóng',
      'common.loading': 'Đang tải...',
      'common.retry': 'Thử lại',
      'common.error': 'Đã có lỗi xảy ra.',
      'common.success': 'Thành công',
      'common.logout': 'Đăng xuất',

      // Navigation / App Shell
      'nav.home': 'Trang chủ',
      'nav.subscriptions': 'Đăng ký',
      'nav.library': 'Thư viện',
      'nav.account': 'Tài khoản',
      'nav.explore': 'Khám phá',
      'nav.upload': 'Đăng video',
      'nav.profile': 'Hồ sơ',

      // Account & Profile
      'profile.title': 'Tài khoản của bạn',
      'profile.editProfile': 'Chỉnh sửa hồ sơ',
      'profile.preferences': 'Cài đặt & Giao diện',
      'profile.password': 'Đổi mật khẩu',
      'profile.notifications': 'Thông báo',
      'profile.sessions': 'Thiết bị & Phiên đăng nhập',
      'profile.channel': 'Kênh của bạn',
      'profile.createChannel': 'Tạo kênh mới',
      'profile.channelInvitations': 'Lời mời quản trị kênh',
      'profile.bioPlaceholder': 'Chưa cập nhật tiểu sử.',
      'profile.country': 'Quốc gia',
      'profile.emailVerified': 'Email đã xác minh',
      'profile.emailUnverified': 'Email chưa xác minh',
      'profile.resendVerification': 'Gửi lại xác minh',

      // Sessions
      'session.unknownDevice': 'Thiết bị không rõ',
      'session.unknownIp': 'Chưa rõ IP',
      'session.current': 'Hiện tại',
      'session.revoke': 'Thu hồi phiên',

      // Preferences Screen
      'prefs.title': 'Cài đặt & Giao diện',
      'prefs.themeHeading': 'Giao diện ứng dụng',
      'prefs.themeSystem': 'Hệ thống',
      'prefs.themeLight': 'Sáng',
      'prefs.themeDark': 'Tối',
      'prefs.langHeading': 'Ngôn ngữ hiển thị',
      'prefs.langVi': 'Tiếng Việt (VI)',
      'prefs.langEn': 'English (EN)',
      'prefs.playbackHeading': 'Phát video',
      'prefs.autoplay': 'Tự động phát video tiếp theo',
      'prefs.autoplaySub': 'Tiếp tục phát các video liên quan khi video hiện tại kết thúc.',
      'prefs.quality': 'Chất lượng video mặc định',
      'prefs.qualitySub': 'Áp dụng khi xem video',
      'prefs.privacyHeading': 'Quyền riêng tư',
      'prefs.subsPrivate': 'Giữ các kênh đã đăng ký riêng tư',
      'prefs.subsPrivateSub': 'Không hiển thị danh sách kênh bạn đăng ký trên trang cá nhân.',
      'prefs.playlistsPrivate': 'Giữ danh sách phát đã lưu riêng tư',
      'prefs.playlistsPrivateSub': 'Chỉ bạn mới có thể xem các playlist đã tạo và lưu.',
      'prefs.autoSaving': 'Đang tự động lưu...',
      'prefs.loadError': 'Không thể tải cài đặt & giao diện.',
      'prefs.saveError': 'Không thể lưu cài đặt.',

      // Edit Profile
      'editProfile.title': 'Chỉnh sửa hồ sơ',
      'editProfile.displayName': 'Tên hiển thị',
      'editProfile.bio': 'Tiểu sử',
      'editProfile.country': 'Quốc gia',
      'editProfile.changeAvatar': 'Đổi ảnh đại diện',
      'editProfile.saveBtn': 'Lưu hồ sơ',

      // Change Password
      'password.title': 'Đổi mật khẩu',
      'password.current': 'Mật khẩu hiện tại',
      'password.new': 'Mật khẩu mới',
      'password.confirm': 'Xác nhận mật khẩu mới',
      'password.updateBtn': 'Cập nhật mật khẩu',

      // Notifications Settings
      'notif.title': 'Cài đặt thông báo',
      'notif.newVideos': 'Video mới từ kênh đã đăng ký',
      'notif.comments': 'Bình luận và phản hồi',
      'notif.subs': 'Người đăng ký mới',
      'notif.marketing': 'Cập nhật tính năng và tin tức HuTube',

      // Auth
      'auth.loginTitle': 'Đăng nhập vào HuTube',
      'auth.registerTitle': 'Tạo tài khoản HuTube mới',
      'auth.email': 'Email',
      'auth.password': 'Mật khẩu',
      'auth.loginBtn': 'Đăng nhập',
      'auth.registerBtn': 'Đăng ký ngay',
    },

    'en': {
      // Common
      'common.save': 'Save changes',
      'common.saving': 'Saving...',
      'common.cancel': 'Cancel',
      'common.delete': 'Delete',
      'common.edit': 'Edit',
      'common.back': 'Back',
      'common.close': 'Close',
      'common.loading': 'Loading...',
      'common.retry': 'Retry',
      'common.error': 'An error occurred.',
      'common.success': 'Success',
      'common.logout': 'Sign out',

      // Navigation / App Shell
      'nav.home': 'Home',
      'nav.subscriptions': 'Subscriptions',
      'nav.library': 'Library',
      'nav.account': 'Account',
      'nav.explore': 'Explore',
      'nav.upload': 'Upload Video',
      'nav.profile': 'Profile',

      // Account & Profile
      'profile.title': 'Your Account',
      'profile.editProfile': 'Edit Profile',
      'profile.preferences': 'Appearance & Preferences',
      'profile.password': 'Change Password',
      'profile.notifications': 'Notifications',
      'profile.sessions': 'Devices & Active Sessions',
      'profile.channel': 'Your Channel',
      'profile.createChannel': 'Create New Channel',
      'profile.channelInvitations': 'Channel Invitations',
      'profile.bioPlaceholder': 'No bio added yet.',
      'profile.country': 'Country',
      'profile.emailVerified': 'Email Verified',
      'profile.emailUnverified': 'Email Unverified',
      'profile.resendVerification': 'Resend Verification',

      // Sessions
      'session.unknownDevice': 'Unknown device',
      'session.unknownIp': 'Unknown IP',
      'session.current': 'Current',
      'session.revoke': 'Revoke session',

      // Preferences Screen
      'prefs.title': 'Appearance & Preferences',
      'prefs.themeHeading': 'App Appearance',
      'prefs.themeSystem': 'System',
      'prefs.themeLight': 'Light',
      'prefs.themeDark': 'Dark',
      'prefs.langHeading': 'Display Language',
      'prefs.langVi': 'Tiếng Việt (VI)',
      'prefs.langEn': 'English (EN)',
      'prefs.playbackHeading': 'Video Playback',
      'prefs.autoplay': 'Autoplay next video',
      'prefs.autoplaySub': 'Continue playing related videos when current video ends.',
      'prefs.quality': 'Default Video Quality',
      'prefs.qualitySub': 'Applied when streaming videos',
      'prefs.privacyHeading': 'Privacy',
      'prefs.subsPrivate': 'Keep my subscriptions private',
      'prefs.subsPrivateSub': 'Do not display subscribed channels on public profile.',
      'prefs.playlistsPrivate': 'Keep saved playlists private',
      'prefs.playlistsPrivateSub': 'Only you can view your created and saved playlists.',
      'prefs.autoSaving': 'Auto-saving changes...',
      'prefs.loadError': 'Unable to load preferences.',
      'prefs.saveError': 'Failed to save preferences.',

      // Edit Profile
      'editProfile.title': 'Edit Profile',
      'editProfile.displayName': 'Display Name',
      'editProfile.bio': 'Bio',
      'editProfile.country': 'Country',
      'editProfile.changeAvatar': 'Change Avatar',
      'editProfile.saveBtn': 'Save Profile',

      // Change Password
      'password.title': 'Change Password',
      'password.current': 'Current Password',
      'password.new': 'New Password',
      'password.confirm': 'Confirm New Password',
      'password.updateBtn': 'Update Password',

      // Notifications Settings
      'notif.title': 'Notification Preferences',
      'notif.newVideos': 'New videos from subscribed channels',
      'notif.comments': 'Comments and replies',
      'notif.subs': 'New subscribers',
      'notif.marketing': 'Feature updates and announcements',

      // Auth
      'auth.loginTitle': 'Sign in to HuTube',
      'auth.registerTitle': 'Create your HuTube account',
      'auth.email': 'Email',
      'auth.password': 'Password',
      'auth.loginBtn': 'Sign In',
      'auth.registerBtn': 'Sign Up',
    }
  };

  static String t(String key) {
    final lang = currentLang.value;
    return _localizedValues[lang]?[key] ?? _localizedValues['vi']?[key] ?? key;
  }
}

extension AppStringsExtension on BuildContext {
  String tr(String key) => AppStrings.t(key);
}
