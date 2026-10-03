# Kịch bản kiểm thử backend HuTube: hiện có, bổ sung và performance

Đối chiếu mã nguồn/OpenAPI local ngày 02/10/2026 (Asia/Bangkok). Tài liệu này là kế hoạch kiểm thử và danh mục test hiện có; không khẳng định toàn bộ API/performance đã chạy trong lần làm tài liệu. Auth E2E chạy thật được ghi riêng trong [báo cáo](../frontend/e2e_testing/artifacts/auth-results.md). [Kịch bản Web](WEB_TEST_SCENARIOS.md) mô tả các flow UI xuyên User–Admin.

## 1. Cơ sở bao phủ và kết quả có thể xác nhận

OpenAPI lấy trực tiếp từ API đang chạy trong runner local: **225 operations trên 197 path**, gồm các alias API được công bố. [backend-endpoints.json](../frontend/e2e_testing/coverage/backend-endpoints.json) liệt kê từng method/path/tag/nhóm kịch bản và các biến thể bắt buộc. Mọi operation đang ghi `PLANNED` vì inventory không suy ra coverage từ tên test. Ngoài OpenAPI phải kiểm tra SignalR `/hubs/notifications`, OpenAPI/Swagger theo môi trường và background workers.

Danh mục nguồn hiện có: **75 method unit, 77 method integration và 31 method Python recommendation**. Theory/InlineData mở rộng thành nhiều test execution, nên số method không phải số case đã chạy. [existing-tests.json](../frontend/e2e_testing/coverage/existing-tests.json) chứa tên từng method, đường dẫn, Fact/Theory và số InlineData; phụ lục cuối tài liệu liệt kê toàn bộ tên. Kết quả kiểm tra ở lượt sửa BUG trước: 110 unit và 83 integration pass; không thay thế kết quả chạy lại trên build mới, không phải số phần trăm branch/endpoint coverage.

Integration factory dùng PostgreSQL thật, migrate schema và constraints thật; bắt buộc `TEST_DATABASE_CONNECTION`. Google verifier, email sender, object storage, video transcoder và recommendation snapshot store trong fixture có test double. Do đó những integration test này kiểm tra nghiệp vụ/database/API nhưng **không chứng minh OAuth, SMTP, R2, FFmpeg hoặc recommendation network thật hoạt động**. Auth Playwright hiện dùng Pickup thực và browser, nhưng media processing/Google/recommendation bị tắt để đúng scope auth.

## 2. Test hiện có theo nhóm

| File / tầng | Nội dung đang được kiểm tra; tên chính xác ở phụ lục |
| --- | --- |
| Unit/AuthRulesTests, AuthServicePlanTests | Normalize email, password/hash/session, blocked status; kế hoạch gán free plan/plan history |
| Unit/ChannelRulesTests, ChannelTests, ChannelQuotaTests | Handle/branding/channel role, invariants, quota upload |
| Unit/VideoRulesTests | Visibility/quality/duration và validation video |
| Unit/RbacTests | Permission/role/channel membership invariants |
| Unit/PlanEntitlementTests | Feature/quota/download quality theo plan |
| Unit/PaymentServiceTests, SepaySignatureVerifierTests | Price/payment constraints, HMAC/signature/timestamp/transaction cases |
| Unit/ModerationStrikeAndAppealTests | Strike expiry/revoke, trạng thái moderation/appeal và ràng buộc nghiệp vụ |
| Unit/R2StorageTests | Adapter storage/read/delete/sign URL theo fake transport; không phải truy cập R2 thật |
| Integration/AuthApiTests | Register pending/hash/free plan/unique case-insensitive; Google fake; login/platform/cookie/origin, refresh replay/concurrency/expiry, device/session revoke/IDOR, reset link reuse/concurrency, blocked account/admin, health/OpenAPI/migration |
| Integration/ContentApiIntegrationTests | Upload/probe/quota concurrency; metadata, playback visibility, comments, playlists/library, account bio và creator flags; payment atomicity/idempotency; purge/restriction theo các method cụ thể |
| Integration/ChunkUploadRecoveryTests | Durable manifest và khôi phục chunk sau restart, partial file/truncation |
| Integration/RbacAndChannelIntegrationTests | Channel create/membership/invite/permission và admin RBAC |
| Integration/PolicyModerationIntegrationTests | Policy/report/claim/decision/appeal/strike/effective state, legacy report mapping |
| Integration/SearchAndFilterIntegrationTests | Search/filter/sort/public visibility và pagination theo method |
| Integration/FeatureFlagIntegrationTests | Tính năng bật/tắt và response khi disabled |
| Integration/RecommendationAdminIntegrationTests | Quyền admin, settings/matrix/cấu hình recommendation |
| Integration/RecommendationFeedIntegrationTests | Personalized/fallback feed và lọc nguồn dữ liệu |
| Integration/RecommendationModelJobIntegrationTests | Create/status/job lifecycle/model update qua fixture |
| Python recommendation-service/tests | Pipeline/data/cohorts, item/user CF, similarity variants, quality gate, train/artifacts/reports, API, R2 update và complexity |

Khi bổ sung, mở method/assertion tương ứng trước để tránh viết test chỉ trùng implementation. Coverage module ở bảng này không có nghĩa mọi biến thể trong module đã có assertion. Ưu tiên gap trong mục 5 và endpoint chưa được chứng minh; cập nhật mapping method → operation → variant bằng evidence từ request/assertion, không tự suy ra từ tên file.

## 3. Môi trường và cách chạy test hiện có

Chạy từ root repository, dùng .NET 10, PostgreSQL test có quyền create/drop **database test**. Integration factory tạo database `hutube_test_<guid>` tách biệt rồi cleanup; account trong database ephemeral này không phát sinh account trên hệ thống sản phẩm. Quy tắc tái sử dụng một account áp dụng cho môi trường E2E/soak persistent; không thay đổi tính độc lập của unit/integration hiện có.

