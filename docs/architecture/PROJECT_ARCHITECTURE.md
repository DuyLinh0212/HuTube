# HuTube - Kiến trúc Project dự kiến

> Phiên bản: 0.2  
> Trạng thái: Draft  
> Kiến trúc tổng thể: Modular Monolith + Clean Architecture rút gọn  
> Backend dùng chung cho 3 nền tảng: Mobile User, User Web và Admin Web

---

# 1. Mục tiêu kiến trúc

HuTube được thiết kế theo các mục tiêu:

- Dễ đọc source code.
- Dễ bảo trì.
- Dễ mở rộng.
- Dễ thay đổi công nghệ bên ngoài.
- Không tạo quá nhiều project hoặc thư mục nhỏ gây khó theo dõi.
- Tách biệt rõ nghiệp vụ và hạ tầng kỹ thuật.
- Hạn chế phụ thuộc chéo giữa các module.
- Dùng chung một Backend cho nhiều client.
- Có tài liệu kỹ thuật đi cùng source code.
- Có khả năng mở rộng hoặc tách service trong tương lai nếu thật sự cần.
- Đảm bảo logic phân quyền nằm ở Backend, không phụ thuộc việc client là Web hay Mobile.

Kiến trúc lựa chọn:

```text
Modular Monolith
+
Clean Architecture rút gọn
```

Không sử dụng Microservices ở giai đoạn đầu.

---

# 2. Tổng quan hệ thống

HuTube có 3 nền tảng phía Client:

1. Mobile App dành cho User.
2. User Web dành cho User.
3. Admin Web dành cho Admin/Moderator.

Cả 3 client cùng sử dụng một Backend ASP.NET Core.

```text
                    ┌─────────────────────┐
                    │   Mobile User App   │
                    └──────────┬──────────┘
                               │
                               │
┌─────────────────────┐        │        ┌─────────────────────┐
│      User Web       │────────┼────────│      Admin Web      │
│      Angular        │        │        │      Angular        │
└─────────────────────┘        │        └─────────────────────┘
                               │
                     REST API / SignalR
                               │
                               ▼
                  ┌─────────────────────────┐
                  │   ASP.NET Core Backend  │
                  │                         │
                  │   Modular Monolith      │
                  │   Clean Architecture    │
                  └────────────┬────────────┘
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
             ▼                 ▼                 ▼
        SQL Server       Cloudflare R2      External Services
                                            ├── Google
                                            ├── VNPay
                                            ├── MoMo
                                            └── ZaloPay
```

---

# 3. Cấu trúc Repository

```text
HuTube/
│
├── backend/
│   ├── HuTube.sln
│   │
│   ├── src/
│   │   ├── HuTube.Domain/
│   │   ├── HuTube.Application/
│   │   ├── HuTube.Infrastructure/
│   │   └── HuTube.Api/
│   │
│   └── tests/
│       ├── HuTube.UnitTests/
│       └── HuTube.IntegrationTests/
│
├── frontend/
│   ├── user-web/
│   └── admin-web/
│
├── mobile/
│   └── user-app/
│
├── database/
│   ├── migrations/
│   ├── updates/
│   ├── seed/
│   └── scripts/
│
├── docs/
│   ├── architecture/
│   ├── api/
│   ├── features/
│   ├── conventions/
│   ├── operations/
│   ├── database/
│   └── decisions/
│
├── scripts/
├── .github/
│   └── workflows/
│
├── docker-compose.yml
├── .env.example
├── .gitignore
├── CHANGELOG.md
└── README.md
```

---

# 4. Nguyên tắc Backend dùng chung

HuTube chỉ sử dụng một Backend API chính cho cả 3 client.

```text
Mobile User ──┐
              │
User Web ─────┼────> HuTube.Api
              │
Admin Web ────┘
```

Không tạo riêng:

```text
HuTube.MobileApi
HuTube.UserWebApi
HuTube.AdminApi
```

nếu nghiệp vụ vẫn dùng chung.

Mục tiêu:

- Tránh lặp business logic.
- Tránh lặp validation.
- Tránh lặp authentication.
- Tránh lặp repository.
- Dễ bảo trì.
- Dễ kiểm soát permission.
- Giảm số lượng service cần deploy.

