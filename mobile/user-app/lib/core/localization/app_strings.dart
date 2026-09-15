import 'dart:async';

import 'package:flutter/widgets.dart';

import '../errors/app_error.dart';
import '../storage/app_preferences.dart';

class AppStrings {
  static final ValueNotifier<String> currentLang = ValueNotifier<String>('vi');
  static const _preferences = AppPreferencesStore();

  static Future<void> restore() async {
    try {
      final language = await _preferences.readLanguage();
      if (language != null && (language == 'vi' || language == 'en')) {
        currentLang.value = language;
      }
    } catch (_) {
      // A storage failure must not prevent the app from starting in Vietnamese.
    }
  }

  static void setLanguage(String lang) {
    if (lang == 'vi' || lang == 'en') {
      currentLang.value = lang;
      unawaited(_persistLanguage(lang));
    }
  }

  static Future<void> _persistLanguage(String language) async {
    try {
      await _preferences.writeLanguage(language);
    } catch (_) {
      // Language switching remains available for the current run.
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
      'profile.channelInvitations': 'Lời mời cộng tác',
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
      'prefs.autoplaySub':
          'Tiếp tục phát các video liên quan khi video hiện tại kết thúc.',
      'prefs.quality': 'Chất lượng video mặc định',
      'prefs.qualitySub': 'Áp dụng khi xem video',
      'prefs.privacyHeading': 'Quyền riêng tư',
      'prefs.subsPrivate': 'Giữ các kênh đã đăng ký riêng tư',
      'prefs.subsPrivateSub':
          'Không hiển thị danh sách kênh bạn đăng ký trên trang cá nhân.',
      'prefs.playlistsPrivate': 'Giữ danh sách phát đã lưu riêng tư',
      'prefs.playlistsPrivateSub':
          'Chỉ bạn mới có thể xem các playlist đã tạo và lưu.',
      'prefs.autoSaving': 'Đang tự động lưu...',
      'prefs.loadError': 'Không thể tải cài đặt & giao diện.',
      'prefs.saveError': 'Không thể lưu cài đặt.',
      'prefs.saved': 'Đã lưu tùy chọn người dùng.',
      'prefs.qualityAuto': 'Tự động',

      // Edit Profile
      'editProfile.title': 'Chỉnh sửa hồ sơ',
      'editProfile.displayName': 'Tên hiển thị',
      'editProfile.bio': 'Tiểu sử',
      'editProfile.country': 'Quốc gia',
      'editProfile.region': 'Khu vực',
      'editProfile.changeAvatar': 'Đổi ảnh đại diện',
      'editProfile.saveBtn': 'Lưu hồ sơ',
      'editProfile.saveError':
          'Không thể lưu thông tin hồ sơ. Vui lòng thử lại.',
      'editProfile.displayNameRequired': 'Tên hiển thị không được để trống.',
      'editProfile.countryVietnam': 'Việt Nam',
      'editProfile.countryUs': 'Hoa Kỳ',
      'editProfile.countryJapan': 'Nhật Bản',
      'editProfile.countryKorea': 'Hàn Quốc',
      'editProfile.countrySingapore': 'Singapore',
      'editProfile.countryOther': 'Khác',

      // Change Password
      'password.title': 'Đổi mật khẩu',
      'password.current': 'Mật khẩu hiện tại',
      'password.new': 'Mật khẩu mới',
      'password.confirm': 'Xác nhận mật khẩu mới',
      'password.updateBtn': 'Cập nhật mật khẩu',
      'password.currentRequired': 'Vui lòng nhập mật khẩu hiện tại.',
      'password.newRequirement': 'Mật khẩu mới phải có tối thiểu 8 ký tự.',
      'password.mismatch': 'Mật khẩu xác nhận không khớp.',
      'password.error': 'Không thể đổi mật khẩu. Vui lòng thử lại.',

      // Notifications Settings
      'notif.title': 'Cài đặt thông báo',
      'notif.newVideos': 'Video mới từ kênh đã đăng ký',
      'notif.comments': 'Bình luận và phản hồi',
      'notif.subs': 'Người đăng ký mới',
      'notif.marketing': 'Cập nhật tính năng và tin tức HuTube',
      'notif.newVideosDesc':
          'Nhận thông báo khi kênh bạn theo dõi xuất bản video mới.',
      'notif.commentsDesc':
          'Thông báo về hoạt động trên bình luận và video của bạn.',
      'notif.subsDesc': 'Nhận tóm tắt về hoạt động của các kênh bạn quan tâm.',
      'notif.marketingDesc': 'Nhận tin tức về các tính năng mới từ HuTube.',
      'notif.autoSaving': 'Đang tự động lưu...',
      'notif.loadError': 'Không thể tải cài đặt thông báo.',
      'notif.saveError': 'Không thể lưu cài đặt.',

      // Auth
      'auth.loginTitle': 'Đăng nhập vào HuTube',
      'auth.registerTitle': 'Tạo tài khoản HuTube mới',
      'auth.email': 'Email',
      'auth.password': 'Mật khẩu',
      'auth.loginBtn': 'Đăng nhập',
      'auth.registerBtn': 'Đăng ký ngay',

      // Shared app chrome
      'common.networkError': 'Không thể kết nối. Kiểm tra mạng rồi thử lại.',
      'common.serverError': 'Máy chủ đang bận. Vui lòng thử lại sau.',
      'common.confirm': 'Xác nhận',
      'common.yes': 'Có',
      'common.no': 'Không',
      'common.share': 'Chia sẻ',
      'common.download': 'Tải xuống',
      'common.send': 'Gửi',
      'common.reply': 'Trả lời',
      'common.search': 'Tìm kiếm',
      'common.notifications': 'Thông báo',
      'common.policy': 'Chính sách',
      'common.menu': 'Mở menu',
      'common.account': 'Tài khoản',
      'common.signIn': 'Đăng nhập',
      'common.create': 'Tạo',
      'common.open': 'Mở',
      'common.all': 'Tất cả',
      'common.copied': 'Đã sao chép.',
      'common.user': 'Người dùng',
      'common.userHuTube': 'Người dùng HuTube',
      'common.appName': 'HuTube',

      // App shell and feed
      'app.restoreSession': 'Đang khôi phục phiên đăng nhập…',
      'app.opening': 'Đang mở HuTube…',
      'app.viewVideo': 'Xem video',
      'app.connection': 'Kiểm tra kết nối',
      'app.connected': 'Đã kết nối HuTube · {environment}',
      'app.apiActive': 'API đang hoạt động',
      'app.navYou': 'Bạn',
      'app.librarySection': 'THƯ VIỆN',
      'app.otherSection': 'KHÁC',
      'app.modulePending':
          '{label} sẽ được kết nối khi module tương ứng hoàn tất.',
      'feed.homeTitle': 'Dành cho bạn',
      'feed.homeDescription': 'Video mới và nổi bật từ cộng đồng HuTube.',
      'feed.exploreTitle': 'Khám phá',
      'feed.exploreDescription':
          'Chọn chủ đề để tìm nội dung mới trong cộng đồng HuTube.',
      'feed.empty': 'Chưa có video phù hợp.',
      'feed.loadError': 'Không thể tải video. Kiểm tra kết nối rồi thử lại.',
      'feed.openVideo': 'Mở video {title}',
      'feed.views': '{count} lượt xem',
      'feed.today': 'Hôm nay',
      'feed.daysAgo': '{count} ngày trước',
      'feed.sortNewest': 'Mới nhất',
      'feed.sortPopular': 'Phổ biến',
      'feed.sortTrending': 'Thịnh hành',
      'feed.allTopics': 'Tất cả chủ đề',

      // Library and downloads
      'library.title': 'Thư viện',
      'library.history': 'Lịch sử',
      'library.liked': 'Đã thích',
      'library.allRatings': 'Tất cả',
      'library.ratingStars': '{count} sao',
      'library.empty': 'Chưa có video trong mục này.',
      'library.loadError':
          'Không thể tải thư viện. Kiểm tra kết nối rồi thử lại.',
      'downloads.title': 'Bản tải xuống',
      'downloads.empty': 'Chưa có video tải xuống.',
      'downloads.queued': 'Đang chờ',
      'downloads.downloading': 'Đang tải {percent}%',
      'downloads.completed': 'Đã lưu trên thiết bị',
      'downloads.paused': 'Đã tạm dừng',
      'downloads.failed': 'Tải thất bại',
      'downloads.remove': 'Xóa khỏi thiết bị',
      'downloads.error': 'Không thể tải video xuống.',

      // Watch and offline playback
      'watch.loadError': 'Không thể tải video này. Vui lòng thử lại.',
      'watch.videoUnavailable': 'Video không khả dụng.',
      'watch.invalidSource':
          'Nguồn video không hợp lệ. Máy chủ cần trả về URL HTTP(S).',
      'watch.playerError': 'Không thể phát nguồn video này.',
      'watch.pipUnsupported':
          'Thiết bị hiện không hỗ trợ PiP cho nguồn video này.',
      'watch.loginInteract': 'Đăng nhập để tương tác với video.',
      'watch.loginRate': 'Đăng nhập để đánh giá video.',
      'watch.ratingTitle': 'Đánh giá video',
      'watch.ratingStars': '{count} sao',
      'watch.ratingSaved': 'Đã cập nhật đánh giá của bạn.',
      'watch.shareText': 'Xem {title} trên HuTube\nhutube://watch/{id}',
      'watch.loginDownload': 'Đăng nhập để tải video xuống.',
      'watch.downloadQuality': 'Chọn chất lượng tải xuống',
      'watch.downloadAdded': 'Đã thêm vào danh sách tải xuống trên thiết bị.',
      'watch.viewsAndChannel': '{views} lượt xem · {channel}',
      'watch.rateAction': 'Đánh giá',
      'watch.shareAction': 'Chia sẻ',
      'watch.downloadAction': 'Tải xuống',
      'watch.pipAction': 'PiP',
      'watch.background': 'Phát nền',
      'watch.chapters': 'Chương',
      'watch.comments': 'Bình luận ({count})',
      'watch.commentHint': 'Viết bình luận...',
      'watch.loginCommentHint': 'Đăng nhập để bình luận',
      'watch.sending': 'Đang gửi...',
      'watch.commentAction': 'Bình luận',
      'watch.related': 'Video liên quan',
      'watch.replyTitle': 'Trả lời {name}',
      'watch.replyHint': 'Viết phản hồi của bạn',
      'watch.replies': '{count} câu trả lời',
      'watch.repliesLoading': 'Đang tải...',
      'offline.missingFile': 'Không tìm thấy file trên thiết bị.',
      'offline.openError': 'Không thể mở file video này.',
      'offline.pipTooltip': 'Picture-in-Picture',
      'offline.pipUnsupported': 'Thiết bị không hỗ trợ PiP cho video này.',
      'offline.backgroundAvailable': 'Phát nền đang khả dụng cho gói của bạn',

      // Account and profile
      'account.hubTitle': 'Bạn',
      'account.heading': 'Tài khoản',
      'account.channelHeading': 'Kênh của bạn',
      'account.serviceHeading': 'Gói dịch vụ',
      'account.editProfile': 'Chỉnh sửa hồ sơ',
      'account.passwordSecurity': 'Mật khẩu và bảo mật',
      'account.appearance': 'Tùy chọn giao diện',
      'account.notificationSettings': 'Cài đặt thông báo',
      'account.checkingChannel': 'Đang kiểm tra kênh…',
      'account.createChannel': 'Tạo kênh',
      'account.createChannelDesc': 'Bắt đầu đăng video với một kênh HuTube.',
      'account.invitations': 'Lời mời cộng tác',
      'account.creatorStudio': 'Creator Studio',
      'account.plans': 'Gói và dung lượng',
      'account.editTooltip': 'Chỉnh sửa hồ sơ',
      'account.profileLoadError': 'Không thể tải hồ sơ để chỉnh sửa.',
      'account.logout': 'Đăng xuất',
      'profile.headerTitle': 'Tài khoản của bạn',
      'profile.channelView': 'Xem kênh',
      'profile.channelManage': 'Quản lý',
      'profile.noChannelTitle': 'Bạn chưa có kênh HuTube',
      'profile.noChannelDescription':
          'Tạo kênh để xuất bản video, xây dựng cộng đồng và tiếp cận hàng triệu khán giả.',
      'profile.createNow': 'Tạo kênh ngay',
      'profile.sessionsHeading': 'Thiết bị đăng nhập',
      'profile.refreshDevices': 'Tải lại thiết bị',
      'profile.sessionsDescription':
          'Thu hồi phiên trên thiết bị bạn không còn sử dụng.',
      'profile.sessionsEmpty': 'Chưa tải được danh sách thiết bị.',
      'profile.logoutOthers': 'Đăng xuất thiết bị khác',
      'profile.logoutAll': 'Đăng xuất mọi thiết bị',
      'profile.logout': 'Đăng xuất',
      'profile.sessionRevoked': 'Đã thu hồi phiên đăng nhập.',
      'profile.sessionRevokeError': 'Không thể thu hồi phiên đăng nhập.',
      'profile.otherDevicesLogoutError':
          'Không thể đăng xuất các thiết bị khác.',
      'profile.updated': 'Đã cập nhật thông tin hồ sơ thành công!',
      'profile.avatarError': 'Không thể cập nhật ảnh đại diện.',
      'editProfile.displayNameHint': 'Nhập tên hiển thị của bạn',
      'editProfile.bioHint': 'Chia sẻ ngắn gọn về bạn với cộng đồng HuTube...',
      'editProfile.noCountry': 'Chưa chọn quốc gia',
      'password.updated': 'Đổi mật khẩu thành công!',
      'password.currentHint': 'Nhập mật khẩu đang sử dụng',
      'password.newHint': 'Tối thiểu 10 ký tự',
      'password.confirmHint': 'Nhập lại mật khẩu mới',
      'notifications.videoUpdates': 'Video mới từ kênh đã đăng ký',
      'notifications.videoUpdatesDesc':
          'Nhận thông báo khi kênh bạn theo dõi đăng video mới.',
      'notifications.comments': 'Bình luận và phản hồi',
      'notifications.commentsDesc':
          'Nhận thông báo về bình luận và câu trả lời liên quan đến bạn.',
      'notifications.channelActivity': 'Hoạt động kênh đăng ký',
      'notifications.channelActivityDesc':
          'Nhận cập nhật từ các kênh bạn đang theo dõi.',
      'notifications.marketing': 'Email thông tin và cập nhật',
      'notifications.marketingDesc':
          'Nhận tin tức về các tính năng mới từ HuTube.',
      'notifications.settingsSaved': 'Đã lưu cài đặt thông báo.',

      // Auth form
      'auth.welcome': 'Chào mừng trở lại',
      'auth.loginDescription': 'Đăng nhập để tiếp tục với tài khoản của bạn.',
      'auth.registerDescription':
          'Bắt đầu với HuTube. Xác minh email để bảo vệ tài khoản của bạn.',
      'auth.forgotTitle': 'Quên mật khẩu?',
      'auth.forgotDescription': 'Nhập email bạn đã dùng để đăng ký HuTube.',
      'auth.verifyTitle': 'Xác minh email',
      'auth.verifyDescription': 'Xác nhận địa chỉ email để hoàn tất đăng ký.',
      'auth.verifyMissing':
          'Liên kết thiếu mã xác minh. Hãy yêu cầu một email mới.',
      'auth.resetTitle': 'Đặt mật khẩu mới',
      'auth.resetDescription':
          'Chọn mật khẩu mới, khác mật khẩu bạn dùng ở nơi khác.',
      'auth.resetMissing':
          'Liên kết thiếu mã đặt lại. Hãy yêu cầu một email mới.',
      'auth.resendTitle': 'Gửi lại email xác minh',
      'auth.resendDescription': 'Nhập email bạn đã dùng để đăng ký HuTube.',
      'auth.displayNameField': 'Tên hiển thị',
      'auth.usernameField': 'Tên người dùng',
      'auth.emailField': 'Email',
      'auth.passwordField': 'Mật khẩu',
      'auth.newPasswordField': 'Mật khẩu mới',
      'auth.confirmPasswordField': 'Nhập lại mật khẩu',
      'auth.displayNameInvalid': 'Nhập tên hiển thị từ 1 đến 120 ký tự.',
      'auth.usernameInvalid':
          '3–50 ký tự: chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.',
      'auth.emailInvalid': 'Nhập địa chỉ email hợp lệ.',
      'auth.passwordRequired': 'Nhập mật khẩu của bạn.',
      'auth.passwordRequirement':
          '10–128 ký tự, gồm chữ hoa, chữ thường và số.',
      'auth.passwordMismatch': 'Mật khẩu nhập lại chưa khớp.',
      'auth.forgotLink': 'Quên mật khẩu?',
      'auth.loginSuccess': 'Đăng nhập thành công.',
      'auth.registerSuccess':
          'Tài khoản đã được tạo. Mở email để xác minh, sau đó đăng nhập.',
      'auth.verifySuccess':
          'Email đã được xác minh. Bạn có thể đăng nhập ngay.',
      'auth.resetSuccess':
          'Mật khẩu đã được đổi. Hãy đăng nhập bằng mật khẩu mới.',
      'auth.forgotSuccess':
          'Nếu email thuộc tài khoản HuTube, bạn sẽ nhận được liên kết đặt lại mật khẩu.',
      'auth.resendSuccess':
          'Nếu tài khoản cần xác minh, chúng tôi đã gửi lại email. Kiểm tra cả thư rác.',
      'auth.accountMessage': 'Đăng nhập để tiếp tục đến tài khoản của bạn.',
      'auth.linkError': 'Không thể mở liên kết. Vui lòng thử lại.',
      'auth.googleCancelled': 'Bạn đã hủy đăng nhập Google.',
      'auth.googleInvalid':
          'Không thể hoàn tất đăng nhập Google. Vui lòng thử lại.',
      'auth.googleUnavailable':
          'Đăng nhập Google chưa khả dụng trên thiết bị này.',
      'auth.invalidCredentials': 'Email hoặc mật khẩu không đúng.',
      'auth.emailNotVerified': 'Email chưa được xác minh.',
      'auth.accountSuspended': 'Tài khoản đang bị tạm khóa.',
      'auth.accountBanned': 'Tài khoản đã bị khóa.',
      'auth.continueGoogle': 'Tiếp tục với Google',
      'auth.showPassword': 'Hiện mật khẩu',
      'auth.hidePassword': 'Ẩn mật khẩu',
      'auth.saveNewPassword': 'Lưu mật khẩu mới',
      'auth.sendEmail': 'Gửi email',
      'auth.createAccount': 'Tạo tài khoản',
      'auth.resendVerification': 'Gửi lại email xác minh',
      'auth.restoreAgain': 'Thử khôi phục phiên lần nữa',
      'auth.requestNewLink': 'Yêu cầu liên kết mới',
      'auth.backToLogin': 'Quay lại đăng nhập',
      'auth.noAccount': 'Chưa có tài khoản? Đăng ký',
      'auth.otherDevicesLoggedOut': 'Đã đăng xuất tất cả thiết bị khác.',
      'auth.allDevicesLoggedOut': 'Đã đăng xuất khỏi tất cả thiết bị.',
      'auth.sessionExpired': 'Phiên đã hết hạn. Vui lòng đăng nhập lại.',
      'auth.storageError': 'Không thể mở bộ nhớ bảo mật. Vui lòng thử lại.',
      'auth.logoutOffline':
          'Đã thoát trên thiết bị. Chưa thể xác nhận thu hồi phiên trên máy chủ.',

      // Channel and collaboration
      'channel.title': 'Kênh',
      'channel.retry': 'Thử lại',
      'channel.copied': 'Đã sao chép liên kết kênh vào bộ nhớ tạm',
      'channel.manage': 'Quản lý kênh và Cài đặt',
      'channel.view': 'Xem kênh',
      'channel.subscribe': 'Đăng ký',
      'channel.subscribed': 'Đã đăng ký',
      'channel.home': 'Trang chủ',
      'channel.videos': 'Video',
      'channel.playlists': 'Danh sách phát',
      'channel.subscriberCount': '{count} người đăng ký',
      'channel.videoCount': '{count} video',
      'channel.viewCount': '{count} lượt xem',
      'channel.descriptionEmpty': 'Kênh chưa có mô tả.',
      'channel.emptyVideos': 'Kênh chưa có video công khai.',
      'channel.about': 'Giới thiệu',
      'channel.otherInfo': 'Thông tin khác',
      'channel.joinWelcome': 'Chào mừng bạn đến với kênh {name} trên HuTube!',
      'channel.joinDescription':
          'Giới thiệu nội dung và định hướng kênh {name}',
      'channel.guide': 'Hướng dẫn sử dụng nền tảng video HuTube toàn tập',
      'channel.stats': '{subscribers} người đăng ký · {videos} video',
      'channel.changeBanner': 'Đổi ảnh bìa',
      'channel.notFound': 'Kênh không tồn tại hoặc đã bị xóa.',
      'channel.subscribedToast': 'Đã đăng ký kênh',
      'channel.unsubscribedToast': 'Đã hủy đăng ký kênh',
      'channel.latestVideo': 'Video mới nhất',
      'channel.welcomeVideo': 'Chào mừng bạn đến với kênh {name} trên HuTube!',
      'channel.recent': 'Gần đây',
      'channel.introVideo': 'Giới thiệu nội dung và định hướng kênh {name}',
      'channel.tutorialVideo':
          'Hướng dẫn sử dụng nền tảng video HuTube toàn tập',
      'channel.daysAgo': '{count} ngày trước',
      'channel.weekAgo': '1 tuần trước',
      'channel.noPlaylists': 'Chưa có danh sách phát nào',
      'channel.description': 'Mô tả',
      'channel.descriptionEmptyLong': 'Kênh này chưa thêm mô tả chi tiết.',
      'channel.detailedInfo': 'Thông tin chi tiết',
      'channel.channelUrl': 'hutube.app/@{handle}',
      'channel.uploadedVideos': '{count} video đã đăng tải',
      'channel.totalViews': '{count} tổng lượt xem',
      'channel.joined': 'Đã tham gia: {date}',
      'channel.invitationExpiryUnknown': 'Hạn mời không xác định',
      'channel.invitationExpiry': 'Hết hạn {date} lúc {time}',
      'channel.invitationRevokeDescription':
          'Lời mời đến {email} sẽ không còn hiệu lực.',
      'channel.revokeInvitationTooltip': 'Thu hồi lời mời',
      'channel.noPendingInvitations': 'Chưa có lời mời nào đang chờ.',
      'channel.unknownEmail': 'Email chưa xác định',
      'channel.emailInvalid': 'Vui lòng nhập email hợp lệ.',
      'channel.nameEmpty': 'Tên kênh không được để trống.',
      'channel.imageReadError':
          'Không thể đọc hoặc tải ảnh lên. Vui lòng chọn ảnh khác.',
      'channel.brandingTitle': 'Hình ảnh kênh',
      'channel.brandingDescription':
          'Ảnh JPG, PNG hoặc WEBP. Ảnh đại diện tối đa 5MB, ảnh bìa tối đa 10MB.',
      'channel.currentBannerSemantic': 'Ảnh bìa kênh hiện tại',
      'channel.uploadingBanner': 'Đang tải ảnh bìa…',
      'channel.uploadingAvatar': 'Đang tải ảnh đại diện…',
      'channel.changeAvatar': 'Đổi ảnh đại diện',
      'channel.basicInfo': 'Thông tin cơ bản',
      'channel.nameHint': 'Nhập tên kênh',
      'channel.handleImmutable': 'Handle không thể thay đổi sau khi tạo',
      'channel.descriptionHintEdit': 'Giới thiệu về kênh của bạn...',
      'channel.inviteHeading': 'Mời cộng tác viên',
      'channel.inviteDescription':
          'Người được mời có thể xem rõ phạm vi quyền trước khi chấp nhận.',
      'channel.dangerTitle': 'Vùng nguy hiểm',
      'channel.dangerDescription':
          'Xóa kênh sẽ chuyển kênh sang trạng thái đã xóa, ẩn các video và giải phóng handle của bạn. Sau khi xóa, bạn có thể tạo một kênh mới.',
      'channel.deleteThis': 'Xóa kênh này',
      'channel.confirmDeleteTitle': 'Xác nhận xóa kênh?',
      'channel.confirmDeleteDescription':
          'Hành động này sẽ ẩn kênh, danh sách video và handle của bạn khỏi HuTube.',
      'channel.confirmDeletePrompt':
          'Nhập chính xác tên kênh "{name}" để xác nhận:',
      'channel.confirmDeleteHint': 'Nhập tên kênh',
      'channel.confirmDeleteAction': 'Xác nhận xóa',
      'channel.deleteError': 'Không thể xóa kênh. Vui lòng thử lại sau.',
      'channel.roleManagerDescription':
          'Quản lý thành viên và nội dung theo quyền được cấp.',
      'channel.roleEditorDescription':
          'Tải lên, chỉnh sửa nội dung, danh sách phát và xem dữ liệu nội dung.',
      'channel.roleModeratorDescription':
          'Kiểm duyệt bình luận và nội dung theo quyền được cấp.',
      'channel.roleViewerDescription':
          'Xem dữ liệu và nội dung được chia sẻ của kênh.',
      'channel.processing': 'Đang xử lý…',
      'channel.joinedChannel': 'Đã tham gia kênh {name}.',
      'channel.pullToRefresh': 'Kéo xuống để kiểm tra lại.',
      'channel.createTitle': 'Tạo kênh mới',
      'channel.created': '🎉 Chúc mừng! Kênh của bạn đã được tạo thành công!',
      'channel.createName': 'Tên kênh',
      'channel.createNameHint': 'Ví dụ: Kênh Công Nghệ 24h',
      'channel.nameRequired': 'Tên kênh không được để trống.',
      'channel.createHandle': 'Handle',
      'channel.createHandleHint': 'congnghe24h',
      'channel.handleInvalid':
          'Handle chỉ được gồm chữ thường, số và dấu gạch ngang.',
      'channel.handleTaken':
          'Handle này đã được sử dụng. Hãy chọn handle khác.',
      'channel.handleAvailable': 'Handle khả dụng.',
      'channel.handleUnavailable': 'Handle chưa khả dụng.',
      'channel.handleDescription':
          'Handle sẽ tạo địa chỉ duy nhất cho kênh của bạn.',
      'channel.createDescription': 'Mô tả kênh',
      'channel.createDescriptionHint': 'Giới thiệu ngắn về kênh của bạn',
      'channel.descriptionHint': 'Giới thiệu ngắn về kênh của bạn',
      'channel.rulesTitle': 'Quy tắc tạo kênh',
      'channel.rulesDescription':
          'Mỗi tài khoản chỉ được sở hữu một kênh. Bạn có thể cộng tác trên các kênh được mời.',
      'channel.createAction': 'Tạo kênh',
      'channel.createError': 'Không thể tạo kênh. Vui lòng thử lại.',
      'channel.settingsTitle': 'Cài đặt kênh',
      'channel.updateSuccess': 'Cập nhật thông tin kênh thành công!',
      'channel.updateError': 'Cập nhật kênh thất bại.',
      'channel.avatarUpdated': 'Đã cập nhật ảnh đại diện kênh.',
      'channel.bannerUpdated': 'Đã cập nhật ảnh bìa kênh.',
      'channel.imageError': 'Tải ảnh lên thất bại.',
      'channel.deleteTitle': 'Xóa kênh?',
      'channel.deleteDescription':
          'Bạn có chắc muốn xóa kênh này? Thao tác này không thể hoàn tác.',
      'channel.deleteAction': 'Xóa kênh',
      'channel.deleteSuccess': 'Đã xóa kênh thành công.',
      'channel.invitationsTitle': 'Lời mời tham gia kênh',
      'channel.noInvitations': 'Bạn chưa có lời mời tham gia kênh nào.',
      'channel.accept': 'Chấp nhận',
      'channel.decline': 'Từ chối',
      'channel.accepted': 'Đã chấp nhận lời mời.',
      'channel.declined': 'Đã từ chối lời mời.',
      'channel.inviteRevoked': 'Đã thu hồi lời mời.',
      'channel.inviteSent': 'Đã gửi lời mời tham gia kênh.',
      'channel.inviteEmail': 'Email người dùng',
      'channel.inviteEmailHint': 'member@example.com',
      'channel.inviteRole': 'Vai trò',
      'channel.inviteAction': 'Gửi lời mời',
      'channel.pendingInvites': 'Lời mời đang chờ',
      'channel.members': 'Thành viên và quyền',
      'channel.owner': 'Chủ sở hữu',
      'channel.remove': 'Gỡ',
      'channel.revoke': 'Thu hồi',
      'channel.confirmRevoke': 'Thu hồi lời mời?',
      'channel.roleManager': 'Quản lý',
      'channel.roleEditor': 'Biên tập viên',
      'channel.roleModerator': 'Kiểm duyệt viên',
      'channel.roleViewer': 'Người xem',

      // Creator Studio
      'creator.title': 'Creator Studio',
      'creator.noChannel': 'Bạn chưa có kênh để quản lý.',
      'creator.invitedChannelTitle': 'Bạn đang được mời cộng tác',
      'creator.invitedChannelDescription':
          'Bạn có thể làm việc trên kênh được cấp quyền mà không cần tạo kênh riêng.',
      'creator.openInvitations': 'Xem lời mời cộng tác',
      'creator.createChannelPrompt': 'Muốn tạo kênh riêng?',
      'creator.channelSelector': 'Kênh đang quản lý',
      'creator.managedAs': '{name} · {role}',
      'creator.uploadDescription':
          'Tải video, kiểm tra quota và gửi kiểm duyệt khi công khai.',
      'creator.contentDescription': 'Xem và điều chỉnh video của kênh.',
      'creator.commentsDescription': 'Quản lý phản hồi trên video của bạn.',
      'creator.settingsDescription': 'Tên, mô tả, ảnh đại diện và ảnh bìa.',
      'creator.invitationsDescription': 'Mời và phản hồi lời mời thành viên.',
      'creator.subtitlesDescription':
          'Trạng thái phụ đề theo video; tính năng biên soạn đang được hoàn thiện.',
      'creator.createChannel': 'Tạo kênh',
      'creator.manageDescription':
          'Quản lý kênh {name} bằng dữ liệu thật từ HuTube.',
      'creator.upload': 'Tải video lên',
      'creator.content': 'Nội dung kênh',
      'creator.comments': 'Bình luận',
      'creator.settings': 'Cài đặt kênh',
      'creator.invitations': 'Lời mời cộng tác',
      'creator.subtitles': 'Phụ đề',
      'creator.overview': 'Tổng quan',
      'creator.analytics': 'Phân tích',
      'creator.latestVideo': 'Video gần nhất',
      'creator.noVideos': 'Chưa có video. Hãy tải video đầu tiên của bạn.',
      'creator.noComments': 'Chưa có bình luận để quản lý.',
      'creator.noManagedVideos': 'Kênh chưa có video.',
      'creator.search': 'Tìm theo tiêu đề video...',
      'creator.filterPrivacy': 'Lọc quyền riêng tư',
      'creator.allVideos': 'Tất cả video',
      'creator.public': 'Công khai',
      'creator.unlisted': 'Không công khai',
      'creator.private': 'Riêng tư',
      'creator.submitReview': 'Gửi duyệt',
      'creator.editVideo': 'Sửa video',
      'creator.deleteVideo': 'Xóa video',
      'creator.deleteVideoTitle': 'Xóa video?',
      'creator.deleteVideoDescription': '“{title}” sẽ bị xóa khỏi HuTube.',
      'creator.save': 'Lưu thay đổi',
      'creator.approved': 'Đã duyệt',
      'creator.pendingReview': 'Chờ kiểm duyệt',
      'creator.reviewing': 'Đang kiểm duyệt',
      'creator.rejected': 'Bị từ chối',
      'creator.notSubmitted': 'Chưa gửi duyệt',
      'creator.commentDeleteTitle': 'Xóa bình luận?',
      'creator.commentDeleteDescription': 'Thao tác này không thể hoàn tác.',
      'creator.deleteComment': 'Xóa bình luận',
      'creator.visibilityUpdated': 'Đã cập nhật chế độ hiển thị.',
      'creator.loadError': 'Không thể tải nội dung kênh.',
      'creator.submitted': 'Video đã được gửi vào hàng đợi kiểm duyệt.',
      'creator.editTitle': 'Chỉnh sửa video',
      'creator.titleField': 'Tiêu đề',
      'creator.descriptionField': 'Mô tả',
      'creator.visibilityField': 'Chế độ hiển thị',
      'creator.publicModeration': 'Công khai (cần kiểm duyệt)',
      'creator.commentsTitle': 'Bình luận kênh',
      'creator.showComment': 'Hiện bình luận',
      'creator.hideComment': 'Ẩn bình luận',

      // Upload
      'upload.title': 'Tải video lên',
      'upload.chooseVideo': 'Chọn file video',
      'upload.chooseThumbnail': 'Ảnh bìa (không bắt buộc)',
      'upload.noFile': 'Không chọn',
      'upload.ageLimit': 'Giới hạn độ tuổi',
      'upload.ageLimitDescription':
          'Nội dung dành cho khán giả từ 18 tuổi trở lên.',
      'upload.madeForKids': 'Nội dung dành cho trẻ em',
      'upload.uploadAction': 'Tải video lên',
      'upload.uploading': 'Đang tải lên…',
      'upload.publicModeration': 'Công khai — đưa vào kiểm duyệt',
      'upload.preparing': 'Đang chuẩn bị…',
      'upload.success': 'Tải video thành công.',
      'upload.videoQuotaHint': 'Video sẽ được kiểm tra quota trước khi tải.',
      'upload.selectedVideo': 'Đã chọn video',
      'upload.thumbnailHint': 'Chọn ảnh trong thư viện.',
      'upload.selectedThumbnail': 'Đã chọn ảnh bìa',
      'upload.titleField': 'Tiêu đề',
      'upload.titleRequired': 'Nhập tiêu đề video.',
      'upload.durationField': 'Thời lượng (giây)',
      'upload.durationHint': 'Nhập thời lượng của file, ví dụ 195.',
      'upload.durationInvalid': 'Nhập số giây hợp lệ.',
      'upload.topic': 'Chủ đề',
      'upload.none': 'Không chọn',
      'upload.tags': 'Thẻ',
      'upload.tagsHint': 'Phân cách bằng dấu phẩy, tối đa 10 thẻ.',
      'upload.visibility': 'Chế độ hiển thị',
      'upload.private': 'Riêng tư',
      'upload.unlisted': 'Không công khai',
      'upload.public': 'Công khai — đưa vào kiểm duyệt',
      'upload.ageRestrictionDescription':
          'Đánh dấu nếu nội dung chỉ phù hợp người trưởng thành.',
      'upload.policyAgreement':
          'Tôi cam kết video tuân thủ Tiêu chuẩn cộng đồng và Điều khoản dịch vụ.',
      'upload.policyRequired': 'Bạn cần xác nhận tuân thủ chính sách nội dung.',
      'upload.quotaExceeded':
          'Gói hiện tại không đủ quota: tối đa {size}, {minutes} phút.',
      'upload.fileReadError': 'Không thể đọc file đã chọn. Hãy chọn lại file.',
      'upload.error': 'Tải video thất bại. Vui lòng thử lại.',
      'upload.publicSuccess': 'Video đã được gửi để xử lý và kiểm duyệt.',

      // Plans
      'plans.title': 'Gói dịch vụ',
      'plans.myPlans': 'Gói của tôi',
      'plans.explorePlans': 'Khám phá gói',
      'plans.usedStorage': 'Dung lượng đã dùng',
      'plans.details': 'Chi tiết gói',
      'plans.share': 'Chia sẻ',
      'plans.subscribe': 'Đăng ký',
      'plans.current': 'Đang sử dụng',
      'plans.free': 'Miễn phí',
      'plans.shared': 'Đã chia sẻ',
      'plans.invite': 'Mời người dùng qua email',
      'plans.inviteHint': 'Email đã đăng ký trong hệ thống',
      'plans.inviteSent': 'Đã gửi lời mời dùng chung gói.',
      'plans.revoke': 'Thu hồi',
      'plans.revokeConfirm': 'Thu hồi quyền dùng gói của người này?',
      'plans.shareLink': 'Liên kết chia sẻ gói',
      'plans.shareCopied': 'Đã sao chép liên kết chia sẻ gói.',
      'plans.noPlans': 'Chưa có gói dịch vụ.',
      'plans.loadError': 'Không thể tải danh sách gói dịch vụ.',
      'plans.subscribeSuccess': 'Đăng ký gói thành công.',
      'plans.subscribeError': 'Không thể đăng ký gói. Vui lòng thử lại.',
      'plans.inviteError': 'Không thể gửi lời mời.',
      'plans.currentTitle': 'Gói hiện tại: {name}',
      'plans.storageUsed': 'Dung lượng đã dùng',
      'plans.remaining': 'Còn lại {size}',
      'plans.expires': 'Hết hạn: {date}',
      'plans.maxMembers': '{count} thành viên tối đa',
      'plans.featuresNone': 'Không có quyền lợi nâng cao',
      'plans.quality': 'Tải lên {upload} · tải xuống {download}',
      'plans.inviteDialogTitle': 'Chia sẻ gói qua email',
      'plans.inviteEmail': 'Email người dùng',
      'plans.inviteEmailHint': 'Email đã đăng ký trong hệ thống',
      'plans.shareSubject': 'Gói {name} của HuTube',
      'plans.shareError': 'Không thể mở bảng chia sẻ trên thiết bị này.',
      'plans.description':
          'Chọn gói phù hợp với kênh và chia sẻ thông tin gói bằng liên kết công khai.',
      'plans.defaultDescription': 'Gói dành cho nhà sáng tạo.',

      // Policies and notifications
      'policies.title': 'Trung tâm chính sách',
      'policies.description':
          'Tìm hiểu các chính sách và nguyên tắc sử dụng HuTube.',
      'policies.terms': 'Điều khoản dịch vụ',
      'policies.privacy': 'Quyền riêng tư',
      'policies.guidelines': 'Nguyên tắc cộng đồng',
      'policies.empty': 'Chưa có nội dung chính sách.',
      'policies.fallbackTitle': 'Nội dung chính sách đang được cập nhật',
      'policies.fallbackText':
          'Không đăng nội dung gây hại, vi phạm bản quyền, lừa đảo hoặc xâm phạm quyền riêng tư. HuTube có thể kiểm tra nội dung trước khi xuất bản.',
      'policies.version': 'Phiên bản {version}',
      'notifications.title': 'Thông báo',
      'notifications.empty': 'Chưa có thông báo.',
      'notifications.markAllRead': 'Đánh dấu tất cả đã đọc',
      'notifications.loadError': 'Không thể tải thông báo.',
      'notifications.readAll': 'Đọc tất cả',
      'notifications.loadMore': 'Tải thêm',
      'notifications.defaultTitle': 'Thông báo',
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
      'profile.channelInvitations': 'Collaboration invitations',
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
      'prefs.langVi': 'Vietnamese (VI)',
      'prefs.langEn': 'English (EN)',
      'prefs.playbackHeading': 'Video Playback',
      'prefs.autoplay': 'Autoplay next video',
      'prefs.autoplaySub':
          'Continue playing related videos when current video ends.',
      'prefs.quality': 'Default Video Quality',
      'prefs.qualitySub': 'Applied when streaming videos',
      'prefs.privacyHeading': 'Privacy',
      'prefs.subsPrivate': 'Keep my subscriptions private',
      'prefs.subsPrivateSub':
          'Do not display subscribed channels on public profile.',
      'prefs.playlistsPrivate': 'Keep saved playlists private',
      'prefs.playlistsPrivateSub':
          'Only you can view your created and saved playlists.',
      'prefs.autoSaving': 'Auto-saving changes...',
      'prefs.loadError': 'Unable to load preferences.',
      'prefs.saveError': 'Failed to save preferences.',
      'prefs.saved': 'Preferences saved.',
      'prefs.qualityAuto': 'Auto',

      // Edit Profile
      'editProfile.title': 'Edit Profile',
      'editProfile.displayName': 'Display Name',
      'editProfile.bio': 'Bio',
      'editProfile.country': 'Country',
      'editProfile.region': 'Region',
      'editProfile.changeAvatar': 'Change Avatar',
      'editProfile.saveBtn': 'Save Profile',
      'editProfile.saveError': 'Unable to save your profile. Please try again.',
      'editProfile.displayNameRequired': 'Display name cannot be empty.',
      'editProfile.countryVietnam': 'Vietnam',
      'editProfile.countryUs': 'United States',
      'editProfile.countryJapan': 'Japan',
      'editProfile.countryKorea': 'South Korea',
      'editProfile.countrySingapore': 'Singapore',
      'editProfile.countryOther': 'Other',

      // Change Password
      'password.title': 'Change Password',
      'password.current': 'Current Password',
      'password.new': 'New Password',
      'password.confirm': 'Confirm New Password',
      'password.updateBtn': 'Update Password',
      'password.currentRequired': 'Please enter your current password.',
      'password.newRequirement':
          'The new password must be at least 8 characters.',
      'password.mismatch': 'The password confirmation does not match.',
      'password.error': 'Unable to change the password. Please try again.',

      // Notifications Settings
      'notif.title': 'Notification Preferences',
      'notif.newVideos': 'New videos from subscribed channels',
      'notif.comments': 'Comments and replies',
      'notif.subs': 'New subscribers',
      'notif.marketing': 'Feature updates and announcements',
      'notif.newVideosDesc':
          'Get notified when a channel you follow publishes a new video.',
      'notif.commentsDesc':
          'Get notifications about activity on your comments and videos.',
      'notif.subsDesc':
          'Get summaries about activity from channels you care about.',
      'notif.marketingDesc': 'Get news about new HuTube features.',
      'notif.autoSaving': 'Auto-saving changes...',
      'notif.loadError': 'Unable to load notification settings.',
      'notif.saveError': 'Unable to save notification settings.',

      // Auth
      'auth.loginTitle': 'Sign in to HuTube',
      'auth.registerTitle': 'Create your HuTube account',
      'auth.email': 'Email',
      'auth.password': 'Password',
      'auth.loginBtn': 'Sign In',
      'auth.registerBtn': 'Sign Up',

      // Shared app chrome
      'common.networkError':
          'Unable to connect. Check your network and try again.',
      'common.serverError': 'The server is busy. Please try again later.',
      'common.confirm': 'Confirm',
      'common.yes': 'Yes',
      'common.no': 'No',
      'common.share': 'Share',
      'common.download': 'Download',
      'common.send': 'Send',
      'common.reply': 'Reply',
      'common.search': 'Search',
      'common.notifications': 'Notifications',
      'common.policy': 'Policies',
      'common.menu': 'Open menu',
      'common.account': 'Account',
      'common.signIn': 'Sign in',
      'common.create': 'Create',
      'common.open': 'Open',
      'common.all': 'All',
      'common.copied': 'Copied.',
      'common.user': 'User',
      'common.userHuTube': 'HuTube user',
      'common.appName': 'HuTube',

      // App shell and feed
      'app.restoreSession': 'Restoring your session…',
      'app.opening': 'Opening HuTube…',
      'app.viewVideo': 'Watch video',
      'app.connection': 'Check connection',
      'app.connected': 'HuTube connected · {environment}',
      'app.apiActive': 'API is active',
      'app.navYou': 'You',
      'app.librarySection': 'LIBRARY',
      'app.otherSection': 'OTHER',
      'app.modulePending':
          '{label} will be connected when the corresponding module is ready.',
      'feed.homeTitle': 'For you',
      'feed.homeDescription':
          'New and notable videos from the HuTube community.',
      'feed.exploreTitle': 'Explore',
      'feed.exploreDescription':
          'Choose a topic to find new content from the HuTube community.',
      'feed.empty': 'No matching videos yet.',
      'feed.loadError':
          'Unable to load videos. Check your connection and try again.',
      'feed.openVideo': 'Open video {title}',
      'feed.views': '{count} views',
      'feed.today': 'Today',
      'feed.daysAgo': '{count} days ago',
      'feed.sortNewest': 'Newest',
      'feed.sortPopular': 'Popular',
      'feed.sortTrending': 'Trending',
      'feed.allTopics': 'All topics',

      // Library and downloads
      'library.title': 'Library',
      'library.history': 'History',
      'library.liked': 'Liked',
      'library.allRatings': 'All',
      'library.ratingStars': '{count} stars',
      'library.empty': 'No videos in this section yet.',
      'library.loadError':
          'Unable to load the library. Check your connection and try again.',
      'downloads.title': 'Downloads',
      'downloads.empty': 'No downloaded videos yet.',
      'downloads.queued': 'Queued',
      'downloads.downloading': 'Downloading {percent}%',
      'downloads.completed': 'Saved on this device',
      'downloads.paused': 'Paused',
      'downloads.failed': 'Download failed',
      'downloads.remove': 'Remove from device',
      'downloads.error': 'Unable to download this video.',

      // Watch and offline playback
      'watch.loadError': 'Unable to load this video. Please try again.',
      'watch.videoUnavailable': 'Video unavailable.',
      'watch.invalidSource':
          'Invalid video source. The server must return an HTTP(S) URL.',
      'watch.playerError': 'Unable to play this video source.',
      'watch.pipUnsupported':
          'Picture-in-picture is not supported for this video source.',
      'watch.loginInteract': 'Sign in to interact with this video.',
      'watch.loginRate': 'Sign in to rate this video.',
      'watch.ratingTitle': 'Rate this video',
      'watch.ratingStars': '{count} stars',
      'watch.ratingSaved': 'Your rating was updated.',
      'watch.shareText': 'Watch {title} on HuTube\nhutube://watch/{id}',
      'watch.loginDownload': 'Sign in to download this video.',
      'watch.downloadQuality': 'Choose download quality',
      'watch.downloadAdded': 'Added to downloads on this device.',
      'watch.viewsAndChannel': '{views} views · {channel}',
      'watch.rateAction': 'Rate',
      'watch.shareAction': 'Share',
      'watch.downloadAction': 'Download',
      'watch.pipAction': 'PiP',
      'watch.background': 'Background play',
      'watch.chapters': 'Chapters',
      'watch.comments': 'Comments ({count})',
      'watch.commentHint': 'Write a comment...',
      'watch.loginCommentHint': 'Sign in to comment',
      'watch.sending': 'Sending...',
      'watch.commentAction': 'Comment',
      'watch.related': 'Related videos',
      'watch.replyTitle': 'Reply to {name}',
      'watch.replyHint': 'Write your reply',
      'watch.replies': '{count} replies',
      'watch.repliesLoading': 'Loading...',
      'offline.missingFile': 'The file was not found on this device.',
      'offline.openError': 'Unable to open this video file.',
      'offline.pipTooltip': 'Picture-in-Picture',
      'offline.pipUnsupported':
          'This device does not support PiP for this video.',
      'offline.backgroundAvailable':
          'Background play is available on your plan',

      // Account and profile
      'account.hubTitle': 'You',
      'account.heading': 'Account',
      'account.channelHeading': 'Your channel',
      'account.serviceHeading': 'Service plan',
      'account.editProfile': 'Edit profile',
      'account.passwordSecurity': 'Password and security',
      'account.appearance': 'Appearance preferences',
      'account.notificationSettings': 'Notification settings',
      'account.checkingChannel': 'Checking channel…',
      'account.createChannel': 'Create a channel',
      'account.createChannelDesc':
          'Start uploading videos with a HuTube channel.',
      'account.invitations': 'Collaboration invitations',
      'account.creatorStudio': 'Creator Studio',
      'account.plans': 'Plans and storage',
      'account.editTooltip': 'Edit profile',
      'account.profileLoadError': 'Unable to load your profile for editing.',
      'account.logout': 'Sign out',
      'profile.headerTitle': 'Your account',
      'profile.channelView': 'View channel',
      'profile.channelManage': 'Manage',
      'profile.noChannelTitle': 'You do not have a HuTube channel yet',
      'profile.noChannelDescription':
          'Create a channel to publish videos, build a community and reach more viewers.',
      'profile.createNow': 'Create a channel now',
      'profile.sessionsHeading': 'Signed-in devices',
      'profile.refreshDevices': 'Refresh devices',
      'profile.sessionsDescription':
          'Revoke sessions on devices you no longer use.',
      'profile.sessionsEmpty': 'Unable to load your devices.',
      'profile.logoutOthers': 'Sign out other devices',
      'profile.logoutAll': 'Sign out all devices',
      'profile.logout': 'Sign out',
      'profile.sessionRevoked': 'Session revoked.',
      'profile.sessionRevokeError': 'Unable to revoke the session.',
      'profile.otherDevicesLogoutError':
          'Unable to sign out the other devices.',
      'profile.updated': 'Profile updated successfully!',
      'profile.avatarError': 'Unable to update your avatar.',
      'editProfile.displayNameHint': 'Enter your display name',
      'editProfile.bioHint':
          'Share a short introduction with the HuTube community...',
      'editProfile.noCountry': 'No country selected',
      'password.updated': 'Password changed successfully!',
      'password.currentHint': 'Enter your current password',
      'password.newHint': 'At least 10 characters',
      'password.confirmHint': 'Enter your new password again',
      'notifications.videoUpdates': 'New videos from subscribed channels',
      'notifications.videoUpdatesDesc':
          'Get notified when a channel you follow posts a new video.',
      'notifications.comments': 'Comments and replies',
      'notifications.commentsDesc':
          'Get updates about comments and replies related to you.',
      'notifications.channelActivity': 'Subscribed channel activity',
      'notifications.channelActivityDesc':
          'Get updates from channels you follow.',
      'notifications.marketing': 'Product news and updates',
      'notifications.marketingDesc': 'Get news about new HuTube features.',
      'notifications.settingsSaved': 'Notification settings saved.',

      // Auth form
      'auth.welcome': 'Welcome back',
      'auth.loginDescription': 'Sign in to continue with your account.',
      'auth.registerDescription':
          'Get started with HuTube. Verify your email to protect your account.',
      'auth.forgotTitle': 'Forgot password?',
      'auth.forgotDescription':
          'Enter the email address you used to sign up for HuTube.',
      'auth.verifyTitle': 'Verify email',
      'auth.verifyDescription':
          'Confirm your email address to finish signing up.',
      'auth.verifyMissing':
          'This link is missing a verification token. Request a new email.',
      'auth.resetTitle': 'Set a new password',
      'auth.resetDescription':
          'Choose a new password that you do not use elsewhere.',
      'auth.resetMissing':
          'This link is missing a reset token. Request a new email.',
      'auth.resendTitle': 'Resend verification email',
      'auth.resendDescription':
          'Enter the email address you used to sign up for HuTube.',
      'auth.displayNameField': 'Display name',
      'auth.usernameField': 'Username',
      'auth.emailField': 'Email',
      'auth.passwordField': 'Password',
      'auth.newPasswordField': 'New password',
      'auth.confirmPasswordField': 'Enter your password again',
      'auth.displayNameInvalid':
          'Enter a display name from 1 to 120 characters.',
      'auth.usernameInvalid':
          '3–50 characters: letters, numbers, periods, underscores or hyphens.',
      'auth.emailInvalid': 'Enter a valid email address.',
      'auth.passwordRequired': 'Enter your password.',
      'auth.passwordRequirement':
          '10–128 characters, including uppercase, lowercase and a number.',
      'auth.passwordMismatch': 'The passwords do not match.',
      'auth.forgotLink': 'Forgot password?',
      'auth.loginSuccess': 'Signed in successfully.',
      'auth.registerSuccess':
          'Account created. Open your email to verify it, then sign in.',
      'auth.verifySuccess': 'Email verified. You can sign in now.',
      'auth.resetSuccess': 'Password changed. Sign in with your new password.',
      'auth.forgotSuccess':
          'If this email belongs to a HuTube account, you will receive a reset link.',
      'auth.resendSuccess':
          'If your account needs verification, we sent another email. Check your spam folder too.',
      'auth.accountMessage': 'Sign in to continue to your account.',
      'auth.linkError': 'Unable to open the link. Please try again.',
      'auth.googleCancelled': 'Google sign-in was cancelled.',
      'auth.googleInvalid':
          'Unable to complete Google sign-in. Please try again.',
      'auth.googleUnavailable':
          'Google sign-in is not available on this device.',
      'auth.invalidCredentials': 'The email or password is incorrect.',
      'auth.emailNotVerified': 'Your email has not been verified.',
      'auth.accountSuspended': 'Your account is temporarily suspended.',
      'auth.accountBanned': 'Your account has been banned.',
      'auth.continueGoogle': 'Continue with Google',
      'auth.showPassword': 'Show password',
      'auth.hidePassword': 'Hide password',
      'auth.saveNewPassword': 'Save new password',
      'auth.sendEmail': 'Send email',
      'auth.createAccount': 'Create account',
      'auth.resendVerification': 'Resend verification email',
      'auth.restoreAgain': 'Try restoring the session again',
      'auth.requestNewLink': 'Request a new link',
      'auth.backToLogin': 'Back to sign in',
      'auth.noAccount': "Don't have an account? Sign up",
      'auth.otherDevicesLoggedOut': 'All other devices were signed out.',
      'auth.allDevicesLoggedOut': 'All devices were signed out.',
      'auth.sessionExpired': 'Your session expired. Please sign in again.',
      'auth.storageError': 'Unable to open secure storage. Please try again.',
      'auth.logoutOffline':
          'You were signed out on this device. The server could not confirm session revocation.',

      // Channel and collaboration
      'channel.title': 'Channel',
      'channel.retry': 'Retry',
      'channel.copied': 'Channel link copied to the clipboard',
      'channel.manage': 'Manage channel and settings',
      'channel.view': 'View channel',
      'channel.subscribe': 'Subscribe',
      'channel.subscribed': 'Subscribed',
      'channel.home': 'Home',
      'channel.videos': 'Videos',
      'channel.playlists': 'Playlists',
      'channel.subscriberCount': '{count} subscribers',
      'channel.videoCount': '{count} videos',
      'channel.viewCount': '{count} views',
      'channel.descriptionEmpty': 'This channel has no description.',
      'channel.emptyVideos': 'This channel has no public videos yet.',
      'channel.about': 'About',
      'channel.otherInfo': 'More information',
      'channel.joinWelcome': 'Welcome to {name} on HuTube!',
      'channel.joinDescription': 'Learn about {name} and its content.',
      'channel.guide': 'The complete HuTube video platform guide',
      'channel.stats': '{subscribers} subscribers · {videos} videos',
      'channel.changeBanner': 'Change banner',
      'channel.notFound': 'This channel does not exist or has been deleted.',
      'channel.subscribedToast': 'Subscribed to the channel',
      'channel.unsubscribedToast': 'Unsubscribed from the channel',
      'channel.latestVideo': 'Latest video',
      'channel.welcomeVideo': 'Welcome to {name} on HuTube!',
      'channel.recent': 'Recently',
      'channel.introVideo': 'An introduction to {name} and its content',
      'channel.tutorialVideo': 'The complete HuTube video platform guide',
      'channel.daysAgo': '{count} days ago',
      'channel.weekAgo': '1 week ago',
      'channel.noPlaylists': 'No playlists yet',
      'channel.description': 'Description',
      'channel.descriptionEmptyLong':
          'This channel has not added a detailed description.',
      'channel.detailedInfo': 'Detailed information',
      'channel.channelUrl': 'hutube.app/@{handle}',
      'channel.uploadedVideos': '{count} uploaded videos',
      'channel.totalViews': '{count} total views',
      'channel.joined': 'Joined: {date}',
      'channel.invitationExpiryUnknown': 'Invitation expiry is unknown',
      'channel.invitationExpiry': 'Expires {date} at {time}',
      'channel.invitationRevokeDescription':
          'The invitation to {email} will no longer be valid.',
      'channel.revokeInvitationTooltip': 'Revoke invitation',
      'channel.noPendingInvitations': 'No pending invitations.',
      'channel.unknownEmail': 'Unknown email',
      'channel.emailInvalid': 'Please enter a valid email address.',
      'channel.nameEmpty': 'Channel name cannot be empty.',
      'channel.imageReadError':
          'Unable to read or upload the image. Please choose another image.',
      'channel.brandingTitle': 'Channel images',
      'channel.brandingDescription':
          'JPG, PNG or WEBP. Avatars up to 5MB and banners up to 10MB.',
      'channel.currentBannerSemantic': 'Current channel banner',
      'channel.uploadingBanner': 'Uploading banner…',
      'channel.uploadingAvatar': 'Uploading avatar…',
      'channel.changeAvatar': 'Change avatar',
      'channel.basicInfo': 'Basic information',
      'channel.nameHint': 'Enter channel name',
      'channel.handleImmutable': 'The handle cannot be changed after creation',
      'channel.descriptionHintEdit': 'Introduce your channel...',
      'channel.inviteHeading': 'Invite a collaborator',
      'channel.inviteDescription':
          'Invitees can review their permission scope before accepting.',
      'channel.dangerTitle': 'Danger zone',
      'channel.dangerDescription':
          'Deleting the channel marks it deleted, hides its videos and releases your handle. You can create a new channel afterward.',
      'channel.deleteThis': 'Delete this channel',
      'channel.confirmDeleteTitle': 'Confirm channel deletion?',
      'channel.confirmDeleteDescription':
          'This action hides the channel, its videos and your handle from HuTube.',
      'channel.confirmDeletePrompt':
          'Enter the exact channel name "{name}" to confirm:',
      'channel.confirmDeleteHint': 'Enter channel name',
      'channel.confirmDeleteAction': 'Confirm deletion',
      'channel.deleteError':
          'Unable to delete the channel. Please try again later.',
      'channel.roleManagerDescription':
          'Manage members and content within the granted permissions.',
      'channel.roleEditorDescription':
          'Upload and edit content, playlists and content analytics.',
      'channel.roleModeratorDescription':
          'Moderate comments and content within the granted permissions.',
      'channel.roleViewerDescription':
          'View the channel data and shared content.',
      'channel.processing': 'Processing…',
      'channel.joinedChannel': 'Joined {name}.',
      'channel.pullToRefresh': 'Pull down to check again.',
      'channel.createTitle': 'Create a new channel',
      'channel.created':
          '🎉 Congratulations! Your channel was created successfully!',
      'channel.createName': 'Channel name',
      'channel.createNameHint': 'Example: Tech Channel 24h',
      'channel.nameRequired': 'Channel name cannot be empty.',
      'channel.createHandle': 'Handle',
      'channel.createHandleHint': 'techchannel24h',
      'channel.handleInvalid':
          'The handle may contain only lowercase letters, numbers and hyphens.',
      'channel.handleTaken':
          'This handle is already in use. Choose another one.',
      'channel.handleAvailable': 'Handle is available.',
      'channel.handleUnavailable': 'Handle is not available.',
      'channel.handleDescription':
          'The handle creates a unique address for your channel.',
      'channel.createDescription': 'Channel description',
      'channel.createDescriptionHint': 'Introduce your channel briefly',
      'channel.descriptionHint': 'Introduce your channel briefly',
      'channel.rulesTitle': 'Channel creation rules',
      'channel.rulesDescription':
          'Each account may own one channel. You can collaborate on channels you are invited to.',
      'channel.createAction': 'Create channel',
      'channel.createError': 'Unable to create the channel. Please try again.',
      'channel.settingsTitle': 'Channel settings',
      'channel.updateSuccess': 'Channel information updated successfully!',
      'channel.updateError': 'Unable to update the channel.',
      'channel.avatarUpdated': 'Channel avatar updated.',
      'channel.bannerUpdated': 'Channel banner updated.',
      'channel.imageError': 'Unable to upload the image.',
      'channel.deleteTitle': 'Delete channel?',
      'channel.deleteDescription':
          'Are you sure you want to delete this channel? This cannot be undone.',
      'channel.deleteAction': 'Delete channel',
      'channel.deleteSuccess': 'Channel deleted successfully.',
      'channel.invitationsTitle': 'Channel invitations',
      'channel.noInvitations': 'You do not have any channel invitations.',
      'channel.accept': 'Accept',
      'channel.decline': 'Decline',
      'channel.accepted': 'Invitation accepted.',
      'channel.declined': 'Invitation declined.',
      'channel.inviteRevoked': 'Invitation revoked.',
      'channel.inviteSent': 'Channel invitation sent.',
      'channel.inviteEmail': 'User email',
      'channel.inviteEmailHint': 'member@example.com',
      'channel.inviteRole': 'Role',
      'channel.inviteAction': 'Send invitation',
      'channel.pendingInvites': 'Pending invitations',
      'channel.members': 'Members and permissions',
      'channel.owner': 'Owner',
      'channel.remove': 'Remove',
      'channel.revoke': 'Revoke',
      'channel.confirmRevoke': 'Revoke invitation?',
      'channel.roleManager': 'Manager',
      'channel.roleEditor': 'Editor',
      'channel.roleModerator': 'Moderator',
      'channel.roleViewer': 'Viewer',

      // Creator Studio
      'creator.title': 'Creator Studio',
      'creator.noChannel': 'You do not have a channel to manage yet.',
      'creator.invitedChannelTitle': 'You have been invited to collaborate',
      'creator.invitedChannelDescription':
          'You can work on channels you have access to without creating your own channel.',
      'creator.openInvitations': 'View collaboration invitations',
      'creator.createChannelPrompt': 'Want to create your own channel?',
      'creator.channelSelector': 'Managed channel',
      'creator.managedAs': '{name} · {role}',
      'creator.uploadDescription':
          'Upload videos, check quota and submit public videos for review.',
      'creator.contentDescription': 'View and adjust channel videos.',
      'creator.commentsDescription': 'Manage feedback on your videos.',
      'creator.settingsDescription': 'Name, description, avatar and banner.',
      'creator.invitationsDescription':
          'Invite and respond to member invitations.',
      'creator.subtitlesDescription':
          'Subtitle status by video; authoring is still being completed.',
      'creator.createChannel': 'Create a channel',
      'creator.manageDescription': 'Manage {name} with live HuTube data.',
      'creator.upload': 'Upload video',
      'creator.content': 'Channel content',
      'creator.comments': 'Comments',
      'creator.settings': 'Channel settings',
      'creator.invitations': 'Collaboration invitations',
      'creator.subtitles': 'Subtitles',
      'creator.overview': 'Overview',
      'creator.analytics': 'Analytics',
      'creator.latestVideo': 'Latest video',
      'creator.noVideos': 'No videos yet. Upload your first video.',
      'creator.noComments': 'No comments to manage yet.',
      'creator.noManagedVideos': 'This channel has no videos yet.',
      'creator.search': 'Search by video title...',
      'creator.filterPrivacy': 'Filter by privacy',
      'creator.allVideos': 'All videos',
      'creator.public': 'Public',
      'creator.unlisted': 'Unlisted',
      'creator.private': 'Private',
      'creator.submitReview': 'Submit for review',
      'creator.editVideo': 'Edit video',
      'creator.deleteVideo': 'Delete video',
      'creator.deleteVideoTitle': 'Delete video?',
      'creator.deleteVideoDescription':
          '“{title}” will be deleted from HuTube.',
      'creator.save': 'Save changes',
      'creator.approved': 'Approved',
      'creator.pendingReview': 'Pending review',
      'creator.reviewing': 'Under review',
      'creator.rejected': 'Rejected',
      'creator.notSubmitted': 'Not submitted',
      'creator.commentDeleteTitle': 'Delete comment?',
      'creator.commentDeleteDescription': 'This action cannot be undone.',
      'creator.deleteComment': 'Delete comment',
      'creator.visibilityUpdated': 'Visibility updated.',
      'creator.loadError': 'Unable to load channel content.',
      'creator.submitted': 'Video submitted for moderation.',
      'creator.editTitle': 'Edit video',
      'creator.titleField': 'Title',
      'creator.descriptionField': 'Description',
      'creator.visibilityField': 'Visibility',
      'creator.publicModeration': 'Public (moderation required)',
      'creator.commentsTitle': 'Channel comments',
      'creator.showComment': 'Show comment',
      'creator.hideComment': 'Hide comment',

      // Upload
      'upload.title': 'Upload video',
      'upload.chooseVideo': 'Choose video file',
      'upload.chooseThumbnail': 'Thumbnail (optional)',
      'upload.noFile': 'No selection',
      'upload.ageLimit': 'Age restriction',
      'upload.ageLimitDescription': 'Content for viewers aged 18 and over.',
      'upload.madeForKids': 'Content made for kids',
      'upload.uploadAction': 'Upload video',
      'upload.uploading': 'Uploading…',
      'upload.publicModeration': 'Public — send for review',
      'upload.preparing': 'Preparing…',
      'upload.success': 'Video uploaded successfully.',
      'upload.videoQuotaHint':
          'The video will be checked against your quota before upload.',
      'upload.selectedVideo': 'Video selected',
      'upload.thumbnailHint': 'Choose an image from your library.',
      'upload.selectedThumbnail': 'Thumbnail selected',
      'upload.titleField': 'Title',
      'upload.titleRequired': 'Enter a video title.',
      'upload.durationField': 'Duration (seconds)',
      'upload.durationHint': 'Enter the file duration, for example 195.',
      'upload.durationInvalid': 'Enter a valid number of seconds.',
      'upload.topic': 'Topic',
      'upload.none': 'None',
      'upload.tags': 'Tags',
      'upload.tagsHint': 'Separate with commas, up to 10 tags.',
      'upload.visibility': 'Visibility',
      'upload.private': 'Private',
      'upload.unlisted': 'Unlisted',
      'upload.public': 'Public — send for review',
      'upload.ageRestrictionDescription':
          'Mark this if the content is intended for adults only.',
      'upload.policyAgreement':
          'I confirm that this video follows the Community Guidelines and Terms of Service.',
      'upload.policyRequired':
          'You must confirm that the content follows our policies.',
      'upload.quotaExceeded':
          'Your plan does not have enough quota: up to {size}, {minutes} minutes.',
      'upload.fileReadError':
          'Unable to read the selected file. Please choose it again.',
      'upload.error': 'Video upload failed. Please try again.',
      'upload.publicSuccess':
          'Video was submitted for processing and moderation.',

      // Plans
      'plans.title': 'Service plans',
      'plans.myPlans': 'My plans',
      'plans.explorePlans': 'Explore plans',
      'plans.usedStorage': 'Storage used',
      'plans.details': 'Plan details',
      'plans.share': 'Share',
      'plans.subscribe': 'Subscribe',
      'plans.current': 'Current plan',
      'plans.free': 'Free',
      'plans.shared': 'Shared',
      'plans.invite': 'Invite someone by email',
      'plans.inviteHint': 'Email registered in the system',
      'plans.inviteSent': 'Shared-plan invitation sent.',
      'plans.revoke': 'Revoke',
      'plans.revokeConfirm': 'Revoke this person’s plan access?',
      'plans.shareLink': 'Plan share link',
      'plans.shareCopied': 'Plan share link copied.',
      'plans.noPlans': 'No service plans yet.',
      'plans.loadError': 'Unable to load service plans.',
      'plans.subscribeSuccess': 'Plan subscription successful.',
      'plans.subscribeError':
          'Unable to subscribe to this plan. Please try again.',
      'plans.inviteError': 'Unable to send the invitation.',
      'plans.currentTitle': 'Current plan: {name}',
      'plans.storageUsed': 'Storage used',
      'plans.remaining': 'Remaining {size}',
      'plans.expires': 'Expires: {date}',
      'plans.maxMembers': '{count} members maximum',
      'plans.featuresNone': 'No advanced benefits',
      'plans.quality': 'Upload {upload} · download {download}',
      'plans.inviteDialogTitle': 'Share plan by email',
      'plans.inviteEmail': 'User email',
      'plans.inviteEmailHint': 'Email registered in the system',
      'plans.shareSubject': 'HuTube {name} plan',
      'plans.shareError': 'Sharing is not available on this device.',
      'plans.description':
          'Choose a plan for your channel and share its public information link.',
      'plans.defaultDescription': 'A plan for creators.',

      // Policies and notifications
      'policies.title': 'Policy center',
      'policies.description':
          'Learn about HuTube policies and community rules.',
      'policies.terms': 'Terms of service',
      'policies.privacy': 'Privacy',
      'policies.guidelines': 'Community guidelines',
      'policies.empty': 'No policy content yet.',
      'policies.fallbackTitle': 'Policy content is being updated',
      'policies.fallbackText':
          'Do not post harmful, infringing, fraudulent or privacy-invasive content. HuTube may review content before publication.',
      'policies.version': 'Version {version}',
      'notifications.title': 'Notifications',
      'notifications.empty': 'No notifications yet.',
      'notifications.markAllRead': 'Mark all as read',
      'notifications.loadError': 'Unable to load notifications.',
      'notifications.readAll': 'Mark all as read',
      'notifications.loadMore': 'Load more',
      'notifications.defaultTitle': 'Notification',
    },
  };