```powershell
dotnet test backend/tests/HuTube.UnitTests/HuTube.UnitTests.csproj --logger "trx;LogFileName=unit.trx"
# Chỉ trỏ vào PostgreSQL test riêng, thay thông số theo máy của bạn.
$env:TEST_DATABASE_CONNECTION='Host=127.0.0.1;Port=55432;Username=hutube_test;Database=postgres;Password=LocalTestOnly2026!'
dotnet test backend/tests/HuTube.IntegrationTests/HuTube.IntegrationTests.csproj --logger "trx;LogFileName=integration.trx"
dotnet test backend/tests/HuTube.IntegrationTests/HuTube.IntegrationTests.csproj --collect:"XPlat Code Coverage"
```

Port/user/password ở lệnh integration là ví dụ cấu hình local, **không tự tạo server đó** và không phải credential PostgreSQL mặc định trên máy. Auth runner dùng cluster riêng port 55439 và tự dừng khi xong; không chạy lệnh integration vào production hoặc nhầm database E2E persistent. Test không có biến kết nối phải fail rõ, không silently skip.

```powershell
Set-Location recommendation-service
.venv/Scripts/python.exe -m pytest tests -q
```

Nếu chưa có Python env, tạo env riêng và cài theo requirements của recommendation-service; Playwright requirements không thay thế dependencies CF. Ghi build SHA/working tree, runtime versions, migration, cấu hình fake/real, TRX/JUnit/coverage và thời gian. Không ghi token/connection secret vào báo cáo. Coverage collector chỉ đo các path chạy, không tự xác nhận đúng nghiệp vụ hay chứng minh Web coverage.

## 4. Contract và biến thể bắt buộc cho mọi operation

Mỗi operation trong inventory có case riêng gắn nhóm bên dưới, kể cả alias route/HTTP method khác. Khi triển khai, xác định từ controller/service: anonymous/authorized, permission, ownership, valid enum, min/max, error code và status thật. Không ép mọi lỗi thành 400 hoặc mọi ownership thành 403 nếu contract dùng 404.

| Biến thể | Assertion bắt buộc |
| --- | --- |
| Happy path | Status, content-type/schema/fields, đúng owner/target, DB trước/sau, audit/event cần thiết; không chỉ `IsSuccessStatusCode` |
| Validation | Required/null/empty/space, min−1/min/max/max+1, Unicode, email/URL/enum sai, negative/overflow, malformed JSON/multipart, unexpected field handling |
| Auth/RBAC | Không token, expired/tampered/wrong issuer/audience, user/admin/super_admin, blocked/revoked/role changed, cross-user/cross-channel IDOR |
| Read/list | ID missing, soft deleted, status/private filtering, search/sort/date/timezone, page boundaries/default/max và tổng trên >50 rows |
| Mutation | Cancel/cancellation, repeated request, idempotency key phạm vi actor, concurrency cùng resource, transaction rollback giữa nhiều save; không tác dụng phụ khi bị từ chối |
| Error contract | ProblemDetails code/traceId, không stack trace/password/token/PII thừa; 429 retry semantics nếu rate limiting hiện có |
| Asset/event | Object tồn tại/chất lượng/duration thật, read URL đúng quyền/thời hạn; SignalR/email đúng recipient và không gửi trùng |
| Environment | Feature flag, thiếu external dependency, timeout/retry budget, Development/Production OpenAPI/Swagger/CORS/cookie config |

## 5. Kịch bản backend bổ sung theo toàn bộ module

Tiền điều kiện chung: database test, actor cố định có quyền rõ, tài nguyên meaningful theo tài liệu Web. Với mutation: Arrange đọc trạng thái và version/ID → Act request thật → Assert response + DB/storage/event → cleanup hoặc restore fixture. Negative phải chứng minh **không có side effect**, kể cả audit/payment/quota khi request bị từ chối.