---

# 5. Backend Architecture

Backend sử dụng 4 project chính.

```text
backend/
│
├── HuTube.sln
│
├── src/
│   ├── HuTube.Domain/
│   ├── HuTube.Application/
│   ├── HuTube.Infrastructure/
│   └── HuTube.Api/
│
└── tests/
    ├── HuTube.UnitTests/
    └── HuTube.IntegrationTests/
```

Không tạo thêm quá nhiều project như:

```text
HuTube.Core
HuTube.Common
HuTube.SharedKernel
HuTube.Persistence
HuTube.Repository
HuTube.Services
HuTube.Contracts
HuTube.Web
```

trừ khi sau này thật sự có nhu cầu rõ ràng.

---

# 6. Dependency Rule của Backend

Dependency phải tuân theo:

```text
HuTube.Domain
      ↑
HuTube.Application
      ↑
HuTube.Api

HuTube.Infrastructure
      ├──> HuTube.Application
      └──> HuTube.Domain
```

Quy định:

- `HuTube.Domain` không reference project nào khác.
- `HuTube.Application` chỉ reference `HuTube.Domain`.
- `HuTube.Infrastructure` reference `HuTube.Application` và `HuTube.Domain`.
- `HuTube.Api` reference `HuTube.Application` và `HuTube.Infrastructure`.

Domain không được phụ thuộc:

- Entity Framework Core.
- SQL Server implementation.
- JWT library.
- SignalR.
- Cloudflare R2 SDK.
- Google SDK.
- VNPay SDK.
- MoMo SDK.
- ZaloPay SDK.
- HTTP.
- Controller.
- Frontend.
- Mobile framework.

---

# 7. HuTube.Domain

Chứa nghiệp vụ cốt lõi.

```text
HuTube.Domain/
├── Users/
├── Channels/
├── Videos/
├── Comments/
├── Playlists/
├── Subscriptions/
├── Notifications/
├── Moderation/
├── Payments/
├── Recommendations/
└── Common/
```

Ví dụ module Videos:

```text
Videos/
├── Video.cs
├── VideoStatus.cs
├── VideoVisibility.cs
└── IVideoRepository.cs
```

Không chia thêm `Entities/`, `Enums/`, `Repositories/`, `ValueObjects/` nếu mỗi thư mục chỉ có vài file.

Chỉ tách thêm khi module đủ lớn và việc tách giúp dễ đọc hơn.

---

# 8. HuTube.Application

Chứa Use Case và logic điều phối.

```text
HuTube.Application/
├── Auth/
├── Users/
├── Channels/
├── Videos/
├── Comments/
├── Playlists/
├── Subscriptions/
├── Notifications/
├── Moderation/
├── Payments/
├── Recommendations/
└── Common/
```

Ví dụ:

```text
Videos/
├── VideoService.cs
├── VideoDto.cs
├── CreateVideoRequest.cs
├── UpdateVideoRequest.cs
└── VideoMapping.cs
```

Application chịu trách nhiệm:

- Điều phối Use Case.
- Gọi Repository abstraction.
- Gọi Storage abstraction.
- Gọi Payment abstraction.
- Gọi Notification abstraction.
- Áp dụng business rule cần thiết.
- Trả kết quả cho API layer.

Không bắt buộc sử dụng MediatR.

Ưu tiên Application Service dễ đọc.

Chỉ bổ sung MediatR/CQRS nếu hệ thống sau này đủ phức tạp để mang lại lợi ích rõ ràng.

---

# 9. HuTube.Infrastructure

Chứa implementation kỹ thuật.

```text
HuTube.Infrastructure/
├── Persistence/
├── Authentication/
├── Storage/
├── Notifications/
├── Payments/
├── ExternalAuth/
├── Recommendation/
└── DependencyInjection.cs
```

## Persistence

```text
Persistence/
├── HuTubeDbContext.cs
├── Configurations/
├── Repositories/
└── Migrations/
```

## Storage

```text
Storage/
├── CloudflareR2Storage.cs
└── CloudflareR2Options.cs
```

## Payments