  static String t(String key) {
    final lang = currentLang.value;
    return _localizedValues[lang]?[key] ?? _localizedValues['vi']?[key] ?? key;
  }

  static String format(String key, [Map<String, Object?> values = const {}]) {
    var result = t(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  static String number(num value) {
    final raw = value is int || value == value.roundToDouble()
        ? value.round().toString()
        : value
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    final parts = raw.split('.');
    final integer = parts.first;
    final sign = integer.startsWith('-') ? '-' : '';
    final digits = sign.isEmpty ? integer : integer.substring(1);
    final grouped = digits.replaceAllMapped(
      RegExp(r'(?<!^)(?=(\d{3})+$)'),
      (match) => currentLang.value == 'vi' ? '.' : ',',
    );
    final decimal = parts.length > 1
        ? (currentLang.value == 'vi' ? ',${parts[1]}' : '.${parts[1]}')
        : '';
    return '$sign$grouped$decimal';
  }

  static String date(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return currentLang.value == 'vi'
        ? '$day/$month/${value.year}'
        : '$month/$day/${value.year}';
  }

  static String dateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${date(value)} $hour:$minute';
  }

  static String relativeDate(DateTime value) {
    final days = DateTime.now().difference(value.toLocal()).inDays;
    if (days <= 0) return t('feed.today');
    if (days < 30) return format('feed.daysAgo', {'count': number(days)});
    return date(value);
  }

  static String apiError(ApiFailure error, {String fallback = 'common.error'}) {
    const codes = <String, String>{
      'NETWORK_ERROR': 'common.networkError',
      'INVALID_CREDENTIALS': 'auth.invalidCredentials',
      'EMAIL_NOT_VERIFIED': 'auth.emailNotVerified',
      'EMAIL_UNVERIFIED': 'auth.emailNotVerified',
      'ACCOUNT_SUSPENDED': 'auth.accountSuspended',
      'ACCOUNT_BANNED': 'auth.accountBanned',
      'ACCOUNT_BLOCKED': 'auth.accountSuspended',
      'GOOGLE_LOGIN_NOT_CONFIGURED': 'auth.googleUnavailable',
      'INVALID_GOOGLE_TOKEN': 'auth.googleInvalid',
      'GOOGLE_LOGIN_CANCELLED': 'auth.googleCancelled',
      'SESSION_EXPIRED': 'auth.sessionExpired',
      'ONE_CHANNEL_LIMIT_EXCEEDED': 'channel.updateError',
      'CHANNEL_HANDLE_ALREADY_EXISTS': 'channel.updateError',
    };
    return t(codes[error.code] ?? fallback);
  }
}

extension AppStringsExtension on BuildContext {
  String tr(String key) => AppStrings.t(key);
}