| Nhóm | Flow và các gap/biến thể cần xác nhận hoặc bổ sung |
| --- | --- |
| B-AUTH (14) | Register→pending→verify→login→refresh→logout; duplicate email/username chuẩn hóa, concurrent register chỉ một record/free history; pending/suspended/deleted; password min/max/hash không plaintext; verify/reset token hash, invalid/expired/replayed và hai request đồng thời; Google fake/real tách suite; login mobile/web/admin cookies/response đúng platform, origin thiếu/sai/preflight; JWT claim/permission giữa phiên; refresh rotation/replay descendants, max session/device reuse và revoked sessions. Account enumeration response, lockout/rate limit nếu được cấu hình |
| B-ACCOUNT (8) | GET/update profile/bio/avatar/preferences/password/sessions, tất cả preference fields có roundtrip; image content sniff/limit; change password revoke policy và version; revoke current/others/foreign ID không leak; simultaneous update không làm mất field ngoài patch; user ID download/export không gồm hash/token |
| B-CHANNEL (25) | Create→settings/branding→invite→accept→role→remove; unique handle hoa thường, reserved/Unicode/bounds; owner membership và limit plan; avatar/banner/watermark validation/storage cleanup; invite normalized email, reuse/expiry/wrong actor; mọi member permission independently; owner không bị member delete; subscribe counts/idempotent; lock/delete tác động video/playback; analytics totals nhiều trang và ranges timezone |
| B-VIDEO (21) | Upload nguồn thật mục 6→probe→processing→renditions→ready→playback→edit→delete; quota reservation đồng thời/release đúng, client quality/duration spoof không vượt server; MIME/extension/0 byte/truncated/container unsupported; visibility/allowComments; metadata clear values, chapter order/bounds/dedup, tags/category references; history/view/watchSeconds clamps/idempotency; job cancellation/restart/source cleanup, removed vs soft delete vs purge, source URL authorization; không trust client actor/owner |
| B-COMMENT (10) | Create→reply→edit→reaction→report→hide/delete; parent thuộc video khác, depth/cycle, disabledComments và blocked actor; ownership quản trị khác tác giả; text Unicode/XSS, bounds; sorting/paging hidden replies/counts; report legacy tạo cùng moderation case đúng; concurrent reaction không double count |
| B-FEED (5) | Anonymous/personalized/home/trending/explore/search theo actual path; cold start/fallback/recommendation unavailable; hidden/private/removed/banned channel bị lọc; date/sort/page và ranking stable ties; không trả interaction của actor khác; recommendation stale IDs/tombstones |
| B-LIBRARY (2) | History và liked thuộc actor, sort/paging >50, duplicate view/rating update không thêm sai record; deleted/private/suspended video không leak source; watchSeconds nguồn tổng đúng |
| B-PLAYLIST (11) | Create→update visibility→add/order/remove→delete; owner vs guest/member; duplicate video, missing/foreign item ID, reorder atomic và stale request; private/unlisted access, tombstone/suspended video, owner fallback route và channel listing; paging/counts đúng |
| B-PLAN (14) | Catalog/detail/current/default free; paid subscribe route yêu cầu payment đúng contract; invite accept/revoke/member ownership/storage allocation; quota tổng và usedBytes/expiry/renew; invalid duration/price/feature/order/max members; inactive/downgrade/expired entitlement; concurrent member acceptance không vượt capacity |
| B-PAYMENT (4) | Create fixed idempotency key→pending→webhook verify→paid→activate plan/history/membership trong một transaction; replay cùng user, key giống khác user, concurrent webhook và DB lỗi giữa saves không kích hoạt nửa chừng; wrong signature/timestamp/body/amount/currency/reference/user, overdue/canceled/partial/overpaid theo contract; invalid không mutate; QR/status access đúng owner, timeout/reconciliation không tạo payment mới |
| B-DOWNLOAD (4) | Entitlement quality/read URL→persist download/history→list/remove/clear; không gói, quality cao hơn source, hidden/private/channel locked, expired URL; HTTP range/content disposition/size; không cho path traversal hoặc URL tùy ý; delete chỉ record của actor, không mất video nguồn |
| B-SUBSCRIPTION (1) | Listing theo actor/visibility, paging/counts; mutations subscription nằm ở Channel vẫn phải test subscribe/unsubscribe lặp và notification preference; guest/foreign subscription privacy |
| B-NOTIFICATION (3) | List/paging/unread, mark one/all read, ownership; SignalR JWT negotiate/reconnect, same notification not duplicated; moderation/payment/invite đúng recipient/body/link; transaction rollback không gửi success event; outbox/delivery retry nếu có phải đo effect thật |
| B-TAXONOMY (3) | Public categories/policies/violation-types active/published, order/group/version/severity; missing/inactive values không lọt public; consistency với admin create/edit/publish/archive; policy decision tham chiếu đúng snapshot/version |
| B-ADMIN (69) | Tất cả operations tag Admin gồm users/channels/videos/roles/permissions/plans/categories/tags/policies/moderation/report/appeal/strike; mapping path từng operation trong inventory. Mỗi CRUD/list/statistics/export có positive+permission+ownership/bounds; chỉnh role không tự elevate/system role unsafe; clear description patch; reset filter/date/CSV value; thống kê phải bao gồm mọi trang; quản trị phải ghi actor/target/reason và gửi thông báo đúng |
| B-MODERATION (8) | Creator moderation detail/notice/report/appeal theo endpoint actual; owner vs foreign actor, valid target/status, duplicate appeal/evidence validation; thống nhất legacy reports và case IDs, effective state khi policy/strike/restriction thay đổi; source/evidence URL không leak |
| B-CF (9) | Account manifest existing/import/new có idempotent mapping, seed jobs/history/status/log và chunk create/status/append/complete/cancel theo inventory; không tạo account mới mỗi replay; JSON/template bounds, path traversal/filename/session actor, wrong chunk index/length/checksum nếu supported; restart/partial manifest, disk full/quota/max file; complete concurrent exactly once, TTL cleanup không xóa job đang dùng |
| B-RECOMMENDATION (11) | Super_admin-only settings/status/matrix/CSV/model jobs/simulation operations; decimal weights finite/negative/zero sum, normalize đúng; active model exists/type, preview/export limits and order; job dedup/retry/cancel/failed history; partial/missing snapshot fallback, service timeout/auth secret không leak; bot manifest reusable, signal bounds/comments meaningful |
| B-SYSTEM (3 + ngoài schema) | `/health`, system info/config routes theo schema; anonymous exposure đúng thiết kế không leak signing/storage keys; DB unavailable health rõ, startup migrations twice idempotent; OpenAPI/Swagger Development vs Production; CORS allowlist thật, content length/range/body limits, cancellation và graceful shutdown; hub/background paths được test riêng |

Số trong ngoặc là operations ở snapshot hiện tại, không phải số assertions hay test đã pass. Các operations Admin được nhóm tiếp theo path khi triển khai, không bỏ qua các method vì cùng tag.

### B-MODERATION-FLOW — đối chiếu trạng thái toàn chuỗi

1. Owner upload video → pending moderation; reviewer1 claim; reviewer2 claim cùng lúc thất bại hợp lệ. Claim/release/expiry không làm mất lịch sử. Áp quyết định approve/reject/escalate đúng permission/policy/reason.
2. Member report video/comment/channel → normalize target/group → reviewer classify/decision; từng action dismiss/warn/age restriction/recommendation restriction/hide/remove/upload restriction/strike/lock/escalate tương ứng target. Assert bảng case/report/decision, trạng thái hiệu lực và notification.
3. Owner appeal evidence → reviewer khác người quyết định duyệt/reject; wrong actor/claimed by other/terminal state bị chặn; historical video state restore theo rules, nhưng asset đã purge không thể hồi sinh.
4. Tạo/revoke/expire strike/restriction và unlock channel; multiple overlapping restrictions không mở khóa sớm. Fake clock kiểm tra biên trước/đúng/sau expiry; worker thật chạy một vòng với dataset controlled.
5. Transaction fail sau decision nhưng trước state/event → rollback nhất quán; retry/idempotency/concurrent submit không tạo double strike/audit/notice. Giữ IDs và toàn bộ before/after để đối chiếu cùng flow UI.

## 6. Suite media và tích hợp thật cần bổ sung

Nguồn duy nhất: `F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\Em Làm Thì Em Mới Có Ăn_ Không Làm Mà Đòi Có Ăn Thì…_720p.mp4`, đã thấy 99.009.115 byte. Kiểm tra file tồn tại, ffprobe lấy duration/codec/width/height và hash trước chạy, lưu manifest. Không rename nguồn hoặc thay video ngẫu nhiên. Video title/category/chapters dùng dữ liệu ở tài liệu Web, account/video ID persistent.

