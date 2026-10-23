# Bộ nhớ đệm dữ liệu đọc của Dalitu

Cập nhật ngày 24/10/2026. Mục tiêu là giảm tải dữ liệu khi ra vào Web User, Studio, Web Admin và Mobile. Dữ liệu chính, quyền truy cập, trạng thái phiên, giao dịch và quota vẫn nằm ở PostgreSQL.

## Những phần đã triển khai

- API có `ReadModelCacheFilter` dùng HybridCache và Upstash Redis cho các nhóm DTO đọc được cho phép. L1 tối đa 5 giây; cache phân biệt người dùng, phiên bản dữ liệu và yêu cầu chuẩn hóa. Chỉ những danh mục thực sự công khai mới dùng key public.
- Web User/Admin có query cache trong bộ nhớ, thường 20 giây; danh mục 60 giây; auth/me chỉ là snapshot giao diện 10 giây. Gộp các request đang chạy, sao chép JSON khi trả cho component, giới hạn 160 mục và 256 KiB mỗi payload. Xóa dữ liệu khi logout, mutation và sự kiện realtime liên quan; không lưu response riêng xuống đĩa.
- Mobile có JSON cache và single-flight dùng chung giữa các ApiClient trong ứng dụng, tách theo user/session và endpoint; không lưu token vào key. Clear khi thay tài khoản hoặc dữ liệu thay đổi. Thanh toán, playback và entitlement vẫn đọc trực tiếp.
- Playlist list trả thêm `previewItems` và cover từ video công khai hợp lệ. Truy vấn batch lấy tối đa 4 video khả dụng mỗi playlist; Web/Mobile không cần gọi thêm từng playlist detail để dựng preview. Client giữ nhánh tương thích khi gặp API cũ.
- Explore tra danh sách subscriptions một lần để xác định trạng thái các creator, thay một request cho mỗi creator.
- Studio có `/api/v1/studio/channels/{channelId}/metrics`, trả projection gọn thay nhiều trang VideoResponse đầy đủ. `includeStats=false` dùng cho lựa chọn video liên quan/phụ đề; trang settings không tải toàn bộ video. Quyền đọc kênh được kiểm tra theo cơ chế hiện có.
- Mobile tải các rail Home song song; Library tải tab/page đang chọn; Channel, nội dung và bình luận Studio tải từng trang. Watch ưu tiên player, sau đó mới lấy bình luận và đề xuất; các trang tiếp theo vẫn truy cập được qua nút tải thêm.
- Admin lấy channel counts bằng một endpoint và một query aggregate. Monitoring gom các counter DB thành một SQL round trip và snapshot 15 giây; RAM, probes và ghi nhận chuyển trạng thái vẫn chạy riêng.
- Status và preview ma trận dùng chung snapshot RAM 30 giây, không đưa ma trận lớn vào Redis. Export và train dùng dữ liệu nguồn riêng. Job status là truy vấn trực tiếp theo khóa chính; poll 5 giây, không gửi khi tab ẩn/offline hoặc request trước chưa xong.
- Recommender giữ ranking ID trong RAM 30 giây, tối đa 500 mục theo user, model và exclude IDs; thống kê sử dụng vẫn được ghi. API xác thực và resolve lại dữ liệu, không tin identity do client tự cung cấp.
- Tích hợp tối ưu query Auth/video đang có: một security snapshot thay các lần đọc session/user/role riêng và tránh UPDATE hoạt động thừa trong một phút; thống kê video detail được gom vào một SQL round trip. Quyết định phiên/quyền không được response-cache.

## TTL và phạm vi

| Nhóm | TTL backend | Ghi chú |
|---|---|---|
| Categories, violation reasons, channel roles | 30 phút | Public DTO; phiên bản catalog |
| Policy công khai | 30 giây | Việc quyết định policy hiệu lực vẫn đọc nguồn |
| Plan catalog/detail hiển thị | 60 giây | Không cache my-plan, token lời mời hay checkout |
| Account | 60 giây | User scope; account revision |
| Feed, search, video, channel, playlist, Studio | 30 giây | User scope trừ danh mục public rõ ràng |
| History, liked, downloads metadata | 15 giây | User/library revision |
| Admin list và reference data | 15 giây | Qua kiểm tra quyền trước cache |
| Queue/report/appeal/strike | 5 giây | Snapshot hiển thị; claim/resolve dùng DB thật |
| Matrix status/preview DTO | 30 giây | Full matrix chỉ RAM, không Redis |
| Payment history | 5 giây | Detail/pending status/webhook không cache chung |
| Notifications | 30 giây | User/revision/page/pageSize; tắt L1 |
| Monitoring DB counters | 15 giây | Snapshot riêng, không cache cả phương thức |

DTO chung thêm jitter nhỏ dưới 10%. Endpoint không có trong allowlist, lỗi HTTP, response null, file và payload lớn hơn 256 KiB không được lưu. HTTP response cache không công khai dữ liệu riêng; đây là cache nội bộ API/app.

## Cấu trúc key

Prefix distributed cache hiện có: `dalitu:<environment>:cache:`. Các thành phần trong dấu ngoặc là mẫu, không phải thông tin máy chủ thực.

