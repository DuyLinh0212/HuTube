# HuTube Design System Specification & Token Guidelines

> **Tài liệu quy chuẩn thiết kế thương hiệu, bảng màu, kích thước layout và bộ nhận diện thương hiệu HuTube.**
> Phiên bản: 2.0 (Cập nhật ngày 06/09/2026)
> Mục đích: Lưu trữ toàn bộ màu sắc, typography, kích thước showcase và 3 phương án logo mới chống vi phạm bản quyền YouTube.

---

## 1. Bảng Màu Hệ Thống (Color Palette & Semantic Tokens)

### 1.1. Màu Thương Hiệu Chủ Đạo (Primary Brand Colors)

| Tên Token | Mã Hex | RGB | Phân Loại & Mục Đích Sử Dụng | Chú Thích Chi Tiết |
| :--- | :--- | :--- | :--- | :--- |
| `--primary` | `#FF2B66` | `rgb(255, 43, 102)` | **Brand Primary (Coral Rose)** | Màu nhận diện cốt lõi của HuTube. Nổi bật, trẻ trung, dùng cho CTA chính, logo mark, highlight từ khóa, link active. |
| `--primary-hover` | `#E61952` | `rgb(230, 25, 82)` | **Brand Primary Hover / Active** | Dùng khi di chuột (hover) vào button chính hoặc khi trạng thái pressed/active. |
| `--primary-light` | `#FF4D80` | `rgb(255, 77, 128)` | **Brand Primary Light** | Điểm bắt đầu của gradient, viền focus ring, viền thẻ nổi bật. |
| `--primary-soft` | `rgba(255, 43, 102, 0.08)` | `rgba(255, 43, 102, 0.08)` | **Brand Tint / Surface Soft** | Nền cho icon box tròn/bo góc, badge tính năng (`.feature-icon-box`), tag danh mục. |
| `--primary-glow` | `rgba(255, 43, 102, 0.32)` | `rgba(255, 43, 102, 0.32)` | **Drop Shadow Glow** | Đổ bóng cho nút CTA chính và thẻ tilted card tạo hiệu ứng 3D nổi bật. |

---

### 1.2. Dải Gradient Chủ Đạo (Brand Gradients)

| Tên Gradient | Cấu Hình CSS | Mục Đích Sử Dụng |
| :--- | :--- | :--- |
| `--primary-gradient` | `linear-gradient(135deg, #FF3B69 0%, #FF2B66 50%, #E61952 100%)` | Nút bấm chính (Submit button), Badge trạng thái active, nền icon ứng dụng. |
| `--hero-bg-mesh` | `radial-gradient(circle at 5% 10%, rgba(255,182,193,0.35) 0%, transparent 45%), radial-gradient(circle at 95% 85%, rgba(255,182,193,0.25) 0%, transparent 45%)` | Nền trang tổng thể (Page Background), tạo ánh sáng hồng ấm áp, sang trọng mà không chói. |
| `--logo-c1-gradient` | `linear-gradient(135deg, #FF2B66 0%, #7C3AED 100%)` | Dải màu cho **Logo Concept 1 (The Dynamic H-Play)** kết hợp giữa Coral và Royal Violet. |
| `--logo-c2-gradient` | `linear-gradient(135deg, #FF2B66 0%, #FF6B35 60%, #FFA800 100%)` | Dải màu cho **Logo Concept 2 (The Creative Ribbon)** tông hoàng hôn ấm áp. |
| `--logo-c3-gradient` | `linear-gradient(135deg, #FF2B66 0%, #7C3AED 50%, #06B6D4 100%)` | Dải màu cho **Logo Concept 3 (The Prism Aperture)** phong cách điện ảnh đa sắc. |

---

### 1.3. Màu Nền & Thẻ Giao Diện (Surfaces & Backgrounds)