| Case | Các bước và expected |
| --- | --- |
| B-MEDIA.01 | Upload với storage Local + FFmpeg thật, processing bật → probe → rendition lower than/equal source → ffprobe mỗi output → play/read range. Assert file thực, audio/duration/quality/byte quota, không chỉ JSON metadata |
| B-MEDIA.02 | Cắt nguồn/kill worker có kiểm soát trong workspace test → restart/recover upload ID → complete một lần; malformed file/probe fail/disk full/cancel → resource reservation release đúng, không orphan bất tận |
| B-MEDIA.03 | Storage R2 sandbox với prefix cố định test → upload/read signed URL/expiry/delete/cleanup theo manifest; credentials thiếu ghi BLOCKED, không đổi bucket production |
| B-MEDIA.04 | Email Pickup real UI link; SMTP sandbox optional delivery đúng recipient; Google sandbox real verified credential, cancel/expired/linked account; callback origin và không tạo user mới do retry |
| B-MEDIA.05 | SePay webhook sandbox/body/signature thật qua HTTP, không chuyển tiền thật; CF service thật train/update/read snapshot với dataset known → feed; missing service/token/csv/timeout phải fail hoặc fallback đúng contract |

Chunk store CF hiện 24 MiB, nguồn này 4 chunk; luôn đọc negotiated size từ API. Không giả định endpoint multipart upload thường dùng cùng protocol chunk. Upload timeout khởi đầu 300 giây theo uplink; transcode poll 2–5 giây, deadline 20 phút cấu hình. Thất bại ghi byte/last chunk/status và giữ checkpoint; không POST job/upload mới để che timeout. Không chạy media nặng trong auth smoke mỗi lần.

## 7. Race, lỗi phụ thuộc và dữ liệu lớn

| Tình huống | Thiết kế test |
| --- | --- |
| Quota upload | Barrier để 2+ uploads vào cùng biên quota; tổng reserved+used không vượt, fail release reservation, retry dùng resource cũ |
| Refresh/reset/payment/claim | Barrier requests cùng token/key/resource; một outcome hợp lệ, losers đúng code; assert DB descendants/history/strike/event cardinality |
| Metadata/membership | Hai update có version/stale state; không ghi nhầm ID hoặc tạo duplicate/over capacity; kiểm tra constraints database thực |
| Pagination | Seed một lần dataset có manifest >50 rows với chủ đề và timestamps có ý nghĩa; counts/analytics/export không chỉ trang đầu; thêm duplicates/ties/Unicode/deleted/private |
| Failure injection | Real PostgreSQL transaction/constraint/trigger fail ở điểm giữa saves; dependency timeout/500/cancel/disk errors; chứng minh rollback và không success notification giả |
| Expiry | TimeProvider/clock có kiểm soát nếu service hỗ trợ, hoặc fixture timestamp local; test biên UTC/timezone/DST khi áp dụng, không đợi hàng giờ |
| Security inputs | SQL-like/XSS text, URL/file traversal/CSV formula, extremely long payload, JWT/IDOR/role revoke; scope localhost/sandbox, không quét hệ thống ngoài |

Unit không mock DbSet để thay thế integration constraint test. Google/storage/transcoder doubles cần được công bố trong report. Failure injection suite tách happy path media thật; expectation theo contract và state, không test private method để đạt coverage đẹp.

## 8. Performance backend — kế hoạch bổ sung, chưa thực thi

### 8.1 Môi trường và account/dataset

Dùng Kestrel process thật + PostgreSQL thật, production-like build/config và dependency mode được ghi rõ; không benchmark WebApplicationFactory hoặc in-memory fake rồi coi là tải production. Công cụ load có thể là k6 hoặc Locust; hiện chưa cài/viết/chạy load script. Lưu cấu hình/script/report tương lai trong `frontend/e2e_testing/performance/`.

Một account chính checkpoint cho functional/hot-resource scenario; workload nhiều user dùng pool **seed một lần có manifest**, reuse giữa các run. Không gọi register cho từng iteration/VU. Serialize refresh của cùng session để baseline không biến thành replay attack; dành scenario riêng kiểm tra refresh race. Không gọi sai password liên tục làm khóa account. Lưu stable IDs và request keys cho writes, không tạo data vô hạn; after-run cleanup chỉ tài nguyên trong manifest.

Dataset baseline có quy mô đã ghi: số user/channel/video/interactions/comments/playlist/moderation cases, phân bố published/private/removed, category/timestamp. Nhánh lớn dùng snapshot riêng 1k/10k/100k metadata/interactions có nguồn/purpose, không nhân bản upload file thật cho từng row. Media test chỉ 1 rồi 3 concurrent uploads, không 100 VU ×99 MB. Các job simulation có thể tạo dataset theo chủ đề đã cấu hình; reuse/checkpoint job trước start.

### 8.2 Profile và thời gian chạy

| Profile | Tải / duration đề xuất | Khi chạy |
| --- | --- | --- |
| PERF-BASE | Cold/warm 1 VU, 30–100 requests mỗi nhóm; ghi cache cold riêng | Sau change query/serialization |
| PERF-READ | Ramp 20→50→100 VU, mỗi mức 2 phút, 1 phút warmup; mix feed/search/detail/library/admin list | Trước release, endpoint weights từ usage/fixture |
| PERF-WRITE | 5→10 VU, 2 phút mỗi mức: comments/rating/profile, riêng hot-resource collisions | Sau change transaction/locking |
| PERF-AUTH | Valid login/session refresh/read; stable user pool, cooldown theo lockout policy; refresh-race tách khỏi baseline | Sau change auth/session |
| PERF-SPIKE | 10→100 VU trong 30 giây, giữ 1 phút rồi giảm; fixed ceiling | Trước release, quan sát hồi phục/rate limit |
| PERF-SOAK | 20–50 VU trong 10–30 phút, memory/connection growth | Chạy riêng, không mỗi commit |
| PERF-MEDIA | File nguồn 99 MB, 1 rồi 3 upload concurrent, 1–3 transcode jobs, budget riêng 20 phút | Sau change media/storage/worker |
| PERF-JOB | Matrix preview/export và 1 model job/simulation; request acceptance đo riêng completion | Sau change CF/matrix/job |