| Key logic | Giá trị |
|---|---|
| `read:v1:<public-or-user>:<revisionHash>:<requestHash>` | JSON DTO thành công |
| `notifications:v1:<user>:<revision>:<page>:<pageSize>` | Trang inbox, tổng số và unread |
| `operations:counters:v1:<15-second-bucket>` | Snapshot counter DB |
| `recommendation:matrix-preview:v1:<30-second-bucket>` | Chỉ L1 RAM, tắt distributed cache |

Request hash bao gồm method/path/query chuẩn hóa, ngôn ngữ và client/app header; riêng POST `feed/resolve` còn có body truy vấn. Không đưa credential hay access token vào key. Bump phiên bản schema key khi thay đổi hợp đồng DTO không tương thích.

Tùy chọn player và Data Protection giữ namespace riêng. Không `FLUSHDB`, quét/xóa tất cả key hay đặt TTL chung lên key ring. Namespace không cách ly chính sách eviction; khi tăng quy mô cần bảo đảm dung lượng hoặc tách kho key ring bền vững.

## Invalidation theo transaction

Migration `20261024080000_ReadCacheRevisions` bổ sung bảng điều khiển PostgreSQL:

| Cột | Kiểu / vai trò |
|---|---|
| `scope` | Text, khóa chính; tên nhóm hoặc partition user |
| `revision` | UUID không null; token phiên bản |

Các nhóm gồm catalog, content, channels, accounts, playlists, comments, plans, moderation và jobs. Account/library/notifications có thêm partition user. Một token `shared` khởi tạo riêng cho database giúp cách ly các bộ key; token này không bị xoay theo mọi lần xem video.

Trigger thu thập scope bị thay đổi vào trạng thái transaction cục bộ. Deferred trigger ở commit xoay mỗi scope một lần theo thứ tự thống nhất, tránh đảo thứ tự khóa giữa cập nhật một dòng và cập nhật hàng loạt. Rollback cũng rollback revision. Cơ chế này bao phủ SaveChanges, bulk SQL và worker; không phụ thuộc một lệnh DEL Redis thành công sau commit.

API đọc revision hiện hành bằng một truy vấn nhỏ có index trước cache lookup. Request đang đọc phiên bản cũ có thể ghi muộn, nhưng key đó không được chọn ở request sau khi DB đã commit phiên bản mới. Key cũ tự hết TTL; không dùng wildcard delete trong đường request. L1 ở process khác cũng không đọc nhầm key cũ.

Mỗi cache hit vẫn có chi phí xác thực và đọc phiên bản; Admin GET vẫn đi qua audit hiện có. Vì vậy không diễn giải cache hit là không có truy vấn DB. Các endpoint có chi phí đọc nhỏ hoặc cần trạng thái tức thời như job/payment status được giữ trực tiếp.

## Các ranh giới giữ dữ liệu hiện hành

- Auth/session/revocation, quyền Admin/kênh, claim/lease, moderation mutation, payment/webhook, quota và upload preflight không được quyết định từ snapshot UI.
- Không cache playback/download authorization hay dùng URL ký quá hạn. Cache DTO không chứa bytes media/evidence/model.
- Không chạy MVC continuation trong factory dùng chung giữa nhiều request: mỗi action giữ DbContext và cancellation riêng. Cache chỉ nhận DTO đã hoàn tất; client coalesce các lần gọi trùng. Factory nội bộ notification/counters/matrix có phạm vi riêng.
- Không biến lỗi phụ thuộc thành list rỗng có cache. Adapter Redis hiện có timeout 3 giây, cooldown 30 giây và fallback nguồn cho read cache. Thiếu bảng revision trong nâng cấp thì bypass cache, không dùng revision giả.
- Có thể bypass DTO cache bằng `ReadCache__Enabled=false`, query `_refresh` hoặc header `Cache-Control: no-cache`. Các cơ chế player preferences/key ring không bị tắt theo cờ DTO này.

## Triển khai EC2

Không cần thêm giá trị bí mật vào repo. Tận dụng kết nối Upstash đang có và biến môi trường ở máy chủ. Docker Compose có service `migrate`; API chờ migration thành công. Khi nâng cấp nên build và migrate trước khi thay container API:

```sh
git pull --ff-only origin main
sudo docker compose -f docker-compose.ec2.yml build api recommendation
sudo docker compose -f docker-compose.ec2.yml run --rm migrate
sudo docker compose -f docker-compose.ec2.yml up -d --no-build
```

Schema bổ sung tương thích với API cũ; rollback ứng dụng không cần xóa bảng dữ liệu nghiệp vụ. Web cần được triển khai cùng API hỗ trợ metrics; Mobile nhận các thay đổi client sau khi cài APK mới.

## Đánh giá

Build API, build production hai Web, Dart analyze và Ruff là các bước kiểm tra đóng gói. Chưa có benchmark tải thực tế để khẳng định phần trăm tăng tốc hay sức chứa người dùng. Cần theo dõi latency, DB commands, hit/miss, Redis command/memory và độ trễ dữ liệu. Header `X-Data-Cache` hỗ trợ quan sát hit/miss DTO cache chung; không thể dùng nó để suy ra toàn bộ request không chạm DB.

Tham khảo: [Microsoft HybridCache](https://learn.microsoft.com/en-us/aspnet/core/performance/caching/hybrid?view=aspnetcore-10.0), [PostgreSQL CREATE TRIGGER](https://www.postgresql.org/docs/17/sql-createtrigger.html).
