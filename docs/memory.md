# HuTube query performance memory

> Cập nhật: 2026-09-27 (Asia/Bangkok)

## Quyết định đã chốt

- Explore hub dùng một truy vấn aggregate lượt xem theo `video_id`. Kết quả top video theo danh mục lấy bằng `ROW_NUMBER`/window-equivalent trong SQL, còn top 12 toàn hệ thống được dùng chung cho bảng xếp hạng và trending.
- Lịch sử xem dùng cửa sổ 30 ngày. `GET /api/v1/library/history` giữ tham số `page` để phân trang trong cửa sổ và nhận thêm `before`; client giữ cố định `windowEnd` cho mọi trang rồi trừ đúng 30 ngày khi tải cửa sổ kế tiếp.
- Các endpoint tìm kiếm dùng `ILIKE` để PostgreSQL có thể dùng trigram index, thay cho `LOWER(column)` trên toàn bảng.
- Các danh sách video, bình luận, reaction và rating được enrich theo batch bằng aggregate/group query; không gọi một query thống kê cho từng dòng.
- Thống kê rating dùng `AVG/COUNT` trong SQL, không tải toàn bộ điểm về ứng dụng.
- Thay tag video tải các tag hiện có một lần và thêm liên kết trong cùng unit of work.
- Feed cá nhân hóa chỉ gửi tối đa 5.000 video đã xem gần nhất cho model; catalogue loại video đã xem bằng `NOT EXISTS` trên database để không tải toàn bộ lịch sử vào RAM.
- Ma trận collaborative filtering join trực tiếp với user/video hợp lệ và đọc history/reaction/rating/comment bằng async enumeration; không tạo các mệnh đề `IN` khổng lồ hay materialize từng stream đầy đủ trước khi xử lý.
- Các endpoint danh sách không có contract phân trang được giới hạn số dòng hợp lý (playlist, download, appeal và lựa chọn admin); nên bổ sung cursor/page nếu sản phẩm cần hiển thị vượt giới hạn này.

## Index đã thêm

Migration `20260927120000_QueryPerformanceIndexes` thêm index cho:

- lịch sử xem theo video và theo `(user_id, video_id, viewed_at)`;
- catalogue public theo category/thời gian;
- reaction, rating, share, comment, comment reaction và video tag;
- subscription active, report theo video, moderation case, appeal target;
- trigram search cho video title/description, channel name, tag name và user username/display name/email.

Migration có `IF NOT EXISTS` để có thể triển khai lặp lại an toàn. `Down` chỉ xóa các index do migration này tạo; extension `pg_trgm` được giữ lại vì có thể được module khác dùng.

## Hợp đồng API lịch sử xem

`before` là mốc kết thúc độc quyền của cửa sổ 30 ngày. Mặc định là thời điểm hiện tại. Client giữ cố định `windowEnd` cho mọi trang của cửa sổ rồi trừ đúng 30 ngày để tạo `before` cho cửa sổ kế tiếp; không dùng timestamp của video cuối cùng làm cursor vì dữ liệu thưa có thể gây chồng lấn. `page/pageSize` vẫn có hiệu lực trong từng cửa sổ để không làm vỡ client cũ.

## Theo dõi sau triển khai

1. Chạy migration trên staging và kiểm tra `EXPLAIN (ANALYZE, BUFFERS)` cho explore, search, history, comments và admin queues.
2. Theo dõi p95/p99 thời gian phản hồi và số query/request trong 24 giờ đầu.
3. Nếu catalogue lớn khiến aggregate lượt xem vẫn nặng, tạo bảng thống kê lượt xem theo `video_id` cập nhật bất đồng bộ rồi thay CTE aggregate bằng bảng đó.
4. Có thể thêm cache ngắn hạn cho explore hub sau khi đo p95; TTL đề xuất 30–60 giây và phải loại bỏ khi nội dung moderation thay đổi.

## Xác nhận thay đổi

- `dotnet build backend/src/HuTube.Infrastructure/HuTube.Infrastructure.csproj --no-restore`: 0 warning, 0 error.
- API build riêng với output tạm: 0 warning, 0 error.
- `npm run build -- --configuration development` tại `frontend/user-web`: hoàn tất.
- Migration `20260927120000_QueryPerformanceIndexes` đã apply thành công trên database local qua `.env.local` vào 2026-09-27; staging/production vẫn cần chạy riêng.
- Đã kiểm tra runtime `GET /api/v1/feed/explore-hub` sau khi restart API local: HTTP 200; SQL window category và aggregate featured creators chạy thành công.
- Sau khi log runtime phát hiện EF Core không dịch được left join với aggregate count, feed và search đã chuyển count sang kiểu nullable rồi dùng `COALESCE` khi sắp xếp/materialize; `GET /api/v1/feed/explore?page=1&pageSize=5` và `GET /api/v1/feed/home?page=1&pageSize=5` đều HTTP 200.
- Danh sách topic/tag admin không còn materialize count nullable từ left join; service tải danh sách và aggregate usage thành hai truy vấn rồi ghép bằng dictionary, tránh lỗi `Nullable object must have a value` với topic/tag chưa có video.
- Admin video/channel aggregate left join cũng dùng projection nullable và coalesce khi sort, đồng nhất với feed/search.
- API local đã được build lại không warning/error và restart trên `http://localhost:5080`.
- Kiểm tra lại bằng `dotnet ef database update --no-build` với `.env.local`: database local báo `No migrations were applied. The database is already up to date.`
- Explore tabs lấy danh mục từ `GET /api/v1/categories`, giữ `categoryId` database khi chọn tab và gửi chính ID đó vào truy vấn ranking; không còn danh sách slug/nhãn gán cứng ở frontend.

## Tính hợp lệ theo thời gian

- Chính sách cửa sổ lịch sử 30 ngày là quyết định sản phẩm hiện tại; nếu UX thay đổi, cập nhật đồng thời service contract, controller và client infinite scroll.
- Tên index và schema trong file này phản ánh migration hiện tại. Khi đổi tên bảng/cột, cập nhật migration mới thay vì sửa lịch sử migration đã chạy.