Các mức là đề xuất, phải chốt theo CPU/RAM/network của máy và SLO. Không tự chạy tải cao lên môi trường đang phục vụ người dùng. Đặt hard stop khi lỗi 5xx vượt 5% trong 30 giây, DB connection gần cạn, disk thấp hoặc timeout liên tục; ghi fail/bottleneck, không tăng VU vô hạn. Kết quả 429 có chủ đích tách khỏi unexpected 5xx, nhưng phải báo throughput bị hạn chế.

### 8.3 Endpoint mix và chỉ số

| Nhóm tải | Kiểm tra |
| --- | --- |
| Read | Feed/search/category/video metadata/channel/playlist/library; payload size, hidden filtering, sort/count, query count/N+1, SQL plan/index |
| Admin | Users/channels/videos/moderation paging/filter/statistics và CSV; p95 với dataset lớn, memory khi export, cancellation; không deserialize matrix vô hạn |
| Write | Comment/reaction/profile/membership; throughput, transaction wait/deadlock, retries/unique collision, dữ liệu không mất/trùng |
| Auth | Password hashing CPU, valid login, token/session refresh; pool/query locks; cookie semantics giữ đúng dưới tải |
| Media | Uplink throughput/byte/peak RAM/disk I/O, temp files, storage latency; time-to-ready, CPU transcode, queue depth; playback TTFF/range request |
| CF/job | Matrix size/export memory, acceptance latency, queue/worker duration, progress polling, model quality invariants; timeout/cancel không tạo job mới |

Thu p50/p95/p99, requests/second, expected vs unexpected status, timeout/error ratio, bytes/request; .NET CPU/RSS/GC/LOH/thread pool, Npgsql active/waiting connections, DB CPU/IO/locks/deadlocks/query duration; storage/network/job queue. Ghi warmup, cache/index/config/database size và máy chạy load để so sánh trước/sau. `EXPLAIN (ANALYZE, BUFFERS)` chỉ với query và database test phù hợp, tránh tác dụng phụ trên production.

Ngưỡng khởi đầu **đề xuất, chưa có số đo**: read p95 <500 ms, p99 <1.500 ms; write p95 <1.000 ms; unexpected 5xx <1%; không deadlock ngoài tình huống cố ý; không quota/payment/claim invariant violation dù latency đạt. Memory sau warmup không tăng liên tục qua soak, kiểm tra mức tăng khoảng 10% rồi điều tra theo dataset. Upload/transcode/job có SLO riêng từ baseline và kích thước thực; không gộp vào read p95. Request job acceptance mục tiêu <2 giây, completion deadline tối đa 30 phút theo workload.

Timeout functional 30 giây không có nghĩa API 29 giây đạt performance. Báo cáo cần bảng profile, throughput, percentile, resource peak và failures; kết luận bằng so sánh cùng dataset/máy, không từ một request nhanh. Không có kết quả benchmark trong đợt tài liệu này.

## 9. Ưu tiên và tiêu chí kết thúc

P0: auth/IDOR/RBAC, payment atomicity/webhook, quota races, moderation SoD/purge, nguồn video thật. P1: đầy đủ CRUD/filter/pagination/notification/plan membership/cancel/restart. P2: dataset lớn/load/soak/frontend performance và dependency failure thật. Các priority chỉ quyết định thứ tự triển khai, không cho phép bỏ case còn lại khi công bố full coverage.

Mapping mỗi method/path + variant đến test assertion và evidence; đủ cả permissions/actor/feature flags/worker path ngoài OpenAPI. Giữ test cũ, thêm gap có ý nghĩa, chạy required suites và coverage collector. Không đặt mục tiêu 100% line coverage thay cho hành vi: chưa có số coverage nhánh thì ghi chưa đo. Benchmark cần baseline và số đo mới; case BLOCKED thiếu dependency phải nêu rõ, không đếm PASS. CI smoke nhẹ; full media/performance chạy riêng có budget, fixture/checkpoint và báo cáo độc lập.

## 10. Phụ lục test method hiện có

<!-- EXISTING_TEST_METHODS: generated from coverage/existing-tests.json -->

### backend/tests/HuTube.IntegrationTests/AuthApiTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/AuthApiTests.cs).

- `Register_NewEmail_ShouldPersistPendingUserAndHashedSecrets` (Fact)
- `Register_ShouldAssignFreePlanAndCreatePlanHistory` (Fact)
- `GoogleLogin_VerifiedIdentity_ShouldCreateActiveAccountAndIssueSession` (Fact)
- `Login_SameDevice_ShouldReuseOneActiveSession` (Fact)
- `Register_DuplicateEmailIgnoringCase_ShouldReturnConflict` (Fact)
- `Register_InvalidInput_ShouldReturnValidation` (Theory; 2 InlineData)
- `Verify_UsedLink_ShouldRejectReplay` (Fact)
- `Verify_ExpiredLink_ShouldReject` (Fact)
- `Resend_PreviousVerificationLink_ShouldInvalidate` (Fact)
- `Login_Unverified_ShouldReject` (Fact)
- `Login_WrongPassword_ShouldRejectAndLockAfterFiveAttempts` (Fact)
- `Login_BlockedStatus_ShouldRejectLoginAndExistingToken` (Theory; 2 InlineData)
- `Login_RefreshLogout_ShouldRevokeAccessImmediately` (Fact)
- `Refresh_ReusedToken_ShouldRevokeDescendant` (Fact)
- `Refresh_ConcurrentRequests_ShouldAllowOnlyOneRotation` (Fact)
- `Refresh_ExpiredToken_ShouldReject` (Fact)
- `LogoutOthers_TwoDevices_ShouldPreserveCurrentOnly` (Fact)
- `LogoutAll_ShouldRevokeEverySessionAndWriteAuditLog` (Fact)
- `RevokeSession_AnotherUsersSession_ShouldReject` (Fact)
- `ResetPassword_ValidLink_ShouldRevokeAllSessionsAndConsumeToken` (Fact)
- `ForgotPassword_UnknownEmail_ShouldReturnSameMessage` (Fact)
- `Admin_OrdinaryUser_ShouldDenyApiAndLogin` (Fact)
- `Admin_DisabledAfterLogin_ShouldBlockImmediately` (Fact)
- `Web_Login_ShouldUseHttpOnlyCookieAndRequireCsrfHeader` (Fact)
- `Web_UntrustedOrigin_ShouldDenyCookieRequest` (Fact)
- `Web_VideoUploadPreflight_ShouldAllowIdempotencyKey` (Fact)
- `Health_OpenApiAndAnonymousProtected_ShouldMatchContract` (Fact)
- `Migration_Reapplied_ShouldPreserveFullBootstrapSchema` (Fact)
- `RevokeSession_DeviceRotatedSinceList_ShouldRevokeReplacement` (Fact)
- `Web_UserOriginWithAdminCookie_ShouldDenyCrossAppRefresh` (Fact)
- `Logout_OldRotatedCookie_ShouldRevokeReplacement` (Fact)
- `ResetPassword_ConcurrentLinkUse_ShouldSucceedOnce` (Fact)
- `ProtectedApi_TamperedToken_ShouldReject` (Fact)
- `ProtectedApi_ExpiredSignedToken_ShouldRejectEvenWithActiveSession` (Fact)
- `ResetPassword_ExpiredLink_ShouldReject` (Fact)
- `Auth_RateLimitExceeded_ShouldReturnRetryContract` (Fact)


