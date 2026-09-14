import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { RuntimeConfig } from '../../core/runtime-config';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

export interface PublicPolicy {
  policyId: string;
  code: string;
  name: string;
  group: 'content' | 'legal';
  content: string;
  severity: string;
  version: string;
  status: string;
  effectiveAt: string;
}

export interface PolicyRuleItem {
  code: string;
  name: string;
  summary: string;
  severity?: 'critical' | 'high' | 'medium' | 'info';
  rules: string[];
  rulesEn?: string[];
  exceptions?: string[];
  exceptionsEn?: string[];
}

export type PolicyTab = 'guidelines' | 'privacy' | 'terms' | 'monetization' | 'enforcement';

@Component({
  selector: 'app-public-policy-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './public-policy-page.html',
  styleUrl: './public-policy-page.scss'
})
export class PublicPolicyPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly policies = signal<PublicPolicy[]>([]);
  readonly activeTab = signal<PolicyTab>('guidelines');
  readonly searchQuery = signal<string>('');

  readonly tabs: { key: PolicyTab; labelKey: string }[] = [
    { key: 'guidelines', labelKey: 'policies.guidelines' },
    { key: 'privacy', labelKey: 'policies.privacy' },
    { key: 'terms', labelKey: 'policies.terms' },
    { key: 'monetization', labelKey: 'policies.monetization' },
    { key: 'enforcement', labelKey: 'policies.enforcement' }
  ];

  readonly currentTabInfo = computed(() => {
    const tab = this.activeTab();
    return {
      title: this.i18n.t(`policies.tab.${tab}.title`),
      description: this.i18n.t(`policies.tab.${tab}.desc`)
    };
  });

  // Interactive Tools state
  readonly adPersonalization = signal<boolean>(true);
  readonly actionToast = signal<string | null>(null);

  // Community Guidelines List (16 items)
  readonly guidelinesList: PolicyRuleItem[] = [
    {
      code: 'CHILD_SAFETY',
      name: 'An toàn cho trẻ em',
      summary: 'Tuyệt đối không khoan nhượng với hành vi bóc lột, lạm dụng tình dục hoặc đưa trẻ em vào tình huống nguy hiểm.',
      severity: 'critical',
      rules: [
        'Nghiêm cấm hình ảnh hoặc video bóc lột, lạm dụng tình dục trẻ em (CSAM/CSAE).',
        'Nghiêm cấm lôi kéo trẻ em vào các hành vi khiêu dâm hoặc các thử thách đe dọa thể xác và tâm lý.',
        'Cấm khai thác hình ảnh trẻ em để câu tương tác hoặc kích động hành vi bắt nạt trẻ vị thành niên.'
      ],
      rulesEn: [
        'Strictly prohibits child sexual abuse material or exploitation (CSAM/CSAE).',
        'Prohibits engaging minors in sexualized acts, predatory grooming, or physically/psychologically dangerous stunts.',
        'Prohibits exploiting minors for engagement or inciting cyberbullying against minors.'
      ],
      exceptions: ['Nội dung tin tức điều tra tội phạm được cơ quan chức năng công bố chính thống.'],
      exceptionsEn: ['Official public interest investigative journalism and law enforcement disclosures.']
    },
    {
      code: 'SEXUAL_CONTENT',
      name: 'Nội dung tình dục và ảnh khỏa thân',
      summary: 'Nghiêm cấm nội dung khiêu dâm, hành vi tình dục rõ ràng hoặc khỏa thân không phù hợp với không gian chung.',
      severity: 'critical',
      rules: [
        'Cấm video có nội dung khiêu dâm, kích dục hoặc mô tả chi tiết quan hệ tình dục thực tế.',
        'Cấm phô bày bộ phận sinh dục hoặc các nội dung thỏa mãn dục tính.',
        'Cấm dịch vụ môi giới mại dâm hoặc khiêu dâm thương mại.'
      ],
      rulesEn: [
        'Prohibits pornography, sexually explicit acts, or graphic depictions of sexual encounters.',
        'Prohibits displaying exposed genitalia or content intended for sexual gratification.',
        'Prohibits commercial sex solicitation or escort service promotions.'
      ],
      exceptions: ['Nghệ thuật điêu khắc, hội họa cổ điển, hoặc nội dung giáo dục sức khỏe giới tính có ngữ cảnh phù hợp.'],
      exceptionsEn: ['Classical sculpture, fine art painting, or sex education content in a suitable educational context.']
    },
    {
      code: 'SELF_HARM',
      name: 'Nội dung tự làm hại bản thân và tự tử',
      summary: 'Cấm khuyến khích, hướng dẫn hoặc cổ xúy các hành vi tự tử và tự gây thương tích.',
      severity: 'critical',
      rules: [
        'Cấm video hướng dẫn chi tiết cách tự sát hoặc tự làm đau bản thân.',
        'Cấm các thử thách nguy hiểm khuyến khích tự hại hoặc rối loạn ăn uống cực đoan.',
        'Cấm lãng mạn hóa hoặc tôn vinh hành vi tự gây tổn thương.'
      ],
      rulesEn: [
        'Prohibits instructional or encouraging guides on suicide or deliberate self-injury.',
        'Prohibits dangerous challenges promoting self-harm or extreme eating disorders.',
        'Prohibits romanticizing, normalizing, or glorifying self-destructive behaviors.'
      ],
      exceptions: ['Nội dung chia sẻ câu chuyện vượt qua khủng hoảng và cung cấp thông tin đường dây hotline hỗ trợ tâm lý.'],
      exceptionsEn: ['Personal recovery journeys, crisis support hotlines, and mental health awareness resources.']
    },
    {
      code: 'VIOLENCE',
      name: 'Nội dung bạo lực hoặc đẫm máu',
      summary: 'Cấm video bạo lực đồ họa tàn bạo, khủng bố, hoặc kích động bạo lực trong thế giới thực.',
      severity: 'critical',
      rules: [
        'Cấm cảnh giết người, tra tấn, tai nạn đẫm máu có hình ảnh rùng rợn không có che mờ.',
        'Cấm kích động tấn công bạo lực hoặc tôn vinh các tổ chức khủng bố, tội phạm.',
        'Cấm truyền phát trực tiếp các vụ xả súng hoặc hành vi vi phạm pháp luật nghiêm trọng.'
      ],
      rulesEn: [
        'Prohibits graphic depictions of murder, torture, or unblurred bloody accidents.',
        'Prohibits inciting violent attacks or glorifying terrorist and extremist criminal groups.',
        'Prohibits live-streaming mass casualty attacks or violent crimes.'
      ],
      exceptions: ['Tư liệu tài liệu lịch sử, phóng sự chiến trường của cơ quan báo chí chính thống có cảnh báo đầu video.'],
      exceptionsEn: ['Documentary history archives and battlefield news dispatches by authorized journalistic outlets with upfront warning labels.']
    },
    {
      code: 'ANIMAL_ABUSE',
      name: 'Ngược đãi động vật',
      summary: 'Nghiêm cấm hành hạ, đánh đập, giết hại dã man động vật hoặc dàn dựng giải cứu giả.',
      severity: 'high',
      rules: [
        'Cấm video quay cảnh đánh đập, tra tấn hoặc kích động chọi thú dã man.',
        'Cấm dàn dựng đưa động vật vào tình thế nguy hiểm rồi tạo video cứu hộ để câu view.'
      ],
      rulesEn: [
        'Prohibits cruelty, torture, intentional beating, or staging brutal animal fights.',
        'Prohibits deliberately endangering animals to produce staged rescue videos for clicks and views.'
      ]
    },
    {
      code: 'HATE_SPEECH',
      name: 'Nội dung kích động thù địch',
      summary: 'Cấm tấn công, hạ nhục cá nhân hoặc tập thể dựa trên các đặc tính được pháp luật bảo vệ.',
      severity: 'high',
      rules: [
        'Cấm ngôn từ thù hận, miệt thị dựa trên chủng tộc, tôn giáo, giới tính, khuynh hướng tính dục hoặc khuyết tật.',
        'Cấm coi một nhóm người là hạ đẳng hoặc truyền bá thuyết âm mưu bài xích cực đoan.'
      ],
      rulesEn: [
        'Prohibits hate speech, slurs, and dehumanizing attacks based on race, religion, gender, sexual orientation, or disability.',
        'Prohibits claiming a protected group is subhuman or propagating hateful exclusionist conspiracies.'
      ]
    },
    {
      code: 'HARASSMENT',
      name: 'Hành vi quấy rối và đe dọa bắt nạt',
      summary: 'Cấm đe dọa, nhục mạ cá nhân, bắt nạt trực tuyến và kích động bầy đàn tấn công.',
      severity: 'high',
      rules: [
        'Cấm đe dọa vũ lực, sỉ nhục ngoại hình lặp đi lặp lại nhằm quấy nhiễu đời tư.',
        'Cấm chia sẻ thông tin nhằm mục đích trù dập hoặc triệt hạ nhân phẩm người khác.'
      ],
      rulesEn: [
        'Prohibits threats of violence, repeated physical appearance shaming, and malicious harassment.',
        'Prohibits publishing private details to incite dogpiling or destroy someone\'s reputation.'
      ]
    },
    {
      code: 'DANGEROUS_ACTIVITIES',
      name: 'Hoạt động nguy hiểm hoặc có hại',
      summary: 'Cấm các thử thách liều lĩnh có nguy cơ gây thương tật nặng hoặc tử vong.',
      severity: 'high',
      rules: [
        'Cấm hướng dẫn chế tạo thuốc nổ, vũ khí hoặc chất độc.',
        'Cấm các thử thách viral nguy hiểm, lái xe bịt mắt hoặc hành vi mạo hiểm không có trang bị bảo hộ an toàn.'
      ],
      rulesEn: [
        'Prohibits instructional guides on manufacturing explosives, firearms, or chemical poisons.',
        'Prohibits dangerous viral stunts, blindfolded driving, or extreme hazards without proper safety equipment.'
      ]
    },
    {
      code: 'SPAM_SCAM',
      name: 'Nội dung rác và hành vi lừa đảo',
      summary: 'Bảo vệ khán giả khỏi bình luận rác hàng loạt, lừa đảo tài chính và các mô hình đa cấp phi pháp.',
      severity: 'high',
      rules: [
        'Cấm đăng tải lặp đi lặp lại cùng một video lên nhiều kênh để chiếm dụng đề xuất.',
        'Cấm mô hình lừa đảo Ponzi, đầu tư tiền ảo không rõ nguồn gốc hoặc cam kết lợi nhuận phi thực tế.',
        'Cấm tặng quà giả mạo nhằm chiếm đoạt tài khoản hoặc mã OTP ngân hàng.'
      ],
      rulesEn: [
        'Prohibits repetitively uploading identical videos across multiple channels to game recommendation feeds.',
        'Prohibits Ponzi schemes, fraudulent crypto investment clubs, or deceptive get-rich-quick guarantees.',
        'Prohibits phishing giveaways aimed at stealing user accounts or banking OTP codes.'
      ]
    },
    {
      code: 'IMPERSONATION',
      name: 'Hành vi mạo danh',
      summary: 'Cấm tạo kênh giả mạo người nổi tiếng, thương hiệu hoặc cơ quan chức năng để gây nhầm lẫn.',
      severity: 'high',
      rules: [
        'Cấm sao chép tên kênh, avatar, banner để đánh lừa người xem.',
        'Kênh fanmade hoặc parody bắt buộc phải ghi rõ tính chất này trong tiêu đề và phần giới thiệu kênh.'
      ],
      rulesEn: [
        'Prohibits copying channel names, avatars, and branding banners to mislead viewers.',
        'Fanmade and parody channels must explicitly state their satirical nature in titles and channel descriptions.'
      ]
    },
    {
      code: 'FAKE_ENGAGEMENT',
      name: 'Tương tác ảo và thao túng nền tảng',
      summary: 'Cấm sử dụng bot, dịch vụ cày view hoặc trao đổi sub/like nhân tạo.',
      severity: 'high',
      rules: [
        'HuTube tự động phát hiện và trừ bỏ các lượt xem, thích, đăng ký có nguồn gốc từ botfarm.',
        'Tài khoản mua bán tương tác ảo bị tước quyền đề xuất và có thể bị đóng băng kênh vĩnh viễn.'
      ],
      rulesEn: [
        'HuTube automatically identifies and purges views, likes, and subscribers originating from clickfarms or bots.',
        'Accounts purchasing artificial engagement will be stripped of recommendation rights and face permanent freezes.'
      ]
    },
    {
      code: 'MISLEADING_METADATA',
      name: 'Metadata sai lệch và clickbait lừa dối',
      summary: 'Tiêu đề, ảnh thu nhỏ (thumbnail) và mô tả phải phản ánh đúng nội dung thực tế của video.',
      severity: 'medium',
      rules: [
        'Cấm giật tít clickbait trắng trợn hoàn toàn không có trong nội dung video.',
        'Cấm gắn thẻ hashtag không liên quan để đánh lừa công cụ tìm kiếm.'
      ],
      rulesEn: [
        'Prohibits blatant clickbait headlines with zero relation to the actual video content.',
        'Prohibits stuffing unrelated tags or hashtags to deceive search ranking algorithms.'
      ]
    },
    {
      code: 'EXTERNAL_LINKS',
      name: 'Liên kết ngoài độc hại',
      summary: 'Cấm đính kèm đường link dẫn tới trang web lừa đảo, mã độc hoặc nội dung cấm.',
      severity: 'critical',
      rules: [
        'Mọi link trong mô tả hoặc bình luận được quét tự động qua hệ thống HuTube Safe Browsing.',
        'Vi phạm dẫn link phishing dẫn tới xử lý gậy phạt ngay lập tức.'
      ],
      rulesEn: [
        'All links in video descriptions and pinned comments are scanned via HuTube Safe Browsing.',
        'Posting phishing or malware links results in immediate strikes and link privileges revocation.'
      ]
    },
    {
      code: 'MISINFORMATION_SYNTHETIC',
      name: 'Thông tin sai lệch và nội dung AI / Deepfake',
      summary: 'Ngăn chặn tin giả nguy hại và kiểm soát tính minh bạch của nội dung do trí tuệ nhân tạo tạo ra.',
      severity: 'high',
      rules: [
        'Cấm bịa đặt thông tin về thảm họa tự nhiên, an ninh quốc gia hoặc thông tin y tế sai lệch trái khuyến nghị Bộ Y tế.',
        'Tác giả phải bật cờ "Nội dung AI" khi tải lên video mô phỏng người thật hoặc sự kiện lịch sử.',
        'Cấm Deepfake nhằm mục đích bôi nhọ, tống tiền hoặc xuyên tạc phát ngôn của người khác.'
      ],
      rulesEn: [
        'Prohibits fabricating claims regarding natural disasters, national security emergencies, or public health falsehoods.',
        'Creators must turn on the "AI-generated" disclosure badge when publishing synthetic media of real people or events.',
        'Prohibits malicious deepfakes used for defamation, extortion, or fabricating public statements.'
      ]
    },
    {
      code: 'REGULATED_GOODS',
      name: 'Hàng hóa và dịch vụ bị kiểm soát đặc biệt',
      summary: 'Tuân thủ quy định pháp luật về hàng cấm, vũ khí, chất ma túy và dịch vụ cờ bạc.',
      severity: 'critical',
      rules: [
        'Cấm bán ngà voi, động vật quý hiếm, tiền giả, giấy tờ giả.',
        'Cấm mua bán, hướng dẫn lắp ráp hoặc chế tạo súng, đạn, vật liệu nổ.',
        'Cấm quảng bá dịch vụ cá cược trực tuyến, casino online hoặc chèn logo nhà cái cá độ vào video.'
      ],
      rulesEn: [
        'Prohibits illicit sales of ivory, endangered wildlife, counterfeit currency, and fake identity papers.',
        'Prohibits selling, modifying, or assembling firearms, ammunition, or bomb components.',
        'Prohibits promoting unlicensed online gambling, casinos, or embedding betting sponsor watermarks.'
      ]
    },
    {
      code: 'CONTENT_SURFACES',
      name: 'Phạm vi áp dụng trên toàn bộ nền tảng',
      summary: 'Quy tắc cộng đồng áp dụng đồng đều và nhất quán trên tất cả điểm chạm của HuTube.',
      severity: 'info',
      rules: [
        'Video dài và video ngắn HuTube Shorts.',
        'Hình thu nhỏ (Thumbnail) và banner đại diện kênh.',
        'Tiêu đề video, mô tả và thẻ hashtag.',
        'Bình luận dưới video và trò chuyện trực tiếp (Live Chat).',
        'Danh sách phát (Playlists) công khai.',
        'Tên kênh, Handle (@tenkenh) và ảnh đại diện (Avatar).'
      ],
      rulesEn: [
        'Long-form videos and HuTube Shorts vertical clips.',
        'Thumbnails, channel art banners, and avatar icons.',
        'Video titles, descriptions, and hashtags.',
        'Comments sections and Live Chat messages.',
        'Public and unlisted playlists.',
        'Channel names, unique handles (@channelhandle), and creator bios.'
      ]
    }
  ];

  // Privacy Policies List (5 items)
  readonly privacyList: PolicyRuleItem[] = [
    {
      code: 'DOXXING_PRIVACY',
      name: 'Chống công khai dữ liệu cá nhân (Doxxing)',
      summary: 'Tuyệt đối cấm phát tán thông tin riêng tư của người khác nhằm mục đích quấy rối.',
      severity: 'critical',
      rules: [
        'Cấm công khai địa chỉ nhà riêng, số điện thoại cá nhân, biển số xe.',
        'Cấm đăng tải tin nhắn riêng tư hoặc hình ảnh chụp lén mà không có sự đồng ý của đối tượng.'
      ],
      rulesEn: [
        'Prohibits revealing private residential addresses, personal phone numbers, or vehicle license plates.',
        'Prohibits posting private chat logs or clandestine recordings without the subject\'s express consent.'
      ]
    },
    {
      code: 'PERSONAL_DOCUMENTS',
      name: 'Bảo vệ giấy tờ định danh và dữ liệu nhạy cảm',
      summary: 'Không hiển thị số CCCD, hộ chiếu, thông tin tài khoản ngân hàng trong video.',
      severity: 'high',
      rules: [
        'Tác giả phải che mờ (blur) thông tin định danh nhạy cảm trước khi xuất bản.',
        'Người bị lộ thông tin có thể gửi yêu cầu gỡ bỏ khẩn cấp tới đội ngũ quản trị.'
      ],
      rulesEn: [
        'Creators must blur sensitive identity credentials prior to publishing.',
        'Individuals whose documents are exposed may file an emergency takedown request to our moderation team.'
      ]
    },
    {
      code: 'NON_CONSENSUAL',
      name: 'Nội dung không có sự đồng thuận',
      summary: 'Nghiêm cấm phát tán hình ảnh hoặc video nhạy cảm khi chưa được sự đồng ý của người trong cuộc.',
      severity: 'critical',
      rules: [
        'Xóa vĩnh viễn và phối hợp với cơ quan pháp luật đối với các trường hợp phát tán video riêng tư trái phép.'
      ],
      rulesEn: [
        'Immediate permanent removal and referral to law enforcement for non-consensual intimate imagery (NCII).'
      ]
    },
    {
      code: 'MINOR_DATA_PROTECTION',
      name: 'Quyền riêng tư của trẻ em và thanh thiếu niên',
      summary: 'Thiết lập bảo vệ tối đa cho người dùng dưới 16 tuổi theo Nghị định 13/2023/NĐ-CP.',
      severity: 'critical',
      rules: [
        'Mặc định tài khoản dưới 16 tuổi ở chế độ riêng tư, tắt tính năng tải xuống và chặn tin nhắn từ người lạ.',
        'Phụ huynh có quyền yêu cầu gỡ bỏ video có hình ảnh con em mình.'
      ],
      rulesEn: [
        'Accounts of users under 16 are set to private by default with downloads disabled and stranger messages blocked.',
        'Parents and legal guardians retain the right to demand removal of videos depicting their minor children.'
      ]
    },
    {
      code: 'SECURITY_ENCRYPTION',
      name: 'Tiêu chuẩn bảo mật TLS 1.3 và lưu trữ AES-256',
      summary: 'Toàn bộ dữ liệu truyền tải và lưu trữ được bảo vệ theo các chuẩn mã hóa hàng đầu.',
      severity: 'info',
      rules: [
        'Mã hóa đường truyền TLS 1.3 đối với mọi tương tác giữa ứng dụng và máy chủ.',
        'Dữ liệu hồ sơ người dùng lưu trữ tại Data Center tại Việt Nam với chuẩn phần cứng AES-256.',
        'Nhật ký hệ thống được bảo lưu theo đúng quy định của Luật An ninh mạng.'
      ],
      rulesEn: [
        'TLS 1.3 encryption across all network communication between client apps and HuTube servers.',
        'User profile and credential data stored at certified domestic Tier-3 Data Centers with AES-256 hardware encryption.',
        'Audit logs retained strictly in compliance with cybersecurity regulations.'
      ]
    }
  ];

  // Terms of Service List (5 items)
  readonly termsList: PolicyRuleItem[] = [
    {
      code: 'TERMS_ACCEPTANCE',
      name: 'Chấp thuận điều khoản và phạm vi dịch vụ',
      summary: 'Quy định pháp lý ràng buộc khi truy cập và sử dụng dịch vụ trên nền tảng HuTube.',
      severity: 'info',
      rules: [
        'Bằng việc truy cập hoặc sử dụng HuTube, bạn đồng ý tuân thủ toàn bộ Điều khoản dịch vụ này.',
        'HuTube cung cấp nền tảng chia sẻ video trực tuyến tuân thủ pháp luật Việt Nam về công nghệ thông tin.'
      ],
      rulesEn: [
        'By accessing or using HuTube, you agree to be bound by these Terms of Service in full.',
        'HuTube provides video sharing services compliant with applicable information technology laws.'
      ]
    },
    {
      code: 'USER_ACCOUNTS',
      name: 'Quyền và trách nhiệm tài khoản người dùng',
      summary: 'Bảo mật thông tin đăng nhập và chịu trách nhiệm về mọi hoạt động diễn ra dưới tài khoản.',
      severity: 'high',
      rules: [
        'Bạn chịu trách nhiệm bảo mật mật khẩu và thiết lập xác thực 2 lớp.',
        'Cam kết cung cấp thông tin trung thực khi đăng ký, không mạo danh cá nhân hoặc tổ chức khác.'
      ],
      rulesEn: [
        'You are solely responsible for maintaining the confidentiality of your password and enabling 2FA.',
        'You agree to provide accurate registration information and refrain from impersonating other entities.'
      ]
    },
    {
      code: 'COPYRIGHT_UGC',
      name: 'Bản quyền nội dung tải lên và giấy phép cấp cho HuTube',
      summary: 'Bạn giữ quyền sở hữu nội dung do chính mình tạo ra và cấp giấy phép phát sóng cho HuTube.',
      severity: 'high',
      rules: [
        'Tác giả giữ toàn bộ quyền sở hữu trí tuệ đối với video do mình sáng tạo.',
        'Khi tải lên công khai, bạn cấp cho HuTube quyền truyền phát và hiển thị video trên hệ sinh thái dịch vụ.',
        'Tuyệt đối không đăng tải tác phẩm của người khác khi chưa có sự cho phép hợp pháp.'
      ],
      rulesEn: [
        'Creators retain full intellectual property rights over their original video uploads.',
        'By uploading publicly, you grant HuTube a worldwide license to host, transcode, and broadcast your content.',
        'Uploading third-party copyrighted works without legal authorization is strictly prohibited.'
      ]
    },
    {
      code: 'SERVICE_TERMINATION',
      name: 'Chấm dứt dịch vụ và đóng tài khoản',
      summary: 'Quyền ngưng cung cấp dịch vụ đối với các hành vi vi phạm nghiêm trọng.',
      severity: 'critical',
      rules: [
        'HuTube có quyền tạm ngưng hoặc khóa vĩnh viễn tài khoản nếu tái phạm Quy tắc cộng đồng hoặc lừa đảo.'
      ],
      rulesEn: [
        'HuTube reserves the right to suspend or terminate accounts in response to repeated strikes or severe legal violations.'
      ]
    },
    {
      code: 'LIABILITY_LIMITATION',
      name: 'Giới hạn trách nhiệm pháp lý',
      summary: 'Phạm vi trách nhiệm pháp lý của HuTube đối với nội dung do người dùng tải lên.',
      severity: 'info',
      rules: [
        'Dịch vụ được cung cấp trên cơ sở nguyên trạng, HuTube không chịu trách nhiệm gián tiếp đối với nội dung bên thứ ba phát tán.'
      ],
      rulesEn: [
        'Services are provided on an "as-is" basis; HuTube assumes no indirect liability for third-party user-generated uploads.'
      ]
    }
  ];

  // Monetization List (3 items)
  readonly monetizationList: PolicyRuleItem[] = [
    {
      code: 'PARTNER_ELIGIBILITY',
      name: 'Điều kiện tham gia Chương trình Đối tác HuTube',
      summary: 'Ngưỡng điều kiện để bật tính năng kiếm tiền và nhận chia sẻ doanh thu.',
      severity: 'high',
      rules: [
        'Kênh cần đạt đủ số lượng người đăng ký và giờ xem công khai hợp lệ trong 12 tháng gần nhất.',
        'Kênh phải tuân thủ 100% Quy tắc cộng đồng và không có gậy cảnh cáo vi phạm đang còn hiệu lực.',
        'Bắt buộc kích hoạt bảo mật xác minh 2 bước trên tài khoản quản trị kênh.'
      ],
      rulesEn: [
        'Channels must meet minimum subscriber and valid public watch hour thresholds within the preceding 12 months.',
        'Channels must maintain 100% adherence to Community Guidelines and have zero active strikes.',
        'Mandatory two-step verification must be activated on the channel manager account.'
      ]
    },
    {
      code: 'AD_SUITABILITY_GUIDE',
      name: 'Tiêu chuẩn nội dung thân thiện với nhà quảng cáo',
      summary: 'Hệ thống đánh giá tính phù hợp để hiển thị quảng cáo thương hiệu.',
      severity: 'medium',
      rules: [
        'Biểu tượng Xanh (Bật đầy đủ): Nội dung văn minh, phù hợp với hầu hết các thương hiệu quảng cáo.',
        'Biểu tượng Vàng (Hạn chế): Video có ngôn từ thô tục, cảnh người lớn nhẹ hoặc chủ đề gây tranh cãi gay gắt.',
        'Biểu tượng Đỏ (Không quảng cáo): Video vi phạm chính sách, hoàn toàn không được phân phối quảng cáo kiếm tiền.'
      ],
      rulesEn: [
        'Green icon (Full monetization): Brand-safe content suitable for virtually all advertisers.',
        'Yellow icon (Limited ads): Content featuring coarse language, mild adult themes, or sensitive debates.',
        'Red icon (Demonetized): Content violating policy, completely ineligible for advertising revenue.'
      ]
    },
    {
      code: 'REVENUE_PAYOUTS',
      name: 'Chia sẻ doanh thu và nghĩa vụ thuế',
      summary: 'Quy trình quyết toán định kỳ và khấu trừ thuế theo quy định pháp luật Việt Nam.',
      severity: 'info',
      rules: [
        'Doanh thu được quyết toán định kỳ hàng tháng qua tài khoản ngân hàng chính chủ.',
        'HuTube thực hiện khấu trừ và nộp thuế thu nhập cá nhân theo đúng biểu thuế nhà nước ban hành.'
      ],
      rulesEn: [
        'Earnings are disbursed monthly to verified bank accounts matching the verified legal identity.',
        'HuTube withholds and submits personal income taxes in compliance with statutory tax laws.'
      ]
    }
  ];

  // Enforcement & Appeals List (4 items)
  readonly enforcementList: PolicyRuleItem[] = [
    {
      code: 'STRIKES_WARNING',
      name: 'Hệ thống cảnh báo và gậy vi phạm',
      summary: 'Cơ chế xử phạt lũy tiến theo từng bước vi phạm nhằm hỗ trợ nhà sáng tạo sửa sai.',
      severity: 'high',
      rules: [
        'Nhắc nhở (Warning): Lần đầu vi phạm sẽ chỉ nhận thông báo nhắc nhở kèm khóa học nhận thức 15 phút. Nội dung bị gỡ nhưng không bị phạt gậy.',
        'Gậy 1 (Strike 1): Kênh bị tạm ngưng quyền tải video, livestream và đăng bài cộng đồng trong vòng 7 ngày.',
        'Gậy 2 (Strike 2): Tái phạm trong 90 ngày sẽ bị đóng băng toàn bộ hoạt động đăng tải trong 14 ngày.',
        'Gậy 3 (Strike 3 - Chấm dứt): Nhận đủ 3 gậy trong vòng 90 ngày dẫn tới việc khóa vĩnh viễn tài khoản và xóa mọi kênh liên đới.'
      ],
      rulesEn: [
        'Warning: First violation receives an educational warning and a 15-minute policy refresher. Content removed without strike penalty.',
        'Strike 1: Channel privileges to upload videos, livestream, or post community updates are frozen for 7 days.',
        'Strike 2: A second violation within 90 days results in a comprehensive 14-day upload freeze.',
        'Strike 3 (Termination): Receiving 3 strikes within 90 days results in permanent account and channel termination.'
      ]
    },
    {
      code: 'EDSA_EXCEPTIONS',
      name: 'Nguyên tắc xem xét ngoại lệ EDSA',
      summary: 'Xem xét ngữ cảnh đặc biệt đối với nội dung có giá trị công chúng.',
      severity: 'info',
      rules: [
        'Giáo dục (Educational): Phục vụ giảng dạy y khoa, sinh học, an toàn giao thông.',
        'Tài liệu (Documentary): Phóng sự điều tra, ghi nhận lịch sử của cơ quan báo chí có thẩm quyền.',
        'Khoa học (Scientific): Nghiên cứu chuyên ngành được kiểm chứng thực nghiệm.',
        'Nghệ thuật (Artistic): Tác phẩm điện ảnh, hội họa cổ điển mang giá trị thẩm mỹ cao.',
        'Lợi ích công chúng (Public Interest): Tin tức thời sự khẩn cấp cảnh báo cộng đồng trước thảm họa.'
      ],
      rulesEn: [
        'Educational: Medical, biology, public safety, and instructional curriculum.',
        'Documentary: Investigative journalism and historical documentation by verified press authorities.',
        'Scientific: Peer-reviewed experimental and academic demonstrations.',
        'Artistic: Cinematic motion pictures, fine art, and aesthetic creative expression.',
        'Public Interest: Urgent emergency warnings and public safety broadcasts.'
      ]
    },
    {
      code: 'APPEALS_PROCESS',
      name: 'Quy trình khiếu nại minh bạch',
      summary: 'Quyền khiếu nại của tác giả khi cho rằng quyết định xử phạt có sự nhầm lẫn.',
      severity: 'info',
      rules: [
        'Khiếu nại nội dung: Tác giả có thể nộp đơn khiếu nại trong vòng 30 ngày kể từ khi video bị gỡ.',
        'Chuyên viên độc lập con người sẽ xem xét lại toàn bộ ngữ cảnh video và phản hồi trong 48 giờ.',
        'Nếu khiếu nại thành công, video sẽ được khôi phục ngay lập tức và gậy cảnh cáo được xóa bỏ.'
      ],
      rulesEn: [
        'Content Appeals: Creators may submit an appeal within 30 days of content removal or disciplinary action.',
        'Independent human specialists re-examine the full context of the video and respond within 48 hours.',
        'If the appeal is upheld, the content is reinstated immediately and any strike is expunged.'
      ]
    },
    {
      code: 'MODERATION_INFRASTRUCTURE',
      name: 'Hạ tầng kiểm duyệt kết hợp AI và chuyên viên con người',
      summary: 'Hệ sinh thái kiểm duyệt đa tầng bảo vệ người dùng của HuTube.',
      severity: 'info',
      rules: [
        'Mô hình AI đa phương thức quét tự động hình ảnh, âm thanh và văn bản tại thời điểm video được tải lên.',
        'Đội ngũ kiểm duyệt viên bản địa thẩm định các trường hợp phức tạp về văn hóa và ngôn ngữ địa phương.',
        'Toàn bộ quyết định kiểm duyệt đều được lưu vết trong hệ thống kiểm toán minh bạch.'
      ],
      rulesEn: [
        'Multimodal AI models automatically analyze visual, audio, and textual streams at ingestion time.',
        'Native human moderation teams adjudicate complex cultural, political, and localized linguistic nuances.',
        'All moderation determinations are logged in an immutable, auditable compliance ledger.'
      ]
    }
  ];

  getItemName(item: PolicyRuleItem): string {
    const key = `policy.${item.code}.name`;
    const val = this.i18n.t(key);
    return val !== key ? val : item.name;
  }

  getItemSummary(item: PolicyRuleItem): string {
    const key = `policy.${item.code}.content`;
    const val = this.i18n.t(key);
    return val !== key ? val : item.summary;
  }

  getItemRules(item: PolicyRuleItem): string[] {
    if (this.i18n.currentLang() === 'en' && item.rulesEn && item.rulesEn.length > 0) {
      return item.rulesEn;
    }
    return item.rules;
  }

  getItemExceptions(item: PolicyRuleItem): string[] {
    if (this.i18n.currentLang() === 'en' && item.exceptionsEn && item.exceptionsEn.length > 0) {
      return item.exceptionsEn;
    }
    return item.exceptions || [];
  }

  getSeverityLabel(severity?: string): string {
    switch (severity) {
      case 'critical':
        return this.i18n.t('policies.sev.critical');
      case 'high':
        return this.i18n.t('policies.sev.high');
      case 'medium':
        return this.i18n.t('policies.sev.medium');
      default:
        return this.i18n.t('policies.sev.info');
    }
  }

  readonly itemCountText = computed(() => this.i18n.t('policies.itemCount', { count: '' + this.activeList().length }));

  readonly activeList = computed(() => {
    const tab = this.activeTab();
    let list: PolicyRuleItem[] = [];

    if (tab === 'guidelines') list = this.guidelinesList;
    else if (tab === 'privacy') list = this.privacyList;
    else if (tab === 'terms') list = this.termsList;
    else if (tab === 'monetization') list = this.monetizationList;
    else if (tab === 'enforcement') list = this.enforcementList;
    else list = this.guidelinesList;

    const q = this.searchQuery().trim().toLowerCase();
    if (!q) return list;

    return list.filter(item => {
      const name = this.getItemName(item).toLowerCase();
      const summary = this.getItemSummary(item).toLowerCase();
      const rules = this.getItemRules(item).some(r => r.toLowerCase().includes(q));
      return name.includes(q) || summary.includes(q) || rules || item.code.toLowerCase().includes(q);
    });
  });

  ngOnInit(): void {
    // 1. Check path
    this.route.url.subscribe(segments => {
      const path = segments[0]?.path || '';
      if (path === 'terms') {
        this.activeTab.set('terms');
      } else if (path === 'privacy') {
        this.activeTab.set('privacy');
      } else if (path === 'guidelines') {
        this.activeTab.set('guidelines');
      }
    });

    // 2. Check query param ?tab=...
    this.route.queryParams.subscribe(params => {
      const tabParam = params['tab'] as PolicyTab | undefined;
      if (tabParam && ['guidelines', 'privacy', 'terms', 'monetization', 'enforcement'].includes(tabParam)) {
        this.activeTab.set(tabParam);
      }
    });

    this.loadBackendPolicies();
  }

  loadBackendPolicies(): void {
    this.loading.set(true);
    this.http.get<PublicPolicy[]>(`${this.config.apiBaseUrl}/policies`).subscribe({
      next: (data) => {
        if (data && data.length > 0) {
          this.policies.set(data);
        }
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
      }
    });
  }

  setTab(tab: PolicyTab): void {
    this.activeTab.set(tab);
    this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab },
      queryParamsHandling: 'merge'
    });
    window.scrollTo({ top: 140, behavior: 'smooth' });
  }

  printDocument(): void {
    window.print();
    this.showToast(this.i18n.t('policies.printToast'));
  }

  downloadPdf(): void {
    window.print();
    this.showToast(this.i18n.t('policies.pdfToast'));
  }

  requestDataExport(): void {
    this.showToast(this.i18n.t('policies.tools.exportSuccess'));
  }

  resetAlgorithm(): void {
    if (confirm(this.i18n.t('policies.tools.resetConfirm'))) {
      this.showToast(this.i18n.t('policies.tools.resetSuccess'));
    }
  }

  toggleAdPersonalization(): void {
    this.adPersonalization.update(v => !v);
    const status = this.adPersonalization()
      ? this.i18n.t('policies.tools.adsStatusOn')
      : this.i18n.t('policies.tools.adsStatusOff');
    this.showToast(this.i18n.t('policies.tools.adsChanged', { status }));
  }

  private showToast(msg: string): void {
    this.actionToast.set(msg);
    setTimeout(() => {
      if (this.actionToast() === msg) {
        this.actionToast.set(null);
      }
    }, 6000);
  }
}
