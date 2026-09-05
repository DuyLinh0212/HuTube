# HuTube - Tech Stack

> Phiên bản: 0.1  
> Trạng thái: Draft

## 1. Backend

| Thành phần | Công nghệ |
|---|---|
| Framework | ASP.NET Core (.NET) |
| ORM | Entity Framework Core |
| Testing | xUnit |
| Mocking | NSubstitute hoặc Moq |
| API Documentation | Swagger / OpenAPI |
| Authentication | JWT Access Token + Refresh Token |
| Social Login | Google OAuth 2.0 / Google Identity |
| Realtime | SignalR |

## 2. Frontend

| Thành phần | Công nghệ |
|---|---|
| Framework | Angular |
| HTTP Client | Angular HttpClient |
| Realtime Client | SignalR JavaScript Client |
| Styling | Quyết định sau |
| State Management | Ưu tiên Angular Signal / RxJS; chỉ thêm thư viện ngoài nếu thật sự cần |

## 3. Database

| Thành phần | Công nghệ |
|---|---|
| Database | PostgreSQL |
| ORM | Entity Framework Core |
| Migration | EF Core Migration |
| Manual Update | SQL Script có version |

## 4. Object Storage

| Thành phần | Công nghệ |
|---|---|
| Storage Provider | Cloudflare R2 |
| Mục đích | Video, thumbnail, avatar, banner và các media/file lớn |
| Giao tiếp | S3-compatible API |

Database chỉ lưu metadata cần thiết của file, không lưu binary video trực tiếp.

Ví dụ metadata:

```text
ObjectKey
Bucket
ContentType
FileSize
OriginalFileName
StorageProvider
CreatedAt
```

## 5. Authentication & Authorization

Authentication:

```text
JWT Access Token
+
Refresh Token
```

Đăng nhập bên thứ ba:

```text
Google Login
```

Sau khi Google xác thực thành công, Backend HuTube vẫn phát hành JWT riêng của HuTube.

Authorization nên sử dụng:

```text
Role
+
Permission
+
Policy-based Authorization
```

## 6. Realtime Notification

Sử dụng:

```text
SignalR
```

Dùng cho các chức năng như:

- Thông báo realtime.
- Cập nhật trạng thái xử lý nếu cần.
- Các sự kiện realtime khác trong tương lai.

## 7. Payment

Các Payment Provider dự kiến:

```text
VNPay
MoMo
ZaloPay
```

Backend phải bọc các provider sau một abstraction chung, ví dụ:

```text
IPaymentGateway
```

Các implementation:

```text
VNPayPaymentGateway
MoMoPaymentGateway
ZaloPayPaymentGateway
```

## 8. Development & DevOps

| Thành phần | Công nghệ |
|---|---|
| Version Control | Git |
| Remote Repository | GitHub |
| CI/CD | GitHub Actions |
| Container | Docker |
| Local Multi-service | Docker Compose |
| Documentation | Markdown |
| API Testing | Swagger / Postman hoặc công cụ tương đương |

## 9. Nguyên tắc lựa chọn công nghệ

- Không thêm thư viện chỉ vì phổ biến.
- Ưu tiên thư viện ổn định, có tài liệu tốt và được duy trì.
- Công nghệ bên ngoài phải được bọc abstraction nếu có khả năng thay đổi.
- Không để Domain phụ thuộc framework hoặc SDK bên ngoài.
- Mọi thay đổi Tech Stack quan trọng phải được ghi bằng ADR trong `docs/decisions/`.