```text
Payments/
├── VNPay/
├── MoMo/
└── ZaloPay/
```

## External Authentication

```text
ExternalAuth/
└── Google/
```

## Realtime Notification

```text
Notifications/
└── SignalR/
```

---

# 10. HuTube.Api

API layer phải mỏng.

```text
HuTube.Api/
├── Controllers/
├── Middleware/
├── Filters/
├── Extensions/
├── Authorization/
├── Hubs/
├── Program.cs
├── appsettings.json
└── appsettings.Development.json
```

Controller chỉ chịu trách nhiệm:

```text
HTTP Request
    ↓
Authentication
    ↓
Authorization
    ↓
Validation
    ↓
Application Service
    ↓
HTTP Response
```

Không viết business logic dài trong Controller.

---

# 11. API dùng chung cho Web và Mobile

User Web và Mobile User phải ưu tiên dùng chung endpoint nếu cùng một Use Case.

Ví dụ:

```text
GET    /api/v1/videos
GET    /api/v1/videos/{videoId}
POST   /api/v1/videos/{videoId}/comments
POST   /api/v1/videos/{videoId}/reactions
POST   /api/v1/reports
GET    /api/v1/me/notifications
```

Không tạo:

```text
/api/mobile/videos
/api/web/videos
```

chỉ vì client khác nhau.

Chỉ tạo endpoint khác khi Use Case hoặc yêu cầu dữ liệu thật sự khác.

---

# 12. API dành cho Admin

Admin vẫn dùng cùng Backend nhưng endpoint quản trị có namespace riêng.

Ví dụ:

```text
GET    /api/v1/admin/users
GET    /api/v1/admin/reports
GET    /api/v1/admin/appeals
PATCH  /api/v1/admin/reports/{reportId}/resolve
PATCH  /api/v1/admin/appeals/{appealId}/approve
PATCH  /api/v1/admin/users/{userId}/status
GET    /api/v1/admin/payments
```

Việc endpoint nằm dưới `/admin` không đủ để bảo mật.

Backend vẫn phải kiểm tra Authentication, Role, Permission và Policy.

---

# 13. Authentication Architecture

Cả 3 client xác thực thông qua Backend.

```text
Mobile User ──┐
              │
User Web ─────┼──> Authentication API
              │
Admin Web ────┘
```

Backend phát hành:

```text
JWT Access Token
+
Refresh Token
```

JWT là token chính của HuTube.

---

# 14. Google Login Architecture

Google Login áp dụng cho User.

```text
User Web / Mobile
        ↓
Google Login
        ↓
Google Identity Token
        ↓
HuTube Backend
        ↓
Verify Google Token
        ↓
Find/Create HuTube User
        ↓
Generate HuTube JWT
        ↓
Return Access Token + Refresh Token
```

Google Token không được sử dụng trực tiếp như token truy cập toàn bộ API HuTube.

---

# 15. Authorization Architecture

Backend là nơi quyết định quyền.

Không tin:

- Role từ Frontend.
- Permission từ Frontend.
- Route Admin Web.
- Việc UI đã ẩn nút.
- Client tự khai báo mình là Admin.

Ví dụ permission:

```text
video.upload
video.manage_own
video.manage_all
report.create
report.review
appeal.create
appeal.review
user.manage
payment.manage
admin.dashboard.view
```

Ưu tiên Policy-based Authorization.

---

# 16. SignalR Architecture

SignalR dùng chung cho cả 3 client nếu cần realtime.

```text
                     SignalR
                        │
          ┌─────────────┼─────────────┐
          │             │             │
          ▼             ▼             ▼
      Mobile User    User Web      Admin Web
```

Application định nghĩa:

```text
IRealtimeNotificationService
```

Infrastructure triển khai:

```text
SignalRNotificationService
```

API chứa:

```text
NotificationHub
```

Có thể tổ chức group:

```text
user:{userId}
admin
moderator
```

---

# 17. Storage Architecture

Cloudflare R2 dùng để lưu:

- Video.
- Thumbnail.
- Avatar.
- Channel Banner.
- Media file lớn.

Application định nghĩa:

```text
IObjectStorage
```

Infrastructure triển khai:

```text
CloudflareR2Storage
```

