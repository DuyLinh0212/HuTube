# Rà luồng quản trị: các điểm cần tối ưu

Rà code trên develop ngày 25/10/2026 trong lúc bổ sung ma trận phân quyền. Đây là
phân tích cấu trúc và số thao tác trong code, chưa phải kết luận profiling trên
AWS. Chưa thay đổi các luồng này trong đợt bổ sung test, trừ bổ sung chức năng
cho sáu quyền còn thiếu. Không quy đổi các vấn đề thành số giây hay tỷ lệ chậm
khi chưa có phép đo.

## Nên xử lý trước

1. **Trang kênh luôn đi qua API đếm chưa tồn tại rồi gọi bốn API dự phòng.**
   `AdminChannelsService.getChannelCounts()` gọi `/admin/channels/counts`, nhưng
   controller chưa có route này; khi 404 sẽ gọi danh sách với pageSize=1 cho
   bốn trạng thái. `AdminChannelsPage.ngOnInit()` còn tải trang danh sách riêng.
   Một lần mở trang vì vậy tạo tối thiểu sáu request nghiệp vụ ở luồng này
   (một 404, bốn đếm dự phòng, một danh sách), ngoài xác thực. Mỗi API danh sách
   vẫn thực hiện các query join/tổng hợp. Nên thêm endpoint bộ đếm gộp, query
   điều kiện trong một lượt và cache ngắn cho bộ đếm; không tải lại cả bốn khi
   chỉ đổi trang. Nguồn: `frontend/admin-web/src/app/features/channels/admin-channels.service.ts`,
   `admin-channels-page.ts`, `backend/src/HuTube.Api/Controllers/AdminController.cs`.

2. **Báo cáo hệ thống chờ nhiều query đếm liên tiếp.**
   `AdminOperationsService.GetReportAsync()` đếm tổng và theo kỳ riêng cho user,
   video, kênh, lượt xem, bình luận, reaction, thuê bao, report, moderation,
   appeal, phiên, chia sẻ, rồi doanh thu và chuỗi thời gian. Độ trễ DB bị cộng
   dồn và các bảng lớn bị quét nhiều lần. Nên gộp aggregate có điều kiện theo
   bảng, cache báo cáo theo kỳ, sau đó cân nhắc bảng thống kê ngày khi có số đo.
   Không dùng `Task.WhenAll` với cùng một DbContext để sửa vấn đề này.
   Nguồn: `backend/src/HuTube.Infrastructure/Operations/AdminOperationsService.cs`,
   phương thức `GetReportAsync`.

3. **Kiểm tra quyền đọc lại dữ liệu nhiều lần trong cùng request.**
   `RequirePermissionAttribute` đọc user, kiểm tra admin rồi gọi
   `HasPermissionAsync` cho từng quyền thay thế. `RbacStore.HasPermissionAsync`
   lại đọc danh sách quyền đầy đủ; các controller còn có kiểm tra bổ sung như
   private hoặc loại quyết định. Nên xây authorization context dùng trong đúng
   một request để tái sử dụng user/role/permission đã đọc. Phải giữ hiệu lực thu
   hồi ngay ở request kế tiếp; không cache quyền bằng TTL dài vì làm hỏng yêu
   cầu vừa được kiểm thử. Nguồn: `backend/src/HuTube.Api/Authorization/PermissionAuthorization.cs`,
   `backend/src/HuTube.Infrastructure/Persistence/RbacStore.cs`.

4. **N+1 khi dựng danh sách role.**
   `RbacService.GetAllRolesAsync()` lặp role và `await CountUsersForRoleAsync`
   từng role. Số round trip tăng theo số role. Nên GroupBy số user theo RoleId
   một lần rồi ghép vào danh sách. Nguồn:
   `backend/src/HuTube.Application/Rbac/RbacService.cs`.

## Các điểm cần đo và tối ưu tiếp

5. **Danh sách kênh/video có nhiều aggregate và đếm cho mỗi lần phân trang.**
   `AdminContentService.GetChannelsAsync/GetVideosAsync` dựng tổng video,
   subscriber, strike, view/report và đếm tổng trước khi lấy trang. Một số phần
   đã batch theo các ID của trang; một số aggregate vẫn nằm trên toàn tập bảng
   trong query join. Cần EXPLAIN ANALYZE để biết phần nào quét rộng; ưu tiên
   page ID trước rồi aggregate dữ liệu của trang, tách số liệu tổng thay đổi
   chậm hoặc dùng counter. Đã có migration index/trigram, không nên thêm index
   trùng một cách máy móc. Nguồn:
   `backend/src/HuTube.Infrastructure/Videos/AdminContentService.cs`,
   `Persistence/Migrations/20260927120000_QueryPerformanceIndexes.cs`.

