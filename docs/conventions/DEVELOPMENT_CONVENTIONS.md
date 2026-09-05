# HuTube - Quy định Coding, Naming & Git

> Phiên bản: 0.1  
> Trạng thái: Draft

## 1. Nguyên tắc chung

- Tên phải thể hiện đúng ý nghĩa.
- Không viết tắt khó hiểu.
- Không dùng tên mơ hồ như `data`, `process`, `manager`, `helper` nếu không thể hiện rõ trách nhiệm.
- Một convention đã chọn phải dùng nhất quán toàn project.
- Ưu tiên code dễ đọc hơn code quá ngắn.

---

# 2. Backend C# Naming

## Class

PascalCase:

```csharp
VideoService
VideoRepository
PaymentService
NotificationHub
```

## Interface

PascalCase + prefix `I`:

```csharp
IVideoRepository
IPaymentGateway
IObjectStorage
IRealtimeNotificationService
```

## Method

PascalCase và bắt đầu bằng động từ:

```csharp
CreateVideoAsync()
GetVideoByIdAsync()
DeleteVideoAsync()
ResolveReportAsync()
ProcessPaymentAsync()
```

Method trả `Task`/`Task<T>` phải có hậu tố:

```text
Async
```

## Property

PascalCase:

```csharp
VideoId
UserId
CreatedAt
UpdatedAt
```

## Private Field

camelCase + `_`:

```csharp
_videoRepository
_dbContext
_logger
```

## Local Variable / Parameter

camelCase:

```csharp
video
currentUser
paymentResult
videoId
```

---

# 3. Backend Method Naming

CRUD:

```text
Create...
Get...
Find...
Search...
Update...
Delete...
Remove...
Add...
```

Nghiệp vụ:

```text
PublishVideoAsync
ApproveAppealAsync
RejectAppealAsync
ResolveReportAsync
SubscribeChannelAsync
CancelSubscriptionAsync
ProcessPaymentAsync
SendNotificationAsync
```

Không dùng:

```text
DoSomething
ProcessData
HandleStuff
Manager
Helper
```

nếu có thể đặt tên cụ thể hơn.

---

# 4. Repository Naming

Interface:

```text
IVideoRepository
IUserRepository
IReportRepository
```

Implementation:

```text
VideoRepository
UserRepository
ReportRepository
```

Không dùng:

```text
VideoDAO
VideoManager
DbHelper
DataUtils
```

---

# 5. DTO Naming

Request:

```text
CreateVideoRequest
UpdateVideoRequest
LoginRequest
CreateReportRequest
```

Response:

```text
VideoResponse
VideoDetailResponse
LoginResponse
PaymentResponse
```

DTO nội bộ:

```text
VideoDto
UserDto
ReportDto
```

---

# 6. Frontend File Naming

Angular filename sử dụng:

```text
kebab-case
```

Đúng:

```text
video-card.component.ts
video-detail.page.ts
video.service.ts
video.model.ts
video.routes.ts
video.guard.ts
auth.interceptor.ts
format-duration.pipe.ts
click-outside.directive.ts
```

Sai:

```text
VideoCard.component.ts
videoCard.component.ts
VideoService.ts
video_service.ts
```

---

# 7. Frontend Class Naming

PascalCase:

```typescript
VideoCardComponent
VideoDetailPage
LoginPage
VideoService
AuthService
```

---

# 8. Angular Selector

Sử dụng kebab-case và prefix project:

```typescript
selector: 'hutube-video-card'
```

Ví dụ:

```text
hutube-video-card
hutube-comment-item
hutube-video-player
```

---

# 9. Frontend Variable Naming

camelCase:

```typescript
videoId
currentUser
selectedCategory
refreshToken
```

Boolean nên bắt đầu bằng:

```text
is
has
can
should
```

Ví dụ:

```typescript
isLoading
isAuthenticated
hasPermission
canDeleteVideo
shouldRefresh
```

---

# 10. Frontend Function Naming

camelCase và phải thể hiện hành động.

Đúng:

```typescript
loadVideos()
getVideoById()
createVideo()
updateVideo()
deleteVideo()
uploadThumbnail()
refreshAccessToken()
openReportDialog()
validateForm()
```

Event Handler:

```typescript
onSubmit()
onClickLike()
onVideoSelected()
onPageChanged()
```

Function trả boolean:

```typescript
isOwner()
hasPermission()
canEdit()
shouldShowButton()
```

Không nên:

