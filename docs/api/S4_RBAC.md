# RBAC Admin API — S4-06

Base local: `http://localhost:5080/api/v1`. Tất cả endpoint dưới đây yêu cầu access token hợp lệ của một tài khoản quản trị. Backend là nguồn quyết định quyền; việc Admin Web ẩn menu hoặc nút chỉ là trải nghiệm người dùng.

## Permission

| Method/route | Permission | Mục đích |
| --- | --- | --- |
| `GET /admin/me` | Active admin access | Phiên admin hiện tại, role và permission thực có |
| `GET /admin/permissions` | `role.view` | Danh mục permission active |
| `GET /admin/roles` | `role.view` | Danh sách role và permission đã gán |
| `POST /admin/roles` | `role.edit` | Tạo custom role |
| `PUT /admin/roles/{roleId}` | `role.edit` | Cập nhật tên, mô tả và permission của role |

Thiếu token trả `401`. Tài khoản không phải admin, bị vô hiệu hóa hoặc không có permission trả `403` theo error contract chung.

## Role response

```json
{
  "roleId": "guid",
  "code": "moderator",
  "name": "Moderator",
  "description": "Kiểm duyệt nội dung",
  "permissions": ["dashboard.view", "moderation.review"]
}
```

## Tạo role

`POST /admin/roles` nhận:

```json
{
  "code": "content_reviewer",
  "name": "Content reviewer",
  "description": "Duyệt nội dung trước khi phát hành",
  "permissionCodes": ["dashboard.view", "moderation.view_queue", "moderation.review"],
  "reason": "Bổ sung nhóm quyền cho đội kiểm duyệt"
}
```

Trả `201 Created` và role mới. `code` gồm 3–48 ký tự chữ thường, số hoặc `_`; phải duy nhất. `name` dài 2–80 ký tự, `description` tối đa 500 ký tự và `reason` dài 3–300 ký tự. Không thể tạo `user`, `admin` hoặc `super_admin` qua endpoint này.

## Cập nhật role

`PUT /admin/roles/{roleId}` nhận:

```json
{
  "name": "Content reviewer",
  "description": "Duyệt nội dung trước khi phát hành",
  "permissionCodes": ["dashboard.view", "moderation.view_queue", "moderation.review"],
  "reason": "Điều chỉnh quyền theo phân công mới"
}
```

Trả `200 OK` với role sau khi cập nhật. Không thể sửa role `user`; role hệ thống `admin` và `super_admin` chỉ do `super_admin` sửa. Ngoài `super_admin`, người thao tác chỉ được gán những permission mà chính họ đang có — ngăn tự nâng quyền qua API.

Mỗi lần tạo hoặc cập nhật tạo audit event `rbac.role_created` hoặc `rbac.role_updated`, kèm actor, lý do, role và snapshot quyền trước/sau. Mã permission lạ hoặc không active trả `400 INVALID_PERMISSION`; code role trùng trả `409 ROLE_CODE_EXISTS`.
