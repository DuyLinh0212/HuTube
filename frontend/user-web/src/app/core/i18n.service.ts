import { Injectable, signal } from '@angular/core';

export type AppLang = 'vi' | 'en';

export const DICTIONARY: Record<AppLang, Record<string, string>> = {
  vi: {
    // Common
    'common.save': 'Lưu thay đổi',
    'common.saving': 'Đang lưu...',
    'common.cancel': 'Hủy',
    'common.delete': 'Xóa',
    'common.edit': 'Chỉnh sửa',
    'common.back': 'Quay lại',
    'common.continue': 'Tiếp tục',
    'common.close': 'Đóng',
    'common.loading': 'Đang tải...',
    'common.search': 'Tìm kiếm',
    'common.actions': 'Hành động',
    'common.success': 'Thành công',
    'common.error': 'Đã xảy ra lỗi',
    'common.or': 'hoặc',
    'common.copy': 'Sao chép',
    'common.copied': 'Đã sao chép vào clipboard',
    'common.retry': 'Thử lại',
    'common.confirm': 'Xác nhận',
    'common.all': 'Tất cả',
    'common.open': 'Mở liên kết',
    'common.skipToContent': 'Bỏ qua để đến nội dung chính',

    // Navigation & Topbar / Sidebar
    'nav.home': 'Trang chủ',
    'nav.explore': 'Khám phá',
    'nav.subscriptions': 'Kênh đăng ký',
    'nav.library': 'Thư viện',
    'nav.history': 'Lịch sử xem',
    'nav.likedVideos': 'Video đã thích',
    'nav.playlists': 'Danh sách phát',
    'nav.yourChannel': 'Kênh của bạn',
    'nav.createChannel': 'Tạo kênh mới',
    'nav.channelInvitations': 'Lời mời tham gia',
    'nav.settings': 'Cài đặt',
    'nav.profile': 'Hồ sơ của bạn',

    // Subscriptions
    'subscriptions.title': 'Kênh đăng ký',
    'subscriptions.latestVideos': 'Video mới nhất',
    'subscriptions.subscribedChannels': 'Kênh bạn đang theo dõi',
    'subscriptions.noChannels': 'Bạn chưa đăng ký kênh nào',
    'subscriptions.noChannelsDesc': 'Đăng ký các kênh yêu thích để cập nhật những video mới nhất ngay tại đây.',
    'subscriptions.exploreChannels': 'Khám phá video & kênh',
    'subscriptions.noVideos': 'Chưa có video mới',
    'subscriptions.noVideosDesc': 'Các kênh bạn theo dõi chưa đăng video mới nào.',
    'subscriptions.loginTitle': 'Đừng bỏ lỡ video mới',
    'subscriptions.loginDesc': 'Đăng nhập để xem cập nhật từ các kênh bạn yêu thích.',
    'subscriptions.loginButton': 'Đăng nhập ngay',

    // Profile Page (matching profile.jpg)
    'profile.quote': 'Những video hay hơn cho một phiên bản tốt hơn của bạn ♡',
    'profile.editProfile': 'Chỉnh sửa hồ sơ',
    'profile.accountSettings': 'Cài đặt tài khoản',
    'profile.tagline': 'Sống vui, xem hay, lan tỏa điều tốt đẹp!',
    'profile.defaultBio': 'Thích những video chữa lành, du lịch, ẩm thực và khám phá thế giới. Mỗi ngày một chút tích cực!',
    'profile.joinedIn': 'Tham gia từ',
    'profile.verifiedUser': 'Đã xác minh',
    'profile.premiumMember': 'HuTube Premium',
    'profile.tabOverview': 'Tổng quan',
    'profile.tabHistory': 'Lịch sử xem',
    'profile.tabLiked': 'Video đã thích',
    'profile.tabPlaylists': 'Danh sách phát',
    'profile.tabWatchLater': 'Xem sau',
    'profile.tabMyPackages': 'Gói của tôi',
    'profile.statWatchTime': 'Thời gian xem',
    'profile.statWatchTimeSub': 'trong 30 ngày qua',
    'profile.statWatchTimeTrend': '↑ 12% so với tháng trước',
    'profile.statLiked': 'Video đã thích',
    'profile.statPlaylists': 'Danh sách phát',
    'profile.statSubs': 'Kênh đăng ký',
    'profile.statBadge': 'Huy hiệu thành viên',
    'profile.statBadgeSince': 'Thành viên từ 03/2024',
    'profile.statBadgeRemaining': 'Còn 247 ngày',
    'profile.continueWatching': 'Tiếp tục xem',
    'profile.viewAll': 'Xem tất cả',
    'profile.recentlySaved': 'Đã lưu gần đây',
    'profile.resumeHint': 'Bạn đang xem dở video này',
    'profile.emptyHistory': 'Chưa có video nào trong lịch sử xem',
    'profile.emptySaved': 'Chưa có video nào được lưu hoặc thích',
    'profile.recentActivity': 'Hoạt động gần đây',
    'profile.favoriteGenres': 'Thể loại yêu thích',
    'profile.edit': 'Chỉnh sửa',
    'profile.genre.travel': 'Du lịch',
    'profile.genre.food': 'Ẩm thực',
    'profile.genre.music': 'Âm nhạc',
    'profile.genre.film': 'Phim ảnh',
    'profile.genre.education': 'Giáo dục',
    'profile.genre.tech': 'Công nghệ',
    'profile.genre.lifestyle': 'Đời sống',
    'profile.genre.health': 'Sức khỏe',
    'profile.genre.other': 'Khác',
    'profile.actLiked': 'Đã thích video',
    'profile.actWatched': 'Đã xem',
    'profile.actPlaylist': 'Đã thêm vào danh sách phát',
    'profile.actSubscribed': 'Đã đăng ký kênh',
    'profile.aboutTitle': 'Thông tin khác',
    'profile.learnMore': 'Tìm hiểu thêm về hồ sơ này',
    'profile.seeMore': '...xem thêm',
    'profile.shareProfile': 'Chia sẻ hồ sơ',
    'profile.description': 'Mô tả',
    'profile.copiedLink': 'Đã sao chép liên kết vào clipboard',

    'nav.studio': 'HuTube Studio',
    'nav.enterStudio': 'Vào Studio',
    'nav.studioSub': 'Sáng tạo & Quản lý video',
    'nav.logout': 'Đăng xuất',
    'nav.collapseSidebar': 'Thu gọn sidebar',
    'nav.expandSidebar': 'Mở rộng sidebar',
    'nav.searchPlaceholder': 'Tìm video, kênh hoặc chủ đề',
    'nav.notifications': 'Thông báo',
    'nav.theme': 'Giao diện',
    'nav.themeLight': 'Chế độ Sáng',
    'nav.themeDark': 'Chế độ Tối',
    'nav.language': 'Ngôn ngữ',
    'nav.langVi': 'Tiếng Việt',
    'nav.langEn': 'English',
    'nav.terms': 'Điều khoản',
    'nav.privacy': 'Quyền riêng tư',
    'nav.guidelines': 'Quy tắc cộng đồng',
    'nav.policyHub': 'Chính sách & An toàn',
    'nav.navigation': 'Điều hướng chính',
    'nav.guestPrompt': 'Đăng nhập để bắt đầu xem, lưu và tương tác với video.',

    // Policy Hub Page
    'policies.hubTitle': 'Chính sách & An toàn',
    'policies.guidelines': 'Quy tắc cộng đồng',
    'policies.privacy': 'Quyền riêng tư & Bảo mật',
    'policies.terms': 'Điều khoản dịch vụ',
    'policies.monetization': 'Kiếm tiền & Đối tác',
    'policies.enforcement': 'Thực thi & Khiếu nại',
    'policies.print': 'In tài liệu',
    'policies.downloadPdf': 'Tải PDF',
    'policies.printToast': 'Đã gửi lệnh in tài liệu chính sách thành công.',
    'policies.pdfToast': 'Đã tải bản sao lưu PDF chính sách thành công.',
    'policies.closeToast': 'Đóng thông báo',
    'policies.categoryNav': 'Danh mục chính sách',
    'policies.breadcrumb': 'Đường dẫn điều hướng',

    'policies.breadcrumbHome': 'Trang chủ',
    'policies.breadcrumbLegal': 'Chính sách & Pháp lý',
    'policies.badgeStandard': 'Tiêu chuẩn HuTube · Tham chiếu Chuẩn Quốc tế & Nghị định 13/2023/NĐ-CP',
    'policies.heroTitle': 'Các chính sách của chúng tôi',
    'policies.heroMission': 'Sứ mệnh của HuTube là trao cho mọi người tiếng nói và cho họ thấy thế giới. Sự cởi mở và quyền tự do biểu đạt đóng vai trò cốt lõi trong sứ mệnh này. Trên nền tảng của chúng tôi, các quan điểm đa chiều đều được khuyến khích, đồng thời luôn duy trì không gian an toàn, lành mạnh cho cộng đồng.',
    'policies.heroUpdated': 'Cập nhật: Năm 2026',
    'policies.heroEffective': 'Hiệu lực: Toàn bộ nền tảng HuTube, ứng dụng di động & dịch vụ trực tuyến',

    'policies.tab.guidelines.title': 'Quy tắc cộng đồng',
    'policies.tab.guidelines.desc': 'Các tiêu chuẩn giữ cho HuTube là một không gian an toàn, tôn trọng và lành mạnh cho mọi người sáng tạo và khán giả.',
    'policies.tab.privacy.title': 'Quyền riêng tư & Bảo mật',
    'policies.tab.privacy.desc': 'Cam kết minh bạch về dữ liệu, bảo vệ thông tin cá nhân theo Nghị định 13/2023/NĐ-CP và trao toàn quyền kiểm soát cho bạn.',
    'policies.tab.terms.title': 'Điều khoản dịch vụ',
    'policies.tab.terms.desc': 'Quy định pháp lý ràng buộc về quyền và nghĩa vụ khi truy cập, chia sẻ video và sử dụng dịch vụ trên HuTube.',
    'policies.tab.monetization.title': 'Kiếm tiền & Đối tác',
    'policies.tab.monetization.desc': 'Tiêu chuẩn tham gia Chương trình Đối tác HuTube, định hướng nội dung phù hợp quảng cáo và cơ chế chia sẻ doanh thu.',
    'policies.tab.enforcement.title': 'Thực thi & Khiếu nại',
    'policies.tab.enforcement.desc': 'Quy trình xử phạt vi phạm minh bạch qua hệ thống cảnh báo, xem xét ngoại lệ EDSA và giải quyết khiếu nại công bằng.',

    'policies.itemCount': '{count} mục',
    'policies.mandatoryRules': 'Các quy chuẩn bắt buộc:',
    'policies.exceptionsEdsa': 'Trường hợp ngoại lệ được xem xét (EDSA):',
    'policies.emptySearchTitle': 'Không tìm thấy chính sách phù hợp',
    'policies.emptySearchDesc': 'Không có quy tắc nào khớp với từ khóa "{query}" trong danh mục này.',
    'policies.clearSearch': 'Xóa từ khóa tìm kiếm',

    'policies.sev.critical': 'Nghiêm trọng',
    'policies.sev.high': 'Mức cao',
    'policies.sev.medium': 'Tiêu chuẩn',
    'policies.sev.info': 'Thông tin',

    'policies.tools.title': 'Quyền và Lựa chọn của Bạn',
    'policies.tools.desc': 'Theo Nghị định 13/2023/NĐ-CP, bạn nắm giữ toàn quyền quản lý dữ liệu cá nhân tại HuTube.',
    'policies.tools.exportTag': 'XUẤT DỮ LIỆU',
    'policies.tools.exportTitle': 'Xuất bản sao dữ liệu',
    'policies.tools.exportDesc': 'Tải về bản sao video, bình luận, lịch sử và thông tin cá nhân dưới định dạng tệp ZIP nén bảo mật.',
    'policies.tools.exportBtn': 'Yêu cầu tệp dữ liệu',
    'policies.tools.algoTag': 'THUẬT TOÁN',
    'policies.tools.algoTitle': 'Đặt lại bảng tin & Lịch sử',
    'policies.tools.algoDesc': 'Xóa sạch lịch sử các clip đã xem, từ khóa tìm kiếm và thiết lập lại 100% thuật toán gợi ý video.',
    'policies.tools.algoBtn': 'Đặt lại bảng tin',
    'policies.tools.adsTag': 'QUẢNG CÁO',
    'policies.tools.adsTitle': 'Quản lý quảng cáo',
    'policies.tools.adsDesc': 'Bật hoặc tắt tính năng theo dõi hành vi bên ngoài để phân phối quảng cáo cá nhân hóa.',
    'policies.tools.adsLabel': 'Cá nhân hóa Ads:',
    'policies.tools.adsStatusOn': 'BẬT',
    'policies.tools.adsStatusOff': 'TẮT',
    'policies.tools.exportSuccess': 'Yêu cầu xuất bản sao dữ liệu đã được ghi nhận. Link tải tệp nén ZIP sẽ gửi tới email của bạn trong vòng 24 giờ theo Nghị định 13/2023/NĐ-CP.',
    'policies.tools.resetSuccess': 'Thuật toán gợi ý cá nhân hóa của bạn đã được thiết lập lại về mặc định.',
    'policies.tools.resetConfirm': 'Bạn có chắc chắn muốn đặt lại toàn bộ dữ liệu gợi ý và lịch sử thuật toán Dành cho bạn?',
    'policies.tools.adsChanged': 'Đã {status} tính năng cá nhân hóa quảng cáo theo hành vi.',

    'policies.strikes.systemTitle': 'Hệ thống Cảnh báo & Gậy Phạt (Strikes System)',
    'policies.strikes.systemDesc': 'HuTube áp dụng cơ chế thực thi nhiều bước kết hợp khóa học chính sách nhằm hỗ trợ người sáng tạo nhận biết lỗi và khắc phục.',
    'policies.strikes.warning.badge': 'Nhắc nhở',
    'policies.strikes.warning.title': 'Nhắc nhở lần đầu',
    'policies.strikes.warning.desc': 'Lần đầu vi phạm sẽ chỉ nhận thông báo nhắc nhở kèm khóa học 15 phút. Nội dung bị gỡ nhưng kênh không bị phạt gậy và không bị hạn chế tính năng.',
    'policies.strikes.s1.badge': 'Cảnh cáo 1',
    'policies.strikes.s1.title': 'Gậy lần 1',
    'policies.strikes.s1.desc': 'Tạm ngưng quyền tải video, livestream, tạo bài viết cộng đồng trong vòng 7 ngày. Gậy tồn tại trên kênh trong 90 ngày.',
    'policies.strikes.s2.badge': 'Cảnh cáo 2',
    'policies.strikes.s2.title': 'Gậy lần 2',
    'policies.strikes.s2.desc': 'Nếu nhận gậy thứ 2 trong vòng 90 ngày kể từ gậy 1, kênh bị đóng băng toàn bộ hoạt động đăng tải trong 14 ngày.',
    'policies.strikes.s3.badge': 'Chấm dứt',
    'policies.strikes.s3.title': 'Gậy lần 3 - Chấm dứt',
    'policies.strikes.s3.desc': 'Nhận đủ 3 gậy trong 90 ngày sẽ dẫn đến việc chấm dứt vĩnh viễn tài khoản HuTube, xóa toàn bộ video và cấm tạo kênh mới.',
    'policies.footer.brandCaption': 'Trung tâm Minh bạch & An toàn Người dùng',
    'policies.footer.lang': 'Tiếng Việt (Việt Nam)',
    'policies.footer.copyright': '© 2026 HuTube LLC. Bảo lưu mọi quyền theo quy chuẩn pháp luật Việt Nam.',

    // 33 Policy Names and Contents (VI)
    'policy.CHILD_SAFETY.name': 'An toàn cho trẻ em',
    'policy.CHILD_SAFETY.content': 'Tuyệt đối không khoan nhượng với hành vi bóc lột, lạm dụng tình dục hoặc đưa trẻ em vào tình huống nguy hiểm. Cấm CSAM/CSAE, cấm lôi kéo vào thử thách đe dọa thể xác và tâm lý.',
    'policy.SEXUAL_CONTENT.name': 'Nội dung tình dục và ảnh khỏa thân',
    'policy.SEXUAL_CONTENT.content': 'Nghiêm cấm nội dung khiêu dâm, hành vi tình dục rõ ràng hoặc khỏa thân không phù hợp với không gian chung. Cho phép ngoại lệ tác phẩm điêu khắc, hội họa hoặc giáo dục giới tính có ngữ cảnh.',
    'policy.SELF_HARM.name': 'Nội dung tự làm hại bản thân và tự tử',
    'policy.SELF_HARM.content': 'Cấm khuyến khích, hướng dẫn hoặc cổ xúy các hành vi tự tử và tự gây thương tích, thử thách bỏ đói hoặc rối loạn ăn uống cực đoan.',
    'policy.VIOLENCE.name': 'Nội dung bạo lực hoặc đẫm máu',
    'policy.VIOLENCE.content': 'Cấm video bạo lực đồ họa tàn bạo, khủng bố, hoặc kích động bạo lực trong thế giới thực. Tư liệu lịch sử hoặc phóng sự báo chí bắt buộc phải có cảnh báo đầu video.',
    'policy.ANIMAL_ABUSE.name': 'Ngược đãi động vật',
    'policy.ANIMAL_ABUSE.content': 'Nghiêm cấm hành hạ, đánh đập, giết hại dã man động vật hoặc dàn dựng giải cứu động vật giả để câu view.',
    'policy.HATE_SPEECH.name': 'Nội dung kích động thù địch',
    'policy.HATE_SPEECH.content': 'Cấm ngôn từ thù hận, miệt thị dựa trên chủng tộc, tôn giáo, giới tính, khuynh hướng tính dục hoặc tình trạng khuyết tật.',
    'policy.HARASSMENT.name': 'Hành vi quấy rối và đe dọa bắt nạt',
    'policy.HARASSMENT.content': 'Cấm đe dọa vũ lực, sỉ nhục ngoại hình lặp đi lặp lại nhằm quấy nhiễu đời tư hoặc triệt hạ nhân phẩm cá nhân.',
    'policy.DANGEROUS_ACTIVITIES.name': 'Hoạt động nguy hiểm hoặc có hại',
    'policy.DANGEROUS_ACTIVITIES.content': 'Cấm các thử thách viral liều lĩnh có nguy cơ gây thương tật nặng hoặc tử vong, cấm hướng dẫn chế tạo vũ khí, chất nổ hoặc độc dược.',
    'policy.SPAM_SCAM.name': 'Nội dung rác và hành vi lừa đảo',
    'policy.SPAM_SCAM.content': 'Bảo vệ khán giả khỏi bình luận rác hàng loạt, lừa đảo đa cấp tài chính, tiền ảo không rõ nguồn gốc hoặc cam kết lợi nhuận phi thực tế.',
    'policy.IMPERSONATION.name': 'Hành vi mạo danh',
    'policy.IMPERSONATION.content': 'Cấm tạo kênh giả mạo người nổi tiếng, cơ quan chức năng hoặc thương hiệu để gây nhầm lẫn và trục lợi.',
    'policy.FAKE_ENGAGEMENT.name': 'Tương tác ảo và thao túng nền tảng',
    'policy.FAKE_ENGAGEMENT.content': 'Cấm dùng bot, dịch vụ cày view hoặc mua bán sub/like ảo. HuTube tự động trừ bỏ và đóng băng các kênh vi phạm thao túng số liệu.',
    'policy.MISLEADING_METADATA.name': 'Metadata sai lệch và clickbait lừa dối',
    'policy.MISLEADING_METADATA.content': 'Tiêu đề, ảnh thu nhỏ (thumbnail) và mô tả phải phản ánh đúng nội dung thực tế của video.',
    'policy.EXTERNAL_LINKS.name': 'Liên kết ngoài độc hại',
    'policy.EXTERNAL_LINKS.content': 'Cấm đính kèm đường link dẫn tới trang web lừa đảo, phát tán mã độc hoặc nội dung cấm.',
    'policy.MISINFORMATION_SYNTHETIC.name': 'Thông tin sai lệch và nội dung AI / Deepfake',
    'policy.MISINFORMATION_SYNTHETIC.content': 'Ngăn chặn tin giả nguy hại và kiểm soát tính minh bạch của nội dung AI. Bắt buộc gắn cờ Nội dung AI đối với video mô phỏng người thật.',
    'policy.REGULATED_GOODS.name': 'Hàng hóa và dịch vụ bị kiểm soát đặc biệt',
    'policy.REGULATED_GOODS.content': 'Tuân thủ pháp luật về hàng cấm, vũ khí, chất ma túy và dịch vụ cờ bạc online, cá cược thể thao.',
    'policy.CONTENT_SURFACES.name': 'Phạm vi áp dụng trên toàn bộ nền tảng',
    'policy.CONTENT_SURFACES.content': 'Quy tắc cộng đồng áp dụng đồng bộ trên video dài, Shorts, livestream, thumbnail, bình luận và danh sách phát.',
    'policy.DOXXING_PRIVACY.name': 'Chống công khai dữ liệu cá nhân (Doxxing)',
    'policy.DOXXING_PRIVACY.content': 'Tuyệt đối cấm phát tán thông tin riêng tư (địa chỉ nhà, số điện thoại, biển số xe) của người khác nhằm mục đích quấy rối.',
    'policy.PERSONAL_DOCUMENTS.name': 'Bảo vệ giấy tờ định danh và dữ liệu nhạy cảm',
    'policy.PERSONAL_DOCUMENTS.content': 'Không hiển thị số CCCD, hộ chiếu, thông tin tài khoản ngân hàng trong video mà không che mờ.',
    'policy.NON_CONSENSUAL.name': 'Nội dung không có sự đồng thuận',
    'policy.NON_CONSENSUAL.content': 'Nghiêm cấm phát tán hình ảnh hoặc video nhạy cảm khi chưa được sự đồng thuận rõ ràng của người trong cuộc.',
    'policy.MINOR_DATA_PROTECTION.name': 'Quyền riêng tư của trẻ em và thanh thiếu niên',
    'policy.MINOR_DATA_PROTECTION.content': 'Thiết lập bảo vệ tối đa cho tài khoản người dùng dưới 16 tuổi theo Nghị định 13/2023/NĐ-CP.',
    'policy.SECURITY_ENCRYPTION.name': 'Tiêu chuẩn bảo mật TLS 1.3 và lưu trữ AES-256',
    'policy.SECURITY_ENCRYPTION.content': 'Toàn bộ dữ liệu truyền tải và lưu trữ được bảo vệ theo các chuẩn mã hóa hàng đầu tại Data Center Việt Nam.',
    'policy.TERMS_ACCEPTANCE.name': 'Chấp thuận điều khoản và phạm vi dịch vụ',
    'policy.TERMS_ACCEPTANCE.content': 'Quy định pháp lý ràng buộc khi truy cập và sử dụng dịch vụ trên nền tảng mạng xã hội video HuTube.',
    'policy.USER_ACCOUNTS.name': 'Quyền và trách nhiệm tài khoản người dùng',
    'policy.USER_ACCOUNTS.content': 'Bảo mật thông tin đăng nhập, xác thực 2 bước và chịu trách nhiệm về mọi hoạt động diễn ra dưới tài khoản.',
    'policy.COPYRIGHT_UGC.name': 'Bản quyền nội dung tải lên và giấy phép cấp cho HuTube',
    'policy.COPYRIGHT_UGC.content': 'Tác giả giữ toàn quyền sở hữu tác phẩm và cấp phép phát sóng cho HuTube. Nghiêm cấm vi phạm bản quyền bên thứ ba.',
    'policy.SERVICE_TERMINATION.name': 'Chấm dứt dịch vụ và đóng tài khoản',
    'policy.SERVICE_TERMINATION.content': 'HuTube có quyền ngưng cung cấp dịch vụ hoặc xóa tài khoản đối với các hành vi vi phạm nghiêm trọng hoặc tái phạm nhiều lần.',
    'policy.LIABILITY_LIMITATION.name': 'Giới hạn trách nhiệm pháp lý',
    'policy.LIABILITY_LIMITATION.content': 'Phạm vi trách nhiệm pháp lý của HuTube đối với các nội dung do bên thứ ba hoặc người dùng tải lên.',
    'policy.PARTNER_ELIGIBILITY.name': 'Điều kiện tham gia Chương trình Đối tác HuTube',
    'policy.PARTNER_ELIGIBILITY.content': 'Ngưỡng điều kiện người đăng ký, giờ xem công khai hợp lệ và kênh không có gậy cảnh cáo vi phạm còn hiệu lực.',
    'policy.AD_SUITABILITY_GUIDE.name': 'Tiêu chuẩn nội dung thân thiện với nhà quảng cáo',
    'policy.AD_SUITABILITY_GUIDE.content': 'Hệ thống đánh giá tính phù hợp hiển thị quảng cáo: Biểu tượng Xanh (Bật đầy đủ), Vàng (Hạn chế), Đỏ (Không quảng cáo).',
    'policy.REVENUE_PAYOUTS.name': 'Chia sẻ doanh thu và nghĩa vụ thuế',
    'policy.REVENUE_PAYOUTS.content': 'Quy trình quyết toán định kỳ hàng tháng qua tài khoản ngân hàng chính chủ và khấu trừ thuế theo quy định pháp luật Việt Nam.',
    'policy.STRIKES_WARNING.name': 'Hệ thống cảnh báo và gậy vi phạm',
    'policy.STRIKES_WARNING.content': 'Cơ chế xử phạt lũy tiến: Nhắc nhở (Warning), Gậy 1 (khóa 7 ngày), Gậy 2 (khóa 14 ngày), Gậy 3 (chấm dứt kênh vĩnh viễn).',
    'policy.EDSA_EXCEPTIONS.name': 'Nguyên tắc xem xét ngoại lệ EDSA',
    'policy.EDSA_EXCEPTIONS.content': 'Xem xét ngữ cảnh đặc biệt đối với nội dung Giáo dục (E), Tài liệu (D), Khoa học (S), Nghệ thuật (A) và Lợi ích công chúng.',
    'policy.APPEALS_PROCESS.name': 'Quy trình khiếu nại minh bạch',
    'policy.APPEALS_PROCESS.content': 'Quyền khiếu nại quyết định kiểm duyệt trong vòng 30 ngày; chuyên viên con người phản hồi và xử lý trong 48 giờ.',
    'policy.MODERATION_INFRASTRUCTURE.name': 'Hạ tầng kiểm duyệt kết hợp AI và chuyên viên con người',
    'policy.MODERATION_INFRASTRUCTURE.content': 'Hệ sinh thái kiểm duyệt đa tầng: AI quét tự động đa phương thức kết hợp đội ngũ kiểm duyệt viên bản địa thẩm định.',

    // Auth
    'auth.loginTitle': 'Đăng nhập vào HuTube',
    'auth.registerTitle': 'Tạo tài khoản HuTube',
    'auth.forgotPasswordTitle': 'Khôi phục mật khẩu',
    'auth.resetPasswordTitle': 'Đặt lại mật khẩu mới',
    'auth.verifyEmailTitle': 'Xác minh tài khoản email',
    'auth.email': 'Email',
    'auth.password': 'Mật khẩu',
    'auth.confirmPassword': 'Xác nhận mật khẩu',
    'auth.displayName': 'Tên hiển thị',
    'auth.username': 'Tên người dùng',
    'auth.loginBtn': 'Đăng nhập',
    'auth.registerBtn': 'Đăng ký ngay',
    'auth.forgotPasswordLink': 'Quên mật khẩu?',
    'auth.dontHaveAccount': 'Chưa có tài khoản HuTube?',
    'auth.alreadyHaveAccount': 'Đã có tài khoản?',
    'auth.resendOtp': 'Gửi lại mã OTP',
    'auth.backToLogin': 'Quay lại đăng nhập',
    'auth.continueGoogle': 'Tiếp tục với Google',

    // Account / Settings
    'account.title': 'Cài đặt tài khoản',
    // Settings Tabs (YouTube-style)
    'account.settingsTitle': 'Cài đặt',
    'account.tabAccount': 'Tài khoản',
    'account.tabNotifications': 'Thông báo',
    'account.tabPlayback': 'Chức năng phát và hiệu suất',
    'account.tabDownloads': 'Nội dung tải xuống',
    'account.tabPrivacy': 'Quyền riêng tư',
    'account.tabConnected': 'Ứng dụng đã kết nối',
    'account.tabBilling': 'Lập hóa đơn và thanh toán',
    'account.tabAdvanced': 'Cài đặt nâng cao',

    // Tab Account Hero & Sections (Image 1)
    'account.accountHeroTitle': 'Chọn cách bạn xuất hiện và nội dung bạn muốn xem trên HuTube',
    'account.signedInAs': 'Đăng nhập bằng',
    'account.channelDescImage1': 'Đây là sự hiện diện công khai của bạn trên HuTube. Bạn cần có một kênh để tải video của riêng mình lên, bình luận về các video hoặc tạo danh sách phát.',
    'account.yourChannelLabel': 'Kênh của bạn',
    'account.channelStatusLink': 'Trạng thái và tính năng của kênh',
    'account.createChannelLink': 'Tạo kênh mới',
    'account.viewAdvancedLink': 'Xem cài đặt nâng cao',
    'account.yourAccountSection': 'Tài khoản của bạn',
    'account.yourAccountDesc': 'Bạn đăng nhập vào HuTube bằng Tài khoản HuTube của mình',
    'account.hutubeAccountLabel': 'Tài khoản HuTube',
    'account.hutubeAccountAction': 'Xem hoặc thay đổi các tùy chọn cài đặt cho Tài khoản HuTube của bạn',
    'account.hutubeAccountRedirect': 'Bạn sẽ được chuyển đến trang Tài khoản của mình',

    // Tab Privacy (Image 2)
    'account.privacyHeroTitle': 'Quản lý nội dung mà bạn chia sẻ trên HuTube',
    'account.privacyHeroSub': 'Chọn người có thể xem kênh đăng ký của bạn',
    'account.privacyHeroReview': 'Xem xét',
    'account.privacyHeroTos': 'Điều khoản dịch vụ của HuTube',
    'account.privacyHeroAnd': 'và',
    'account.privacyHeroPrivacyPolicy': 'Chính sách quyền riêng tư của HuTube',
    'account.subscriptionsHeading': 'Kênh đăng ký',
    'account.keepSubsPrivate': 'Đặt tất cả các kênh đăng ký của tôi ở chế độ riêng tư',
    'account.keepSubsPrivateDesc': 'Người khác sẽ không thể thấy danh sách kênh đăng ký của bạn, trừ khi bạn dùng những tính năng khiến danh sách này xuất hiện công khai.',
    'account.keepSubsPrivateLinkText': 'về các tính năng khiến danh sách kênh đăng ký xuất hiện công khai hoặc tìm hiểu cách quản lý danh sách kênh đăng ký',
    'account.clickHere': 'tại đây',
    'account.mentionsHeading': 'Lượt đề cập',
    'account.allowMentions': 'Cho phép người dùng đề cập đến tôi',
    'account.allowMentionsDesc': 'Mọi người đều có thể đề cập đến bạn trong tiêu đề video, nội dung mô tả video, bài đăng và bình luận. Quản lý phần cài đặt thông báo về lượt đề cập',
    'account.liveChatHeading': 'Trò chuyện trực tiếp',
    'account.topFanRanking': 'Bảng xếp hạng người hâm mộ hàng đầu',
    'account.topFanRankingDesc': 'Được xếp hạng trong bảng xếp hạng người hâm mộ hàng đầu với tư cách người xem và kiếm điểm kinh nghiệm (XP) thông qua hoạt động tương tác. Nếu bạn tắt chế độ này, mọi thông tin về việc bạn tham gia bảng xếp hạng trước đây sẽ bị xoá.',
    'account.celebrateSuperChat': 'Ăn mừng Super Chat và Super Stickers',
    'account.celebrateSuperChatDesc': 'Các cột mốc quan trọng về hoạt động mua Super Chat và Super Stickers sẽ được công bố trong cuộc trò chuyện trực tiếp.',
    'account.learnMore': 'Tìm hiểu thêm',
    'account.privacySaved': 'Đã cập nhật cài đặt quyền riêng tư',

    // Tab Downloads (Matching YouTube Screenshot)
    'account.downloadsHeroTitle': 'Kiểm soát các tùy chọn tải nội dung xuống',
    'account.downloadsHeroSub': 'Các tùy chọn tải nội dung xuống chỉ áp dụng cho trình duyệt này',
    'account.downloadQualityHeading': 'Chất lượng tải xuống',
    'account.downloadQualityAsk': 'Hỏi mỗi lần tải xuống',
    'account.downloadQuality1080p': 'HD đầy đủ (1080p)',
    'account.downloadQuality720p': 'Cao (720p)',
    'account.downloadQuality480p': 'Chuẩn (480p)',
    'account.downloadQuality144p': 'Thấp (144p)',
    'account.smartDownloadsHeading': 'Tải xuống thông minh',
    'account.smartDownloadsToggle': 'Bật tính năng tải xuống thông minh',
    'account.smartDownloadsDesc': 'Chúng tôi sẽ tự động tải video đề xuất xuống cho bạn.',
    'account.deleteAllDownloadsHeading': 'Xóa tất cả video tải xuống',
    'account.deleteAllDownloadsDesc': 'Khi bạn xóa video tải xuống, thiết bị này sẽ có thêm dung lượng trống',
    'account.deleteAllDownloadsBtn': 'Xóa tất cả video tải xuống',
    'account.deleteAllDownloadsSuccess': 'Đã xóa tất cả video tải xuống trên thiết bị này',
    'account.downloadQualitySaved': 'Đã cập nhật chất lượng tải xuống',
    'account.smartDownloadsSaved': 'Đã cập nhật tính năng tải xuống thông minh',

    // Tab Billing and Payments
    'account.billingHeroTitle': 'Lập hóa đơn và thanh toán',
    'account.billingHeroSub': 'Quản lý phương thức thanh toán và các gói thành viên HuTube',
    'account.paymentMethodsHeading': 'Phương thức thanh toán',
    'account.noPaymentMethod': 'Chưa có phương thức thanh toán nào được lưu',
    'account.addPaymentMethod': 'Thêm phương thức thanh toán',
    'account.membershipsHeading': 'Giao dịch mua và gói thành viên',
    'account.membershipsDesc': 'Tận hưởng trải nghiệm HuTube không quảng cáo, tải video ngoại tuyến và xem phát trong nền với HuTube Premium',
    'account.learnMorePremium': 'Tìm hiểu về HuTube Premium',

    'account.tabProfile': 'Hồ sơ',
    'account.tabPassword': 'Mật khẩu',
    'account.tabPreferences': 'Giao diện & Cài đặt',
    'account.tabSessions': 'Thiết bị & Phiên',
    'account.profileHeading': 'Thông tin cá nhân',
    'account.profileDesc': 'Quản lý thông tin công khai và ảnh đại diện của bạn.',
    'account.avatarTitle': 'Ảnh đại diện',
    'account.avatarHint': 'JPG, PNG, WEBP hoặc GIF. Kích thước tối đa 5MB.',
    'account.changeAvatar': 'Thay đổi ảnh',
    'account.saveProfile': 'Lưu hồ sơ',
    'account.displayName': 'Họ và tên',
    'account.displayNamePlaceholder': 'Nhập họ và tên hiển thị',
    'account.email': 'Email',
    'account.verified': 'Đã xác minh',
    'account.unverified': 'Chưa xác minh',
    'account.username': 'Tên người dùng',
    'account.channelUrlPrefix': 'URL kênh của bạn:',
    'account.country': 'Địa chỉ / Quốc gia',
    'account.countryVN': 'Việt Nam',
    'account.countryUS': 'Hoa Kỳ',
    'account.countryJP': 'Nhật Bản',
    'account.countryKR': 'Hàn Quốc',
    'account.countrySG': 'Singapore',
    'account.bio': 'Giới thiệu bản thân',
    'account.bioPlaceholder': 'Chia sẻ đôi nét về bạn...',
    'account.userId': 'Mã định danh tài khoản (User ID)',
    'account.copy': 'Sao chép',
    'account.copied': 'Đã sao chép',
    'account.subscribersCount': 'người đăng ký',
    'account.videosCount': 'video',
    'account.viewChannel': 'Xem kênh',
    'account.customizeChannel': 'Tùy chỉnh kênh',
    'account.yourHuTubeChannel': 'Kênh HuTube của bạn',
    'account.noChannelDesc': 'Bạn chưa có kênh HuTube. Hãy tạo kênh ngay để bắt đầu tải video, xây dựng cộng đồng và chia sẻ đam mê sáng tạo!',
    'account.createChannelBtn': 'Tạo kênh mới',
    'account.passwordHeading': 'Đổi mật khẩu',
    'account.passwordDesc': 'Để bảo mật, hãy sử dụng mật khẩu mạnh có ít nhất 10 ký tự.',
    'account.currentPassword': 'Mật khẩu hiện tại',
    'account.newPassword': 'Mật khẩu mới',
    'account.confirmNewPassword': 'Nhập lại mật khẩu mới',
    'account.savePassword': 'Cập nhật mật khẩu',
    'account.notifHeading': 'Tùy chọn thông báo',
    'account.notifDesc': 'Chọn các loại thông báo bạn muốn nhận qua hệ thống và email.',
    'account.notifInAppTitle': 'Thông báo trong ứng dụng',
    'account.notifInAppDesc': 'Hiển thị thông báo trên chuông thông báo khi có hoạt động mới.',
    'account.notifEmailTitle': 'Thông báo qua Email',
    'account.notifEmailDesc': 'Nhận email thông báo về các cập nhật tài khoản quan trọng.',
    'account.notifNewVideoTitle': 'Video mới từ kênh đã đăng ký',
    'account.notifNewVideoDesc': 'Nhận thông báo khi kênh bạn theo dõi xuất bản video mới.',
    'account.notifCommentReplyTitle': 'Phản hồi bình luận',
    'account.notifCommentReplyDesc': 'Thông báo khi có người trả lời hoặc thích bình luận của bạn.',
    'account.notifMentionTitle': 'Nhắc đến bạn (Mentions)',
    'account.notifMentionDesc': 'Nhận thông báo khi ai đó nhắc đến bạn trong video hoặc bình luận.',
    'account.notifChannelActivityTitle': 'Hoạt động từ kênh của bạn',
    'account.notifChannelActivityDesc': 'Cập nhật lượt xem, người đăng ký mới và tương tác với kênh.',
    'account.notifNewVideos': 'Video mới từ kênh đã đăng ký',
    'account.notifComments': 'Bình luận và phản hồi',
    'account.notifSubs': 'Người đăng ký mới',
    'account.notifMarketing': 'Cập nhật tính năng và bản tin HuTube',
    'account.prefsHeading': 'Giao diện & Ngôn ngữ',
    'account.prefsDesc': 'Tùy chỉnh trải nghiệm xem và giao diện ứng dụng của bạn.',
    'account.themeLabel': 'Giao diện (Chế độ màu)',
    'account.themeLight': 'Nền sáng (Mặc định)',
    'account.themeDark': 'Nền tối (Dịu mắt)',
    'account.langLabel': 'Ngôn ngữ hiển thị',
    'account.playbackHeading': 'Phát video',
    'account.autoplayNext': 'Tự động phát video tiếp theo',
    'account.defaultQuality': 'Chất lượng video mặc định',
    'account.privacyHeading': 'Quyền riêng tư',
    'account.keepPlaylistsPrivate': 'Giữ danh sách phát đã lưu ở chế độ riêng tư',
    'account.keepPlaylistsPrivateDesc': 'Chỉ bạn mới có quyền xem các playlist bạn đã lưu.',
    'account.savePrefs': 'Lưu cài đặt',
    'account.sessionsHeading': 'Phiên đăng nhập đang hoạt động',
    'account.sessionsDesc': 'Danh sách các thiết bị hiện đang đăng nhập vào tài khoản của bạn.',
    'account.currentDevice': 'Thiết bị hiện tại',
    'account.thisDevice': 'Thiết bị này',
    'account.signedInAt': 'Đăng nhập:',
    'account.lastActiveAt': 'Hoạt động:',
    'account.ipAddress': 'Địa chỉ IP:',
    'account.revoke': 'Thu hồi',
    'account.confirmRevokeText': 'Bạn có chắc chắn muốn đăng xuất phiên trên thiết bị',
    'account.noSessions': 'Không có phiên đăng nhập nào.',
    'account.logoutOthers': 'Đăng xuất khỏi các thiết bị khác',
    'account.logoutAll': 'Đăng xuất mọi thiết bị',
    'account.revokeSession': 'Đăng xuất thiết bị này',
    'account.profileSaved': 'Đã lưu thông tin hồ sơ thành công.',
    'account.avatarSizeError': 'Kích thước ảnh đại diện tối đa là 5MB.',
    'account.avatarUpdated': 'Đã cập nhật ảnh đại diện mới.',
    'account.enterCurrentPassword': 'Vui lòng nhập mật khẩu hiện tại.',
    'account.newPasswordLength': 'Mật khẩu mới cần từ 10 đến 128 ký tự.',
    'account.passwordsDoNotMatch': 'Mật khẩu xác nhận chưa khớp.',
    'account.notifSaved': 'Đã lưu tùy chọn thông báo thành công.',
    'account.prefsSaved': 'Đã lưu cài đặt giao diện và ngôn ngữ.',
    'account.userIdCopied': 'Đã sao chép ID người dùng vào clipboard.',
    'account.retryLogout': 'Hãy thử đăng xuất lại.',
    'account.loggedOutOthers': 'Đã đăng xuất khỏi các thiết bị khác.',
    'account.sessionEnded': 'Đã kết thúc phiên đăng nhập thiết bị.',

    // Channel
    'channel.subscribers': 'người đăng ký',
    'channel.videos': 'Video',
    'channel.playlists': 'Danh sách phát',
    'channel.about': 'Giới thiệu',
    'channel.customize': 'Tùy chỉnh kênh',
    'channel.manageVideos': 'Quản lý video',
    'channel.createTitle': 'Khởi tạo kênh HuTube',
    'channel.createDesc': 'Bắt đầu hành trình sáng tạo nội dung của riêng bạn trên HuTube.',
    'channel.name': 'Tên kênh',
    'channel.handle': 'Tên định danh (Handle)',
    'channel.description': 'Mô tả kênh',
    'channel.createBtn': 'Tạo kênh ngay',
    'channel.invitationsTitle': 'Lời mời tham gia quản lý kênh',
    'channel.accept': 'Chấp nhận',
    'channel.decline': 'Từ chối',
    'channel.noInvitations': 'Bạn hiện không có lời mời nào.',

    // Studio
    'studio.title': 'HuTube Creator Studio',
    'studio.overview': 'Tổng quan',
    'studio.content': 'Nội dung',
    'studio.uploadVideo': 'Upload video',
    'studio.analytics': 'Phân tích',
    'studio.comments': 'Bình luận',
    'studio.subtitles': 'Phụ đề',
    'studio.settings': 'Cài đặt kênh',
    'studio.proTitle': 'HuTube Pro',
    'studio.proDesc': 'Mở khóa nhiều tính năng hơn cho nhà sáng tạo',
    'studio.upgradeNow': 'Nâng cấp ngay',
    'studio.collapse': 'Thu gọn',
    'studio.searchPlaceholder': 'Tìm kiếm trong kênh của bạn...',
    'studio.create': 'Tạo',
    'studio.creator': 'Creator',
    'studio.backToWeb': 'Trở về HuTube',
    'studio.overviewSubtitle': 'Tổng quan kênh và hiệu suất 28 ngày qua',
    'studio.subscribersCount': 'Số người đăng ký',
    'studio.viewsCount': 'Lượt xem',
    'studio.watchTime': 'Thời gian xem (giờ)',
    'studio.estimatedRevenue': 'Doanh thu ước tính',
    'studio.past28Days': '28 ngày qua',
    'studio.latestVideo': 'Video mới nhất của bạn',
    'studio.viewAllVideos': 'Xem tất cả video →',
    'studio.publishedYesterday': 'Đã xuất bản: Hôm qua',
    'studio.public': 'Công khai',
    'studio.draft': 'Bản nháp',
    'studio.views': 'lượt xem',
    'studio.likes': 'lượt thích',
    'studio.commentsCount': 'bình luận',
    'studio.analyticsBtn': '📊 Số liệu phân tích',
    'studio.commentsBtn': '💬 Bình luận',
    'studio.contentSubtitle': 'Quản lý các video, bài viết và danh sách phát trên kênh',
    'studio.filterPlaceholder': 'Lọc video theo tiêu đề...',
    'studio.all': 'Tất cả',
    'studio.colVideo': 'Video',
    'studio.colVisibility': 'Hiển thị',
    'studio.colDate': 'Ngày đăng',
    'studio.colViews': 'Lượt xem',
    'studio.colComments': 'Bình luận',
    'studio.colLikes': 'Tỷ lệ thích',
    'studio.colActions': 'Thao tác',
    'studio.edit': 'Sửa',
    'studio.continue': 'Tiếp tục',
    'studio.analyticsSubtitle': 'Dữ liệu phân tích lưu lượng, người xem và tương tác',
    'studio.analyticsSummary': 'Kênh của bạn đã có 148.900 lượt xem trong 28 ngày qua',
    'studio.analyticsDiff': 'Nhiều hơn 23.400 lượt xem so với chu kỳ trước',
    'studio.realtimeViews': 'Lượt xem theo thời gian thực',
    'studio.videoViewsLegend': '● Lượt xem video',
    'studio.commentsSubtitle': 'Kiểm duyệt và phản hồi các bình luận của người xem',
    'studio.publishedComments': 'Đã xuất bản',
    'studio.heldForReview': 'Giữ lại để xem xét',
    'studio.hoursAgo': 'giờ trước',
    'studio.onVideo': 'trên',
    'studio.reply': 'Trả lời',
    'studio.like': '❤️ Thích',
    'studio.subtitlesSubtitle': 'Quản lý phụ đề đa ngôn ngữ và tạo phụ đề tự động bằng HuTube AI',
    'studio.primaryLanguage': 'Ngôn ngữ chính',
    'studio.autoSubtitle': 'Tự động',
    'studio.reviewed': 'Đã duyệt',
    'studio.addLanguage': 'Thêm ngôn ngữ',
    'studio.settingsSubtitle': 'Cấu hình kênh, cài đặt tải lên mặc định và quyền hạn',
    'studio.defaultCurrency': 'Đơn vị tiền tệ mặc định',
    'studio.currencyVND': 'VND - Đồng Việt Nam (₫)',
    'studio.currencyUSD': 'USD - Đô la Mỹ ($)',
    'studio.defaultLicense': 'Tiêu chuẩn giấy phép mặc định',
    'studio.licenseStandard': 'Giấy phép Chuẩn của HuTube',
    'studio.licenseCC': 'Creative Commons - Ghi nhận quyền tác giả (CC BY)',
    'studio.defaultCommentsMode': 'Chế độ bình luận mặc định cho video mới',
    'studio.commentsAllowAll': 'Cho phép tất cả bình luận',
    'studio.commentsHoldInappropriate': 'Giữ lại các bình luận có khả năng không phù hợp để xem xét',
    'studio.commentsDisable': 'Tắt tính năng bình luận',

    // Upload Video 6 Steps
    'upload.title': 'Upload video',
    'upload.subtitle': 'Chia sẻ câu chuyện của bạn với cộng đồng HuTube',
    'upload.step1': 'Chọn file',
    'upload.step2': 'Chi tiết video',
    'upload.step3': 'Thành phần video',
    'upload.step4': 'Kiểm tra ban đầu',
    'upload.step5': 'Chế độ hiển thị',
    'upload.step6': 'Publish',

    'upload.step1.boxTitle': 'Chọn file video',
    'upload.step1.boxDesc': 'Tải lên video từ máy tính của bạn để bắt đầu',
    'upload.step1.dragDrop': 'Kéo và thả file video vào đây',
    'upload.step1.btn': 'Chọn file',
    'upload.step1.formats': 'Hỗ trợ định dạng: MP4, MOV, AVI, MKV, WebM',
    'upload.step1.maxSize': 'Dung lượng tối đa: 256 GB',
    'upload.step1.uploading': 'Đang tải lên...',
    'upload.step1.remaining': 'Còn khoảng 2 phút',
    'upload.step1.cancel': 'Hủy',
    'upload.step1.tip': 'Mẹo: Sử dụng video có độ phân giải từ 1080p trở lên để mang lại trải nghiệm tốt nhất cho người xem.',

    'upload.step2.heading': 'Thông tin cơ bản',
    'upload.step2.subheading': 'Cung cấp thông tin chi tiết để giúp người xem dễ dàng tìm thấy video của bạn',
    'upload.step2.videoTitle': 'Tiêu đề',
    'upload.step2.titleHint': 'Tiêu đề nên ngắn gọn, rõ ràng và thu hút người xem.',
    'upload.step2.desc': 'Mô tả',
    'upload.step2.descHint': 'Mô tả chi tiết giúp video của bạn hiển thị tốt hơn trong kết quả tìm kiếm.',
    'upload.step2.thumbnail': 'Hình thu nhỏ (Thumbnail)',
    'upload.step2.changeThumb': 'Thay đổi thumbnail',
    'upload.step2.thumbHint': 'Chọn hình ảnh thu hút người xem. Nên dùng ảnh có tỷ lệ 16:9 (1280 x 720).',
    'upload.step2.category': 'Danh mục',
    'upload.cat.travel': 'Du lịch & Đời sống',
    'upload.cat.music': 'Âm nhạc',
    'upload.cat.tech': 'Công nghệ',
    'upload.cat.education': 'Giáo dục',
    'upload.cat.gaming': 'Trò chơi (Gaming)',
    'upload.cat.entertainment': 'Giải trí',
    'upload.step2.untitled': 'Chưa đặt tiêu đề',
    'upload.step2.tags': 'Thẻ (Tags)',
    'upload.step2.tagsPlaceholder': 'Thêm tag (nhấn Enter)',
    'upload.step2.tagsHint': 'Thêm từ khóa để giúp video dễ dàng được tìm thấy.',
    'upload.step2.language': 'Ngôn ngữ',
    'upload.step2.langHint': 'Chọn ngôn ngữ chính trong video của bạn.',
    'upload.step2.saveDraft': 'Lưu bản nháp',

    'upload.step3.heading': 'Thành phần video',
    'upload.step3.subheading': 'Thêm chương (chapter) để giúp người xem dễ dàng theo dõi nội dung video của bạn.',
    'upload.step3.chapterList': 'Danh sách chương',
    'upload.step3.chapterName': 'Tên chương',
    'upload.step3.chapterStart': 'Thời gian bắt đầu',
    'upload.step3.addChapter': 'Thêm chương mới',
    'upload.step3.chapterNamePlaceholder': 'Nhập tên chương...',
    'upload.step3.timePlaceholder': 'mm:ss (vd: 14:00)',
    'upload.step3.addBtn': 'Thêm chương',
    'upload.step3.chapterTip': 'Mẹo: Kéo thanh thời gian hoặc nhấn vào video ở thời điểm muốn đặt chương, sau đó nhập tên và thêm chương.',
    'upload.step3.aiSubTitle': 'Phụ đề thông minh HuTube AI',
    'upload.step3.aiSubDesc': 'Tự động nhận diện giọng nói và tạo phụ đề có dấu chính xác 98%.',
    'upload.step5.schedDate': 'Ngày công chiếu',
    'upload.step5.schedTime': 'Giờ công chiếu',

    'upload.step4.heading': 'Kiểm tra ban đầu',
    'upload.step4.subheading': 'Chúng tôi đang kiểm tra video của bạn để đảm bảo đáp ứng các tiêu chuẩn của HuTube.',
    'upload.step4.checkFile': 'Tệp video hợp lệ',
    'upload.step4.checkFileSub': 'Định dạng, dung lượng, độ phân giải...',
    'upload.step4.checkMeta': 'Metadata đầy đủ',
    'upload.step4.checkMetaSub': 'Tiêu đề, mô tả, thẻ, danh mục...',
    'upload.step4.checkThumb': 'Thumbnail đạt yêu cầu',
    'upload.step4.checkThumbSub': 'Độ phân giải, tỷ lệ, nội dung phù hợp...',
    'upload.step4.checkCopyright': 'Kiểm tra bản quyền ban đầu',
    'upload.step4.checkCopyrightSub': 'So khớp với cơ sở dữ liệu nội dung có bản quyền...',
    'upload.step4.checkPolicy': 'Kiểm tra nội dung theo chính sách',
    'upload.step4.checkPolicySub': 'Rà soát nội dung nhạy cảm, bạo lực, ngôn từ...',
    'upload.step4.checkTech': 'Xử lý kỹ thuật',
    'upload.step4.checkTechSub': 'Tạo phiên bản xem trước, tạo phụ đề tự động...',
    'upload.step4.passed': 'Đạt',
    'upload.step4.warning': 'Cần chú ý',
    'upload.step4.processing': 'Đang xử lý',
    'upload.step4.issuesHeading': 'Vấn đề cần xem lại',
    'upload.step4.issueDesc': 'Mô tả có thể chi tiết hơn',
    'upload.step4.issueDescSub': 'Mô tả video của bạn đang khá ngắn. Hãy bổ sung thêm thông tin để người xem dễ dàng hiểu nội dung.',
    'upload.step4.issueChapter': 'Thời gian chương (chapters) cần kiểm tra lại',
    'upload.step4.issueChapterSub': 'Một số mốc thời gian có thể chưa chính xác. Vui lòng kiểm tra lại để đảm bảo trải nghiệm tốt nhất.',
    'upload.step4.continueNotice': 'Bạn vẫn có thể tiếp tục. Chúng tôi sẽ thông báo nếu có vấn đề quan trọng cần xử lý.',

    'upload.step5.heading': 'Chế độ hiển thị',
    'upload.step5.subheading': 'Chọn ai có thể xem video của bạn',
    'upload.step5.public': 'Công khai (Public)',
    'upload.step5.publicDesc': 'Mọi người đều có thể tìm kiếm, xem và chia sẻ video của bạn.',
    'upload.step5.recommended': 'Đề xuất',
    'upload.step5.unlisted': 'Không công khai (Unlisted)',
    'upload.step5.unlistedDesc': 'Chỉ những người có đường liên kết mới có thể xem video.',
    'upload.step5.private': 'Riêng tư (Private)',
    'upload.step5.privateDesc': 'Chỉ bạn và những người bạn chọn mới có thể xem video.',
    'upload.step5.publishTime': 'Thời điểm đăng',
    'upload.step5.publishTimeSub': 'Chọn thời điểm video sẽ được xuất bản',
    'upload.step5.publishNow': 'Đăng ngay khi được phê duyệt',
    'upload.step5.publishNowDesc': 'Video sẽ được đăng công khai sau khi xử lý và được duyệt bởi đội ngũ HuTube.',
    'upload.step5.schedule': 'Lên lịch',
    'upload.step5.scheduleDesc': 'Chọn ngày và giờ bạn muốn video được đăng sau khi được phê duyệt.',
    'upload.step5.otherOptions': 'Tùy chọn khác',
    'upload.step5.otherOptionsSub': 'Thiết lập bổ sung cho video của bạn',
    'upload.step5.allowComments': 'Cho phép bình luận',
    'upload.step5.allowCommentsDesc': 'Người xem có thể bình luận về video của bạn.',
    'upload.step5.addPlaylist': 'Thêm vào danh sách phát',
    'upload.step5.selectPlaylist': 'Chọn danh sách phát (tùy chọn)',
    'upload.step5.policyNotice': 'Lưu ý: Video chỉ được hiển thị công khai sau khi quá trình xử lý hoàn tất và được đội ngũ HuTube phê duyệt.',

    'upload.step6.congrats': 'Video đã được gửi để xuất bản!',
    'upload.step6.congratsDesc': 'Video của bạn đã được xử lý và sẵn sàng hiển thị trên kênh. Cảm ơn bạn đã chia sẻ nội dung tuyệt vời với cộng đồng HuTube!',
    'upload.step6.moderationPending': 'Video đã được gửi để kiểm duyệt!',
    'upload.step6.moderationPendingDesc': 'Video đang chờ đội ngũ HuTube phê duyệt. Video chỉ hiển thị công khai sau khi được duyệt; bạn có thể theo dõi trạng thái trong trang Nội dung.',
    'upload.step6.moderationStatus': 'Đang chờ kiểm duyệt',
    'upload.step6.summaryHeading': 'Thông tin video',
    'upload.step6.videoLink': 'Liên kết video',
    'upload.step6.watchVideo': 'Xem video',
    'upload.step6.copyLink': 'Sao chép liên kết',
    'upload.step6.share': 'Chia sẻ',
    'upload.step6.backToContent': 'Về trang nội dung',
    'upload.step6.uploadAnother': 'Tải video khác',

    // Sidebar Widgets
    'upload.sidebar.preview': 'Xem trước video',
    'upload.sidebar.fileInfo': 'Thông tin file',
    'upload.sidebar.format': 'Định dạng',
    'upload.sidebar.size': 'Dung lượng',
    'upload.sidebar.duration': 'Thời lượng',
    'upload.sidebar.resolution': 'Độ phân giải',
    'upload.sourceQuality': 'Chất lượng video nguồn',
    'upload.sourceQualityHint': 'Chỉ có thể chọn mức không vượt quá độ phân giải của video gốc.',
    'upload.sidebar.storageQuota': 'Dung lượng lưu trữ',
    'upload.sidebar.storageUsed': 'Đã sử dụng',
    'upload.sidebar.importantNotes': 'Lưu ý quan trọng',
    'upload.sidebar.note1': 'Chỉ tải lên nội dung do bạn sở hữu hoặc có quyền sử dụng.',
    'upload.sidebar.note2': 'Không đăng tải nội dung vi phạm bản quyền, bạo lực, thù hận hoặc thông tin sai lệch.',
    'upload.sidebar.note3': 'HuTube có thể kiểm tra tự động nội dung của bạn trước khi xuất bản.',
    'upload.sidebar.policyLink': 'Tìm hiểu thêm về chính sách nội dung của HuTube →',
    'upload.sidebar.statusTitle': 'Trạng thái xử lý',
    'upload.sidebar.statusUploaded': 'Upload hoàn tất',
    'upload.sidebar.statusProcessed': 'Xử lý video hoàn tất',
    'upload.sidebar.statusChecked': 'Kiểm tra ban đầu hoàn tất',
    'upload.sidebar.statusReady': 'Sẵn sàng xuất bản',
    'upload.sidebar.statusPublished': 'Đã xuất bản',
    'upload.sidebar.nextTitle': 'Tiếp theo, bạn có thể:',
    'upload.sidebar.nextSubtitles': 'Chỉnh sửa phụ đề',
    'upload.sidebar.nextShare': 'Chia sẻ video với cộng đồng',
    'upload.sidebar.nextAnalytics': 'Xem thống kê video',
    'upload.sidebar.nextManage': 'Quản lý video trong Creator Studio',

    // UI completion: public pages and collaboration flows
    'ui.loadingVideos': 'Đang tải video…',
    'ui.videoLoadError': 'Không thể tải danh sách video.',
    'ui.noVideos': 'Chưa có video nào.',
    'ui.videoList': 'Danh sách video',
    'ui.views': 'lượt xem',
    'ui.seconds': 'giây',
    'ui.people': 'người',
    'ui.videos': 'video',
    'ui.closePopup': 'Đóng popup',
    'ui.verifiedChannel': 'Kênh đã xác minh',
    'ui.openCreatorStudio': 'Mở Creator Studio',
    'ui.more': '...xem thêm',
    'ui.otherLinks': 'và {count} đường liên kết khác',
    'ui.workEmail': 'Email công việc',
    'ui.description': 'Mô tả',
    'ui.links': 'Đường liên kết',
    'ui.otherInfo': 'Thông tin khác',
    'ui.vietnam': 'Việt Nam',
    'ui.joined': 'Đã tham gia {date}',
    'ui.subscribers': 'người đăng ký',
    'ui.comments': 'bình luận',
    'ui.watchHours': 'giờ',
    'ui.upload': 'Tải video lên',
    'ui.likes': 'lượt thích',
    'ui.public': '🌐 Công khai',
    'ui.unlisted': '🔗 Không công khai',
    'ui.private': '🔒 Riêng tư',
    'ui.moderationApproved': '✓ Đã duyệt',
    'ui.moderationPending': '⏳ Chờ duyệt',
    'ui.moderationReviewing': '🔍 Đang thẩm định',
    'ui.moderationRejected': '✕ Bị từ chối',
    'ui.moderationNotSubmitted': 'Chưa gửi duyệt',
    'ui.saving': 'Đang lưu…',
    'ui.noData': 'Chưa có dữ liệu.',
    'ui.all': 'Tất cả',
    'ui.yes': 'Có',
    'ui.no': 'Không',
    'ui.supported': '✓ Hỗ trợ',
    'ui.notSupported': '✕ Không hỗ trợ',
    'ui.copyLink': 'Sao chép liên kết',
    'ui.share': 'Chia sẻ',
    'ui.openLink': 'Mở liên kết',
    'ui.invite': 'Mời thành viên',
    'ui.revoke': 'Thu hồi',
    'ui.status': 'Trạng thái',
    'ui.date': 'Ngày',
    'ui.actions': 'Thao tác',

    'home.loading': 'Đang tải video…',
    'home.error': 'Không thể tải danh sách video.',
    'home.empty': 'Chưa có video nào.',
    'home.videoList': 'Danh sách video',
    'home.views': 'lượt xem',
    'explore.filters': 'Bộ lọc khám phá',
    'explore.heading': 'Khám phá video',
    'explore.searchHeading': 'Kết quả tìm kiếm',
    'explore.subtitle': 'Tìm câu chuyện, kiến thức và nhà sáng tạo mới trên HuTube.',
    'explore.searchSubmit': 'Tìm kiếm',
    'explore.topics': 'Chủ đề nổi bật',
    'explore.sortBy': 'Sắp xếp theo',
    'explore.videoCountUnit': 'video',
    'explore.pagination': 'Phân trang kết quả',
    'explore.previousPage': 'Trang trước',
    'explore.nextPage': 'Trang tiếp theo',
    'explore.sort': 'Sắp xếp',
    'explore.newest': 'Mới nhất',
    'explore.popular': 'Phổ biến',
    'explore.trending': 'Thịnh hành',
    'explore.sortRelevance': 'Liên quan nhất',
    'explore.sortViews': 'Xem nhiều nhất',
    'explore.sortEngagement': 'Tương tác cao',
    'explore.category': 'Danh mục',
    'explore.allCategories': 'Tất cả danh mục',
    'explore.videoList': 'Danh sách video',
    'explore.searchPlaceholder': 'Tìm kiếm video, kênh, chủ đề...',
    'explore.filterTitle': 'Bộ lọc',
    'explore.activeFilters': 'Đang lọc',
    'explore.clearFilters': 'Xóa bộ lọc',
    'explore.clearAllFilters': 'Xóa tất cả bộ lọc',
    'explore.durationAll': 'Tất cả thời lượng',
    'explore.durationShort': 'Dưới 4 phút',
    'explore.durationMedium': '4 – 20 phút',
    'explore.durationLong': 'Trên 20 phút',
    'explore.dateAll': 'Mọi thời điểm',
    'explore.dateToday': 'Hôm nay',
    'explore.dateThisWeek': 'Tuần này',
    'explore.dateThisMonth': 'Tháng này',
    'explore.dateThisYear': 'Năm nay',
    'explore.resultsCount': 'Tìm thấy {count} video',
    'explore.noResultsTitle': 'Không tìm thấy kết quả',
    'explore.noResultsDesc': 'Thử thay đổi từ khóa hoặc đặt lại bộ lọc để xem thêm video.',
    'explore.tryDifferentKeywords': 'Thử từ khóa khác',
    'explore.searchLabel': 'Tìm kiếm trong trang khám phá',

    'library.ratingFilter': 'Lọc video theo đánh giá của bạn',
    'library.ratingLabel': 'Lọc theo đánh giá',
    'library.loading': 'Đang tải thư viện video',
    'library.watch': 'Xem {title}',
    'library.yourRating': 'Bạn: {rating}',
    'library.overallRating': 'Điểm chung {rating}/5 ({count})',
    'library.watched': 'Đã xem {progress}',
    'library.resume': 'Bạn đang xem dở video này',
    'library.pagination': 'Phân trang thư viện',
    'library.previous': '← Trước',
    'library.next': 'Sau →',
    'library.page': 'Trang {page} / {total}',
    'library.noMatching': 'Không có video phù hợp',
    'library.noLiked': 'Chưa có video đã thích',
    'library.noHistory': 'Chưa có lịch sử xem',
    'library.matchingHint': 'Thử chọn một mức đánh giá khác.',
    'library.likedHint': 'Những video bạn bấm Thích sẽ xuất hiện ở đây.',
    'library.historyHint': 'Video bạn mở và xem sẽ được lưu lại tại đây.',
    'library.seeAllLiked': 'Xem tất cả video đã thích',
    'library.loadError': 'Không thể tải thư viện video.',

    'channel.collaborationTitle': 'Bạn đang được mời cộng tác',
    'channel.collaborationDesc': 'Bạn không cần tạo kênh riêng để làm việc trên kênh đã được mời.',
    'channel.viewInvitations': 'Xem lời mời',
    'channel.ownedTitle': 'Bạn đã sở hữu một kênh trên HuTube',
    'channel.ownedDesc': 'Mỗi tài khoản được liên kết tối đa với một kênh phát sóng.',
    'channel.viewYourChannel': 'Xem kênh của bạn',
    'channel.formTitle': 'Tạo kênh HuTube của bạn',
    'channel.formDesc': 'Bắt đầu chia sẻ nội dung video sáng tạo và kết nối với cộng đồng người xem.',
    'channel.uploadBanner': 'Tải lên ảnh bìa kênh (khuyên dùng tỉ lệ 16:9 hoặc ảnh ngang)',
    'channel.bannerAlt': 'Xem trước ảnh bìa',
    'channel.uploadAvatar': 'Nhấp để tải lên ảnh đại diện kênh',
    'channel.avatarAlt': 'Xem trước ảnh đại diện',
    'channel.nameRequired': 'Tên kênh *',
    'channel.namePlaceholder': 'Ví dụ: Khoa Học TV, Đi Để Trưởng Thành...',
    'channel.handleLabel': 'Handle (Tên định danh) *',
    'channel.handlePlaceholder': 'mychannel',
    'channel.handleHelp': 'Handle sẽ là địa chỉ duy nhất của bạn: hutube.vn/@{handle}',
    'channel.descriptionLabel': 'Mô tả kênh',
    'channel.descriptionPlaceholder': 'Giới thiệu về nội dung kênh của bạn để người xem hiểu thêm...',
    'channel.contactEmail': 'Email liên hệ công việc',
    'channel.contactEmailPlaceholder': 'contact@example.com',
    'channel.creating': 'Đang tạo kênh...',
    'channel.createNow': 'Tạo kênh ngay',
    'channel.cancel': 'Hủy',
    'channel.bannerClick': 'Nhấp để tải lên ảnh bìa',
    'channel.content': 'Nội dung kênh',
    'channel.unavailable': 'Kênh này không khả dụng',
    'channel.backProfile': 'Quay lại trang cá nhân',
    'channel.descriptionFallback': 'Tìm hiểu thêm về kênh này',
    'channel.studio': 'Vào Studio',
    'channel.subscribe': 'Đã đăng ký',
    'channel.follow': 'Theo dõi',
    'channel.turnOnNotifications': 'Bật thông báo của kênh',
    'channel.turnOffNotifications': 'Tắt thông báo của kênh',
    'channel.notificationsEnabled': 'Đã bật thông báo cho kênh này.',
    'channel.notificationsDisabled': 'Đã tắt thông báo cho kênh này.',
    'channel.notificationsUpdateError': 'Không thể cập nhật thông báo lúc này.',
    'channel.tabs': 'Nội dung kênh',
    'channel.noVideos': 'Chưa có video nào',
    'channel.noVideosDesc': 'Kênh này chưa tải lên video nào. Hãy quay lại sau nhé!',
    'channel.noPlaylists': 'Chưa có danh sách phát',
    'channel.noPlaylistsDesc': 'Chưa có playlist công khai nào được tạo trên kênh này.',
    'channel.contactDetails': 'Chi tiết liên hệ',
    'channel.noLinks': 'Chưa có đường liên kết bên ngoài.',
    'channel.channelUrl': 'www.hutube.vn/@{handle}',
    'channel.joined': 'Đã tham gia {date}',
    'channel.totalViews': 'lượt xem',
    'channel.shareCopied': 'Đã sao chép!',
    'channel.share': 'Chia sẻ kênh',
    'channel.report': 'Báo cáo người dùng',
    'channel.reload': 'Tải lại',
    'channel.loadingInvitations': 'Đang tải lời mời và kênh cộng tác…',
    'channel.pendingInvitations': 'Lời mời đang chờ',
    'channel.pendingDesc': 'Kiểm tra vai trò và phạm vi quyền trước khi tham gia.',
    'channel.expires': 'Hết hạn {date}',
    'channel.processing': 'Đang xử lý…',
    'channel.inviteAccept': 'Chấp nhận',
    'channel.inviteDecline': 'Từ chối',
    'channel.noPending': 'Không có lời mời đang chờ',
    'channel.noPendingDesc': 'Lời mời mới gửi tới email tài khoản sẽ xuất hiện tại đây.',
    'channel.collaborating': 'Kênh đang cộng tác',
    'channel.collaboratingDesc': 'Mở Studio trên từng kênh theo đúng vai trò và quyền được cấp.',
    'channel.noAccessible': 'Bạn chưa có kênh nào được cấp quyền.',
    'channel.openStudio': 'Mở Studio',
    'channel.basic': 'Thông tin cơ bản',
    'channel.branding': 'Xây dựng thương hiệu',
    'channel.members': 'Thành viên & quyền',
    'channel.danger': 'Xóa kênh',
    'channel.viewChannel': 'Xem trang kênh',
    'channel.save': 'Lưu thay đổi',
    'channel.addLink': 'Thêm đường liên kết',
    'channel.remove': 'Gỡ',
    'channel.role': 'Vai trò',
    'channel.inviteUser': 'Email người dùng',
    'channel.sendInvite': 'Gửi lời mời',
    'channel.pending': 'Lời mời đang chờ',
    'channel.withdraw': 'Thu hồi',
    'channel.deleteConfirm': 'Xác nhận xóa kênh',
    'channel.delete': 'Xóa kênh này',
    'channel.otherLink': 'Liên kết khác',
    'channel.platform': 'Nền tảng',
    'channel.linkUrl': 'URL liên kết',
    'channel.roleOwner': 'Chủ sở hữu',
    'channel.roleManager': 'Quản lý',
    'channel.roleEditor': 'Biên tập viên',
    'channel.roleModerator': 'Kiểm duyệt viên',
    'channel.roleViewer': 'Người xem',
    'channel.roleManagerDesc': 'Quản lý hồ sơ, nội dung, thành viên và cài đặt kênh; không thể xóa kênh hoặc thay chủ sở hữu.',
    'channel.roleEditorDesc': 'Tải lên, chỉnh sửa nội dung, playlist và xem dữ liệu nội dung.',
    'channel.roleModeratorDesc': 'Quản lý cộng đồng và bình luận, không được chỉnh sửa video hay cài đặt kênh.',
    'channel.roleViewerDesc': 'Chỉ xem dashboard và dữ liệu nội bộ được cấp.',
    'channel.nameError': 'Vui lòng nhập tên kênh.',
    'channel.handleMinError': 'Handle cần tối thiểu 3 ký tự (chữ cái, số, _, -, .).',
    'channel.handleCharsError': 'Handle chỉ gồm chữ cái không dấu, số, _, -, .',
    'channel.handleInvalidError': 'Handle không hợp lệ hoặc đã có người sử dụng.',
    'channel.createError': 'Không thể tạo kênh. Vui lòng thử lại.',
    'channel.loadInvitationsError': 'Không thể tải lời mời. Vui lòng thử lại.',
    'channel.acceptSuccess': 'Bạn đã tham gia kênh {channel}.',
    'channel.declineSuccess': 'Đã từ chối lời mời từ {channel}.',
    'channel.fullManagement': 'Toàn quyền quản lý kênh',
    'channel.videoManagement': 'Có thể quản lý nội dung video',
    'channel.commentManagement': 'Có thể quản lý bình luận',
    'channel.viewGrantedData': 'Chỉ xem dữ liệu được cấp',
    'channel.processInvitationError': 'Không thể xử lý lời mời. Vui lòng thử lại.',
    'channel.notFound': 'Không tìm thấy thông tin kênh.',
    'channel.handleNotFound': 'Không tìm thấy handle kênh.',
    'channel.loadError': 'Không thể tải thông tin kênh.',
    'channel.nameEmpty': 'Tên kênh không được để trống.',
    'channel.handleLength': 'Handle cần từ 3 đến 50 ký tự.',
    'channel.linkUrlError': 'URL liên kết phải bắt đầu bằng http:// hoặc https://.',
    'channel.basicSaved': 'Đã cập nhật thông tin kênh.',
    'channel.avatarSaved': 'Đã cập nhật ảnh đại diện kênh.',
    'channel.bannerSaved': 'Đã cập nhật ảnh bìa kênh.',
    'channel.inviteSent': 'Đã gửi lời mời và email thông báo cho thành viên.',
    'channel.roleUpdated': 'Đã cập nhật vai trò của {member}.',
    'channel.removeConfirm': 'Gỡ {member} khỏi kênh?',
    'channel.memberRemoved': 'Đã gỡ thành viên khỏi kênh.',
    'channel.inviteWithdrawn': 'Đã thu hồi lời mời.',
    'channel.confirmNameMismatch': 'Tên kênh xác nhận chưa khớp chính xác.',
    'channel.handleChannel': 'Handle kênh *',
    'channel.address': 'Địa chỉ kênh của bạn: hutube.vn/@{handle}',
    'channel.businessEmail': 'Email liên hệ kinh doanh',
    'channel.links': 'Đường liên kết',
    'channel.linksDesc': 'Chia sẻ đường liên kết bên ngoài với người xem. Các đường liên kết này sẽ hiển thị trên hồ sơ kênh và trang giới thiệu của bạn.',
    'channel.reorderLink': 'Kéo để sắp xếp',
    'channel.removeLink': 'Xóa đường liên kết',
    'channel.avatarTitle': 'Ảnh đại diện kênh',
    'channel.avatarDesc': 'Ảnh đại diện sẽ xuất hiện bên cạnh video và bình luận của bạn trên HuTube.',
    'channel.changeAvatar': 'Thay đổi ảnh đại diện',
    'channel.bannerTitle': 'Hình ảnh biểu ngữ (Banner)',
    'channel.bannerDesc': 'Hình ảnh này sẽ xuất hiện ở đầu trang kênh của bạn.',
    'channel.changeBanner': 'Thay đổi biểu ngữ',
    'channel.noBanner': 'Chưa có banner',
    'channel.watermarkTitle': 'Hình mờ video (Watermark)',
    'channel.watermarkDesc': 'Hình mờ sẽ xuất hiện ở góc dưới bên phải trình phát video của bạn.',
    'channel.saveWatermark': 'Lưu watermark',
    'channel.rolesDesc': 'Mỗi vai trò có một tập quyền cố định và luôn được kiểm tra lại tại API.',
    'channel.memberEmailPlaceholder': 'member@example.com',
    'channel.roleDescription': 'Mô tả vai trò đã chọn',
    'channel.memberRole': 'Vai trò của {member}',
    'channel.noOtherMembers': 'Chưa có thành viên nào ngoài chủ sở hữu.',
    'channel.deleteDesc': 'Thao tác này sẽ gỡ bỏ kênh của bạn khỏi kết quả tìm kiếm và trang công khai. Chỉ chủ sở hữu mới có quyền xóa.',
    'channel.deleteMine': 'Xóa kênh của tôi',
    'channel.deleteWarning': 'Bạn đang chuẩn bị xóa kênh',
    'channel.deleteNamePrompt': 'Vui lòng nhập chính xác tên kênh để xác nhận:',
    'channel.deleteNamePlaceholder': 'Nhập tên kênh: {name}',
    'channel.confirmDelete': 'Xác nhận xóa',
    'channel.platform.facebook': 'Facebook',
    'channel.platform.instagram': 'Instagram',
    'channel.platform.tiktok': 'TikTok',
    'channel.platform.x': 'X',
    'channel.platform.other': 'Liên kết khác',

    'plans.myPlans': 'Gói của tôi',
    'plans.explore': 'Khám phá gói',
    'plans.retry': 'Thử lại',
    'plans.loadingMine': 'Đang tải thông tin gói của bạn...',
    'plans.activeDesc': 'Gói hiện đang kích hoạt trên tài khoản của bạn',
    'plans.detailShare': 'Chi tiết & chia sẻ gói',
    'plans.switchOther': 'Đổi sang gói khác',
    'plans.upgrade': 'Xem gói nâng cấp',
    'plans.upgradePlan': 'Nâng cấp lên gói này',
    'plans.owner': 'Chủ sở hữu',
    'plans.sharedMember': 'Thành viên dùng chung',
    'plans.startDate': 'Ngày bắt đầu',
    'plans.endDate': 'Hạn sử dụng',
    'plans.expired': 'Đã hết hạn',
    'plans.autoRenew': 'Tự động gia hạn',
    'plans.enabled': 'Đang bật',
    'plans.quotaTitle': 'Quota dung lượng kênh',
    'plans.quotaDesc': 'Dung lượng video đã tải lên kênh hiện tại',
    'plans.usage': 'Mức sử dụng dung lượng',
    'plans.used': 'đã sử dụng',
    'plans.remaining': 'Còn lại:',
    'plans.maxUpload': 'Video upload tối đa',
    'plans.quality': 'Độ phân giải',
    'plans.maxMembers': 'Thành viên tối đa',
    'plans.maxDuration': 'Thời lượng video tối đa',
    'plans.capabilities': 'Tải xuống / phát nền / PiP',
    'plans.sharedTitle': 'Chia sẻ gói cho gia đình / nhóm',
    'plans.sharedCount': 'Hiện có {current} / {max} người đang dùng chung',
    'plans.sharedNotice': 'Bạn đang là thành viên tham gia gói được chia sẻ. Chỉ chủ gói mới có quyền mời hoặc quản lý thành viên.',
    'plans.personalNotice': 'Gói hiện tại là gói cá nhân. Để chia sẻ cho người khác, bạn có thể chuyển sang gói nhóm.',
    'plans.groupPlans': 'Xem các gói chia sẻ nhóm →',
    'plans.invitePlaceholder': 'Nhập email người bạn muốn chia sẻ...',
    'plans.inviteMember': 'Mời thành viên',
    'plans.maxReached': 'Đã đạt số lượng thành viên tối đa của gói này.',
    'plans.memberEmail': 'Email thành viên',
    'plans.invitedDate': 'Ngày mời',
    'plans.memberStatus': 'Trạng thái',
    'plans.accepted': 'Đã tham gia',
    'plans.waiting': 'Đang chờ xác nhận',
    'plans.noMembers': 'Chưa có thành viên nào được mời vào gói này.',
    'plans.allocatedQuota': 'Dung lượng được cấp',
    'plans.usedQuota': 'Đã dùng',
    'plans.unallocated': 'Chưa phân bổ:',
    'plans.allocatedTotal': 'Đã phân bổ:',
    'plans.ownerQuota': 'Hạn mức chủ gói:',
    'plans.editQuota': 'Sửa dung lượng',
    'plans.setQuota': 'Đặt hạn mức',
    'plans.sharedQuota': 'Dùng chung gói',
    'plans.storageGBPlaceholder': 'Quota (GB, trống = dùng chung)',
    'plans.invalidQuota': 'Hạn mức phải là số không âm.',
    'plans.quotaBelowUsed': 'Hạn mức không được nhỏ hơn dung lượng đã sử dụng.',
    'plans.usedShort': 'đã dùng',
    'plans.remainingShort': 'còn lại',
    'plans.storageUpdated': 'Cập nhật dung lượng thành công.',
    'plans.storageUpdateError': 'Không thể cập nhật dung lượng.',
    'plans.noPlan': 'Bạn chưa đăng ký gói dịch vụ nào',
    'plans.noPlanDesc': 'Nâng cấp gói để tăng dung lượng kênh, chất lượng upload và chia sẻ quyền lợi cho bạn bè.',
    'plans.exploreNow': 'Khám phá các gói dịch vụ ngay',
    'plans.flexible': 'Lựa chọn linh hoạt',
    'plans.choose': 'Chọn gói phù hợp với kênh của bạn',
    'plans.chooseDesc': 'Thêm dung lượng, chất lượng video và thành viên dùng chung khi kênh phát triển.',
    'plans.current': 'Đang dùng:',
    'plans.currentBadge': 'Gói hiện tại của bạn',
    'plans.popular': 'Được chọn nhiều',
    'plans.serviceDesc': 'Gói dịch vụ cho nhà sáng tạo.',
    'plans.days': 'ngày',
    'plans.storage': 'Dung lượng',
    'plans.uploadDownload': 'Upload / Download',
    'plans.standard': 'Tiêu chuẩn',
    'plans.duration': 'Thời lượng',
    'plans.download': 'Tải xuống',
    'plans.backgroundPip': 'Phát nền / PiP',
    'plans.manage': 'Quản lý gói này',
    'plans.switch': 'Đổi sang gói này',
    'plans.buy': 'Mua gói này',
    'plans.detailAndShare': 'Xem chi tiết và chia sẻ',
    'plans.detailLoading': 'Đang tải gói dịch vụ...',
    'plans.back': '← Quay lại danh sách gói',
    'plans.currentUse': '✓ Bạn đang sử dụng gói này',
    'plans.activeNote': 'Gói đang còn hạn. Bạn có thể đăng ký lại sau khi gói hết hạn.',
    'plans.activating': 'Đang kích hoạt...',
    'plans.loginSubscribe': 'Đăng nhập để đăng ký',
    'plans.benefits': 'Quyền lợi & Thông số',
    'plans.benefitsDesc': 'Chi tiết giới hạn và tài nguyên của gói này',
    'plans.maxStorage': 'Dung lượng lưu trữ kênh',
    'plans.maxPerVideo': 'Dung lượng tối đa mỗi video',
    'plans.maxQualityUpload': 'Chất lượng tối đa upload',
    'plans.maxQualityDownload': 'Chất lượng tối đa tải xuống',
    'plans.sharedSeats': 'Số thành viên chia sẻ gói',
    'plans.shareInfo': 'Chia sẻ thông tin gói',
    'plans.shareDesc': 'Gửi liên kết công khai cho bạn bè hoặc người thân cùng xem',
    'plans.planUrl': 'Đường dẫn trang gói:',
    'plans.shareUrlLabel': 'Liên kết chia sẻ gói',
    'plans.shareTip': 'Lưu ý: Liên kết này hoàn toàn công khai, không chứa dữ liệu nhạy cảm hay thông tin tài khoản của bạn.',
    'plans.inviteAcceptTitle': 'Lời mời dùng chung gói',
    'plans.inviteIncomplete': 'Liên kết lời mời không đầy đủ.',
    'plans.inviteLogin': 'Đăng nhập bằng đúng email đã nhận lời mời để tiếp tục.',
    'plans.inviteLoginButton': 'Đăng nhập để chấp nhận',
    'plans.inviteCheckEmail': 'Kiểm tra email tài khoản rồi xác nhận lời mời tham gia gói.',
    'plans.acceptInvite': 'Chấp nhận lời mời',
    'plans.openMine': 'Mở Gói của tôi',
    'plans.loadError': 'Không tải được danh sách gói dịch vụ.',
    'plans.inviteError': 'Không thể gửi lời mời.',
    'plans.revokeError': 'Không thể thu hồi thành viên.',
    'plans.minutes': '{count} phút',
    'plans.hours': '{count} giờ',
    'plans.hoursMinutes': '{hours} giờ {minutes} phút',
    'plans.invalid': 'Gói dịch vụ không hợp lệ.',
    'plans.notFound': 'Không tìm thấy gói dịch vụ.',
    'plans.copiedShare': 'Đã sao chép liên kết chia sẻ.',
    'plans.copyError': 'Không thể sao chép tự động. Hãy chọn và sao chép liên kết trong ô bên trên.',
    'plans.shareError': 'Không thể mở bảng chia sẻ trên thiết bị này.',
    'plans.subscribeSuccess': 'Đăng ký gói thành công. Bạn có thể quản lý quota và thành viên trong Gói của tôi.',
    'plans.joined': 'Đã tham gia gói dịch vụ.',
    'plans.inviteInvalid': 'Lời mời không hợp lệ hoặc đã hết hạn.',
    'plans.viewMode': 'Chế độ hiển thị gói dịch vụ',
    'plans.catalogLabel': 'Các gói dịch vụ',
    'plans.allPlans': 'Tất cả gói dịch vụ',
    'plans.detailDesc': 'Gói dịch vụ dành riêng cho nhà sáng tạo và người xem nâng cao trên HuTube.',
    'plans.notPurchased': 'Chưa mua gói này',
    'plans.backgroundPlay': 'Phát nền',
    'plans.pip': 'Chế độ phát thu nhỏ (PiP)',
    'plans.processingInvite': 'Đang xác nhận…',

    'watch.loading': 'Đang tải video',
    'watch.unavailableTitle': 'Không thể mở video',
    'watch.home': 'Về trang chủ',
    'watch.notReady': 'Video chưa sẵn sàng để phát.',
    'watch.videoInfo': 'Thông tin video',
    'watch.play': 'Phát video',
    'watch.pause': 'Tạm dừng',
    'watch.back10': 'Lùi 10 giây',
    'watch.forward10': 'Tiến 10 giây',
    'watch.unmute': 'Bật âm thanh',
    'watch.mute': 'Tắt âm thanh',
    'watch.volume': 'Âm lượng',
    'watch.quality': 'Chất lượng',
    'watch.videoQuality': 'Chất lượng video',
    'watch.speed': 'Tốc độ',
    'watch.restoreSize': 'Khôi phục kích thước video',
    'watch.minimize': 'Thu nhỏ video',
    'watch.pictureInPicture': 'Phát trong cửa sổ nổi',
    'watch.exitPictureInPicture': 'Đóng cửa sổ nổi',
    'watch.fullscreen': 'Toàn màn hình',
    'watch.progress': 'Tiến trình video',
    'watch.actions': 'Tác vụ video',
    'watch.like': 'Thích video',
    'watch.dislike': 'Không thích video',
    'watch.loginInteract': 'Đăng nhập để tương tác',
    'watch.download': 'Tải xuống',
    'watch.loginDownload': 'Đăng nhập để tải xuống',
    'watch.ratingGroup': 'Đánh giá video từ 1 đến 5 sao',
    'watch.rating': 'Đánh giá',
    'watch.ratingStar': 'Đánh giá {star} sao',
    'watch.clearRating': 'Bỏ đánh giá',
    'watch.shortcut': 'K / Space phát · J/L ±10s · F toàn màn hình · M tắt tiếng · I thu nhỏ',
    'watch.shareVideo': 'Chia sẻ video',
    'watch.shareDesc': 'Sao chép liên kết để gửi cho người khác.',
    'watch.videoLink': 'Liên kết video',
    'watch.downloadTitle': 'Tải video xuống',
    'watch.downloadDesc': 'Chất lượng khả dụng theo gói hiện tại.',
    'watch.preparing': 'Đang chuẩn bị…',
    'watch.noDownloadQuality': 'Gói hiện tại chưa có chất lượng tải xuống khả dụng.',
    'watch.chapters': 'Nội dung video',
    'watch.chaptersDesc': 'Các chương giúp bạn đi thẳng đến phần muốn xem.',
    'watch.chapterCount': 'chương',
    'watch.comments': 'Bình luận',
    'watch.commentCount': '{count} bình luận trong video này',
    'watch.newest': 'Mới nhất',
    'watch.commentPlaceholder': 'Viết bình luận của bạn…',
    'watch.keepCivil': 'Hãy giữ cuộc trò chuyện văn minh.',
    'watch.sendComment': 'Gửi bình luận',
    'watch.loginComment': 'Đăng nhập để tham gia bình luận về video này.',
    'watch.reply': 'Trả lời',
    'watch.replyPlaceholder': 'Viết câu trả lời…',
    'watch.send': 'Gửi',
    'watch.likeComment': 'Thích',
    'watch.dislikeComment': 'Không thích',
    'watch.hideReplies': 'Ẩn câu trả lời',
    'watch.viewReplies': 'Xem {count} câu trả lời',
    'watch.show': 'Hiện',
    'watch.hide': 'Ẩn',
    'watch.remove': 'Xóa',
    'watch.report': 'Báo cáo',
    'watch.replies': 'Các câu trả lời',
    'watch.replyLoading': 'Đang tải câu trả lời…',
    'watch.descriptionEmpty': 'Video này chưa có phần mô tả.',

    // Studio pages
    'studio.loading': 'Đang tải…',
    'studio.channelOverview': 'Tổng quan kênh',
    'studio.recentVideo': 'Video gần nhất',
    'studio.seeAll': 'Xem tất cả',
    'studio.emptyVideo': 'Chưa có video. Hãy tải video đầu tiên của bạn.',
    'studio.searchVideo': 'Tìm kiếm theo tiêu đề video...',
    'studio.colModeration': 'Trạng thái kiểm duyệt',
    'studio.interaction': 'Tương tác',
    'studio.noVideosList': 'Chưa có video nào trong danh sách.',
    'studio.visible': 'Đang hiển thị',
    'studio.hidden': 'Đã ẩn',
    'studio.showAgain': 'Hiện lại',
    'studio.hide': 'Ẩn',
    'studio.send': 'Gửi',
    'studio.replyPlaceholder': 'Nhập câu trả lời',
    'studio.noComments': 'Không có bình luận ở trạng thái này.',
    'studio.noSubtitles': 'Chưa có phụ đề',
    'studio.noVideo': 'Chưa có video.',
    'studio.notSet': 'Chưa đặt',
    'studio.channelInfo': 'Thông tin kênh',
    'studio.saveChannelInfo': 'Lưu thông tin kênh',
    'studio.viewOnly': 'Quyền chỉ xem',
    'studio.viewOnlyDesc': 'Bạn có thể xem dữ liệu kênh nhưng không được chỉnh sửa thông tin cơ bản.',
    'studio.display': 'Hiển thị',
    'studio.language': 'Ngôn ngữ',
    'studio.light': 'Sáng',
    'studio.dark': 'Tối',
    'studio.saveSettings': 'Lưu cài đặt',
    'studio.permissionError': 'Bạn không có quyền chỉnh sửa thông tin kênh.',
    'studio.saved': 'Đã lưu cài đặt kênh.',
    'studio.saveError': 'Không thể lưu cài đặt kênh.'
    ,'studio.performanceByVideo': 'Hiệu suất theo video'
    ,'studio.channelMetrics': 'Số liệu kênh'
    ,'studio.publicModerationToast': 'Đã chuyển video "{title}" sang Công khai và gửi vào Hàng đợi kiểm duyệt.'
    ,'studio.publicToast': 'Đã chuyển video "{title}" sang chế độ Công khai.'
    ,'studio.unlistedToast': 'Đã chuyển video "{title}" sang chế độ Không công khai.'
    ,'studio.privateToast': 'Đã chuyển video "{title}" sang chế độ Riêng tư.'
    ,'studio.visibilityError': 'Không thể cập nhật chế độ hiển thị video.'
     ,'ui.delete': 'Xóa'
     ,'ui.confirmLogoutTitle': 'Xác nhận đăng xuất'
     ,'ui.confirmLogoutDesc': 'Bạn có chắc muốn đăng xuất khỏi tài khoản này không?'
     ,'ui.userHuTube': 'Người dùng HuTube'
     ,'ui.user': 'Người dùng'
     ,'ui.liked': 'Đã thích'
     ,'ui.playlist': 'Danh sách phát'
     ,'ui.subscriptions': 'Kênh đăng ký'
    ,'ui.quickActions': 'Tác vụ nhanh'
    ,'ui.closeAccountMenu': 'Đóng menu tài khoản'
    ,'ui.account': 'Tài khoản'
    ,'ui.accountStats': 'Thống kê tài khoản'
    ,'ui.accountActions': 'Tác vụ tài khoản'
    ,'ui.signIn': 'Đăng nhập'
    ,'ui.collaborationChannel': 'Kênh cộng tác'
    ,'ui.openCollaborationChannel': 'Mở kênh đang cộng tác'
    ,'ui.collaborationInvites': 'Lời mời cộng tác'
    ,'ui.waitingConfirmation': 'Chờ bạn xác nhận'
    ,'ui.createFirstChannel': 'Tạo kênh đầu tiên'
    ,'ui.startCreatingContent': 'Bắt đầu sáng tạo nội dung'
    ,'ui.createOwnChannel': 'Tạo kênh riêng'
    ,'ui.startOwnChannel': 'Bắt đầu kênh của bạn'
    ,'ui.channelSettings': 'Cài đặt kênh'
    ,'ui.channelSettingsDesc': 'Tùy chỉnh kênh của bạn'
    ,'ui.packageDesc': 'Quản lý và đăng ký gói'
    ,'ui.accountSettings': 'Cài đặt tài khoản'
    ,'ui.accountSettingsDesc': 'Bảo mật, thông báo và tùy chọn'
    ,'ui.myLinks': 'Liên kết của tôi'
    ,'ui.addLinks': 'Thêm Instagram, Facebook, TikTok…'
    ,'ui.notificationsList': 'Danh sách thông báo'
    ,'ui.markAllRead': 'Đánh dấu đã đọc'
    ,'ui.noNotifications': 'Chưa có thông báo.'
    ,'ui.loadingNotifications': 'Đang tải…'
    ,'ui.cancelUpload': 'Hủy tải lên'
    ,'ui.closeUpload': 'Đóng tiến trình tải lên'
    ,'ui.uploading': 'Đang tải video lên…'
    ,'ui.processingVideo': 'Đang tạo chất lượng video…'
    ,'ui.uploadSuccess': 'Tải video thành công'
    ,'ui.uploadFailed': 'Tải video thất bại'
    ,'ui.creatorStudio': 'Creator Studio'
    ,'ui.newBadge': 'Mới'
    ,'ui.collaborateOnChannel': 'Cộng tác trên kênh'
    ,'ui.closeMenu': 'Đóng menu'
    ,'ui.searchShortcut': 'Ctrl K'
    ,'ui.reportPrompt': 'Chọn mã vi phạm:'
    ,'ui.reportDescriptionPrompt': 'Mô tả thêm (không bắt buộc):'

    ,'auth.introLabel': 'NHÀ SÁNG TẠO · NGƯỜI XEM · CỘNG ĐỒNG'
    ,'auth.heroCreate': 'Sáng tạo.'
    ,'auth.heroShare': 'Chia sẻ.'
    ,'auth.heroBelong': 'Thuộc về.'
    ,'auth.heroDescription': 'HuTube trao quyền để bạn sáng tạo, kết nối và khám phá thế giới video cùng cộng đồng tôn vinh câu chuyện và góc nhìn của bạn.'
    ,'auth.featureCreate': 'Sáng tạo không giới hạn'
    ,'auth.featureCreateDesc': 'Biến ý tưởng thành những video tuyệt vời'
    ,'auth.featureShare': 'Chia sẻ thế giới của bạn'
    ,'auth.featureShareDesc': 'Kết nối với những người xem đồng điệu'
    ,'auth.featureBelong': 'Khám phá & Thuộc về'
    ,'auth.featureBelongDesc': 'Nơi bạn luôn tìm thấy nguồn cảm hứng'
    ,'auth.tagline': 'Video hay hơn, con người tốt đẹp hơn'
    ,'auth.slideStory': 'Câu chuyện của bạn<br>thuộc về nơi đây'
    ,'auth.slideWorld': 'Một thế giới lớn hơn<br>trong mỗi video'
    ,'auth.slideInspire': 'Truyền cảm hứng cho<br>thế giới quanh bạn'
    ,'auth.cardExplore': 'KHÁM PHÁ'
    ,'auth.cardCreate': 'SÁNG TẠO'
    ,'auth.cardLearn': 'HỌC HỎI'
    ,'auth.cardShare': 'CHIA SẺ'
    ,'auth.cardBelong': 'THUỘC VỀ'
    ,'auth.subTagline': 'MỘT INTERNET CỞI MỞ, SÁNG TẠO VÀ TỬ TẾ HƠN'
    ,'auth.loginSubtitle': 'Chào mừng bạn trở lại HuTube.'
    ,'auth.adminSubtitle': 'Dành cho đội ngũ quản trị.'
    ,'auth.registerSubtitle': 'Bắt đầu với email của bạn.'
    ,'auth.verifySubtitle': 'Hoàn tất xác minh để bảo vệ tài khoản.'
    ,'auth.forgotSubtitle': 'Nhập email để nhận liên kết đặt lại mật khẩu.'
    ,'auth.resetSubtitle': 'Chọn mật khẩu mới cho tài khoản của bạn.'
    ,'auth.verificationHelp': 'Chưa nhận được email xác minh?'
    ,'auth.resendEmail': 'Gửi lại email'
    ,'auth.usernameHint': '3–50 ký tự: chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.'
    ,'auth.usernameInvalid': 'Tên người dùng chưa đúng định dạng.'
    ,'auth.emailInvalid': 'Nhập địa chỉ email hợp lệ.'
    ,'auth.passwordHint': '10–128 ký tự, gồm chữ hoa, chữ thường và số.'
    ,'auth.passwordInvalid': 'Mật khẩu chưa đáp ứng yêu cầu.'
    ,'auth.passwordLoginRequired': 'Nhập mật khẩu của bạn.'
    ,'auth.showPassword': 'Hiện mật khẩu'
    ,'auth.hidePassword': 'Ẩn mật khẩu'
    ,'auth.googleLogin': 'Đăng nhập bằng Google'
    ,'auth.resendEmailLabel': 'Email nhận liên kết mới'
    ,'auth.mobileAppLink': 'Mở trong ứng dụng HuTube'
    ,'auth.appLoginLink': 'Đăng nhập trên ứng dụng HuTube'
    ,'auth.sessionExpired': 'Phiên đăng nhập đã hết hạn. Đăng nhập lại để tiếp tục.'
    ,'auth.resetMissingToken': 'Liên kết thiếu mã xác nhận. Vui lòng yêu cầu đặt lại mật khẩu.'
    ,'auth.googleCredentialMissing': 'Không nhận được thông tin xác thực từ Google.'
    ,'auth.googleLoadError': 'Không tải được đăng nhập Google. Vui lòng thử lại.'
    ,'auth.formInvalid': 'Vui lòng kiểm tra các trường được đánh dấu.'
    ,'auth.passwordMismatch': 'Mật khẩu xác nhận chưa khớp.'
    ,'auth.registerSuccess': 'Tài khoản đã được tạo. Kiểm tra hộp thư để xác minh email trước khi đăng nhập.'
    ,'auth.forgotSuccess': 'Nếu email có trong hệ thống, hướng dẫn đặt lại mật khẩu sẽ được gửi đến bạn. Hãy kiểm tra cả thư rác.'
    ,'auth.resetSuccess': 'Đã đổi mật khẩu và kết thúc các phiên cũ. Bạn có thể đăng nhập bằng mật khẩu mới.'
    ,'auth.verifySuccess': 'Email đã được xác minh. Bạn có thể đăng nhập ngay.'
    ,'auth.resendSuccess': 'Nếu tài khoản cần xác minh, một liên kết mới sẽ được gửi đến email của bạn.'

    ,'account.channelId': 'Mã nhận dạng kênh (Channel ID)'
    ,'account.settingsAria': 'Cài đặt tài khoản'
     ,'account.dismissMessage': 'Đóng thông báo'

    ,'watch.unavailableError': 'Video không khả dụng hoặc bạn không có quyền xem video này.'
    ,'watch.playbackQualityError': 'Không tải được các bản chất lượng cao hơn. Video nguồn vẫn có thể phát.'
    ,'watch.renditionError': 'Không thể phát bản chất lượng này. Hãy thử chọn chất lượng khác.'
    ,'watch.lowerRenditionFallback': 'Bản phát hiện tại gặp lỗi; HuTube đang thử chất lượng thấp hơn.'
    ,'watch.sourceFallback': 'Bản phát chất lượng gặp lỗi; HuTube đang thử tệp nguồn.'
    ,'watch.pictureInPictureUnsupported': 'Trình duyệt này không hỗ trợ chế độ cửa sổ nổi.'
    ,'watch.pictureInPictureFailed': 'Không thể mở video trong cửa sổ nổi.'
    ,'watch.playError': 'Không thể phát video ở thời điểm này.'
    ,'watch.loginReaction': 'Vui lòng đăng nhập để thích hoặc không thích video.'
    ,'watch.interactionError': 'Vui lòng đăng nhập để tương tác với video.'
    ,'watch.loginRating': 'Vui lòng đăng nhập để đánh giá video.'
    ,'watch.ratingSaved': 'Đã cập nhật đánh giá của bạn.'
    ,'watch.shareReadyPublic': 'Liên kết video công khai đã sẵn sàng để chia sẻ.'
    ,'watch.shareReady': 'Liên kết video đã sẵn sàng để chia sẻ.'
    ,'watch.copyHint': 'Hãy sao chép liên kết trong ô bên trên.'
    ,'watch.shareCopied': 'Đã sao chép liên kết video.'
    ,'watch.copyError': 'Không thể sao chép tự động. Hãy sao chép liên kết thủ công.'
    ,'watch.loginCommentAction': 'Vui lòng đăng nhập để bình luận.'
    ,'watch.commentError': 'Không thể gửi bình luận.'
    ,'watch.loginReply': 'Vui lòng đăng nhập để trả lời bình luận.'
    ,'watch.replyError': 'Không thể gửi câu trả lời.'
    ,'watch.replySaved': 'Đã gửi câu trả lời.'
    ,'watch.loginCommentInteraction': 'Vui lòng đăng nhập để tương tác với bình luận.'
    ,'watch.commentUpdateError': 'Không thể cập nhật bình luận.'
    ,'watch.loginCommentManage': 'Vui lòng đăng nhập để quản lý bình luận.'
    ,'watch.loginCommentDelete': 'Vui lòng đăng nhập để xóa bình luận.'
    ,'watch.deleteCommentConfirm': 'Xóa bình luận này?'
    ,'watch.loginReport': 'Vui lòng đăng nhập để báo cáo bình luận.'
    ,'watch.noViolationTypes': 'Hiện chưa có loại vi phạm để gửi báo cáo.'
    ,'watch.violationChoice': 'Chọn mã vi phạm:\n{choices}'
    ,'watch.invalidViolationCode': 'Mã vi phạm không hợp lệ.'
    ,'watch.reportSent': 'Đã gửi báo cáo bình luận.'
    ,'watch.reportError': 'Không thể gửi báo cáo. Vui lòng thử lại.'
    ,'watch.downloadUnsupported': 'Gói hiện tại không hỗ trợ tải xuống video.'
    ,'watch.downloadCreatedWithLink': 'Đã tạo bản tải xuống. Bạn có thể mở liên kết từ thông báo tải xuống.'
    ,'watch.downloadCreated': 'Đã tạo bản tải xuống.'
    ,'watch.downloadError': 'Không thể tạo bản tải xuống.'
    ,'watch.noReplies': 'Chưa có câu trả lời.'
    ,'watch.emptyCommentsTitle': 'Chưa có bình luận nào'
    ,'watch.emptyCommentsDesc': 'Hãy là người đầu tiên chia sẻ cảm nhận về video này.'
    ,'watch.recommendations': 'Video đề xuất'
    ,'watch.recommendationFilters': 'Bộ lọc video đề xuất'
    ,'watch.relatedVideos': 'Video liên quan'
    ,'watch.sameChannel': 'Cùng của kênh'
    ,'watch.categoryVietnam': 'Du lịch Việt Nam'
    ,'watch.recommendedTitle': 'Đề xuất cho bạn'
    ,'watch.recommendedDesc': 'Tiếp tục khám phá trên HuTube'
    ,'watch.autoplay': 'Tự động phát'
    ,'watch.newlyPosted': 'Mới đăng'
     ,'watch.noRecommended': 'Chưa có video đề xuất.'
     ,'watch.sourceQuality': 'Nguồn'
     ,'watch.views': '{count} lượt xem'
     ,'watch.subscribers': '{count} người đăng ký'
     ,'watch.subscribe': 'Đăng ký'
     ,'watch.subscribed': 'Đã đăng ký'
     ,'watch.cannotSubscribeSelf': 'Bạn không thể đăng ký kênh của chính mình.'
     ,'watch.subscribeError': 'Lỗi khi đăng ký kênh.'
     ,'watch.unsubscribeError': 'Lỗi khi hủy đăng ký kênh.'
     ,'watch.defaultLanguage': 'Tiếng Việt'
     ,'watch.videoDescriptionEmpty': 'Video này chưa có phần mô tả.'
     ,'watch.chapterCountLabel': '{count} chương'
     ,'watch.guestCommentPrompt': 'Đăng nhập để tham gia bình luận về video này.'
     ,'watch.repliesCount': 'Xem {count} câu trả lời'
     ,'watch.showComment': 'Hiện'
     ,'watch.hideComment': 'Ẩn'
     ,'watch.repliesEmpty': 'Chưa có câu trả lời.'
     ,'watch.reportDescriptionPrompt': 'Mô tả thêm (không bắt buộc):'
     ,'watch.repliesError': 'Không thể tải câu trả lời.'
     ,'watch.recommendationViews': '{count} lượt xem'
     ,'watch.originalBadge': 'HUTUBE ORIGINAL'

    ,'plans.defaultUploadQuality': '1080p Full HD'
     ,'plans.defaultDownloadQuality': '720p'
     ,'plans.eyebrow': 'Tài khoản & gói dịch vụ'

    ,'upload.stepperAria': 'Các bước tải lên video'
    ,'upload.readingVideo': 'Đang đọc video và tách khung hình…'
    ,'upload.checkingStorage': 'Đang kiểm tra dung lượng thật…'
    ,'upload.creatingQualities': 'Đang tạo các chất lượng video…'
    ,'upload.uploadingNow': 'Đang tải lên…'
    ,'upload.ready': 'Sẵn sàng tải lên'
    ,'upload.noCategory': 'Không chọn'
    ,'upload.languageVietnamese': 'Tiếng Việt (Vietnamese)'
    ,'upload.languageEnglish': 'English (US)'
    ,'upload.languageJapanese': '日本語 (Japanese)'
    ,'upload.quality4K': '2160p (4K)'
    ,'upload.watching': 'Đang xem:'
    ,'upload.addChapterAt': 'Thêm chương tại mốc'
    ,'upload.pausePreview': 'Tạm dừng'
    ,'upload.playPreview': 'Phát xem trước'
    ,'upload.timelineAria': 'Dòng thời gian video'
    ,'upload.timelineHelp': 'Kéo trên thanh để tua video. Kéo chấm chương để đổi thời điểm, hoặc sửa trực tiếp bên dưới.'
    ,'upload.chapterNameAria': 'Tên chương'
    ,'upload.chapterStartAria': 'Thời điểm bắt đầu'
    ,'upload.preModeration': 'Tiền kiểm duyệt'
    ,'upload.preModerationDesc': 'Video sẽ được gửi đến hàng đợi thẩm định trước khi hiển thị công khai trên HuTube.'
    ,'upload.commitment': 'Tôi cam kết video này tuân thủ'
    ,'upload.and': 'và'
    ,'upload.noPlaylist': '-- Chọn danh sách phát (tùy chọn) --'
    ,'upload.untitledCategory': 'Chưa phân loại'
    ,'upload.previewVideo': 'Chọn video để xem bản preview'
    ,'upload.checkApi404': 'API hiện tại chưa có endpoint này. Hãy khởi động lại backend local hoặc redeploy API trước khi tải lên.'
    ,'upload.checkApiOffline': 'Không thể kết nối API. Kiểm tra backend, CORS và thử lại.'
     ,'upload.checkApiError': 'Không thể kiểm tra file với máy chủ.'
     ,'upload.noData': 'Chưa có dữ liệu'
     ,'upload.storageRemaining': 'Còn lại {value}'
     ,'upload.frameLabel': 'Khung hình {index}'
     ,'upload.playlistDalat': 'Du lịch Đà Lạt'
     ,'upload.playlistVietnam': 'Vẻ đẹp Việt Nam'
     ,'upload.policyCommitmentDesc': 'Tôi xác nhận video này tuân thủ {community} và {terms} của HuTube.'
     ,'upload.commitmentSuffix': 'của HuTube. Video không chứa nội dung kích động thù địch, bạo lực, khiêu dâm hoặc vi phạm bản quyền.'
     ,'upload.fileTypeError': 'File không phải định dạng video được hỗ trợ. Chọn MP4, WebM, MOV hoặc MKV.'
     ,'upload.metadataError': 'Không đọc được thông tin video. File có thể bị hỏng hoặc trình duyệt không hỗ trợ định dạng này.'
     ,'upload.selectFileError': 'Vui lòng chọn file video trước.'
     ,'upload.selectVideoError': 'Vui lòng chọn file video.'
     ,'upload.preparingWait': 'Đang đọc video và tạo hình thu nhỏ, vui lòng chờ một chút.'
     ,'upload.storageWait': 'Đang kiểm tra dung lượng lưu trữ, vui lòng chờ một chút.'
     ,'upload.preflightUnavailable': 'Chưa kiểm tra được file với máy chủ.'
     ,'upload.titleRequired': 'Vui lòng nhập tiêu đề video.'
     ,'upload.policyRequired': 'Vui lòng xác nhận cam kết tuân thủ Tiêu chuẩn cộng đồng HuTube trước khi gửi duyệt.'
     ,'upload.uploadInProgress': 'Đang có một video khác được tải lên.'
     ,'upload.chaptersInvalid': 'Các chương phải có tiêu đề, mốc thời gian tăng dần và nằm trong video.'
     ,'upload.previewError': 'Trình duyệt không thể phát bản xem trước của file này.'
     ,'upload.chapterFieldsInvalid': 'Nhập tiêu đề và mốc thời gian hợp lệ trong video.'
     ,'upload.duplicateChapterTime': 'Mỗi mốc thời gian chỉ được dùng cho một chương.'
     ,'upload.customThumbnail': 'Tùy chỉnh'
     ,'upload.videoThumbnailAlt': 'Ảnh thu nhỏ video'
     ,'upload.categoryFallback': 'Chưa phân loại'
     ,'upload.publicCommitmentAlert': '* Cần xác nhận cam kết đối với video công khai trước khi gửi duyệt.'
     ,'upload.publishPublic': 'Gửi duyệt & Xuất bản'
     ,'upload.saveVideo': 'Lưu video'

    ,'studio.roleOwner': 'Chủ sở hữu'
    ,'studio.roleManager': 'Quản lý'
    ,'studio.roleEditor': 'Biên tập viên'
    ,'studio.roleModerator': 'Kiểm duyệt viên'
    ,'studio.roleViewer': 'Người xem'
    ,'studio.roleContributor': 'Cộng tác viên'
    ,'studio.manageChannel': 'Kênh đang quản lý'
    ,'studio.collaboration': 'Cộng tác'
    ,'studio.collaborationTitle': 'Cộng tác trên kênh'
    ,'studio.defaultCreator': 'Nắng Lang Thang'
    ,'studio.commentManagedReason': 'Chủ kênh quản lý'
     ,'studio.defaultUsername': '@creator'
     ,'ui.studioNavigation': 'Điều hướng HuTube Creator Studio'
     ,'channel.membersList': 'Danh sách thành viên kênh'
     ,'channel.handleMinCreate': 'Handle cần tối thiểu 3 ký tự.'
     ,'channel.handleMaxCreate': 'Handle tối đa 50 ký tự.'
     ,'channel.handleNoSpaces': 'Handle không được chứa khoảng trắng.'
     ,'channel.handleChars': 'Handle chỉ gồm chữ cái không dấu, số, _, -, .'
     ,'channel.handleChecking': 'Đang kiểm tra tính khả dụng…'
     ,'channel.handleCheckError': 'Không thể kiểm tra handle lúc này.'
     ,'channel.handleAvailable': 'Handle này có thể sử dụng.'
     ,'channel.handleTaken': 'Handle này đã được sử dụng.'
     ,'explore.error': 'Không thể tải danh sách video khám phá.'
     ,'library.notRated': 'Chưa đánh giá'
     ,'plans.inviteSent': 'Đã gửi lời mời gói dịch vụ.'
     ,'plans.revokeSent': 'Đã thu hồi lời mời.'
     ,'plans.members': '{count} người'
     ,'plans.shareText': 'Gói {name} của HuTube'
     ,'plans.qualityUpload': 'Tải lên {quality}'
     ,'plans.qualityDownload': 'Tải xuống {quality}'
     ,'plans.subscribeErrorFallback': 'Không thể đăng ký gói dịch vụ ({status}).'
     ,'auth.about': 'Giới thiệu về HuTube'
     ,'auth.accountLink': 'HuTube — trang tài khoản'
     ,'auth.slideStoryAlt': 'Người sáng tạo kể câu chuyện của mình'
     ,'auth.slideWorldAlt': 'Khám phá thế giới qua video'
     ,'auth.slideInspireAlt': 'Cộng đồng truyền cảm hứng'
     ,'auth.layoutTagline': 'Nền tảng video mở, sáng tạo và tử tế hơn.'
     ,'auth.layoutFooter': '© 2026 HuTube LLC. Bảo lưu mọi quyền.'
     ,'auth.deviceMobile': 'Điện thoại'
     ,'auth.deviceDesktop': 'Máy tính'
     ,'auth.requestError': 'Không thể hoàn tất yêu cầu. Vui lòng thử lại.'
     ,'auth.invalidCredentials': 'Email hoặc mật khẩu chưa đúng.'
     ,'auth.emailNotVerified': 'Vui lòng xác minh email trước khi đăng nhập.'
     ,'auth.accountSuspended': 'Tài khoản đang bị tạm khóa.'
     ,'auth.accountBanned': 'Tài khoản đã bị khóa.'
     ,'auth.adminAccessDenied': 'Tài khoản không có quyền quản trị hoặc quyền đã bị vô hiệu hóa.'
     ,'auth.adminDisabled': 'Quyền quản trị của tài khoản đã bị vô hiệu hóa.'
     ,'auth.emailExists': 'Email này đã được sử dụng.'
     ,'auth.usernameExists': 'Tên người dùng này đã được sử dụng.'
     ,'auth.invalidToken': 'Liên kết không hợp lệ hoặc đã hết hạn. Hãy yêu cầu liên kết mới.'
     ,'auth.tokenExpired': 'Liên kết đã hết hạn. Hãy yêu cầu liên kết mới.'
     ,'auth.googleNotConfigured': 'Đăng nhập Google chưa được cấu hình.'
     ,'auth.invalidGoogleToken': 'Không thể xác thực tài khoản Google. Vui lòng thử lại.'
     ,'auth.googleConflict': 'Email này đã được liên kết với một tài khoản Google khác.'
     ,'auth.serverUnavailable': 'Chưa kết nối được máy chủ. Kiểm tra kết nối và thử lại.'
     ,'auth.tooManyRequests': 'Bạn đã thử quá nhiều lần. Vui lòng đợi một lát rồi thử lại.'
     ,'auth.accessDenied': 'Tài khoản không có quyền truy cập hoặc đã bị vô hiệu hóa.'
     ,'account.apiChecking': 'Đang kiểm tra kết nối…'
     ,'account.apiConnected': 'Đã kết nối'
     ,'account.apiUnavailable': 'Chưa kết nối được máy chủ'
     ,'account.locationVietnam': 'Việt Nam'
     ,'account.passwordChanged': 'Mật khẩu đã được thay đổi.'
     ,'channel.reportSuccess': 'Cảm ơn bạn đã gửi báo cáo. Chúng tôi sẽ xem xét nội dung này theo Nguyên tắc cộng đồng HuTube.'
     ,'notification.channelInviteToast': 'Bạn có lời mời tham gia kênh{channel}.'
     ,'studio.accessibleChannelsError': 'Không thể tải danh sách kênh bạn có quyền truy cập.'
     ,'studio.channelDataError': 'Không thể tải dữ liệu Studio cho kênh này.'
     ,'upload.serverNoVideo': 'Máy chủ không trả về thông tin video sau khi tải lên.'
     ,'upload.uploadError': 'Không thể tải video lên. Kiểm tra API local và thử lại.'
     ,'ui.statusPublished': 'Đã xuất bản'
     ,'ui.statusDraft': 'Bản nháp'
     ,'ui.statusProcessing': 'Đang xử lý'
     ,'ui.statusScheduled': 'Đã lên lịch'
     ,'ui.statusPending': 'Đang chờ'
     ,'ui.statusRejected': 'Bị từ chối'
     ,'title.login': 'Đăng nhập · HuTube'
     ,'title.register': 'Đăng ký · HuTube'
     ,'title.verifyEmail': 'Xác minh email · HuTube'
     ,'title.forgotPassword': 'Quên mật khẩu · HuTube'
     ,'title.resetPassword': 'Đặt lại mật khẩu · HuTube'
     ,'title.home': 'Trang chủ · HuTube'
     ,'title.explore': 'Khám phá · HuTube'
     ,'title.watch': 'Xem video · HuTube'
     ,'title.terms': 'Điều khoản dịch vụ · HuTube'
     ,'title.privacy': 'Chính sách bảo mật · HuTube'
     ,'title.guidelines': 'Tiêu chuẩn cộng đồng · HuTube'
     ,'title.policies': 'Trung tâm chính sách · HuTube'
     ,'title.plans': 'Gói dịch vụ · HuTube'
     ,'title.planInvite': 'Nhận lời mời gói · HuTube'
     ,'title.planDetail': 'Chi tiết gói · HuTube'
     ,'title.account': 'Cài đặt · HuTube'
     ,'title.history': 'Lịch sử xem · HuTube'
     ,'title.liked': 'Video đã thích · HuTube'
     ,'title.channelCreate': 'Tạo kênh · HuTube'
     ,'title.channel': 'Kênh · HuTube'
     ,'title.channelCustomize': 'Tùy chỉnh kênh · HuTube'
     ,'title.studioSetup': 'Thiết lập kênh · Studio'
     ,'title.studioOverview': 'Creator Studio · HuTube'
     ,'title.studioContent': 'Nội dung kênh · Studio'
     ,'title.studioUpload': 'Tải lên video · Studio'
     ,'title.studioAnalytics': 'Số liệu phân tích · Studio'
     ,'title.studioComments': 'Bình luận · Studio'
     ,'title.studioSubtitles': 'Phụ đề · Studio'
     ,'title.studioSettings': 'Cài đặt · Studio'
     ,'title.studioInvitations': 'Cộng tác · Studio'
  },

  en: {
    // Common
    'common.save': 'Save changes',
    'common.saving': 'Saving...',
    'common.cancel': 'Cancel',
    'common.delete': 'Delete',
    'common.edit': 'Edit',
    'common.back': 'Back',
    'common.continue': 'Continue',
    'common.close': 'Close',
    'common.loading': 'Loading...',
    'common.search': 'Search',
    'common.actions': 'Actions',
    'common.success': 'Success',
    'common.error': 'An error occurred',
    'common.or': 'or',
    'common.copy': 'Copy',
    'common.copied': 'Copied to clipboard',
    'common.retry': 'Retry',
    'common.confirm': 'Confirm',
    'common.all': 'All',
    'common.open': 'Open link',
    'common.skipToContent': 'Skip to main content',

    // Navigation & Topbar / Sidebar
    'nav.home': 'Home',
    'nav.explore': 'Explore',
    'nav.subscriptions': 'Subscriptions',
    'nav.library': 'Library',
    'nav.history': 'Watch history',
    'nav.likedVideos': 'Liked videos',
    'nav.playlists': 'Playlists',
    'nav.yourChannel': 'Your channel',
    'nav.createChannel': 'Create new channel',
    'nav.channelInvitations': 'Channel invitations',
    'nav.settings': 'Settings',
    'nav.profile': 'Your profile',

    // Subscriptions
    'subscriptions.title': 'Subscriptions',
    'subscriptions.latestVideos': 'Latest videos',
    'subscriptions.subscribedChannels': 'Channels you follow',
    'subscriptions.noChannels': 'You have not subscribed to any channels yet',
    'subscriptions.noChannelsDesc': 'Subscribe to your favorite channels to see their latest videos right here.',
    'subscriptions.exploreChannels': 'Explore videos & channels',
    'subscriptions.noVideos': 'No new videos yet',
    'subscriptions.noVideosDesc': 'The channels you follow have not posted any new videos yet.',
    'subscriptions.loginTitle': 'Don\'t miss new videos',
    'subscriptions.loginDesc': 'Sign in to see updates from your favorite channels.',
    'subscriptions.loginButton': 'Sign in now',

    // Profile Page (matching profile.jpg)
    'profile.quote': 'Better videos for a better version of you ♡',
    'profile.editProfile': 'Edit profile',
    'profile.accountSettings': 'Account settings',
    'profile.tagline': 'Live joyfully, watch passionately, spread goodness!',
    'profile.defaultBio': 'Loving healing videos, travel, cuisine and discovering the world. A bit of positivity every day!',
    'profile.joinedIn': 'Joined',
    'profile.verifiedUser': 'Verified',
    'profile.premiumMember': 'HuTube Premium',
    'profile.tabOverview': 'Overview',
    'profile.tabHistory': 'Watch history',
    'profile.tabLiked': 'Liked videos',
    'profile.tabPlaylists': 'Playlists',
    'profile.tabWatchLater': 'Watch later',
    'profile.tabMyPackages': 'My memberships',
    'profile.statWatchTime': 'Watch time',
    'profile.statWatchTimeSub': 'in past 30 days',
    'profile.statWatchTimeTrend': '↑ 12% vs last month',
    'profile.statLiked': 'Liked videos',
    'profile.statPlaylists': 'Playlists',
    'profile.statSubs': 'Subscriptions',
    'profile.statBadge': 'Member badge',
    'profile.statBadgeSince': 'Member since 03/2024',
    'profile.statBadgeRemaining': '247 days remaining',
    'profile.continueWatching': 'Continue watching',
    'profile.viewAll': 'View all',
    'profile.recentlySaved': 'Recently saved',
    'profile.resumeHint': 'You were watching this video',
    'profile.emptyHistory': 'No watch history yet',
    'profile.emptySaved': 'No saved or liked videos yet',
    'profile.recentActivity': 'Recent activity',
    'profile.favoriteGenres': 'Favorite genres',
    'profile.edit': 'Edit',
    'profile.genre.travel': 'Travel',
    'profile.genre.food': 'Food',
    'profile.genre.music': 'Music',
    'profile.genre.film': 'Movies & Film',
    'profile.genre.education': 'Education',
    'profile.genre.tech': 'Technology',
    'profile.genre.lifestyle': 'Lifestyle',
    'profile.genre.health': 'Health',
    'profile.genre.other': 'Other',
    'profile.actLiked': 'Liked video',
    'profile.actWatched': 'Watched',
    'profile.actPlaylist': 'Added to playlist',
    'profile.actSubscribed': 'Subscribed to channel',
    'profile.aboutTitle': 'More info',
    'profile.learnMore': 'Learn more about this profile',
    'profile.seeMore': '...more',
    'profile.shareProfile': 'Share profile',
    'profile.description': 'Description',
    'profile.copiedLink': 'Profile link copied to clipboard',

    'nav.studio': 'HuTube Studio',
    'nav.enterStudio': 'Creator Studio',
    'nav.studioSub': 'Create & manage videos',
    'nav.logout': 'Sign out',
    'nav.collapseSidebar': 'Collapse sidebar',
    'nav.expandSidebar': 'Expand sidebar',
    'nav.searchPlaceholder': 'Search videos, channels or topics',
    'nav.notifications': 'Notifications',
    'nav.theme': 'Appearance',
    'nav.themeLight': 'Light Mode',
    'nav.themeDark': 'Dark Mode',
    'nav.language': 'Language',
    'nav.langVi': 'Vietnamese (VI)',
    'nav.langEn': 'English (EN)',
    'nav.terms': 'Terms',
    'nav.privacy': 'Privacy',
    'nav.guidelines': 'Community Guidelines',
    'nav.policyHub': 'Policy & Safety',
    'nav.navigation': 'Primary navigation',
    'nav.guestPrompt': 'Sign in to start watching, saving, and interacting with videos.',

    // Policy Hub Page
    'policies.hubTitle': 'Policy & Safety',
    'policies.guidelines': 'Community Guidelines',
    'policies.privacy': 'Privacy & Security',
    'policies.terms': 'Terms of Service',
    'policies.monetization': 'Monetization & Partner',
    'policies.enforcement': 'Enforcement & Appeals',
    'policies.print': 'Print Document',
    'policies.downloadPdf': 'Download PDF',
    'policies.printToast': 'Successfully sent print command for policy document.',
    'policies.pdfToast': 'Successfully exported PDF copy of policy document.',
    'policies.closeToast': 'Dismiss notification',
    'policies.categoryNav': 'Policy categories',
    'policies.breadcrumb': 'Breadcrumb',

    'policies.breadcrumbHome': 'Home',
    'policies.breadcrumbLegal': 'Policy & Legal',
    'policies.badgeStandard': 'HuTube Standards · International Best Practices & Decree 13/2023/ND-CP',
    'policies.heroTitle': 'Our Platform Policies',
    'policies.heroMission': 'HuTube’s mission is to give everyone a voice and show them the world. Openness and freedom of expression are central to this mission. Diverse viewpoints are encouraged while maintaining a safe, healthy environment for our community.',
    'policies.heroUpdated': 'Updated: 2026',
    'policies.heroEffective': 'Scope: Entire HuTube platform, mobile apps & web services',

    'policies.tab.guidelines.title': 'Community Guidelines',
    'policies.tab.guidelines.desc': 'Standards that keep HuTube a safe, respectful, and vibrant space for creators and viewers alike.',
    'policies.tab.privacy.title': 'Privacy & Security',
    'policies.tab.privacy.desc': 'Transparent data practices, comprehensive protection compliant with Decree 13/2023/ND-CP, putting you in full control.',
    'policies.tab.terms.title': 'Terms of Service',
    'policies.tab.terms.desc': 'Binding legal terms defining your rights and obligations when accessing, sharing videos, and using HuTube services.',
    'policies.tab.monetization.title': 'Monetization & Partner',
    'policies.tab.monetization.desc': 'Eligibility criteria for the HuTube Partner Program, advertiser-friendly guidelines, and revenue sharing rules.',
    'policies.tab.enforcement.title': 'Enforcement & Appeals',
    'policies.tab.enforcement.desc': 'Transparent disciplinary enforcement via strike stages, EDSA contextual exceptions, and a fair appeals framework.',

    'policies.itemCount': '{count} items',
    'policies.mandatoryRules': 'Mandatory Standards:',
    'policies.exceptionsEdsa': 'Contextual Exceptions (EDSA):',
    'policies.emptySearchTitle': 'No matching policies found',
    'policies.emptySearchDesc': 'No rules or terms match "{query}" in this category.',
    'policies.clearSearch': 'Clear search keyword',

    'policies.sev.critical': 'Critical',
    'policies.sev.high': 'High',
    'policies.sev.medium': 'Standard',
    'policies.sev.info': 'Info',

    'policies.tools.title': 'Your Rights & Choices',
    'policies.tools.desc': 'In accordance with Decree 13/2023/ND-CP, you have full control over your personal data on HuTube.',
    'policies.tools.exportTag': 'DATA EXPORT',
    'policies.tools.exportTitle': 'Download Your Data Archive',
    'policies.tools.exportDesc': 'Download an encrypted ZIP archive containing your videos, comments, history, and profile data.',
    'policies.tools.exportBtn': 'Request Data Archive',
    'policies.tools.algoTag': 'ALGORITHM',
    'policies.tools.algoTitle': 'Reset Feed & History',
    'policies.tools.algoDesc': 'Clear watched videos, search history, and reset 100% of your recommendation algorithm.',
    'policies.tools.algoBtn': 'Reset Feed',
    'policies.tools.adsTag': 'ADVERTISING',
    'policies.tools.adsTitle': 'Manage Ad Settings',
    'policies.tools.adsDesc': 'Toggle personalized advertising based on off-platform behavioral tracking.',
    'policies.tools.adsLabel': 'Personalized Ads:',
    'policies.tools.adsStatusOn': 'ON',
    'policies.tools.adsStatusOff': 'OFF',
    'policies.tools.exportSuccess': 'Your data export request has been received. A secure download link for the ZIP archive will be sent to your email within 24 hours pursuant to Decree 13/2023/ND-CP.',
    'policies.tools.resetSuccess': 'Your personalized recommendation algorithms have been reset to factory defaults.',
    'policies.tools.resetConfirm': 'Are you sure you want to reset all recommendation data and watch history?',
    'policies.tools.adsChanged': 'Personalized behavioral advertising has been set to {status}.',

    'policies.strikes.systemTitle': 'Community Strikes & Disciplinary System',
    'policies.strikes.systemDesc': 'HuTube applies a multi-step progressive enforcement mechanism paired with educational policy courses to help creators understand and correct mistakes.',
    'policies.strikes.warning.badge': 'Warning',
    'policies.strikes.warning.title': 'Initial Educational Warning',
    'policies.strikes.warning.desc': 'First-time violations trigger an educational notification and a 15-minute policy refresher. Content is removed without a strike penalty or functional restrictions.',
    'policies.strikes.s1.badge': 'Strike 1',
    'policies.strikes.s1.title': 'Strike 1 (7-day freeze)',
    'policies.strikes.s1.desc': 'Freezes ability to upload videos, livestream, or post community updates for 7 days. The strike remains active on the channel for 90 days.',
    'policies.strikes.s2.badge': 'Strike 2',
    'policies.strikes.s2.title': 'Strike 2 (14-day freeze)',
    'policies.strikes.s2.desc': 'Receiving a second strike within 90 days freezes all content publishing capabilities across the channel for 14 full days.',
    'policies.strikes.s3.badge': 'Strike 3',
    'policies.strikes.s3.title': 'Strike 3 (Permanent Termination)',
    'policies.strikes.s3.desc': 'Accumulating 3 strikes within 90 days results in permanent account and channel termination, deleting all videos and barring future channel creation.',
    'policies.footer.brandCaption': 'Transparency & User Safety Hub',
    'policies.footer.lang': 'English (US)',
    'policies.footer.copyright': '© 2026 HuTube LLC. All rights reserved under statutory laws.',

    // 33 Policy Names and Contents (EN)
    'policy.CHILD_SAFETY.name': 'Child Safety',
    'policy.CHILD_SAFETY.content': 'Zero tolerance for child sexual abuse or exploitation (CSAM/CSAE), endangerment, or involving minors in physically or emotionally harmful challenges.',
    'policy.SEXUAL_CONTENT.name': 'Sexual Content & Nudity',
    'policy.SEXUAL_CONTENT.content': 'Pornography, explicit sexual acts, and gratuitous nudity are strictly prohibited. Exceptions apply for classical sculpture, painting, or contextual sex education.',
    'policy.SELF_HARM.name': 'Suicide & Self-Harm',
    'policy.SELF_HARM.content': 'Encouraging, instructing, or promoting suicide, self-injury, eating disorders, or extreme starvation challenges is prohibited.',
    'policy.VIOLENCE.name': 'Violent or Graphic Content',
    'policy.VIOLENCE.content': 'Brutal graphic violence, terrorism, and incitement to real-world violence are strictly banned. Historical or journalistic archives require content warnings.',
    'policy.ANIMAL_ABUSE.name': 'Animal Abuse',
    'policy.ANIMAL_ABUSE.content': 'Cruelty, torture, gratuitous killing of animals, or staging fake animal rescues for views is strictly prohibited.',
    'policy.HATE_SPEECH.name': 'Hate Speech',
    'policy.HATE_SPEECH.content': 'Content attacking or demeaning individuals or groups based on protected attributes such as race, religion, gender, sexual orientation, or disability is prohibited.',
    'policy.HARASSMENT.name': 'Harassment & Cyberbullying',
    'policy.HARASSMENT.content': 'Threats of violence, persistent personal attacks, doxxing, or malicious shaming intended to demean individuals are forbidden.',
    'policy.DANGEROUS_ACTIVITIES.name': 'Harmful or Dangerous Content',
    'policy.DANGEROUS_ACTIVITIES.content': 'Reckless viral stunts risking severe injury or death, instructional guides for explosives, weapons, or toxic poisons are prohibited.',
    'policy.SPAM_SCAM.name': 'Spam & Deceptive Practices',
    'policy.SPAM_SCAM.content': 'Mass spamming, financial pyramid schemes, illegitimate crypto scams, and unrealistic profit guarantees are strictly barred.',
    'policy.IMPERSONATION.name': 'Impersonation',
    'policy.IMPERSONATION.content': 'Impersonating celebrities, public authorities, or established brands to deceive viewers or gain illicit benefit is prohibited.',
    'policy.FAKE_ENGAGEMENT.name': 'Fake Engagement',
    'policy.FAKE_ENGAGEMENT.content': 'Artificially inflating views, likes, comments, or subscriber counts with botfarms or exchange services is prohibited. Metrics will be purged and channels frozen.',
    'policy.MISLEADING_METADATA.name': 'Misleading Metadata & Clickbait',
    'policy.MISLEADING_METADATA.content': 'Titles, thumbnails, and descriptions must accurately represent actual video content. Sensationalized deceptive clickbait is prohibited.',
    'policy.EXTERNAL_LINKS.name': 'Harmful External Links',
    'policy.EXTERNAL_LINKS.content': 'Inserting links leading to malware, phishing domains, prohibited content, or scam services is strictly banned.',
    'policy.MISINFORMATION_SYNTHETIC.name': 'Misinformation & Synthetic AI / Deepfake',
    'policy.MISINFORMATION_SYNTHETIC.content': 'Preventing dangerous disinformation and ensuring AI transparency. Creators must label synthetic media simulating real individuals or historical events.',
    'policy.REGULATED_GOODS.name': 'Regulated Goods & Illegal Services',
    'policy.REGULATED_GOODS.content': 'Strict adherence to laws prohibiting trafficking of illegal weapons, narcotics, wildlife parts, and unlicensed online gambling.',
    'policy.CONTENT_SURFACES.name': 'Scope & Platform Surfaces',
    'policy.CONTENT_SURFACES.content': 'Community Guidelines apply universally across long-form videos, Shorts, livestreams, thumbnails, comments, and public playlists.',
    'policy.DOXXING_PRIVACY.name': 'Anti-Doxxing & Personal Privacy',
    'policy.DOXXING_PRIVACY.content': 'Strictly bans publishing private personal information (residential addresses, phone numbers, license plates) to harass or endanger individuals.',
    'policy.PERSONAL_DOCUMENTS.name': 'Identity Documents & Sensitive Data',
    'policy.PERSONAL_DOCUMENTS.content': 'Displaying citizen IDs, passports, driver licenses, or banking credentials without proper redaction is forbidden.',
    'policy.NON_CONSENSUAL.name': 'Non-Consensual Imagery',
    'policy.NON_CONSENSUAL.content': 'Publishing intimate imagery or clandestine footage without explicit affirmative consent is strictly banned and reported to authorities.',
    'policy.MINOR_DATA_PROTECTION.name': 'Minor Data Protection',
    'policy.MINOR_DATA_PROTECTION.content': 'Maximum privacy and protection controls for accounts of users under 16, compliant with personal data protection regulations.',
    'policy.SECURITY_ENCRYPTION.name': 'Security & Encryption Standards',
    'policy.SECURITY_ENCRYPTION.content': 'All user data in transit and at rest is secured via TLS 1.3 and hardware-level AES-256 encryption at domestic Tier-3 Data Centers.',
    'policy.TERMS_ACCEPTANCE.name': 'Terms Acceptance & Service Scope',
    'policy.TERMS_ACCEPTANCE.content': 'Binding legal contract governing all access and utilization of video sharing and social community services on HuTube.',
    'policy.USER_ACCOUNTS.name': 'User Accounts & Security',
    'policy.USER_ACCOUNTS.content': 'Safeguarding login credentials, enabling 2-factor authentication, and assuming legal responsibility for activities conducted under your account.',
    'policy.COPYRIGHT_UGC.name': 'Copyright & UGC License',
    'policy.COPYRIGHT_UGC.content': 'Creators retain intellectual property rights over original content while granting HuTube a global license to host and broadcast. Infringement is barred.',
    'policy.SERVICE_TERMINATION.name': 'Service Termination & Account Closure',
    'policy.SERVICE_TERMINATION.content': 'HuTube reserves the right to suspend or terminate accounts in response to severe terms violations, repeated strikes, or illicit conduct.',
    'policy.LIABILITY_LIMITATION.name': 'Limitation of Liability',
    'policy.LIABILITY_LIMITATION.content': 'Scope of platform legal liability regarding third-party user-generated uploads and external third-party content.',
    'policy.PARTNER_ELIGIBILITY.name': 'Partner Program Eligibility',
    'policy.PARTNER_ELIGIBILITY.content': 'Subscriber thresholds, valid public watch hours, and maintaining zero active community guidelines strikes to unlock monetization.',
    'policy.AD_SUITABILITY_GUIDE.name': 'Advertiser-Friendly Content Guidelines',
    'policy.AD_SUITABILITY_GUIDE.content': 'Evaluation criteria for brand ads suitability: Green icon (Full monetization), Yellow (Limited ads), Red (Demonetized).',
    'policy.REVENUE_PAYOUTS.name': 'Revenue Payouts & Tax Withholding',
    'policy.REVENUE_PAYOUTS.content': 'Monthly revenue disbursements to verified bank accounts and statutory tax withholding compliance under national tax law.',
    'policy.STRIKES_WARNING.name': 'Community Strikes & Enforcement System',
    'policy.STRIKES_WARNING.content': 'Progressive disciplinary enforcement: Educational Warning, Strike 1 (7-day lock), Strike 2 (14-day freeze), Strike 3 (permanent termination).',
    'policy.EDSA_EXCEPTIONS.name': 'EDSA Exceptions Framework',
    'policy.EDSA_EXCEPTIONS.content': 'Contextual exceptions for Educational (E), Documentary (D), Scientific (S), Artistic (A), and Public Interest matters.',
    'policy.APPEALS_PROCESS.name': 'Transparent Appeals Process',
    'policy.APPEALS_PROCESS.content': 'Right to appeal moderation decisions within 30 days; dedicated human specialists review and resolve within 48 hours.',
    'policy.MODERATION_INFRASTRUCTURE.name': 'Moderation Infrastructure & Human-in-the-Loop',
    'policy.MODERATION_INFRASTRUCTURE.content': 'Multi-layered moderation ecosystem: multimodal automated AI scanning paired with native human moderation specialists.',

    // Auth
    'auth.loginTitle': 'Sign in to HuTube',
    'auth.registerTitle': 'Create your HuTube account',
    'auth.forgotPasswordTitle': 'Recover password',
    'auth.resetPasswordTitle': 'Set a new password',
    'auth.verifyEmailTitle': 'Verify your email',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.confirmPassword': 'Confirm password',
    'auth.displayName': 'Display name',
    'auth.username': 'Username',
    'auth.loginBtn': 'Sign In',
    'auth.registerBtn': 'Sign Up',
    'auth.forgotPasswordLink': 'Forgot password?',
    'auth.dontHaveAccount': "Don't have an account?",
    'auth.alreadyHaveAccount': 'Already have an account?',
    'auth.resendOtp': 'Resend OTP',
    'auth.backToLogin': 'Back to sign in',
    'auth.continueGoogle': 'Continue with Google',

    // Account / Settings
    'account.title': 'Account Settings',
    // Settings Tabs (YouTube-style)
    'account.settingsTitle': 'Settings',
    'account.tabAccount': 'Account',
    'account.tabNotifications': 'Notifications',
    'account.tabPlayback': 'Playback and performance',
    'account.tabDownloads': 'Downloads',
    'account.tabPrivacy': 'Privacy',
    'account.tabConnected': 'Connected apps',
    'account.tabBilling': 'Billing and payments',
    'account.tabAdvanced': 'Advanced settings',

    // Tab Account Hero & Sections (Image 1)
    'account.accountHeroTitle': 'Choose how you appear and what you see on HuTube',
    'account.signedInAs': 'Signed in as',
    'account.channelDescImage1': 'This is your public presence on HuTube. You need a channel to upload your own videos, comment on videos, or create playlists.',
    'account.yourChannelLabel': 'Your channel',
    'account.channelStatusLink': 'Channel status and features',
    'account.createChannelLink': 'Create a new channel',
    'account.viewAdvancedLink': 'View advanced settings',
    'account.yourAccountSection': 'Your account',
    'account.yourAccountDesc': 'You sign in to HuTube with your HuTube account',
    'account.hutubeAccountLabel': 'HuTube Account',
    'account.hutubeAccountAction': 'View or change your HuTube account settings',
    'account.hutubeAccountRedirect': 'You will be redirected to your account page',

    // Tab Privacy (Image 2)
    'account.privacyHeroTitle': 'Manage what you share on HuTube',
    'account.privacyHeroSub': 'Choose who can see your subscriptions',
    'account.privacyHeroReview': 'Review the',
    'account.privacyHeroTos': 'HuTube Terms of Service',
    'account.privacyHeroAnd': 'and',
    'account.privacyHeroPrivacyPolicy': 'HuTube Privacy Policy',
    'account.subscriptionsHeading': 'Subscriptions',
    'account.keepSubsPrivate': 'Keep all my subscriptions private',
    'account.keepSubsPrivateDesc': "Other people will not be able to see your subscriptions, unless you use features that make them public.",
    'account.keepSubsPrivateLinkText': 'about features that make subscriptions public, or manage your subscriptions',
    'account.clickHere': 'here',
    'account.mentionsHeading': 'Mentions',
    'account.allowMentions': 'Allow people to mention me',
    'account.allowMentionsDesc': 'People will be able to mention you in video titles, descriptions, posts, and comments. Manage your mention notification settings',
    'account.liveChatHeading': 'Live chat',
    'account.topFanRanking': 'Top fan ranking',
    'account.topFanRankingDesc': 'Get ranked on top fan leaderboards as a viewer and earn experience points (XP) through interactions. If you turn this off, all info about your previous participation will be deleted.',
    'account.celebrateSuperChat': 'Celebrate Super Chat and Super Stickers',
    'account.celebrateSuperChatDesc': 'Key milestones for Super Chat and Super Sticker purchases will be announced in live chat.',
    'account.learnMore': 'Learn more',
    'account.privacySaved': 'Privacy settings updated',

    // Tab Downloads (Matching YouTube Screenshot)
    'account.downloadsHeroTitle': 'Control download options',
    'account.downloadsHeroSub': 'Download options apply to this browser only',
    'account.downloadQualityHeading': 'Download quality',
    'account.downloadQualityAsk': 'Ask each time',
    'account.downloadQuality1080p': 'Full HD (1080p)',
    'account.downloadQuality720p': 'High (720p)',
    'account.downloadQuality480p': 'Standard (480p)',
    'account.downloadQuality144p': 'Low (144p)',
    'account.smartDownloadsHeading': 'Smart downloads',
    'account.smartDownloadsToggle': 'Turn on smart downloads',
    'account.smartDownloadsDesc': "We'll automatically download recommended videos for you.",
    'account.deleteAllDownloadsHeading': 'Delete all downloads',
    'account.deleteAllDownloadsDesc': 'When you delete downloaded videos, this device will have more free storage',
    'account.deleteAllDownloadsBtn': 'Delete all downloads',
    'account.deleteAllDownloadsSuccess': 'All downloads have been deleted on this device',
    'account.downloadQualitySaved': 'Download quality updated',
    'account.smartDownloadsSaved': 'Smart downloads setting updated',

    // Tab Billing and Payments
    'account.billingHeroTitle': 'Billing and payments',
    'account.billingHeroSub': 'Manage payment methods and HuTube memberships',
    'account.paymentMethodsHeading': 'Payment methods',
    'account.noPaymentMethod': 'No payment methods saved',
    'account.addPaymentMethod': 'Add payment method',
    'account.membershipsHeading': 'Purchases and memberships',
    'account.membershipsDesc': 'Enjoy ad-free HuTube, offline downloads and background play with HuTube Premium',
    'account.learnMorePremium': 'Learn about HuTube Premium',

    'account.tabProfile': 'Profile',
    'account.tabPassword': 'Password',
    'account.tabPreferences': 'Appearance & Preferences',
    'account.tabSessions': 'Devices & Sessions',
    'account.profileHeading': 'Personal Information',
    'account.profileDesc': 'Manage your public information and avatar.',
    'account.avatarTitle': 'Profile picture',
    'account.avatarHint': 'JPG, PNG, WEBP or GIF. Max 5MB.',
    'account.changeAvatar': 'Change photo',
    'account.saveProfile': 'Save profile',
    'account.displayName': 'Full name',
    'account.displayNamePlaceholder': 'Enter your display name',
    'account.email': 'Email',
    'account.verified': 'Verified',
    'account.unverified': 'Unverified',
    'account.username': 'Username',
    'account.channelUrlPrefix': 'Your channel URL:',
    'account.country': 'Location / Country',
    'account.countryVN': 'Vietnam',
    'account.countryUS': 'United States',
    'account.countryJP': 'Japan',
    'account.countryKR': 'South Korea',
    'account.countrySG': 'Singapore',
    'account.bio': 'About you',
    'account.bioPlaceholder': 'Tell viewers about yourself...',
    'account.userId': 'Account Identifier (User ID)',
    'account.copy': 'Copy',
    'account.copied': 'Copied',
    'account.subscribersCount': 'subscribers',
    'account.videosCount': 'videos',
    'account.viewChannel': 'View channel',
    'account.customizeChannel': 'Customize channel',
    'account.yourHuTubeChannel': 'Your HuTube Channel',
    'account.noChannelDesc': "You don't have a HuTube channel yet. Create one now to start uploading videos, building a community, and sharing your creative passion!",
    'account.createChannelBtn': 'Create new channel',
    'account.passwordHeading': 'Change Password',
    'account.passwordDesc': 'For security, use a strong password with at least 10 characters.',
    'account.currentPassword': 'Current password',
    'account.newPassword': 'New password',
    'account.confirmNewPassword': 'Confirm new password',
    'account.savePassword': 'Update password',
    'account.notifHeading': 'Notification Preferences',
    'account.notifDesc': 'Choose what notifications you want to receive.',
    'account.notifInAppTitle': 'In-app notifications',
    'account.notifInAppDesc': 'Show notifications on the notification bell when new activity occurs.',
    'account.notifEmailTitle': 'Email notifications',
    'account.notifEmailDesc': 'Receive email notifications for important account updates.',
    'account.notifNewVideoTitle': 'New videos from subscribed channels',
    'account.notifNewVideoDesc': 'Get notified when channels you subscribe to publish new videos.',
    'account.notifCommentReplyTitle': 'Comment replies',
    'account.notifCommentReplyDesc': 'Notify when someone replies to or likes your comment.',
    'account.notifMentionTitle': 'Mentions',
    'account.notifMentionDesc': 'Get notified when someone mentions you in a video or comment.',
    'account.notifChannelActivityTitle': 'Your channel activity',
    'account.notifChannelActivityDesc': 'Updates on views, new subscribers, and channel engagement.',
    'account.notifNewVideos': 'New videos from subscribed channels',
    'account.notifComments': 'Comments and replies',
    'account.notifSubs': 'New subscribers',
    'account.notifMarketing': 'Feature updates and announcements',
    'account.prefsHeading': 'Appearance & Language',
    'account.prefsDesc': 'Customize your viewing and UI preferences.',
    'account.themeLabel': 'Appearance (Color Mode)',
    'account.themeLight': 'Light Mode (Default)',
    'account.themeDark': 'Dark Mode (Comfortable)',
    'account.langLabel': 'Display Language',
    'account.playbackHeading': 'Playback',
    'account.autoplayNext': 'Autoplay next video',
    'account.defaultQuality': 'Default video quality',
    'account.privacyHeading': 'Privacy',
    'account.keepPlaylistsPrivate': 'Keep saved playlists private',
    'account.keepPlaylistsPrivateDesc': 'Only you can view the playlists you have saved.',
    'account.savePrefs': 'Save preferences',
    'account.sessionsHeading': 'Active Sessions',
    'account.sessionsDesc': 'Devices currently logged into your account.',
    'account.currentDevice': 'Current device',
    'account.thisDevice': 'This device',
    'account.signedInAt': 'Signed in:',
    'account.lastActiveAt': 'Active:',
    'account.ipAddress': 'IP address:',
    'account.revoke': 'Revoke',
    'account.confirmRevokeText': 'Are you sure you want to sign out session on device',
    'account.noSessions': 'No active sessions found.',
    'account.logoutOthers': 'Sign out other devices',
    'account.logoutAll': 'Sign out all devices',
    'account.revokeSession': 'Sign out this session',
    'account.profileSaved': 'Profile information saved successfully.',
    'account.avatarSizeError': 'Avatar file size must be less than 5MB.',
    'account.avatarUpdated': 'Avatar updated successfully.',
    'account.enterCurrentPassword': 'Please enter your current password.',
    'account.newPasswordLength': 'New password must be between 10 and 128 characters.',
    'account.passwordsDoNotMatch': 'Passwords do not match.',
    'account.notifSaved': 'Notification preferences saved successfully.',
    'account.prefsSaved': 'Preferences and appearance saved.',
    'account.userIdCopied': 'User ID copied to clipboard.',
    'account.retryLogout': 'Please try logging out again.',
    'account.loggedOutOthers': 'Logged out from other devices.',
    'account.sessionEnded': 'Device session ended.',

    // Channel
    'channel.subscribers': 'subscribers',
    'channel.videos': 'Videos',
    'channel.playlists': 'Playlists',
    'channel.about': 'About',
    'channel.customize': 'Customize channel',
    'channel.manageVideos': 'Manage videos',
    'channel.createTitle': 'Create HuTube Channel',
    'channel.createDesc': 'Begin your creative storytelling journey on HuTube.',
    'channel.name': 'Channel Name',
    'channel.handle': 'Channel Handle',
    'channel.description': 'Channel Description',
    'channel.createBtn': 'Create Channel Now',
    'channel.invitationsTitle': 'Channel Management Invitations',
    'channel.accept': 'Accept',
    'channel.decline': 'Decline',
    'channel.noInvitations': 'You have no pending invitations.',

    // Studio
    'studio.title': 'HuTube Creator Studio',
    'studio.overview': 'Dashboard',
    'studio.content': 'Content',
    'studio.uploadVideo': 'Upload video',
    'studio.analytics': 'Analytics',
    'studio.comments': 'Comments',
    'studio.subtitles': 'Subtitles',
    'studio.settings': 'Channel Settings',
    'studio.proTitle': 'HuTube Pro',
    'studio.proDesc': 'Unlock premium creator tools and analytics',
    'studio.upgradeNow': 'Upgrade now',
    'studio.collapse': 'Collapse',
    'studio.searchPlaceholder': 'Search across your channel...',
    'studio.create': 'Create',
    'studio.creator': 'Creator',
    'studio.backToWeb': 'Back to HuTube',
    'studio.overviewSubtitle': 'Channel overview and performance for the last 28 days',
    'studio.subscribersCount': 'Subscribers',
    'studio.viewsCount': 'Views',
    'studio.watchTime': 'Watch time (hours)',
    'studio.estimatedRevenue': 'Estimated revenue',
    'studio.past28Days': 'last 28 days',
    'studio.latestVideo': 'Your latest video',
    'studio.viewAllVideos': 'View all videos →',
    'studio.publishedYesterday': 'Published: Yesterday',
    'studio.public': 'Public',
    'studio.draft': 'Draft',
    'studio.views': 'views',
    'studio.likes': 'likes',
    'studio.commentsCount': 'comments',
    'studio.analyticsBtn': '📊 Analytics',
    'studio.commentsBtn': '💬 Comments',
    'studio.contentSubtitle': 'Manage videos, posts, and playlists on your channel',
    'studio.filterPlaceholder': 'Filter videos by title...',
    'studio.all': 'All',
    'studio.colVideo': 'Video',
    'studio.colVisibility': 'Visibility',
    'studio.colDate': 'Date',
    'studio.colViews': 'Views',
    'studio.colComments': 'Comments',
    'studio.colLikes': 'Likes vs dislikes',
    'studio.colActions': 'Actions',
    'studio.edit': 'Edit',
    'studio.continue': 'Continue',
    'studio.analyticsSubtitle': 'Traffic, viewer, and engagement analytics',
    'studio.analyticsSummary': 'Your channel got 148,900 views in the last 28 days',
    'studio.analyticsDiff': '23,400 more views than previous period',
    'studio.realtimeViews': 'Real-time views',
    'studio.videoViewsLegend': '● Video views',
    'studio.commentsSubtitle': 'Moderate and respond to viewer comments',
    'studio.publishedComments': 'Published',
    'studio.heldForReview': 'Held for review',
    'studio.hoursAgo': 'hours ago',
    'studio.onVideo': 'on',
    'studio.reply': 'Reply',
    'studio.like': '❤️ Like',
    'studio.subtitlesSubtitle': 'Manage multilingual subtitles and auto-generate with HuTube AI',
    'studio.primaryLanguage': 'Primary language',
    'studio.autoSubtitle': 'Automatic',
    'studio.reviewed': 'Reviewed',
    'studio.addLanguage': 'Add language',
    'studio.settingsSubtitle': 'Configure channel, default upload settings, and permissions',
    'studio.defaultCurrency': 'Default currency',
    'studio.currencyVND': 'VND - Vietnamese Dong (₫)',
    'studio.currencyUSD': 'USD - US Dollar ($)',
    'studio.defaultLicense': 'Default license standard',
    'studio.licenseStandard': 'Standard HuTube License',
    'studio.licenseCC': 'Creative Commons - Attribution (CC BY)',
    'studio.defaultCommentsMode': 'Default comments mode for new videos',
    'studio.commentsAllowAll': 'Allow all comments',
    'studio.commentsHoldInappropriate': 'Hold potentially inappropriate comments for review',
    'studio.commentsDisable': 'Disable comments',

    // Upload Video 6 Steps
    'upload.title': 'Upload video',
    'upload.subtitle': 'Share your story with the HuTube community',
    'upload.step1': 'Choose file',
    'upload.step2': 'Video details',
    'upload.step3': 'Video elements',
    'upload.step4': 'Initial checks',
    'upload.step5': 'Visibility',
    'upload.step6': 'Publish',

    'upload.step1.boxTitle': 'Choose video file',
    'upload.step1.boxDesc': 'Upload a video from your computer to begin',
    'upload.step1.dragDrop': 'Drag and drop video files here',
    'upload.step1.btn': 'Select file',
    'upload.step1.formats': 'Supported formats: MP4, MOV, AVI, MKV, WebM',
    'upload.step1.maxSize': 'Maximum size: 256 GB',
    'upload.step1.uploading': 'Uploading...',
    'upload.step1.remaining': 'About 2 minutes remaining',
    'upload.step1.cancel': 'Cancel',
    'upload.step1.tip': 'Tip: Upload in 1080p or higher to deliver the best viewing experience to your audience.',

    'upload.step2.heading': 'Basic Information',
    'upload.step2.subheading': 'Provide details so viewers can easily find and enjoy your video',
    'upload.step2.videoTitle': 'Title',
    'upload.step2.titleHint': 'A clear, engaging title helps attract more viewers.',
    'upload.step2.desc': 'Description',
    'upload.step2.descHint': 'A detailed description improves search indexing and recommendations.',
    'upload.step2.thumbnail': 'Thumbnail',
    'upload.step2.changeThumb': 'Change thumbnail',
    'upload.step2.thumbHint': 'Choose an engaging thumbnail. 16:9 ratio (1280 x 720) is recommended.',
    'upload.step2.category': 'Category',
    'upload.cat.travel': 'Travel & Lifestyle',
    'upload.cat.music': 'Music',
    'upload.cat.tech': 'Technology',
    'upload.cat.education': 'Education',
    'upload.cat.gaming': 'Gaming',
    'upload.cat.entertainment': 'Entertainment',
    'upload.step2.untitled': 'Untitled Video',
    'upload.step2.tags': 'Tags',
    'upload.step2.tagsPlaceholder': 'Add tag (press Enter)',
    'upload.step2.tagsHint': 'Add keywords to help people discover your video.',
    'upload.step2.language': 'Language',
    'upload.step2.langHint': 'Select the primary spoken language of the video.',
    'upload.step2.saveDraft': 'Save draft',

    'upload.step3.heading': 'Video Elements',
    'upload.step3.subheading': 'Add video chapters to make it easy for viewers to navigate your content.',
    'upload.step3.chapterList': 'Chapter List',
    'upload.step3.chapterName': 'Chapter title',
    'upload.step3.chapterStart': 'Start time',
    'upload.step3.addChapter': 'Add new chapter',
    'upload.step3.chapterNamePlaceholder': 'Enter chapter title...',
    'upload.step3.timePlaceholder': 'mm:ss (e.g. 14:00)',
    'upload.step3.addBtn': 'Add chapter',
    'upload.step3.chapterTip': 'Tip: Scrub along the timeline or click the video at the desired point, then enter a title and add chapter.',
    'upload.step3.aiSubTitle': 'HuTube AI Smart Subtitles',
    'upload.step3.aiSubDesc': 'Automatically recognize speech and generate 98% accurate subtitles.',
    'upload.step5.schedDate': 'Premiere Date',
    'upload.step5.schedTime': 'Premiere Time',

    'upload.step4.heading': 'Initial Checks',
    'upload.step4.subheading': 'We are screening your video to ensure it meets HuTube quality and policy standards.',
    'upload.step4.checkFile': 'Valid video file',
    'upload.step4.checkFileSub': 'Format, size, resolution...',
    'upload.step4.checkMeta': 'Complete metadata',
    'upload.step4.checkMetaSub': 'Title, description, tags, category...',
    'upload.step4.checkThumb': 'Qualified thumbnail',
    'upload.step4.checkThumbSub': 'Resolution, aspect ratio, content...',
    'upload.step4.checkCopyright': 'Copyright check',
    'upload.step4.checkCopyrightSub': 'Matching against copyrighted content databases...',
    'upload.step4.checkPolicy': 'Community guidelines review',
    'upload.step4.checkPolicySub': 'Screening sensitive, violent, or offensive content...',
    'upload.step4.checkTech': 'Technical processing',
    'upload.step4.checkTechSub': 'Generating streaming renditions and automated captions...',
    'upload.step4.passed': 'Pass',
    'upload.step4.warning': 'Attention',
    'upload.step4.processing': 'Processing',
    'upload.step4.issuesHeading': 'Items to review',
    'upload.step4.issueDesc': 'Description could be more detailed',
    'upload.step4.issueDescSub': 'Your video description is quite brief. Adding more context helps recommendations.',
    'upload.step4.issueChapter': 'Review chapter timestamps',
    'upload.step4.issueChapterSub': 'Some chapter intervals appear uneven. Please verify for optimal viewing experience.',
    'upload.step4.continueNotice': 'You may proceed with publishing. We will notify you if any critical issue arises.',

    'upload.step5.heading': 'Visibility',
    'upload.step5.subheading': 'Choose who can watch your video',
    'upload.step5.public': 'Public',
    'upload.step5.publicDesc': 'Everyone can search for, view, and share your video.',
    'upload.step5.recommended': 'Recommended',
    'upload.step5.unlisted': 'Unlisted',
    'upload.step5.unlistedDesc': 'Only people with the video link can watch it.',
    'upload.step5.private': 'Private',
    'upload.step5.privateDesc': 'Only you and invited viewers can access this video.',
    'upload.step5.publishTime': 'Publishing Schedule',
    'upload.step5.publishTimeSub': 'Choose when your video goes live',
    'upload.step5.publishNow': 'Publish upon approval',
    'upload.step5.publishNowDesc': 'Video will be made public immediately once checks and encoding complete.',
    'upload.step5.schedule': 'Schedule',
    'upload.step5.scheduleDesc': 'Select a date and time for automated publishing.',
    'upload.step5.otherOptions': 'Additional Options',
    'upload.step5.otherOptionsSub': 'Configure engagement settings for your video',
    'upload.step5.allowComments': 'Allow comments',
    'upload.step5.allowCommentsDesc': 'Viewers can leave comments on your video.',
    'upload.step5.addPlaylist': 'Add to playlist',
    'upload.step5.selectPlaylist': 'Select playlist (optional)',
    'upload.step5.policyNotice': 'Notice: Videos are made public only after automated processing completes and passes HuTube guidelines.',

    'upload.step6.congrats': 'Your video has been submitted for publishing!',
    'upload.step6.congratsDesc': 'Your video has been processed and is ready to appear on your channel. Thank you for sharing great content with HuTube!',
    'upload.step6.moderationPending': 'Video sent for moderation!',
    'upload.step6.moderationPendingDesc': 'Your video is waiting for HuTube review. It will appear publicly only after approval; you can track its status in Content.',
    'upload.step6.moderationStatus': 'Awaiting moderation',
    'upload.step6.summaryHeading': 'Video Details',
    'upload.step6.videoLink': 'Video link',
    'upload.step6.watchVideo': 'Watch video',
    'upload.step6.copyLink': 'Copy link',
    'upload.step6.share': 'Share',
    'upload.step6.backToContent': 'Back to Content',
    'upload.step6.uploadAnother': 'Upload another video',

    // Sidebar Widgets
    'upload.sidebar.preview': 'Video Preview',
    'upload.sidebar.fileInfo': 'File Information',
    'upload.sidebar.format': 'Format',
    'upload.sidebar.size': 'File size',
    'upload.sidebar.duration': 'Duration',
    'upload.sidebar.resolution': 'Resolution',
    'upload.sourceQuality': 'Source video quality',
    'upload.sourceQualityHint': 'Only qualities up to the original video resolution can be selected.',
    'upload.sidebar.storageQuota': 'Channel Storage',
    'upload.sidebar.storageUsed': 'Used',
    'upload.sidebar.importantNotes': 'Important Guidelines',
    'upload.sidebar.note1': 'Only upload content that you own or have explicit permission to use.',
    'upload.sidebar.note2': 'Do not post content that violates copyright, promotes violence, or spreads disinformation.',
    'upload.sidebar.note3': 'HuTube automatically inspects media before public indexing.',
    'upload.sidebar.policyLink': 'Learn more about HuTube Content Guidelines →',
    'upload.sidebar.statusTitle': 'Processing Status',
    'upload.sidebar.statusUploaded': 'Upload complete',
    'upload.sidebar.statusProcessed': 'Video encoding complete',
    'upload.sidebar.statusChecked': 'Automated checks passed',
    'upload.sidebar.statusReady': 'Ready to publish',
    'upload.sidebar.statusPublished': 'Published',
    'upload.sidebar.nextTitle': 'Next up:',
    'upload.sidebar.nextSubtitles': 'Edit subtitles & CC',
    'upload.sidebar.nextShare': 'Share with community',
    'upload.sidebar.nextAnalytics': 'View analytics',
    'upload.sidebar.nextManage': 'Manage in Creator Studio',

    // UI completion: public pages and collaboration flows
    'ui.loadingVideos': 'Loading videos…',
    'ui.videoLoadError': 'Unable to load the video list.',
    'ui.noVideos': 'No videos yet.',
    'ui.videoList': 'Video list',
    'ui.views': 'views',
    'ui.seconds': 'seconds',
    'ui.people': 'people',
    'ui.videos': 'videos',
    'ui.closePopup': 'Close popup',
    'ui.verifiedChannel': 'Verified channel',
    'ui.openCreatorStudio': 'Open Creator Studio',
    'ui.more': '...see more',
    'ui.otherLinks': 'and {count} other links',
    'ui.workEmail': 'Business email',
    'ui.description': 'Description',
    'ui.links': 'Links',
    'ui.otherInfo': 'More information',
    'ui.vietnam': 'Vietnam',
    'ui.joined': 'Joined {date}',
    'ui.subscribers': 'subscribers',
    'ui.comments': 'comments',
    'ui.watchHours': 'hours',
    'ui.upload': 'Upload video',
    'ui.likes': 'likes',
    'ui.public': '🌐 Public',
    'ui.unlisted': '🔗 Unlisted',
    'ui.private': '🔒 Private',
    'ui.moderationApproved': '✓ Approved',
    'ui.moderationPending': '⏳ Pending review',
    'ui.moderationReviewing': '🔍 Under review',
    'ui.moderationRejected': '✕ Rejected',
    'ui.moderationNotSubmitted': 'Not submitted',
    'ui.saving': 'Saving…',
    'ui.noData': 'No data yet.',
    'ui.all': 'All',
    'ui.yes': 'Yes',
    'ui.no': 'No',
    'ui.supported': '✓ Supported',
    'ui.notSupported': '✕ Not supported',
    'ui.copyLink': 'Copy link',
    'ui.share': 'Share',
    'ui.openLink': 'Open link',
    'ui.invite': 'Invite member',
    'ui.revoke': 'Revoke',
    'ui.status': 'Status',
    'ui.date': 'Date',
    'ui.actions': 'Actions',

    'home.loading': 'Loading videos…',
    'home.error': 'Unable to load the video list.',
    'home.empty': 'No videos yet.',
    'home.videoList': 'Video list',
    'home.views': 'views',
    'explore.filters': 'Explore filters',
    'explore.heading': 'Explore videos',
    'explore.searchHeading': 'Search results',
    'explore.subtitle': 'Find new stories, ideas, and creators on HuTube.',
    'explore.searchSubmit': 'Search',
    'explore.topics': 'Popular topics',
    'explore.sortBy': 'Sort by',
    'explore.videoCountUnit': 'videos',
    'explore.pagination': 'Search result pages',
    'explore.previousPage': 'Previous page',
    'explore.nextPage': 'Next page',
    'explore.sort': 'Sort by',
    'explore.newest': 'Newest',
    'explore.popular': 'Popular',
    'explore.trending': 'Trending',
    'explore.sortRelevance': 'Most relevant',
    'explore.sortViews': 'Most viewed',
    'explore.sortEngagement': 'Most engaging',
    'explore.category': 'Category',
    'explore.allCategories': 'All categories',
    'explore.videoList': 'Video list',
    'explore.searchPlaceholder': 'Search videos, channels, topics...',
    'explore.filterTitle': 'Filters',
    'explore.activeFilters': 'Active filters',
    'explore.clearFilters': 'Clear filter',
    'explore.clearAllFilters': 'Clear all filters',
    'explore.durationAll': 'Any duration',
    'explore.durationShort': 'Under 4 minutes',
    'explore.durationMedium': '4 – 20 minutes',
    'explore.durationLong': 'Over 20 minutes',
    'explore.dateAll': 'Any time',
    'explore.dateToday': 'Today',
    'explore.dateThisWeek': 'This week',
    'explore.dateThisMonth': 'This month',
    'explore.dateThisYear': 'This year',
    'explore.resultsCount': 'Found {count} videos',
    'explore.noResultsTitle': 'No results found',
    'explore.noResultsDesc': 'Try different keywords or clear your filters to see more videos.',
    'explore.tryDifferentKeywords': 'Try different keywords',
    'explore.searchLabel': 'Search in explore page',

    'library.ratingFilter': 'Filter videos by your rating',
    'library.ratingLabel': 'Filter by rating',
    'library.loading': 'Loading video library',
    'library.watch': 'Watch {title}',
    'library.yourRating': 'You: {rating}',
    'library.overallRating': 'Overall {rating}/5 ({count})',
    'library.watched': 'Watched {progress}',
    'library.resume': 'You are still watching this video',
    'library.pagination': 'Video library pagination',
    'library.previous': '← Previous',
    'library.next': 'Next →',
    'library.page': 'Page {page} / {total}',
    'library.noMatching': 'No matching videos',
    'library.noLiked': 'No liked videos yet',
    'library.noHistory': 'No watch history yet',
    'library.matchingHint': 'Try choosing a different rating.',
    'library.likedHint': 'Videos you like will appear here.',
    'library.historyHint': 'Videos you open and watch will be saved here.',
    'library.seeAllLiked': 'View all liked videos',
    'library.loadError': 'Unable to load the video library.',

    'channel.collaborationTitle': 'You have been invited to collaborate',
    'channel.collaborationDesc': 'You do not need to create your own channel to work on an invited channel.',
    'channel.viewInvitations': 'View invitations',
    'channel.ownedTitle': 'You already own a HuTube channel',
    'channel.ownedDesc': 'Each account can be linked to one broadcasting channel.',
    'channel.viewYourChannel': 'View your channel',
    'channel.formTitle': 'Create your HuTube channel',
    'channel.formDesc': 'Start sharing creative videos and connect with your viewers.',
    'channel.uploadBanner': 'Upload a channel banner (16:9 or landscape recommended)',
    'channel.bannerAlt': 'Banner preview',
    'channel.uploadAvatar': 'Click to upload a channel avatar',
    'channel.avatarAlt': 'Avatar preview',
    'channel.nameRequired': 'Channel name *',
    'channel.namePlaceholder': 'Example: Science TV, Travel Stories...',
    'channel.handleLabel': 'Handle *',
    'channel.handlePlaceholder': 'mychannel',
    'channel.handleHelp': 'Your handle is your unique address: hutube.vn/@{handle}',
    'channel.descriptionLabel': 'Channel description',
    'channel.descriptionPlaceholder': 'Introduce your channel so viewers know what to expect...',
    'channel.contactEmail': 'Business contact email',
    'channel.contactEmailPlaceholder': 'contact@example.com',
    'channel.creating': 'Creating channel...',
    'channel.createNow': 'Create channel now',
    'channel.cancel': 'Cancel',
    'channel.bannerClick': 'Click to upload a banner',
    'channel.content': 'Channel content',
    'channel.unavailable': 'This channel is unavailable',
    'channel.backProfile': 'Back to profile',
    'channel.descriptionFallback': 'Learn more about this channel',
    'channel.studio': 'Open Studio',
    'channel.subscribe': 'Subscribed',
    'channel.follow': 'Subscribe',
    'channel.turnOnNotifications': 'Turn on channel notifications',
    'channel.turnOffNotifications': 'Turn off channel notifications',
    'channel.notificationsEnabled': 'Notifications are on for this channel.',
    'channel.notificationsDisabled': 'Notifications are off for this channel.',
    'channel.notificationsUpdateError': 'Could not update notifications right now.',
    'channel.tabs': 'Channel content',
    'channel.noVideos': 'No videos yet',
    'channel.noVideosDesc': 'This channel has not uploaded any videos yet. Check back later!',
    'channel.noPlaylists': 'No playlists yet',
    'channel.noPlaylistsDesc': 'No public playlists have been created on this channel.',
    'channel.contactDetails': 'Contact details',
    'channel.noLinks': 'No external links yet.',
    'channel.channelUrl': 'www.hutube.vn/@{handle}',
    'channel.joined': 'Joined {date}',
    'channel.totalViews': 'views',
    'channel.shareCopied': 'Copied!',
    'channel.share': 'Share channel',
    'channel.report': 'Report user',
    'channel.reload': 'Reload',
    'channel.loadingInvitations': 'Loading invitations and collaboration channels…',
    'channel.pendingInvitations': 'Pending invitations',
    'channel.pendingDesc': 'Review the role and permission scope before joining.',
    'channel.expires': 'Expires {date}',
    'channel.processing': 'Processing…',
    'channel.inviteAccept': 'Accept',
    'channel.inviteDecline': 'Decline',
    'channel.noPending': 'No pending invitations',
    'channel.noPendingDesc': 'New invitations sent to your account email will appear here.',
    'channel.collaborating': 'Collaboration channels',
    'channel.collaboratingDesc': 'Open Studio on each channel with its assigned role and permissions.',
    'channel.noAccessible': 'You do not have access to any channel yet.',
    'channel.openStudio': 'Open Studio',
    'channel.basic': 'Basic information',
    'channel.branding': 'Branding',
    'channel.members': 'Members & permissions',
    'channel.danger': 'Delete channel',
    'channel.viewChannel': 'View channel',
    'channel.save': 'Save changes',
    'channel.addLink': 'Add link',
    'channel.remove': 'Remove',
    'channel.role': 'Role',
    'channel.inviteUser': 'User email',
    'channel.sendInvite': 'Send invitation',
    'channel.pending': 'Pending invitation',
    'channel.withdraw': 'Withdraw',
    'channel.deleteConfirm': 'Confirm channel deletion',
    'channel.delete': 'Delete this channel',
    'channel.otherLink': 'Other link',
    'channel.platform': 'Platform',
    'channel.linkUrl': 'Link URL',
    'channel.roleOwner': 'Owner',
    'channel.roleManager': 'Manager',
    'channel.roleEditor': 'Editor',
    'channel.roleModerator': 'Moderator',
    'channel.roleViewer': 'Viewer',
    'channel.roleManagerDesc': 'Manages the channel profile, content, members, and settings; cannot delete the channel or transfer ownership.',
    'channel.roleEditorDesc': 'Uploads and edits content, manages playlists, and views content data.',
    'channel.roleModeratorDesc': 'Manages the community and comments, but cannot edit videos or channel settings.',
    'channel.roleViewerDesc': 'Can only view the dashboard and the internal data granted to them.',
    'channel.nameError': 'Please enter a channel name.',
    'channel.handleMinError': 'The handle must be at least 3 characters (letters, numbers, _, -, .).',
    'channel.handleCharsError': 'The handle may contain only unaccented letters, numbers, _, -, and .',
    'channel.handleInvalidError': 'This handle is invalid or already in use.',
    'channel.createError': 'Unable to create the channel. Please try again.',
    'channel.loadInvitationsError': 'Unable to load invitations. Please try again.',
    'channel.acceptSuccess': 'You joined {channel}.',
    'channel.declineSuccess': 'Invitation from {channel} declined.',
    'channel.fullManagement': 'Full channel management',
    'channel.videoManagement': 'Can manage video content',
    'channel.commentManagement': 'Can manage comments',
    'channel.viewGrantedData': 'View granted data only',
    'channel.processInvitationError': 'Unable to process the invitation. Please try again.',
    'channel.notFound': 'Channel information was not found.',
    'channel.handleNotFound': 'Channel handle was not found.',
    'channel.loadError': 'Unable to load channel information.',
    'channel.nameEmpty': 'Channel name cannot be empty.',
    'channel.handleLength': 'The handle must be between 3 and 50 characters.',
    'channel.linkUrlError': 'Link URLs must start with http:// or https://.',
    'channel.basicSaved': 'Channel information updated.',
    'channel.avatarSaved': 'Channel avatar updated.',
    'channel.bannerSaved': 'Channel banner updated.',
    'channel.inviteSent': 'Invitation and notification email sent to the member.',
    'channel.roleUpdated': 'The role for {member} was updated.',
    'channel.removeConfirm': 'Remove {member} from the channel?',
    'channel.memberRemoved': 'Member removed from the channel.',
    'channel.inviteWithdrawn': 'Invitation withdrawn.',
    'channel.confirmNameMismatch': 'The confirmation channel name does not match.',
    'channel.handleChannel': 'Channel handle *',
    'channel.address': 'Your channel address: hutube.vn/@{handle}',
    'channel.businessEmail': 'Business contact email',
    'channel.links': 'Links',
    'channel.linksDesc': 'Share external links with viewers. These links appear on your channel profile and introduction page.',
    'channel.reorderLink': 'Drag to reorder',
    'channel.removeLink': 'Remove link',
    'channel.avatarTitle': 'Channel avatar',
    'channel.avatarDesc': 'Your avatar appears beside your videos and comments on HuTube.',
    'channel.changeAvatar': 'Change avatar',
    'channel.bannerTitle': 'Channel banner',
    'channel.bannerDesc': 'This image appears at the top of your channel.',
    'channel.changeBanner': 'Change banner',
    'channel.noBanner': 'No banner yet',
    'channel.watermarkTitle': 'Video watermark',
    'channel.watermarkDesc': 'The watermark appears in the bottom-right corner of your video player.',
    'channel.saveWatermark': 'Save watermark',
    'channel.rolesDesc': 'Each role has a fixed permission set that is always checked by the API.',
    'channel.memberEmailPlaceholder': 'member@example.com',
    'channel.roleDescription': 'Selected role description',
    'channel.memberRole': 'Role for {member}',
    'channel.noOtherMembers': 'No members besides the owner yet.',
    'channel.deleteDesc': 'This removes your channel from search results and public pages. Only the owner can delete it.',
    'channel.deleteMine': 'Delete my channel',
    'channel.deleteWarning': 'You are about to delete the channel',
    'channel.deleteNamePrompt': 'Enter the exact channel name to confirm:',
    'channel.deleteNamePlaceholder': 'Enter channel name: {name}',
    'channel.confirmDelete': 'Confirm deletion',
    'channel.platform.facebook': 'Facebook',
    'channel.platform.instagram': 'Instagram',
    'channel.platform.tiktok': 'TikTok',
    'channel.platform.x': 'X',
    'channel.platform.other': 'Other link',

    'plans.myPlans': 'My plans',
    'plans.explore': 'Explore plans',
    'plans.retry': 'Retry',
    'plans.loadingMine': 'Loading your plan information...',
    'plans.activeDesc': 'This plan is active on your account',
    'plans.detailShare': 'Plan details & sharing',
    'plans.switchOther': 'Switch plan',
    'plans.upgrade': 'View upgrades',
    'plans.upgradePlan': 'Upgrade to this plan',
    'plans.owner': 'Owner',
    'plans.sharedMember': 'Shared member',
    'plans.startDate': 'Start date',
    'plans.endDate': 'End date',
    'plans.expired': 'Expired',
    'plans.autoRenew': 'Auto-renew',
    'plans.enabled': 'On',
    'plans.quotaTitle': 'Channel storage quota',
    'plans.quotaDesc': 'Video storage currently used by this channel',
    'plans.usage': 'Storage usage',
    'plans.used': 'used',
    'plans.remaining': 'Remaining:',
    'plans.maxUpload': 'Maximum video upload',
    'plans.quality': 'Resolution',
    'plans.maxMembers': 'Maximum members',
    'plans.maxDuration': 'Maximum video duration',
    'plans.capabilities': 'Download / background play / PiP',
    'plans.sharedTitle': 'Share plan with family / group',
    'plans.sharedCount': '{current} / {max} people currently sharing',
    'plans.sharedNotice': 'You are a member of a shared plan. Only the plan owner can invite or manage members.',
    'plans.personalNotice': 'This is an individual plan. Switch to a group plan to share it with others.',
    'plans.groupPlans': 'View group sharing plans →',
    'plans.invitePlaceholder': 'Enter the email to share with...',
    'plans.inviteMember': 'Invite member',
    'plans.maxReached': 'This plan has reached its maximum number of members.',
    'plans.memberEmail': 'Member email',
    'plans.invitedDate': 'Invited date',
    'plans.memberStatus': 'Status',
    'plans.accepted': 'Joined',
    'plans.waiting': 'Awaiting confirmation',
    'plans.noMembers': 'No members have been invited to this plan yet.',
    'plans.allocatedQuota': 'Allocated Quota',
    'plans.usedQuota': 'Used',
    'plans.unallocated': 'Unallocated:',
    'plans.allocatedTotal': 'Total Allocated:',
    'plans.ownerQuota': 'Owner limit:',
    'plans.editQuota': 'Edit quota',
    'plans.setQuota': 'Set limit',
    'plans.sharedQuota': 'Shared plan',
    'plans.storageGBPlaceholder': 'Quota (GB, empty = shared)',
    'plans.invalidQuota': 'Quota must be a non-negative number.',
    'plans.quotaBelowUsed': 'Quota cannot be lower than used storage.',
    'plans.usedShort': 'used',
    'plans.remainingShort': 'remaining',
    'plans.storageUpdated': 'Storage quota updated successfully.',
    'plans.storageUpdateError': 'Failed to update storage quota.',
    'plans.noPlan': 'You are not subscribed to a service plan',
    'plans.noPlanDesc': 'Upgrade to increase channel storage, upload quality, and share benefits with friends.',
    'plans.exploreNow': 'Explore service plans',
    'plans.flexible': 'Flexible options',
    'plans.choose': 'Choose a plan for your channel',
    'plans.chooseDesc': 'Add storage, video quality, and shared members as your channel grows.',
    'plans.current': 'Using:',
    'plans.currentBadge': 'Your current plan',
    'plans.popular': 'Most popular',
    'plans.serviceDesc': 'A service plan for creators.',
    'plans.days': 'days',
    'plans.storage': 'Storage',
    'plans.uploadDownload': 'Upload / Download',
    'plans.standard': 'Standard',
    'plans.duration': 'Duration',
    'plans.download': 'Downloads',
    'plans.backgroundPip': 'Background play / PiP',
    'plans.manage': 'Manage this plan',
    'plans.switch': 'Switch to this plan',
    'plans.buy': 'Buy this plan',
    'plans.detailAndShare': 'View details and share',
    'plans.detailLoading': 'Loading service plan...',
    'plans.back': '← Back to plans',
    'plans.currentUse': '✓ You are using this plan',
    'plans.activeNote': 'This plan is active. You can subscribe again after it expires.',
    'plans.activating': 'Activating...',
    'plans.loginSubscribe': 'Sign in to subscribe',
    'plans.benefits': 'Benefits & specifications',
    'plans.benefitsDesc': 'Detailed plan limits and resources',
    'plans.maxStorage': 'Channel storage',
    'plans.maxPerVideo': 'Maximum video size',
    'plans.maxQualityUpload': 'Maximum upload quality',
    'plans.maxQualityDownload': 'Maximum download quality',
    'plans.sharedSeats': 'Shared plan seats',
    'plans.shareInfo': 'Share plan information',
    'plans.shareDesc': 'Send a public link for friends or family to view',
    'plans.planUrl': 'Plan page URL:',
    'plans.shareUrlLabel': 'Plan share link',
    'plans.shareTip': 'Note: This link is public and contains no sensitive data or account information.',
    'plans.inviteAcceptTitle': 'Shared plan invitation',
    'plans.inviteIncomplete': 'The invitation link is incomplete.',
    'plans.inviteLogin': 'Sign in with the email address that received the invitation to continue.',
    'plans.inviteLoginButton': 'Sign in to accept',
    'plans.inviteCheckEmail': 'Check your account email and confirm the plan invitation.',
    'plans.acceptInvite': 'Accept invitation',
    'plans.openMine': 'Open My plans',
    'plans.loadError': 'Unable to load service plans.',
    'plans.inviteError': 'Unable to send the invitation.',
    'plans.revokeError': 'Unable to revoke the member.',
    'plans.minutes': '{count} minutes',
    'plans.hours': '{count} hours',
    'plans.hoursMinutes': '{hours} hours {minutes} minutes',
    'plans.invalid': 'This service plan is invalid.',
    'plans.notFound': 'Service plan not found.',
    'plans.copiedShare': 'Plan share link copied.',
    'plans.copyError': 'Automatic copying failed. Select and copy the link from the field above.',
    'plans.shareError': 'Sharing is not available on this device.',
    'plans.subscribeSuccess': 'Plan subscription successful. You can manage quota and members in My plans.',
    'plans.joined': 'You joined the service plan.',
    'plans.inviteInvalid': 'This invitation is invalid or has expired.',
    'plans.viewMode': 'Plan display mode',
    'plans.catalogLabel': 'Service plans',
    'plans.allPlans': 'All service plans',
    'plans.detailDesc': 'A plan for creators and advanced viewers on HuTube.',
    'plans.notPurchased': 'Plan not purchased',
    'plans.backgroundPlay': 'Background play',
    'plans.pip': 'Picture-in-picture (PiP)',
    'plans.processingInvite': 'Confirming…',

    'watch.loading': 'Loading video',
    'watch.unavailableTitle': 'Unable to open video',
    'watch.home': 'Go to home',
    'watch.notReady': 'This video is not ready to play.',
    'watch.videoInfo': 'Video information',
    'watch.play': 'Play video',
    'watch.pause': 'Pause',
    'watch.back10': 'Rewind 10 seconds',
    'watch.forward10': 'Forward 10 seconds',
    'watch.unmute': 'Turn on sound',
    'watch.mute': 'Mute',
    'watch.volume': 'Volume',
    'watch.quality': 'Quality',
    'watch.videoQuality': 'Video quality',
    'watch.speed': 'Speed',
    'watch.restoreSize': 'Restore video size',
    'watch.minimize': 'Minimize video',
    'watch.pictureInPicture': 'Play in a floating window',
    'watch.exitPictureInPicture': 'Close floating window',
    'watch.fullscreen': 'Fullscreen',
    'watch.progress': 'Video progress',
    'watch.actions': 'Video actions',
    'watch.like': 'Like video',
    'watch.dislike': 'Dislike video',
    'watch.loginInteract': 'Sign in to interact',
    'watch.download': 'Download',
    'watch.loginDownload': 'Sign in to download',
    'watch.ratingGroup': 'Rate this video from 1 to 5 stars',
    'watch.rating': 'Rating',
    'watch.ratingStar': 'Rate {star} stars',
    'watch.clearRating': 'Clear rating',
    'watch.shortcut': 'K / Space play · J/L ±10s · F fullscreen · M mute · I minimize',
    'watch.shareVideo': 'Share video',
    'watch.shareDesc': 'Copy the link to send it to someone else.',
    'watch.videoLink': 'Video link',
    'watch.downloadTitle': 'Download video',
    'watch.downloadDesc': 'Quality available on your current plan.',
    'watch.preparing': 'Preparing…',
    'watch.noDownloadQuality': 'No downloadable quality is available on the current plan.',
    'watch.chapters': 'Video contents',
    'watch.chaptersDesc': 'Chapters take you directly to the part you want to watch.',
    'watch.chapterCount': 'chapters',
    'watch.comments': 'Comments',
    'watch.commentCount': '{count} comments on this video',
    'watch.newest': 'Newest',
    'watch.commentPlaceholder': 'Write a comment…',
    'watch.keepCivil': 'Keep the conversation respectful.',
    'watch.sendComment': 'Post comment',
    'watch.loginComment': 'Sign in to join the conversation about this video.',
    'watch.reply': 'Reply',
    'watch.replyPlaceholder': 'Write a reply…',
    'watch.send': 'Send',
    'watch.likeComment': 'Like',
    'watch.dislikeComment': 'Dislike',
    'watch.hideReplies': 'Hide replies',
    'watch.viewReplies': 'View {count} replies',
    'watch.show': 'Show',
    'watch.hide': 'Hide',
    'watch.remove': 'Delete',
    'watch.report': 'Report',
    'watch.replies': 'Replies',
    'watch.replyLoading': 'Loading replies…',
    'watch.descriptionEmpty': 'This video has no description yet.',

    // Studio pages
    'studio.loading': 'Loading…',
    'studio.channelOverview': 'Channel overview',
    'studio.recentVideo': 'Latest video',
    'studio.seeAll': 'View all',
    'studio.emptyVideo': 'No videos yet. Upload your first video.',
    'studio.searchVideo': 'Search by video title...',
    'studio.colModeration': 'Moderation status',
    'studio.interaction': 'Engagement',
    'studio.noVideosList': 'No videos in this list.',
    'studio.visible': 'Visible',
    'studio.hidden': 'Hidden',
    'studio.showAgain': 'Show again',
    'studio.hide': 'Hide',
    'studio.send': 'Send',
    'studio.replyPlaceholder': 'Write a reply',
    'studio.noComments': 'No comments in this state.',
    'studio.noSubtitles': 'No subtitles yet',
    'studio.noVideo': 'No videos yet.',
    'studio.notSet': 'Not set',
    'studio.channelInfo': 'Channel information',
    'studio.saveChannelInfo': 'Save channel information',
    'studio.viewOnly': 'View-only access',
    'studio.viewOnlyDesc': 'You can view channel data but cannot edit basic information.',
    'studio.display': 'Display',
    'studio.language': 'Language',
    'studio.light': 'Light',
    'studio.dark': 'Dark',
    'studio.saveSettings': 'Save settings',
    'studio.permissionError': 'You do not have permission to edit channel information.',
    'studio.saved': 'Channel settings saved.',
    'studio.saveError': 'Unable to save channel settings.'
    ,'studio.performanceByVideo': 'Performance by video'
    ,'studio.channelMetrics': 'Channel metrics'
    ,'studio.publicModerationToast': '"{title}" was made public and sent to the moderation queue.'
    ,'studio.publicToast': '"{title}" is now public.'
    ,'studio.unlistedToast': '"{title}" is now unlisted.'
    ,'studio.privateToast': '"{title}" is now private.'
    ,'studio.visibilityError': 'Unable to update video visibility.'
     ,'ui.delete': 'Delete'
     ,'ui.confirmLogoutTitle': 'Confirm sign out'
     ,'ui.confirmLogoutDesc': 'Are you sure you want to sign out of this account?'
     ,'ui.userHuTube': 'HuTube user'
     ,'ui.user': 'User'
     ,'ui.liked': 'Liked'
     ,'ui.playlist': 'Playlist'
     ,'ui.subscriptions': 'Subscriptions'
    ,'ui.quickActions': 'Quick actions'
    ,'ui.closeAccountMenu': 'Close account menu'
    ,'ui.account': 'Account'
    ,'ui.accountStats': 'Account statistics'
    ,'ui.accountActions': 'Account actions'
    ,'ui.signIn': 'Sign in'
    ,'ui.collaborationChannel': 'Collaborating channel'
    ,'ui.openCollaborationChannel': 'Open collaborating channel'
    ,'ui.collaborationInvites': 'Collaboration invites'
    ,'ui.waitingConfirmation': 'Awaiting your confirmation'
    ,'ui.createFirstChannel': 'Create your first channel'
    ,'ui.startCreatingContent': 'Start creating content'
    ,'ui.createOwnChannel': 'Create your own channel'
    ,'ui.startOwnChannel': 'Start your channel'
    ,'ui.channelSettings': 'Channel settings'
    ,'ui.channelSettingsDesc': 'Customize your channel'
    ,'ui.packageDesc': 'Manage and subscribe to plans'
    ,'ui.accountSettings': 'Account settings'
    ,'ui.accountSettingsDesc': 'Security, notifications and preferences'
    ,'ui.myLinks': 'My links'
    ,'ui.addLinks': 'Add Instagram, Facebook, TikTok…'
    ,'ui.notificationsList': 'Notification list'
    ,'ui.markAllRead': 'Mark all as read'
    ,'ui.noNotifications': 'No notifications yet.'
    ,'ui.loadingNotifications': 'Loading…'
    ,'ui.cancelUpload': 'Cancel upload'
    ,'ui.closeUpload': 'Close upload progress'
    ,'ui.uploading': 'Uploading video…'
    ,'ui.processingVideo': 'Creating video qualities…'
    ,'ui.uploadSuccess': 'Video uploaded successfully'
    ,'ui.uploadFailed': 'Video upload failed'
    ,'ui.creatorStudio': 'Creator Studio'
    ,'ui.newBadge': 'New'
    ,'ui.collaborateOnChannel': 'Collaborate on a channel'
    ,'ui.closeMenu': 'Close menu'
    ,'ui.searchShortcut': 'Ctrl K'
    ,'ui.reportPrompt': 'Choose a violation code:'
    ,'ui.reportDescriptionPrompt': 'Additional description (optional):'

    ,'auth.introLabel': 'CREATORS · VIEWERS · COMMUNITY'
    ,'auth.heroCreate': 'Create.'
    ,'auth.heroShare': 'Share.'
    ,'auth.heroBelong': 'Belong.'
    ,'auth.heroDescription': 'HuTube gives you the tools to create, connect and explore a world of video with a community that celebrates your stories and perspective.'
    ,'auth.featureCreate': 'Create without limits'
    ,'auth.featureCreateDesc': 'Turn your ideas into amazing videos'
    ,'auth.featureShare': 'Share your world'
    ,'auth.featureShareDesc': 'Connect with viewers who share your interests'
    ,'auth.featureBelong': 'Discover & belong'
    ,'auth.featureBelongDesc': 'A place where you can always find inspiration'
    ,'auth.tagline': 'Better videos, better people'
    ,'auth.slideStory': 'Your story<br>belongs here'
    ,'auth.slideWorld': 'A bigger world<br>in every video'
    ,'auth.slideInspire': 'Inspire the<br>world around you'
    ,'auth.cardExplore': 'EXPLORE'
    ,'auth.cardCreate': 'CREATE'
    ,'auth.cardLearn': 'LEARN'
    ,'auth.cardShare': 'SHARE'
    ,'auth.cardBelong': 'BELONG'
    ,'auth.subTagline': 'A MORE OPEN, CREATIVE, KINDER INTERNET'
    ,'auth.loginSubtitle': 'Welcome back to HuTube.'
    ,'auth.adminSubtitle': 'For the administration team.'
    ,'auth.registerSubtitle': 'Get started with your email.'
    ,'auth.verifySubtitle': 'Finish verification to protect your account.'
    ,'auth.forgotSubtitle': 'Enter your email to receive a password reset link.'
    ,'auth.resetSubtitle': 'Choose a new password for your account.'
    ,'auth.verificationHelp': "Didn't receive the verification email?"
    ,'auth.resendEmail': 'Send email again'
    ,'auth.usernameHint': '3–50 characters: letters, numbers, periods, underscores or hyphens.'
    ,'auth.usernameInvalid': 'Username format is not valid.'
    ,'auth.emailInvalid': 'Enter a valid email address.'
    ,'auth.passwordHint': '10–128 characters, including uppercase, lowercase and numbers.'
    ,'auth.passwordInvalid': 'Password does not meet the requirements.'
    ,'auth.passwordLoginRequired': 'Enter your password.'
    ,'auth.showPassword': 'Show password'
    ,'auth.hidePassword': 'Hide password'
    ,'auth.googleLogin': 'Sign in with Google'
    ,'auth.resendEmailLabel': 'Email to receive a new link'
    ,'auth.mobileAppLink': 'Open in the HuTube app'
    ,'auth.appLoginLink': 'Sign in in the HuTube app'
    ,'auth.sessionExpired': 'Your session expired. Sign in again to continue.'
    ,'auth.resetMissingToken': 'This link is missing a verification token. Request a new password reset link.'
    ,'auth.googleCredentialMissing': 'Google did not return authentication details.'
    ,'auth.googleLoadError': 'Unable to load Google Sign-In. Please try again.'
    ,'auth.formInvalid': 'Check the fields marked in the form.'
    ,'auth.passwordMismatch': 'Passwords do not match.'
    ,'auth.registerSuccess': 'Your account was created. Check your inbox to verify your email before signing in.'
    ,'auth.forgotSuccess': 'If the email exists in our system, password reset instructions will be sent to you. Check your spam folder too.'
    ,'auth.resetSuccess': 'Your password was changed and old sessions were ended. You can now sign in with the new password.'
    ,'auth.verifySuccess': 'Your email has been verified. You can sign in now.'
    ,'auth.resendSuccess': 'If your account needs verification, a new link will be sent to your email.'

    ,'account.channelId': 'Channel identifier (Channel ID)'
    ,'account.settingsAria': 'Account settings'
     ,'account.dismissMessage': 'Dismiss notification'

    ,'watch.unavailableError': 'This video is unavailable or you do not have permission to view it.'
    ,'watch.playbackQualityError': 'Higher-quality versions could not be loaded. The source video may still play.'
    ,'watch.renditionError': 'This quality could not be played. Try another quality.'
    ,'watch.lowerRenditionFallback': 'This rendition failed; HuTube is trying a lower quality.'
    ,'watch.sourceFallback': 'The quality rendition failed; HuTube is trying the source file.'
    ,'watch.pictureInPictureUnsupported': 'This browser does not support picture-in-picture.'
    ,'watch.pictureInPictureFailed': 'Could not open the floating video window.'
    ,'watch.playError': 'The video cannot play at this time.'
    ,'watch.loginReaction': 'Sign in to like or dislike this video.'
    ,'watch.interactionError': 'Sign in to interact with this video.'
    ,'watch.loginRating': 'Sign in to rate this video.'
    ,'watch.ratingSaved': 'Your rating was updated.'
    ,'watch.shareReadyPublic': 'The public video link is ready to share.'
    ,'watch.shareReady': 'The video link is ready to share.'
    ,'watch.copyHint': 'Copy the link from the field above.'
    ,'watch.shareCopied': 'Video link copied.'
    ,'watch.copyError': 'Automatic copying failed. Copy the link manually.'
    ,'watch.loginCommentAction': 'Sign in to comment.'
    ,'watch.commentError': 'Unable to post the comment.'
    ,'watch.loginReply': 'Sign in to reply to comments.'
    ,'watch.replyError': 'Unable to post the reply.'
    ,'watch.replySaved': 'Reply posted.'
    ,'watch.loginCommentInteraction': 'Sign in to interact with comments.'
    ,'watch.commentUpdateError': 'Unable to update the comment.'
    ,'watch.loginCommentManage': 'Sign in to manage comments.'
    ,'watch.loginCommentDelete': 'Sign in to delete comments.'
    ,'watch.deleteCommentConfirm': 'Delete this comment?'
    ,'watch.loginReport': 'Sign in to report a comment.'
    ,'watch.noViolationTypes': 'There are no violation types available for reporting.'
    ,'watch.violationChoice': 'Choose a violation code:\n{choices}'
    ,'watch.invalidViolationCode': 'Invalid violation code.'
    ,'watch.reportSent': 'Comment report sent.'
    ,'watch.reportError': 'Unable to send the report. Please try again.'
    ,'watch.downloadUnsupported': 'The current plan does not support video downloads.'
    ,'watch.downloadCreatedWithLink': 'Download created. You can open the link from the download notification.'
    ,'watch.downloadCreated': 'Download created.'
    ,'watch.downloadError': 'Unable to create the download.'
    ,'watch.noReplies': 'No replies yet.'
    ,'watch.emptyCommentsTitle': 'No comments yet'
    ,'watch.emptyCommentsDesc': 'Be the first to share your thoughts about this video.'
    ,'watch.recommendations': 'Recommended videos'
    ,'watch.recommendationFilters': 'Recommended video filters'
    ,'watch.relatedVideos': 'Related videos'
    ,'watch.sameChannel': 'From this channel'
    ,'watch.categoryVietnam': 'Vietnam travel'
    ,'watch.recommendedTitle': 'Recommended for you'
    ,'watch.recommendedDesc': 'Keep exploring on HuTube'
    ,'watch.autoplay': 'Autoplay'
    ,'watch.newlyPosted': 'Newly posted'
     ,'watch.noRecommended': 'No recommended videos yet.'
     ,'watch.sourceQuality': 'Source'
     ,'watch.views': '{count} views'
     ,'watch.subscribers': '{count} subscribers'
     ,'watch.subscribe': 'Subscribe'
     ,'watch.subscribed': 'Subscribed'
     ,'watch.cannotSubscribeSelf': 'You cannot subscribe to your own channel.'
     ,'watch.subscribeError': 'Error subscribing to channel.'
     ,'watch.unsubscribeError': 'Error unsubscribing from channel.'
     ,'watch.defaultLanguage': 'Vietnamese'
     ,'watch.videoDescriptionEmpty': 'This video has no description yet.'
     ,'watch.chapterCountLabel': '{count} chapters'
     ,'watch.guestCommentPrompt': 'Sign in to join the conversation about this video.'
     ,'watch.repliesCount': 'View {count} replies'
     ,'watch.showComment': 'Show'
     ,'watch.hideComment': 'Hide'
     ,'watch.repliesEmpty': 'No replies yet.'
     ,'watch.reportDescriptionPrompt': 'Additional details (optional):'
     ,'watch.repliesError': 'Unable to load replies.'
     ,'watch.recommendationViews': '{count} views'
     ,'watch.originalBadge': 'HUTUBE ORIGINAL'

    ,'plans.defaultUploadQuality': '1080p Full HD'
     ,'plans.defaultDownloadQuality': '720p'
     ,'plans.eyebrow': 'Account & plans'

    ,'upload.stepperAria': 'Video upload steps'
    ,'upload.readingVideo': 'Reading video and extracting frames…'
    ,'upload.checkingStorage': 'Checking actual storage…'
    ,'upload.creatingQualities': 'Creating video qualities…'
    ,'upload.uploadingNow': 'Uploading…'
    ,'upload.ready': 'Ready to upload'
    ,'upload.noCategory': 'No category'
    ,'upload.languageVietnamese': 'Vietnamese'
    ,'upload.languageEnglish': 'English (US)'
    ,'upload.languageJapanese': 'Japanese'
    ,'upload.quality4K': '2160p (4K)'
    ,'upload.watching': 'Viewing:'
    ,'upload.addChapterAt': 'Add chapter at position'
    ,'upload.pausePreview': 'Pause'
    ,'upload.playPreview': 'Play preview'
    ,'upload.timelineAria': 'Video timeline'
    ,'upload.timelineHelp': 'Drag the bar to seek. Drag a chapter marker to change its time, or edit it below.'
    ,'upload.chapterNameAria': 'Chapter name'
    ,'upload.chapterStartAria': 'Start time'
    ,'upload.preModeration': 'Pre-moderation'
    ,'upload.preModerationDesc': 'The video will be sent to review before it becomes public on HuTube.'
    ,'upload.commitment': 'I confirm that this video follows the'
    ,'upload.and': 'and'
    ,'upload.noPlaylist': '-- Select a playlist (optional) --'
    ,'upload.untitledCategory': 'Uncategorized'
    ,'upload.previewVideo': 'Select a video to preview it'
    ,'upload.checkApi404': 'The current API does not have this endpoint. Restart the local backend or redeploy the API before uploading.'
    ,'upload.checkApiOffline': 'Unable to connect to the API. Check the backend and CORS, then try again.'
     ,'upload.checkApiError': 'Unable to check the file with the server.'
     ,'upload.noData': 'No data yet'
     ,'upload.storageRemaining': '{value} remaining'
     ,'upload.frameLabel': 'Frame {index}'
     ,'upload.playlistDalat': 'Da Lat travel'
     ,'upload.playlistVietnam': 'Vietnam beauty'
     ,'upload.policyCommitmentDesc': 'I confirm this video follows HuTube\'s {community} and {terms}.'
     ,'upload.commitmentSuffix': 'on HuTube. It contains no hate, violence, sexual content, or copyright infringement.'
     ,'upload.fileTypeError': 'This file format is not supported. Choose MP4, WebM, MOV, or MKV.'
     ,'upload.metadataError': 'Unable to read video metadata. The file may be damaged or unsupported by this browser.'
     ,'upload.selectFileError': 'Select a video file first.'
     ,'upload.selectVideoError': 'Select a video file.'
     ,'upload.preparingWait': 'Reading the video and creating thumbnails. Please wait.'
     ,'upload.storageWait': 'Checking storage. Please wait.'
     ,'upload.preflightUnavailable': 'The file could not be checked with the server.'
     ,'upload.titleRequired': 'Enter a video title.'
     ,'upload.policyRequired': 'Confirm that the video follows the HuTube Community Guidelines before submitting it.'
     ,'upload.uploadInProgress': 'Another video is already uploading.'
     ,'upload.chaptersInvalid': 'Chapters need titles, increasing timestamps, and must stay within the video.'
     ,'upload.previewError': 'This browser cannot play the file preview.'
     ,'upload.chapterFieldsInvalid': 'Enter a valid title and timestamp within the video.'
     ,'upload.duplicateChapterTime': 'Each timestamp can be used by only one chapter.'
     ,'upload.customThumbnail': 'Custom'
     ,'upload.videoThumbnailAlt': 'Video thumbnail'
     ,'upload.categoryFallback': 'Uncategorized'
     ,'upload.publicCommitmentAlert': '* Confirm the commitment for a public video before submitting it.'
     ,'upload.publishPublic': 'Submit & publish'
     ,'upload.saveVideo': 'Save video'

    ,'studio.roleOwner': 'Owner'
    ,'studio.roleManager': 'Manager'
    ,'studio.roleEditor': 'Editor'
    ,'studio.roleModerator': 'Moderator'
    ,'studio.roleViewer': 'Viewer'
    ,'studio.roleContributor': 'Contributor'
    ,'studio.manageChannel': 'Channel you manage'
     ,'studio.collaboration': 'Collaborate'
     ,'studio.collaborationTitle': 'Collaborate on a channel'
     ,'studio.defaultCreator': 'Wandering Sunshine'
     ,'studio.commentManagedReason': 'Channel owner managed this comment'
     ,'studio.defaultUsername': '@creator'
     ,'ui.studioNavigation': 'HuTube Creator Studio navigation'
     ,'channel.membersList': 'Channel member list'
     ,'channel.handleMinCreate': 'The handle must be at least 3 characters.'
     ,'channel.handleMaxCreate': 'The handle can be at most 50 characters.'
     ,'channel.handleNoSpaces': 'The handle cannot contain spaces.'
     ,'channel.handleChars': 'Use unaccented letters, numbers, _, -, and . only.'
     ,'channel.handleChecking': 'Checking availability…'
     ,'channel.handleCheckError': 'Unable to check the handle right now.'
     ,'channel.handleAvailable': 'This handle is available.'
     ,'channel.handleTaken': 'This handle is already in use.'
     ,'explore.error': 'Unable to load explore videos.'
     ,'library.notRated': 'Not rated'
     ,'plans.inviteSent': 'Plan invitation sent.'
     ,'plans.revokeSent': 'Invitation revoked.'
     ,'plans.members': '{count} members'
     ,'plans.shareText': 'HuTube {name} plan'
     ,'plans.qualityUpload': 'Upload {quality}'
     ,'plans.qualityDownload': 'Download {quality}'
     ,'plans.subscribeErrorFallback': 'Unable to subscribe to this plan ({status}).'
     ,'auth.about': 'About HuTube'
     ,'auth.accountLink': 'HuTube — account page'
     ,'auth.slideStoryAlt': 'A creator telling their story'
     ,'auth.slideWorldAlt': 'Explore the world through video'
     ,'auth.slideInspireAlt': 'An inspiring community'
     ,'auth.layoutTagline': 'A more open, creative, kinder video platform.'
     ,'auth.layoutFooter': '© 2026 HuTube LLC. All rights reserved.'
     ,'auth.deviceMobile': 'Mobile'
     ,'auth.deviceDesktop': 'Desktop'
     ,'auth.requestError': 'Unable to complete the request. Please try again.'
     ,'auth.invalidCredentials': 'The email or password is incorrect.'
     ,'auth.emailNotVerified': 'Verify your email before signing in.'
     ,'auth.accountSuspended': 'This account is temporarily suspended.'
     ,'auth.accountBanned': 'This account has been banned.'
     ,'auth.adminAccessDenied': 'This account does not have admin access or it has been disabled.'
     ,'auth.adminDisabled': 'Admin access for this account has been disabled.'
     ,'auth.emailExists': 'This email is already in use.'
     ,'auth.usernameExists': 'This username is already in use.'
     ,'auth.invalidToken': 'This link is invalid or expired. Request a new link.'
     ,'auth.tokenExpired': 'This link has expired. Request a new link.'
     ,'auth.googleNotConfigured': 'Google Sign-In is not configured.'
     ,'auth.invalidGoogleToken': 'Unable to verify the Google account. Please try again.'
     ,'auth.googleConflict': 'This email is already linked to another Google account.'
     ,'auth.serverUnavailable': 'The server is unavailable. Check your connection and try again.'
     ,'auth.tooManyRequests': 'Too many attempts. Wait a moment and try again.'
     ,'auth.accessDenied': 'This account cannot access the resource or has been disabled.'
     ,'account.apiChecking': 'Checking connection…'
     ,'account.apiConnected': 'Connected'
     ,'account.apiUnavailable': 'The server is unavailable'
     ,'account.locationVietnam': 'Vietnam'
     ,'account.passwordChanged': 'Your password was changed.'
     ,'channel.reportSuccess': 'Thanks for your report. We will review it under HuTube Community Guidelines.'
     ,'notification.channelInviteToast': 'You have an invitation to join channel{channel}.'
     ,'studio.accessibleChannelsError': 'Unable to load channels you can access.'
     ,'studio.channelDataError': 'Unable to load Studio data for this channel.'
     ,'upload.serverNoVideo': 'The server did not return video information after upload.'
     ,'upload.uploadError': 'Unable to upload the video. Check the local API and try again.'
     ,'ui.statusPublished': 'Published'
     ,'ui.statusDraft': 'Draft'
     ,'ui.statusProcessing': 'Processing'
     ,'ui.statusScheduled': 'Scheduled'
     ,'ui.statusPending': 'Pending'
     ,'ui.statusRejected': 'Rejected'
     ,'title.login': 'Sign in · HuTube'
     ,'title.register': 'Create account · HuTube'
     ,'title.verifyEmail': 'Verify email · HuTube'
     ,'title.forgotPassword': 'Forgot password · HuTube'
     ,'title.resetPassword': 'Reset password · HuTube'
     ,'title.home': 'Home · HuTube'
     ,'title.explore': 'Explore · HuTube'
     ,'title.watch': 'Watch video · HuTube'
     ,'title.terms': 'Terms of Service · HuTube'
     ,'title.privacy': 'Privacy Policy · HuTube'
     ,'title.guidelines': 'Community Guidelines · HuTube'
     ,'title.policies': 'Policy Center · HuTube'
     ,'title.plans': 'Plans · HuTube'
     ,'title.planInvite': 'Accept plan invitation · HuTube'
     ,'title.planDetail': 'Plan details · HuTube'
     ,'title.account': 'Settings · HuTube'
     ,'title.history': 'Watch history · HuTube'
     ,'title.liked': 'Liked videos · HuTube'
     ,'title.channelCreate': 'Create channel · HuTube'
     ,'title.channel': 'Channel · HuTube'
     ,'title.channelCustomize': 'Customize channel · HuTube'
     ,'title.studioSetup': 'Channel setup · Studio'
     ,'title.studioOverview': 'Creator Studio · HuTube'
     ,'title.studioContent': 'Channel content · Studio'
     ,'title.studioUpload': 'Upload video · Studio'
     ,'title.studioAnalytics': 'Analytics · Studio'
     ,'title.studioComments': 'Comments · Studio'
     ,'title.studioSubtitles': 'Subtitles · Studio'
     ,'title.studioSettings': 'Settings · Studio'
     ,'title.studioInvitations': 'Collaborations · Studio'
  }
};

@Injectable({
  providedIn: 'root'
})
export class I18nService {
  private readonly STORAGE_KEY = 'hutube_lang';
  readonly currentLang = signal<AppLang>('vi');
  readonly lang = this.currentLang;

  constructor() {
    const saved = localStorage.getItem(this.STORAGE_KEY) as AppLang | null;
    if (saved === 'vi' || saved === 'en') {
      this.currentLang.set(saved);
    }
  }

  setLang(lang: AppLang): void {
    if (lang === 'vi' || lang === 'en') {
      this.currentLang.set(lang);
      localStorage.setItem(this.STORAGE_KEY, lang);
    }
  }

  formatNumber(value: number | string | null | undefined, options: Intl.NumberFormatOptions = {}): string {
    const numericValue = Number(value ?? 0);
    return new Intl.NumberFormat(this.currentLang() === 'vi' ? 'vi-VN' : 'en-US', options)
      .format(Number.isFinite(numericValue) ? numericValue : 0);
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