SQL Server chỉ lưu metadata cần thiết, không lưu binary video trực tiếp.

---

# 18. Payment Architecture

Các Payment Provider:

```text
VNPay
MoMo
ZaloPay
```

Application định nghĩa:

```text
IPaymentGateway
```

Infrastructure triển khai:

```text
VNPayPaymentGateway
MoMoPaymentGateway
ZaloPayPaymentGateway
```

Không viết logic riêng của từng Payment Provider trực tiếp trong Controller.

---

# 19. Database Architecture

Database chính:

```text
SQL Server
```

Backend truy cập qua:

```text
Entity Framework Core
```

Luồng:

```text
Client
  ↓
ASP.NET Core API
  ↓
Application
  ↓
Repository Interface
  ↓
Infrastructure Repository
  ↓
EF Core
  ↓
SQL Server
```

Frontend và Mobile không được truy cập Database trực tiếp.

---

# 20. Frontend Architecture tổng thể

HuTube có hai Web Application:

```text
frontend/
├── user-web/
└── admin-web/
```

Hai ứng dụng build và deploy độc lập.

Không gom toàn bộ User + Admin vào một Angular application chỉ bằng route và role nếu chưa có lý do rõ ràng.

---

# 21. User Web Architecture

```text
frontend/user-web/
└── src/
    ├── app/
    │   ├── core/
    │   ├── shared/
    │   ├── features/
    │   ├── layouts/
    │   ├── app.config.ts
    │   └── app.routes.ts
    │
    ├── assets/
    ├── environments/
    └── styles/
```

Các feature dự kiến:

```text
features/
├── auth/
├── home/
├── video/
├── channel/
├── search/
├── comment/
├── playlist/
├── subscription/
├── notification/
├── report/
├── payment/
├── recommendation/
└── profile/
```

---

# 22. Admin Web Architecture

```text
frontend/admin-web/
└── src/
    ├── app/
    │   ├── core/
    │   ├── shared/
    │   ├── features/
    │   ├── layouts/
    │   ├── app.config.ts
    │   └── app.routes.ts
    │
    ├── assets/
    ├── environments/
    └── styles/
```

Các feature dự kiến:

```text
features/
├── auth/
├── dashboard/
├── users/
├── videos/
├── channels/
├── reports/
├── appeals/
├── payments/
├── categories/
├── permissions/
└── system/
```

Admin Web chỉ chứa chức năng quản trị.

---

# 23. Angular Workspace dùng chung

Do User Web và Admin Web đều dùng Angular, team có thể cân nhắc một Angular Workspace chung.

Ví dụ:

```text
frontend/
├── projects/
│   ├── user-web/
│   └── admin-web/
├── angular.json
└── package.json
```

Hoặc:

```text
frontend/
├── apps/
│   ├── user-web/
│   └── admin-web/
└── libs/
    ├── api-models/
    ├── ui/
    └── utilities/
```

Chỉ share thành phần thực sự dùng chung.

Nếu Workspace chung làm cấu trúc phức tạp hơn lợi ích nhận được thì giữ hai Angular project độc lập.

---

# 24. Mobile Architecture

Mobile App dành cho User.

```text
mobile/
└── user-app/
```

Mobile framework chưa được quyết định trong tài liệu này.

Mobile phải:

- Gọi cùng Backend API với User Web nếu Use Case giống nhau.
- Dùng JWT của HuTube.
- Có thể kết nối SignalR nếu cần notification realtime.
- Không truy cập SQL Server trực tiếp.
- Không chứa secret của Backend.
- Không tin dữ liệu phân quyền phía client.

---

# 25. Không duplicate business logic theo Client

Không triển khai:

```text
MobileVideoService
WebVideoService
AdminVideoService
```

ở Backend nếu cùng một nghiệp vụ.

Ưu tiên:

```text
VideoService
```

Nếu Admin có Use Case riêng thì tạo theo nghiệp vụ:

```text
VideoService
VideoModerationService
```

thay vì đặt theo tên client.

---

# 26. Testing Architecture

```text
backend/tests/
├── HuTube.UnitTests/
└── HuTube.IntegrationTests/
```