6. **Hàng đợi duyệt nạp cả active và processed ngay khi vào trang.**
   `AdminModerationPage.loadData()` gọi hai queue pageSize=100 và tải policies,
   rồi nối hai danh sách. Claim/resolve lại tải dữ liệu. Nên chỉ tải tab đang
   mở, phân trang ở server, cache policies theo phiên bản và cập nhật đúng dòng
   sau mutation. Nguồn:
   `frontend/admin-web/src/app/features/moderation/admin-moderation-page.ts`.

7. **Thống kê người dùng ghép nhiều tập dữ liệu và chờ recommendation service.**
   `AdminUserService.GetStatisticsAsync()` tải các nhóm hành vi rồi gọi
   `recommendationClient.GetRecommendationsAsync`. Một thành phần ngoài DB
   có thể giữ cả response thống kê. Nên tách phần đề xuất thành tải bổ sung,
   giới hạn số dữ liệu hành vi dùng để hiển thị, đẩy aggregate về DB và đo từng
   đoạn. `GetUsersAsync()` cũng tính lại các bộ đếm tổng ở mỗi trang. Nguồn:
   `backend/src/HuTube.Infrastructure/Users/AdminUserService.cs`.

8. **Các trang danh sách gọi load bằng subscribe độc lập.**
   Kênh/video có thể phát nhiều request khi người dùng đổi bộ lọc hoặc trang
   nhanh. Không có hủy request trước bằng switchMap ở các hàm load này; response
   cũ có thể về sau và ghi lại trạng thái. Nên dùng một luồng bộ lọc có
   distinctUntilChanged/switchMap, giữ dữ liệu cũ khi đang tải và hủy request khi
   rời trang. Cần test response về đảo thứ tự. Nguồn:
   `frontend/admin-web/src/app/features/channels/admin-channels-page.ts`,
   `frontend/admin-web/src/app/features/videos/admin-videos-page.ts`.

9. **Response giám sát phụ thuộc nhiều dịch vụ ngoài.**
   `GetSystemOverviewAsync()` đã khởi chạy một số tác vụ đồng thời và một số
   provider đã có cache, nhưng response cuối vẫn chờ service status, R2, Neon,
   Redis và dữ liệu hoạt động. Frontend polling mỗi 60 giây. Nên đo thời gian
   riêng từng provider; trả snapshot gần nhất kèm thời điểm cập nhật, cập nhật
   provider nền và không giữ phần dashboard nhanh theo provider chậm. Nguồn:
   `AdminOperationsService.GetSystemOverviewAsync`,
   `frontend/admin-web/src/app/features/operations/system-notifications-page.ts`.

10. **Xuất dữ liệu lớn vẫn là tác vụ đồng bộ và tạo CSV trong trình duyệt.**
    API xuất mới đã có quyền riêng, bộ lọc, thứ tự ổn định và snapshot nhất quán,
    nhưng vẫn đọc từng lô 100, tạo danh sách đầy đủ rồi Web tạo Blob CSV. Với
    dữ liệu lớn sẽ tăng RAM, số query và thời gian giữ transaction. Nên đo
    ngưỡng thực tế rồi chuyển export lớn sang job có trạng thái và file tải,
    hoặc stream CSV có kiểm soát; không bỏ lọc private hay kiểm tra quyền khi
    tối ưu. Nguồn: `AdminContentService.ExportAsync`,
    `AdminContentActionsController`, các hàm `exportCsv` ở Web Admin.

## Phạm vi đã xem và các điểm đã có sẵn

Đã đối chiếu các route của 16 nhóm quyền, authorization, các service/controller
đọc dữ liệu và các điểm tải lại chính trên giao diện. Không gắn nhãn mọi vòng
lặp là N+1: báo cáo vi phạm đã batch dữ liệu liên quan theo case ID; appeal,
audit, payment, subscription đã có phân trang server; AuthService có shareReplay
cho quá trình restore, nên không kết luận hai guard tự động tạo hai lần refresh.
CF Seeder đã có chia chunk/tác vụ dài; chưa có benchmark để kết luận nó là
nguyên nhân làm chậm các trang admin khác. Policy/taxonomy/plan là tập dữ liệu
thường nhỏ; ưu tiên sau các điểm phía trên.

Bước đo đề xuất: ghi số query và thời gian DB của từng endpoint, P50/P95 theo
thao tác mở trang/lọc/chuyển trang/claim/resolve/export, kích thước JSON và
waterfall request trên bộ dữ liệu 1k/10k/100k. Dùng dữ liệu test và môi trường
staging; giữ các ca thu hồi quyền/phân quyền hiện tại làm regression.