### backend/tests/HuTube.IntegrationTests/ChunkUploadRecoveryTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/ChunkUploadRecoveryTests.cs).

- `RestartResumesCommittedChunkAndTruncatesInterruptedWrite` (Fact)


### backend/tests/HuTube.IntegrationTests/ContentApiIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/ContentApiIntegrationTests.cs).

- `NotificationPreferencesAndPaging_ControlReplyDelivery` (Fact)
- `UploadModeratePublish_ExposesVideoInPublicFeedsAndPlayback` (Fact)
- `VideoInteractions_AreMutuallyExclusiveAndPersistWatchProgressRatingShare` (Fact)
- `VideoLikeCommentLikeAndReply_CreateRealtimeNotificationRows` (Fact)
- `Comments_ReplyReactionReportAndOwnerModeration_WorkEndToEnd` (Fact)
- `SettingsDownloadsAndCreatorManagement_PersistAndEnforceOwnership` (Fact)
- `UploadPreflightRetryAndCancel_EnforcePlanAndRetainMediaUntilPurge` (Fact)
- `CategoriesCreatorEditFilterAndSoftDelete_WorkEndToEnd` (Fact)
- `CommentCrudSortAndGuestAuthorization_WorkEndToEnd` (Fact)
- `PrivatePlaylistItems_AreTombstonesForOtherViewers` (Fact)
- `MetadataDoesNotIssueSourceUrls_AndSuspendedChannelsCannotPlay` (Fact)
- `ProfileBioPersists_AndModeratorRestrictionsSurviveCreatorEdits` (Fact)
- `DisabledComments_RejectNewComments` (Fact)
- `PaymentIdempotency_IsScopedToUserAndSurvivesCompletionAndConcurrency` (Fact)
- `PaymentFinalSaveFailure_RollsBackActivatedPlanAndHistory` (Fact)
- `DeletedVideoPurge_PreservesDatabaseConstraintsAndReleasesQuotaOnce` (Fact)
- `ConcurrentUploads_ReserveQuotaUsingFreshValues_AndCleanRejectedObjects` (Fact)
- `UploadProbeOverridesClientClaims_AndRevalidatesActualDuration` (Fact)


### backend/tests/HuTube.IntegrationTests/FeatureFlagIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/FeatureFlagIntegrationTests.cs).

- `DisabledModerationAndPlan_BypassesPlanButLocksPublicVisibility` (Fact)


### backend/tests/HuTube.IntegrationTests/PolicyModerationIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/PolicyModerationIntegrationTests.cs).

- `PublicPolicies_ShouldExposeSeededRows_AndModeratorCanViewAssignedPolicyPermission` (Fact)
- `SuperAdmin_CanCreateAndPublishPolicy` (Fact)
- `SuperAdmin_CanManageTopicsAndTags` (Fact)
- `SuperAdmin_CanInspectAndLockUnlockUser` (Fact)
- `Moderator_CanViewQueue` (Fact)
- `SuperAdmin_CanClaimAndResolveCase_WithWireDecision` (Theory; 5 InlineData)
- `Moderation_ShouldRejectPascalCaseDecisionValues` (Fact)


### backend/tests/HuTube.IntegrationTests/RbacAndChannelIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/RbacAndChannelIntegrationTests.cs).

- `INT_S4_03_AdminRbac_Moderator_CanViewQueue_ButCannotApprove` (Fact)
- `INT_S4_06_AdminRbac_SuperAdminCanCreateAndUpdateCustomRole` (Fact)
- `INT_S4_04_ChannelMembership_OwnerAndEditor_PermissionEnforcement` (Fact)


### backend/tests/HuTube.IntegrationTests/RecommendationAdminIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/RecommendationAdminIntegrationTests.cs).

- `RecommendationEndpointsRequireLiveSuperAdminRole` (Fact)
- `CreatingBotsDoesNotResetAnExistingAccount` (Fact)
- `MatrixDiffCountsAddedChangedAndRemovedPairs` (Fact)
- `SimulationUsesExistingServicesAndPreservesBotCredentials` (Fact)


### backend/tests/HuTube.IntegrationTests/RecommendationFeedIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/RecommendationFeedIntegrationTests.cs).

- `ViewedVideoIsExcludedFromCfAndFallbackOnEveryPage` (Fact)


### backend/tests/HuTube.IntegrationTests/RecommendationModelJobIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/RecommendationModelJobIntegrationTests.cs).

- `ModelJobUploadsDatedCsvAndDoesNotReplaceManifestOnFailure` (Fact)


### backend/tests/HuTube.IntegrationTests/SearchAndFilterIntegrationTests.cs

[Mở file test](../backend/tests/HuTube.IntegrationTests/SearchAndFilterIntegrationTests.cs).