| Tên Token | Mã Hex | Chú Thích |
| :--- | :--- | :--- |
| `--page-bg` | `#FAF8F7` | Nền trang web tổng thể. Tông màu cát ấm/kem nhạt (warm off-white), tạo cảm giác dễ chịu hơn màu trắng tinh `#FFFFFF`. |
| `--card-bg` | `#FFFFFF` | Nền thẻ form đăng ký/đăng nhập và nền menu điều hướng. |
| `--card-border` | `#E5E7EB` | Viền mỏng 1px - 1.5px cho input field, social buttons, separator lines. |
| `--card-hover` | `#F9FAFB` | Nền khi hover vào social button (Google/Apple) hoặc item trong danh sách. |

---

### 1.4. Màu Văn Bản & Hệ Trung Tính (Typography & Neutral Shades)

| Tên Token | Mã Hex | Phân Loại & Ứng Dụng |
| :--- | :--- | :--- |
| `--text-dark` | `#111827` | **Headline & Primary Text** (Slate 900): Tiêu đề chính, nhãn quan trọng, tên thương hiệu. |
| `--text-body` | `#374151` | **Body Text** (Slate 700): Văn bản bình thường, thông tin nhập liệu, mô tả. |
| `--text-muted` | `#6B7280` | **Subtext & Descriptions** (Slate 500): Mô tả phụ, nhãn nhỏ trên input (`.input-label`). |
| `--text-light` | `#9CA3AF` | **Placeholder & Tracker** (Slate 400): Text gợi ý trong ô input, tracker danh mục (`CREATORS · VIEWERS · COMMUNITY`). |

---

### 1.5. Màu Trạng Thái (Semantic Status Colors)

| Trạng Thái | Mã Hex | Ứng Dụng |
| :--- | :--- | :--- |
| **Success** | `#10B981` | Thông báo đăng ký thành công, xác minh email hoàn tất, tích xanh tài khoản. |
| **Error** | `#EF4444` | Báo lỗi validation mật khẩu, email không hợp lệ, đăng nhập thất bại. |
| **Warning** | `#F59E0B` | Cảnh báo bảo mật, phiên đăng nhập sắp hết hạn. |
| **Info / Link** | `#3B82F6` | Liên kết điều khoản bên thứ ba hoặc hướng dẫn mở rộng. |

---

## 2. Quy Chuẩn Kích Thước Khung Giao Diện (Layout Specifications)

Dựa trên thông số đo lường thực tế từ bản mẫu thiết kế:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ HuTube Header Navigation                                      (h: 60px)      │
├──────────────────────────────────────────────────────┬───────────────────────┤
│  LEFT SHOWCASE FRAME: (w) 898px x (h) 542px          │ RIGHT FORM CARD:      │
│  ┌────────────────────────┬────────────────────────┐ │ (w) 420px - 430px     │
│  │ Info Column (~370px)   │ Showcase Cluster (~480)│ │                       │
│  │ - Tracker & Heading    │ - Tilted Card (300x430)│ │ - Single-line Title   │
│  │ - 3 Feature Pills      │ - 5 Mini Cards(122x68) │ │ - Compact Inputs      │
│  │ - Hand Slogan          │ - 3s Auto Carousel     │ │ - Social Buttons      │
│  │                        │ - Dots + Sub-tagline   │ │ - Non-scroll Desktop  │
│  └────────────────────────┴────────────────────────┘ │                       │
└──────────────────────────────────────────────────────┴───────────────────────┘
```

### 2.1. Khung Showcase Bên Trái (Left Showcase Frame)
- **Kích thước chuẩn**: Chiều rộng `(w) 898px`, Chiều cao tối thiểu `(h) 542px`.
- **Cấu trúc 2 cột con bên trong khung**:
  - **Cột thông tin (Info Column)**:
    - Chiều rộng: `370px` - `380px`.
    - Tiêu đề chính (`.hero-heading`): `font-size: 44px`, `line-height: 1.05`, `font-weight: 800`.
    - 3 Khối tính năng (`.feature-item`): Icon box bo góc `12px`, kích thước `36px x 36px`.
    - Slogan viết tay (`.handwritten-tag`): Font Caveat `28px`, nghiêng `-6deg`.
  - **Cụm thẻ trình diễn (Showcase Cluster)**:
    - Chiều rộng: `~480px`.
    - **Thẻ chính nghiêng 3D (`.main-tilted-card`)**:
      - Kích thước: Rộng `300px`, Cao `430px`.
      - Bo góc: `26px`.
      - Góc nghiêng: `transform: rotate(-6.5deg)`.
      - Cơ chế: **Auto-Carousel tự chuyển slide mỗi 3 giây (3000ms)** kèm hiệu ứng crossfade mượt mà `0.7s`.
    - **Cột 5 thẻ nhỏ (`.mini-cards-stack`)**:
      - Kích thước mỗi thẻ: Rộng `122px`, Cao `68px`.
      - Bo góc: `14px`.
      - Khoảng cách giữa các thẻ: `8px` (5 thẻ x 68px + 4 khe x 8px = `372px`, khớp hoàn hảo với chiều cao thẻ lớn).
      - Chức năng: Hover phóng to nhẹ (`scale(1.08)`), click để chuyển ngay sang slide tương ứng.
    - **Thanh điều hướng chấm (Dots Indicator)**:
      - 3 chấm tương ứng với 3 hero slide.
      - Chấm đang chọn: dạng viên thuốc (pill) rộng `24px`, cao `4px`, màu `#FF2B66`.
      - Dòng chữ chân trang: `"A MORE OPEN, CREATIVE, KINDER INTERNET"`.