Unit Test tập trung business logic.

Integration Test tập trung API, EF Core, SQL Server, Authentication, Authorization, Middleware, Payment callback, SignalR và Storage integration quan trọng.

---

# 27. Database Directory

```text
database/
├── migrations/
├── updates/
├── seed/
└── scripts/
```

Không sửa Production Database mà không có migration hoặc SQL update script lưu trong repository.

---

# 28. Documentation Architecture

```text
docs/
├── architecture/
├── api/
├── features/
├── conventions/
├── operations/
├── database/
└── decisions/
```

Các quyết định lớn nên dùng ADR.

Ví dụ:

```text
ADR-001-modular-monolith.md
ADR-002-clean-architecture.md
ADR-003-sql-server.md
ADR-004-cloudflare-r2.md
ADR-005-angular.md
ADR-006-multiple-client-architecture.md
ADR-007-payment-gateway-abstraction.md
```

---

# 29. Security Boundary

Backend là Security Boundary chính.

```text
Mobile
User Web
Admin Web
    ↓
Không đáng tin tuyệt đối
    ↓
Backend
    ↓
Authentication
Authorization
Validation
Business Rules
```

Client chỉ hỗ trợ UX.

Backend phải kiểm tra lại toàn bộ quyền.

---

# 30. Secret Management

Không lưu secret trong Angular, Mobile source, Git repository hoặc Markdown.

Secret chỉ lưu trong:

- Environment Variables.
- Secret Manager.
- CI/CD Secrets.
- Hosting Environment.

Ví dụ:

```text
DATABASE_CONNECTION_STRING
JWT_SECRET_KEY
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
VNPAY_SECRET_KEY
MOMO_SECRET_KEY
ZALOPAY_KEY1
ZALOPAY_KEY2
```

---

# 31. Deployment Model dự kiến

Deploy độc lập:

```text
HuTube Backend
User Web
Admin Web
Mobile Build
```

Cả ba client cùng truy cập Backend.

```text
User Web ──────┐
               │
Admin Web ─────┼──> Backend API
               │
Mobile App ────┘
```

Backend kết nối SQL Server, Cloudflare R2 và các External Service.

---

# 32. Cấu trúc cuối cùng đề xuất

```text
HuTube/
│
├── backend/
│   ├── HuTube.sln
│   ├── src/
│   │   ├── HuTube.Domain/
│   │   ├── HuTube.Application/
│   │   ├── HuTube.Infrastructure/
│   │   └── HuTube.Api/
│   └── tests/
│       ├── HuTube.UnitTests/
│       └── HuTube.IntegrationTests/
│
├── frontend/
│   ├── user-web/
│   └── admin-web/
│
├── mobile/
│   └── user-app/
│
├── database/
│   ├── migrations/
│   ├── updates/
│   ├── seed/
│   └── scripts/
│
├── docs/
│   ├── architecture/
│   ├── api/
│   ├── features/
│   ├── conventions/
│   ├── operations/
│   ├── database/
│   └── decisions/
│
├── scripts/
├── .github/
│   └── workflows/
│
├── docker-compose.yml
├── .env.example
├── .gitignore
├── CHANGELOG.md
└── README.md
```

---

# 33. Nguyên tắc kiến trúc cần giữ

1. Một Backend dùng chung cho cả 3 client.
2. Không duplicate business logic theo Mobile/Web/Admin.
3. Admin Web tách khỏi User Web.
4. User Web và Mobile dùng chung API nếu Use Case giống nhau.
5. Backend là nơi quyết định Authentication và Authorization.
6. Domain không phụ thuộc framework hoặc SDK bên ngoài.
7. Infrastructure chịu trách nhiệm tích hợp SQL Server, R2, SignalR, Google và Payment Provider.
8. Application sử dụng abstraction để dễ thay implementation.
9. Không tạo quá nhiều folder hoặc interface nếu chưa cần.
10. Không chuyển Microservices khi chưa có nhu cầu thực tế.
11. Database thay đổi phải có migration hoặc update script.
12. Kiến trúc quan trọng phải được ghi bằng ADR.
13. Ưu tiên code dễ đọc và dễ lần theo luồng xử lý.