- `Search_ByKeyword_MatchesTitleChannelDescriptionAndTags` (Fact)
- `Search_WithSpecialCharactersAndEmptyQuery_ReturnsSafely` (Fact)
- `Search_WithCombinedFilters_CategoryDurationAndDate` (Fact)
- `Search_StrictlyExcludesNonPublicVideos` (Fact)
- `Search_PaginationAndSorting` (Fact)


### backend/tests/HuTube.UnitTests/AuthRulesTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/AuthRulesTests.cs).

- `NormalizeEmail_InvalidEmail_ShouldReject` (Theory; 4 InlineData)
- `NormalizeEmail_MixedCase_ShouldNormalize` (Fact)
- `ValidatePassword_WeakPassword_ShouldReject` (Theory; 4 InlineData)
- `ValidatePassword_TooLong_ShouldReject` (Fact)
- `ValidatePassword_Valid_ShouldAccept` (Fact)
- `IsBlocked_RestrictedAccount_ShouldBlock` (Theory; 3 InlineData)
- `IsBlocked_SoftDeleted_ShouldBlock` (Fact)
- `IsActive_ExpiredSession_ShouldReject` (Fact)
- `Revoke_Repeated_ShouldPreserveFirstReason` (Fact)
- `Hash_Password_ShouldUseRandomSaltAndVerify` (Fact)
- `CreateOpaqueToken_Repeated_ShouldBeUniqueAndStoreOnlyHash` (Fact)


### backend/tests/HuTube.UnitTests/AuthServicePlanTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/AuthServicePlanTests.cs).

- `RegisterAsync_CallsAddUserAsync_AndUserHasFreePlan` (Fact)


### backend/tests/HuTube.UnitTests/ChannelQuotaTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/ChannelQuotaTests.cs).

- `CanReserve_ShouldRejectWhenUploadWouldExceedLimit` (Fact)
- `CanReserve_ShouldAllowExactLimitBoundary` (Fact)
- `Remaining_ShouldNeverGoNegative` (Fact)


### backend/tests/HuTube.UnitTests/ChannelRulesTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/ChannelRulesTests.cs).

- `IsValidHandle_ValidatesCorrectly` (Theory; 10 InlineData)
- `NormalizeHandle_NormalizesToLowercaseWithoutAtPrefix` (Theory; 3 InlineData)
- `SoftDelete_SetsStatusToDeletedAndIsActiveFalse` (Fact)


### backend/tests/HuTube.UnitTests/ChannelTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/ChannelTests.cs).

- `CreateChannel_ShouldSucceed_AndMakeCreatorOwner` (Fact)
- `CreateChannel_DuplicateHandle_ShouldThrow409` (Fact)
- `UpdateChannel_NonMember_ShouldThrow403` (Fact)
- `InviteMember_And_Accept_ShouldCreateActiveMember` (Fact)
- `AccessibleChannels_ShouldIncludeAcceptedMemberWithoutOwnedChannel` (Fact)
- `InviteMember_ShouldSendInvitationEmail` (Fact)
- `RevokedInvitation_CannotBeAccepted` (Fact)
- `ExpiredInvitation_IsMarkedExpired_AndCannotBeDeclined` (Fact)
- `DuplicatePendingInvitation_ShouldBeRejected` (Fact)
- `ChangeRole_ManagerCannotChangeAnotherManager` (Fact)
- `RemoveMember_CannotRemoveOwner` (Fact)
- `Subscribe_Success_ShouldCreateActiveSubscription` (Fact)
- `Subscribe_OwnChannel_ShouldThrow400` (Fact)
- `Subscribe_InactiveChannel_ShouldThrowNotActive` (Fact)
- `Subscribe_DuplicateRequest_ShouldBeIdempotent` (Fact)
- `Unsubscribe_Success_ShouldPauseSubscription_AndDecrementCount` (Fact)
- `Unsubscribe_DuplicateOrNonExistent_ShouldNotThrow` (Fact)
- `GetSubscribedChannels_ShouldReturnOnlyActiveChannels` (Fact)


### backend/tests/HuTube.UnitTests/ModerationStrikeAndAppealTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/ModerationStrikeAndAppealTests.cs).

- `AutoLockRule_FifthVideoRejection_LocksChannelAndCreatesStrike` (Fact)
- `StrikeTier_Progression_And_Revocation_RestoresActiveStatus` (Fact)
- `Appeal_SeparationOfDuties_PreventsOriginalReviewerFromResolving` (Fact)
- `Report_CanReportVideoCommentAndChannel` (Fact)


### backend/tests/HuTube.UnitTests/PaymentServiceTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/PaymentServiceTests.cs).

- `InitiateAsync_WhenPaidPlan_CreatesPendingPaymentWithQr` (Fact)
- `InitiateAsync_WhenFreePlan_ThrowsBadRequest` (Fact)
- `HandleSepayWebhookAsync_WhenValidPayment_ActivatesPlanAndMarksPaid` (Fact)
- `HandleSepayWebhookAsync_WhenDuplicateTransactionId_IgnoresSilently` (Fact)
- `HandleSepayWebhookAsync_WhenAmountLessThanRequired_DoesNotActivatePlan` (Fact)
- `HandleSepayWebhookAsync_WhenPaymentExpired_CancelsPayment` (Fact)
- `GetPaymentAsync_ReturnsCorrectPaymentDetails` (Fact)


### backend/tests/HuTube.UnitTests/PlanEntitlementTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/PlanEntitlementTests.cs).

- `ReadFlags_ShouldReturnOnlyBooleanEntitlements` (Fact)
- `ReadFlags_ShouldNormalizeEntitlementKeys` (Fact)
- `ReadFlags_ShouldFailClosedForInvalidOrNonObjectJson` (Theory; 4 InlineData)
- `CanReserve_ShouldAvoidOverflowAndRejectInvalidCounters` (Fact)


### backend/tests/HuTube.UnitTests/R2StorageTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/R2StorageTests.cs).

- `LoadDevelopmentFile_ReadsLastBucketScopedCredentialWithoutLoggingSecrets` (Fact)
- `GetReadUrlAsync_ForPrivateR2Object_ReturnsTemporarySignedUrl` (Fact)