```typescript
video()
data()
process()
handle()
doSomething()
```

---

# 11. Observable và Signal

RxJS Observable dùng hậu tố `$`:

```typescript
currentUser$
notifications$
videos$
```

Angular Signal không dùng `$`:

```typescript
currentUser
notifications
videos
```

---

# 12. Frontend Model / Interface

PascalCase:

```typescript
Video
User
CreateVideoRequest
VideoDetailResponse
```

Không bắt buộc prefix `I`.

Ưu tiên:

```typescript
Video
```

thay vì:

```typescript
IVideo
```

---

# 13. API URL Convention

Base:

```text
/api/v1/
```

Resource là danh từ số nhiều:

```text
GET    /api/v1/videos
GET    /api/v1/videos/{videoId}
POST   /api/v1/videos
PATCH  /api/v1/videos/{videoId}
DELETE /api/v1/videos/{videoId}
```

Không dùng:

```text
/api/v1/getVideos
/api/v1/createVideo
/api/v1/deleteVideo
```

Action đặc biệt:

```text
POST /api/v1/videos/{videoId}/publish
POST /api/v1/reports/{reportId}/resolve
POST /api/v1/appeals/{appealId}/approve
```

---

# 14. Error Code Convention

Sử dụng:

```text
UPPER_SNAKE_CASE
```

Ví dụ:

```text
VIDEO_NOT_FOUND
INVALID_REFRESH_TOKEN
PERMISSION_DENIED
PAYMENT_FAILED
REPORT_ALREADY_RESOLVED
```

---

# 15. Branch Naming

Branch chính:

```text
main
develop
```

Không làm việc trực tiếp trên `main`.

Các loại branch:

```text
feature/<short-description>
fix/<short-description>
hotfix/<short-description>
refactor/<short-description>
docs/<short-description>
db/<short-description>
test/<short-description>
ci/<short-description>
```

Quy tắc:

- chữ thường.
- kebab-case.
- không dấu.
- không khoảng trắng.
- tên ngắn và mô tả đúng nội dung.

Đúng:

```text
feature/video-upload
feature/google-login
feature/report-management
feature/vnpay-payment
fix/video-thumbnail-null
fix/refresh-token-expired
refactor/payment-gateway
docs/api-convention
db/add-report-resolution
test/video-service
```

Sai:

```text
feature/VideoUpload
feature/video_upload
new-feature
duylinh
fixbug
abc
```

Nếu dùng Task ID:

```text
feature/hut-123-video-upload
```

---

# 16. Commit Message

Khuyến nghị Conventional Commits.

```text
feat:
fix:
refactor:
docs:
test:
chore:
ci:
perf:
build:
```

HuTube có thể bổ sung:

```text
db:
```

Ví dụ:

```text
feat: add video upload api
fix: handle expired refresh token
refactor: extract payment gateway interface
docs: add api naming convention
test: add video service unit tests
db: add report resolution table
```

---

# 17. Test Naming

Sử dụng:

```text
Method_Condition_ExpectedResult
```

Ví dụ:

```text
CreateVideo_WhenTitleEmpty_ShouldFail
DeleteVideo_WhenUserIsNotOwner_ShouldReturnForbidden
ResolveReport_WhenModeratorAuthorized_ShouldSucceed
ProcessPayment_WhenSignatureInvalid_ShouldFail
```

---

# 18. Security Rules cho Developer

- Không commit `.env`.
- Không commit secret.
- Không log password.
- Không log access token.
- Không log refresh token.
- Không log payment secret.
- Không tin Role/Permission từ Frontend.
- Không bỏ authorization chỉ vì UI đã ẩn nút.
- Validate input ở Backend.
- Verify payment callback signature.
- Verify Google token ở Backend.
- Upload phải kiểm tra MIME type, size và extension.
- SQL phải parameterized hoặc thông qua EF Core.
- Production phải chạy HTTPS.

---

# 19. Quy tắc tổ chức code

- Không đưa business logic vào Controller.
- Không đưa feature-specific code vào `shared`.
- Không tạo `Helper` hoặc `Utils` chung nếu chưa thực sự dùng chung.
- Không tạo abstraction nếu không mang lại lợi ích rõ ràng.
- Không đặt 100 API vào một service frontend.
- Mỗi feature chịu trách nhiệm code thuộc feature đó.
- Nếu file trở nên quá lớn mới tách tiếp.
- Không tách folder chỉ để chứa một file.