### 2.2. Khung Thẻ Form Đăng Ký / Đăng Nhập (Right Auth Card)
- **Chiều rộng**: `420px` - `430px`.
- **Bo góc**: `26px`.
- **Đổ bóng**: `0 20px 45px -12px rgba(255, 43, 102, 0.12), 0 8px 20px -4px rgba(0, 0, 0, 0.03)`.
- **Tối ưu không cuộn trang (No-scroll Desktop)**:
  - Tiêu đề gộp 1 dòng: `Create your HuTube account` (`font-size: 23px`).
  - Ô input tối ưu chiều cao `44px`, khoảng cách `8px - 9px`.
  - Checkbox điều khoản thu gọn gọn gàng: *"I agree to the Terms & Privacy Policy and receive creator updates."*
  - Toàn bộ chiều cao vừa vặn trong màn hình desktop chuẩn (1080p, 1440p, 1366x768).

---

## 3. Danh Mục Hình Ảnh Assets (Asset Dictionary)

Toàn bộ ảnh đã được khởi tạo chuẩn tỉ lệ và lưu đồng bộ tại 3 vị trí:
1. `assets/auth/`
2. `frontend/user-web/public/assets/auth/`
3. `mobile/user-app/assets/auth/`

| Tên File | Kích Thước | Tỉ Lệ | Nội Dung Mô Tả | Vị Trí Sử Dụng |
| :--- | :--- | :--- | :--- | :--- |
| `hero_register.jpg` | 1080x1520 | 2:3 | Nhiếp ảnh gia ngắm hoàng hôn rực rỡ trên thung lũng sương mù | Slide 1 của Main Card: *"Your Story Belongs Here"* |
| `hero_login.jpg` | 1080x1520 | 2:3 | Chàng trai đeo tai nghe ngắm hồ núi hùng vĩ từ vách đá | Slide 2 của Main Card: *"A Bigger World in Every Video"* |
| `hero_community.jpg` | 1080x1520 | 2:3 | Nữ sáng tạo nội dung cầm gimbal quay hoàng hôn thành phố biển | Slide 3 của Main Card: *"Inspire The World Around You"* |
| `card_explore.jpg` | 600x380 | 16:10 | Dãy núi tuyết phản chiếu mặt hồ hoang sơ | Thẻ nhỏ số 1: EXPLORE |
| `card_create.jpg` | 600x380 | 16:10 | Đêm nhạc concert sôi động với ánh sáng tím neon | Thẻ nhỏ số 2: CREATE |
| `card_learn.jpg` | 600x380 | 16:10 | Mèo vằn đáng yêu nhìn thẳng ống kính với ánh mắt tò mò | Thẻ nhỏ số 3: LEARN |
| `card_share.jpg` | 600x380 | 16:10 | Chiếc xe van dã ngoại phong cách vintage trên cung đường đèo | Thẻ nhỏ số 4: SHARE |
| `card_belong.jpg` | 600x380 | 16:10 | Người lữ hành đứng trên đỉnh mây lúc bình minh | Thẻ nhỏ số 5: BELONG |