### backend/tests/HuTube.UnitTests/RbacTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/RbacTests.cs).

- `GetAdminMe_WhenNotAdmin_Throws403` (Fact)
- `GetAdminMe_WhenAdmin_ReturnsRoleAndPermissions` (Fact)
- `HasPermission_ResolvesCorrectly` (Fact)
- `LogAudit_CreatesEntry` (Fact)
- `CreateRole_AsSuperAdmin_CreatesPermissionsAndAuditEntry` (Fact)
- `UpdateRole_RejectsPermissionBeyondActorDelegation` (Fact)


### backend/tests/HuTube.UnitTests/SepaySignatureVerifierTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/SepaySignatureVerifierTests.cs).

- `Verify_WhenTimestampMalformedOrOutsideWindow_RejectsWithoutThrowing` (Theory; 4 InlineData)
- `Verify_WhenSecretKeyIsEmpty_ReturnsFalse` (Fact)
- `Verify_WhenSignatureIsNull_ReturnsFalse` (Fact)
- `Verify_WhenValidSignature_ReturnsTrue` (Fact)
- `Verify_WhenInvalidSignature_ReturnsFalse` (Fact)
- `Verify_WhenTimestampTooOld_ReturnsFalse` (Fact)


### backend/tests/HuTube.UnitTests/VideoRulesTests.cs

[Mở file test](../backend/tests/HuTube.UnitTests/VideoRulesTests.cs).

- `LowerQualities_ReturnsOnlyRenditionsBelowSource` (Theory; 4 InlineData)
- `ValidateVisibility_WithSupportedValue_DoesNotThrow` (Theory; 3 InlineData)
- `ValidateVisibility_WithUnsupportedValue_Throws` (Fact)
- `ValidateUpload_WithSupportedContentType_DoesNotThrow` (Theory; 3 InlineData)
- `ValidateUpload_WhenFileExceedsLimit_Throws` (Fact)
- `ValidateChapters_WithIncreasingTimeline_ReturnsNormalizedChapters` (Fact)
- `ValidateChapters_WhenTimelineIsNotIncreasing_Throws` (Fact)
- `CalculateProgress_ClampsAndCalculatesPercentage` (Theory; 2 InlineData)
- `ValidateComment_WithInvalidContent_Throws` (Theory; 3 InlineData)
- `ValidateRating_WithScoreOutsideOneToFive_Throws` (Fact)


### recommendation-service/tests/test_api.py

[Mở file test](../recommendation-service/tests/test_api.py).

- `test_internal_api_requires_token_and_excludes_seen` (pytest)
- `test_unknown_user_returns_404` (pytest)
- `test_invalid_limit_returns_422` (pytest)
- `test_model_admin_routes_require_separate_token` (pytest)
- `test_no_model_returns_503` (pytest)


### recommendation-service/tests/test_artifacts.py

[Mở file test](../recommendation-service/tests/test_artifacts.py).

- `test_artifact_round_trip_preserves_recommendations` (pytest)


### recommendation-service/tests/test_cohorts.py

[Mở file test](../recommendation-service/tests/test_cohorts.py).

- `test_temporal_split_keeps_latest_interaction_for_test` (pytest)


### recommendation-service/tests/test_complexity.py

[Mở file test](../recommendation-service/tests/test_complexity.py).

- `test_complexity_benchmark_uses_only_dense_item_based_strategy` (pytest)


### recommendation-service/tests/test_data_pipeline.py

[Mở file test](../recommendation-service/tests/test_data_pipeline.py).

- `test_null_and_zero_have_different_masks` (pytest)
- `test_local_movielens_has_official_counts` (pytest)


### recommendation-service/tests/test_hutube_training.py

[Mở file test](../recommendation-service/tests/test_hutube_training.py).

- `test_missing_matrix_never_generates_sample_data` (pytest)
- `test_empty_matrix_is_rejected` (pytest)
- `test_hash_mismatch_is_rejected` (pytest)
- `test_train_only_item_based_cosine` (pytest)
- `test_weighted_score_configuration_is_persisted` (pytest)


### recommendation-service/tests/test_item_cf.py

[Mở file test](../recommendation-service/tests/test_item_cf.py).

- `test_item_cf_predicts_and_excludes_seen_items` (pytest)


### recommendation-service/tests/test_quality_gate.py

[Mở file test](../recommendation-service/tests/test_quality_gate.py).

- `test_quality_gate_accepts_complete_safe_benchmark` (pytest)
- `test_quality_gate_rejects_invalid_runtime` (pytest)
- `test_quality_gate_requires_both_models` (pytest)


### recommendation-service/tests/test_r2_update.py

[Mở file test](../recommendation-service/tests/test_r2_update.py).

- `test_r2_training_restart_and_failed_update_keep_active_model` (pytest)
- `test_training_lease_excludes_replicas_and_fences_old_owner` (pytest)
- `test_job_creation_excludes_other_replica_and_recovers_default_aggregation` (pytest)


### recommendation-service/tests/test_reports.py

[Mở file test](../recommendation-service/tests/test_reports.py).

- `test_html_report_is_self_contained_and_runtime_only` (pytest)
- `test_html_report_includes_complexity_benchmark` (pytest)
- `test_cf_comparison_report_is_runtime_only` (pytest)
- `test_comparison_report_renders_six_variants_and_runtime_labels` (pytest)


### recommendation-service/tests/test_similarity_variants.py

[Mở file test](../recommendation-service/tests/test_similarity_variants.py).

- `test_pearson_uses_rating_direction_and_not_missing_zeroes` (pytest)
- `test_jaccard_uses_presence_not_rating_magnitude` (pytest)
- `test_fit_all_models_creates_user_and_item_variants` (pytest)


### recommendation-service/tests/test_training.py

[Mở file test](../recommendation-service/tests/test_training.py).

- `test_both_from_scratch_models_train_and_evaluate` (pytest)


### recommendation-service/tests/test_user_cf.py

[Mở file test](../recommendation-service/tests/test_user_cf.py).

- `test_user_cf_recommends_from_similar_users` (pytest)