---

## 4. Sáu Phương Án Thiết Kế Logo HuTube Mới (Tránh Bản Quyền YouTube)

> [!CAUTION]
> **Vấn đề bản quyền**: Logo YouTube sử dụng hình chữ nhật bo tròn màu đỏ `#FF0000` chứa tam giác Play màu trắng. Việc dùng lại hình dạng này sẽ khiến ứng dụng bị từ chối phê duyệt trên Google Play Store / Apple App Store và có nguy cơ bị khiếu nại bản quyền thương hiệu.
>
> Dưới đây là 6 mẫu logo độc quyền đã được thiết kế vector SVG sẵn tại `docs/design/logos/`:

### Phương Án 1: The Dynamic H-Play (Chữ H Công Nghệ & Mũi Tên Động Lực)
- **File vector**: [`docs/design/logos/logo_concept_1.svg`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logos/logo_concept_1.svg)
- **Ý nghĩa & Triết lý**: Chữ **"H"** được tạo bởi 2 cột trụ vững chắc (Creators & Viewers). Cầu nối ở giữa chính là một mũi tên **Play (▶)** vát góc công nghệ với chấm ngọc sáng ở tâm.
- **Màu sắc**: Chuyển sắc từ Coral Rose (`#FF2B66`) sang Royal Violet (`#7C3AED`).
- **Phong cách**: Hiện đại, công nghệ, dứt khoát (Next-Gen style như Linear, Figma).

### Phương Án 2: The Creative Ribbon (Dải Lụa Sáng Tạo Vô Cực)
- **File vector**: [`docs/design/logos/logo_concept_2.svg`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logos/logo_concept_2.svg)
- **Ý nghĩa & Triết lý**: Dải ruy băng Möbius uốn lượn vô cực thành hình chữ H và luồng video tuần hoàn. Nếp gấp tạo nút Play âm bản tinh tế. Tôn vinh *"Good Videos, Better People"*.
- **Màu sắc**: Gradient hoàng hôn ấm áp (`#FF2B66` Coral ➔ `#FF6B35` Cam ➔ `#FFA800` Vàng rực rỡ).
- **Phong cách**: Thân thiện, ấm áp, giàu cảm hứng.

### Phương Án 3: The Prism Aperture (Ống Kính Điện Ảnh Đa Góc Nhìn)
- **File vector**: [`docs/design/logos/logo_concept_3.svg`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logos/logo_concept_3.svg)
- **Ý nghĩa & Triết lý**: Ba lá khẩu độ máy quay (Aperture Iris) mở ra đón ánh sáng: *"A Bigger World in Every Video"*, tâm là kim cương Play tỏa sáng.
- **Màu sắc**: Coral (`#FF2B66`), Deep Violet (`#7C3AED`) và Electric Cyan (`#06B6D4`).
- **Phong cách**: Chuẩn điện ảnh (Cinema-grade), sắc nét, chất lượng 4K.

### Phương Án 4: HyperTube Velocity (Ống Siêu Tốc & Neon Stream)
- **File vector**: [`docs/design/logos/logo_concept_4.svg`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logos/logo_concept_4.svg)
- **Ý nghĩa & Triết lý**: Hai ống trụ năng lượng đa sắc uốn cong 3D trên nền tối. Nút Play tốc độ cao cắt ngang như luồng truyền dữ liệu siêu tốc độ.
- **Màu sắc**: Neon Coral (`#FF1361`) ➔ Neon Cyan (`#00F2FE`) trên nền Dark Slate (`#0F172A`).
- **Phong cách**: Gen Z, gaming, livestreaming, công nghệ tương lai (Futuristic streaming).

### Phương Án 5: Hu-Heart Play (Legacy)
- **File vector lưu trữ**: [`docs/design/logos/logo_concept_5.svg`](logos/logo_concept_5.svg)
- **Thiết kế tinh chỉnh theo phản hồi người dùng**:
  - **Hình khối trái tim (Heart Silhouette)**: Rõ ràng, cân đối tuyệt đối với 2 vòm cánh cong mềm mại và chóp nhọn phía dưới, góc phản quang 3D bóng bẩy.
  - **Nút Play (▶)**: Sắc nét, nổi bật với màu trắng tinh khôi `#FFFFFF`, bóng đổ tương phản cao, căn chỉnh quang học chính xác ở tâm trái tim.
  - **Tên thương hiệu (Wordmark)**: Chữ `Hu` (Slate 900) kết hợp `Tube` (Coral `#FF2B66`) cùng biểu tượng trái tim nhỏ tinh tế ở góc trên.
- **Ý nghĩa & Triết lý**: Hu = Human, Hug & Heart. Tôn vinh tinh thần *"Good Videos, Better People"* và *"A Kinder Internet"*. Nền tảng kết nối con người ấm áp, truyền cảm hứng và an toàn.
- **Màu sắc**: Radiant Coral Rose (`#FF4D80` ➔ `#FF2B66` ➔ `#E61952`) cùng điểm nhấn trắng tinh khiết.
- **Phong cách**: Thân thiện, nhân văn, hiện đại, giàu cảm xúc, khác biệt hoàn toàn với YouTube.

### Phương Án 6: Origami Film 3D (Dải Phim Gấp Không Gian Đa Chiều)
- **File vector**: [`docs/design/logos/logo_concept_6.svg`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logos/logo_concept_6.svg)
- **Ý nghĩa & Triết lý**: Dải phim điện ảnh gấp nếp theo nghệ thuật Origami đa chiều. Nếp gấp chéo tạo thành mũi tên Play với đổ bóng Isometric tinh xảo.
- **Màu sắc**: Deep Crimson (`#BE123C`) ➔ Ruby Rose (`#FF2B66`) ➔ Royal Amethyst (`#7C3AED`).
- **Phong cách**: Sang trọng, Studio chuyên nghiệp, đẳng cấp và trường tồn.

### Logo Chính Thức: HuTube Orbit
- **File mark chính thức**: [`docs/design/brand/hutube-orbit-mark.png`](brand/hutube-orbit-mark.png).
- **Concept do AI tạo**: [`docs/design/brand/hutube-orbit-concept.png`](brand/hutube-orbit-concept.png).
- **Ý nghĩa**: Hai dải quỹ đạo đan quanh chữ **H**, đại diện cho luồng nội dung liên tục giữa người xem và nhà sáng tạo; điểm tròn phía trên là một thành viên trong cộng đồng HuTube.
- **Màu sắc**: Coral Rose (`#FF2B66`) kết hợp Royal Violet (`#7C3AED`) trên nền Deep Plum (`#17111F`) khi dùng làm launcher icon.
- **Nguyên tắc sử dụng**: Mark 3D là logo hiển thị chính trên web, admin và mobile. Wordmark `HuTube` được ghép bằng typography giao diện để luôn sắc nét. Favicon và app icon phải được sinh từ chính mark này.

> [!TIP]
> Bạn có thể mở trực tiếp file [`docs/design/logo-preview.html`](file:///f:/NgDuyLinh/Khoa_Luan_Tot_Nghiep/HuTube/docs/design/logo-preview.html) trên trình duyệt để so sánh trực quan cả 6 logo trên nền sáng/tối và thử nghiệm thanh Menu thực tế!
