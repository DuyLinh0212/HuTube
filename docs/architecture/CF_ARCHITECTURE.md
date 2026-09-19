# HuTube - Kiến trúc Collaborative Filtering (CF)

> Phiên bản: 1.0
> Trạng thái: MBMF benchmark service đã triển khai; tích hợp .NET chưa triển khai
> Phạm vi: Module Recommendation / Collaborative Filtering của HuTube

## 1. Mục tiêu và phạm vi

Module CF chịu trách nhiệm tạo danh sách video đề xuất cho User dựa trên các tín
hiệu tương tác như view, watch ratio, like, dislike, comment và share.

Tài liệu này mô tả kiến trúc triển khai của Module CF trong toàn hệ thống HuTube,
bao gồm hai ngữ cảnh liên quan:

1. **CF Lab ('DemoCF')**: môi trường nghiên cứu, benchmark và trực quan hóa các
   thuật toán Collaborative Filtering.
2. **Recommendation production flow ('HuTube')**: luồng đề xuất thật cho Web và
   Mobile, trong đó Backend .NET là cổng API chính và Python đảm nhiệm phần model.

CF Lab có thể tái sử dụng thuật toán, metric và pipeline nghiên cứu cho production,
nhưng không được xem là Backend chính của HuTube.

## 2. Quyết định kiến trúc

Module CF sử dụng kiến trúc hybrid gồm ba process chính:

| Process | Công nghệ | Vai trò |
|---|---|---|
| HuTube API | ASP.NET Core / .NET | Backend chính, public API, nghiệp vụ và bảo mật |
| Recommendation Service | Python FastAPI | Load model và suy luận Top-K |
| Training Worker | Python | Preprocessing, training, evaluation và xuất model artifact |

> Các quyết định quan trọng:

- Frontend chỉ gọi HuTube Backend .NET, không gọi Python trực tiếp.
- .NET gọi Python qua internal HTTP API; FastAPI là framework của Python Service.
- Python trả về `itemId`, `source` và score; không quyết định item nào được phép
  hiển thị.
- Adapter .NET chỉ đổi `itemId` thành `videoId` với artifact `BOT` hoặc `REAL`.
- .NET chịu trách nhiệm hydrate Video DTO, kiểm tra quyền và lọc video không hợp lệ.
- Khi Python timeout hoặc lỗi, .NET phải trả fallback feed để Home không bị lỗi.
- Training có thể chạy độc lập, không được làm nghẽn request online.

## 3. Kiến trúc tổng quan

~~~mermaid
flowchart LR
    U[Web / Mobile Frontend]
    API[HuTube API<br/>ASP.NET Core]
    DB[(HuTube PostgreSQL)]
    PY[Recommendation Service<br/>Python FastAPI]
    MODEL[(Model Artifact<br/>Object Storage / Persistent Storage)]
    TRAIN[Training Worker<br/>Python]
    FALLBACK[Fallback Feed<br/>Popular / Recent]

    U -->|Public API| API
    API -->|Auth, business rules| DB
    API -->|POST /internal/recommendations| PY
    PY -->|Top-K itemId + source + score| API
    API -->|Hydrate, filter, DTO| U
    API -. timeout / 5xx .-> FALLBACK
    DB -->|Snapshot / interaction data| TRAIN
    TRAIN -->|Train + evaluate| MODEL
    MODEL -->|Load version| PY
~~~

### 3.1. Luồng online recommendation

~~~mermaid
sequenceDiagram
    participant F as Frontend
    participant N as .NET HuTube API
    participant P as Python Recommendation Service
    participant D as HuTube Database

    F->>N: GET /api/v1/recommendations/home?limit=20
    N->>N: Xác định User và quyền truy cập
    N->>P: POST /internal/recommendations
    P->>P: Load model + tính điểm Top-K
    P-->>N: itemId + source + score + modelVersion
    N->>D: Lấy metadata Video/Channel
    N->>N: Lọc Deleted, Private, Blocked, Restricted
    N->>N: Bù candidate nếu danh sách thiếu
    N-->>F: Recommendation DTO + cursor
~~~

Nếu Python không phản hồi trong thời gian cấu hình, .NET không trả lỗi toàn trang.
Luồng xử lý chuyển sang fallback feed và ghi log/metric để theo dõi.

### 3.2. Luồng offline training

~~~mermaid
flowchart TD
    E[Raw User-Video Events]
    S[Training Snapshot]
    P[Preprocessing + Mask/Weight]
    T[MBMF / CF Training]
    V[Temporal Validation + Metrics]
    A[Versioned Model Artifact]
    R[Model Registry / Storage]
    L[Online Service Reload]

    E --> S --> P --> T --> V
    V -->|Pass quality gate| A --> R --> L
    V -->|Fail| X[Không promote model]
~~~

Training và inference dùng cùng mapping user_id, item_id, cấu hình model và
schema dữ liệu. Mapping phải được lưu kèm model artifact để tránh sai lệch index khi
load lại model.

## 4. Phân chia trách nhiệm

### 4.1. HuTube Backend .NET

Backend .NET là system of record và là public API boundary của HuTube.

- Authentication và xác định User hiện tại.
- Authorization, channel permission và policy.
- Nhận request recommendation từ Web/Mobile.
- Validate limit, cursor và các tham số public.
- Gọi Python Recommendation Service bằng service credential.
- Lấy metadata đầy đủ từ Database.
- Lọc video Deleted, Private, Blocked, Rejected hoặc bị hạn chế đề xuất.
- Áp dụng business rule, diversity/candidate policy nếu có.
- Trả response DTO ổn định cho Web/Mobile.
- Fallback khi Python lỗi, timeout hoặc model chưa sẵn sàng.
- Expose Admin API cho model status, retrain request, history và rollback.

### 4.2. Python Recommendation Service

Python Service chỉ đảm nhiệm phần machine learning và ranking cần thiết cho inference.

- Load model artifact theo model_version.
- Nhận user_id, limit và danh sách item cần exclude.
- Tạo candidate và tính preference score.
- Xếp hạng Top-K.
- Trả về item_id, source, score, model_version và metadata kỹ thuật tối thiểu.
- Health check, readiness check và reload model atomic.

Python Service không chịu trách nhiệm:

- Phát hành JWT hoặc kiểm tra quyền User.
- Quyết định video private/deleted có được hiển thị hay không.
- Trả full Video DTO cho frontend.
- Expose endpoint inference công khai ra Internet.
- Ghi đè business data của HuTube.

### 4.3. Training Worker

Training Worker chạy theo lịch hoặc theo yêu cầu Admin, tách khỏi process phục vụ
inference online.

- Đọc raw interaction hoặc training snapshot.
- Chuẩn hóa unified schema.
- Preprocess và tạo train/validation/test split theo thời gian.
- Train model CF/MBMF.
- Tính metric: Precision@K, Recall@K, NDCG@K, HitRate@K và các metric liên quan.
- Lưu model artifact, config, mapping và metrics theo version.
- Chỉ promote model khi vượt quality gate.
- Không ghi model binary vào Git repository.

## 5. Kiến trúc thư mục đề xuất

### 5.1. HuTube Backend .NET

Đây là các thư mục thuộc Backend chính, phù hợp với cấu trúc hiện tại trong
HuTube/backend/src:

~~~text
HuTube/backend/src/
├── HuTube.Domain/
│   └── Recommendations/
│       ├── Recommendation.cs
│       ├── RecommendationItem.cs
│       └── IRecommendationRepository.cs
│
├── HuTube.Application/
│   └── Recommendations/
│       ├── Contracts/
│       │   ├── RecommendationItemDto.cs
│       │   ├── RecommendationFeedDto.cs
│       │   └── RecommendationOptions.cs
│       ├── IRecommendationProvider.cs
│       ├── RecommendationService.cs
│       ├── GetHomeRecommendations.cs
│       └── AdminRecommendationService.cs
│
├── HuTube.Infrastructure/
│   └── Recommendation/
│       ├── PythonRecommendationClient.cs
│       ├── PythonRecommendationContracts.cs
│       ├── RecommendationOptions.cs
│       ├── RecommendationFallbackService.cs
│       └── DependencyInjection.cs
│
└── HuTube.Api/
    └── Recommendations/
        ├── RecommendationEndpoints.cs
        └── AdminRecommendationEndpoints.cs
~~~

Nguyên tắc dependency:

~~~text
HuTube.Api
    ↓
HuTube.Application
    ↓
HuTube.Domain

HuTube.Infrastructure ──implements──> Application abstractions
HuTube.Infrastructure ──HTTP──> Python Recommendation Service
~~~

HuTube.Domain và HuTube.Application không được phụ thuộc trực tiếp vào FastAPI,
Python SDK hoặc model binary. Chi tiết gọi Python nằm trong Infrastructure thông qua
interface/abstraction của Application.

### 5.2. Python Recommendation Service và Training Worker

Service MBMF benchmark hiện được triển khai theo cấu trúc sau:

~~~text
HuTube/recommendation-service/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app, lifespan, health/readiness
│   ├── api.py                  # Internal inference endpoints
│   ├── config.py               # Environment settings
│   ├── schemas.py              # Request/response contracts
│   ├── inference.py            # Online Top-K inference
│   ├── model_registry.py       # Load/reload/version model
│   ├── recommenders/
│   │   ├── __init__.py
│   │   ├── base.py
│   │   ├── item_cf.py           # Adjusted-cosine offline baseline
│   │   └── mbmf.py
│   └── data/
│       ├── __init__.py
│       ├── models.py            # UnifiedInteraction + missing mask
│       ├── movielens.py         # ML-100K loader/validator
│       ├── mapping.py           # ID mapping + seen-item CSR
│       └── split.py             # Temporal split theo từng user
│
├── configs/
│   ├── movielens-100k.yaml
│   └── movielens-100k-smoke.yaml
├── data/                         # Dataset/artifact local, không commit lên Git
│   ├── raw/
│   │   └── movielens/
│   │       └── ml-100k/
│   ├── processed/                # Dữ liệu đã chuẩn hóa
│   ├── snapshots/                # Training snapshot theo version
│   └── artifacts/                # Model local; production dùng object storage
│
├── training/
│   ├── __init__.py
│   ├── cli.py
│   ├── config.py
│   ├── datasets.py
│   ├── losses.py
│   ├── trainer.py
│   ├── evaluate.py
│   ├── item_cf.py               # ItemCF evaluation cùng split/metrics
│   ├── comparison.py            # MBMF vs ItemCF report
│   ├── artifacts.py
│   ├── reports.py
│   └── quality_gate.py
│
├── reports/<model-version>/      # JSON/CSV/Markdown/HTML/PNG
├── tests/
├── .env.example
├── pyproject.toml
├── Dockerfile
└── README.md
~~~

Phân biệt hai thư mục cùng tên `data`:

- `app/data/` là **source code**: reader, mapping và tính trọng số.
- `data/` ở root là **dữ liệu thực tế**: MovieLens, snapshot, processed data và
  artifact local.

V1 chỉ hỗ trợ MovieLens 100K, đặt tại:

~~~text
HuTube/recommendation-service/data/raw/movielens/ml-100k/
~~~

Trong môi trường production, không đưa dataset lớn hoặc model binary vào Git.
`data/raw`, `data/processed`, `data/snapshots` và `data/artifacts` nên được
gitignore; training worker có thể đọc chúng từ volume riêng hoặc Object Storage.

DemoCF/backend hiện là CF Lab FastAPI. Các module hiện có được mapping như sau:

| Hiện tại | Vai trò |
|---|---|
| app/main.py | Khởi tạo FastAPI application |
| app/api.py | API benchmark, replay và sandbox của CF Lab |
| app/recommenders.py | Các thuật toán CF dùng chung cho nghiên cứu |
| app/benchmark.py | Chạy benchmark và lưu kết quả |
| app/metrics.py | Tính metric đánh giá |
| app/jobs.py | Chạy benchmark background |
| app/production_recommendations.py | Adapter tạo recommendation production hiện tại |
| tests/ | Unit/integration test cho CF Lab |

CF Lab có thể là nguồn để tái sử dụng recommenders, metrics và pipeline, nhưng
production service nên có contract inference riêng. Không nên để frontend HuTube
phụ thuộc vào các endpoint benchmark như /api/benchmarks hoặc /api/sandboxes.

## 6. API contract

### 6.1. Public API của .NET

~~~http
GET /api/v1/recommendations/home?limit=20
Authorization: Bearer <access-token>
~~~

Response ví dụ:

~~~json
{
  "items": [
    {
      "videoId": "video-001",
      "title": "Video mẫu",
      "thumbnailUrl": "https://...",
      "channel": {
        "channelId": "channel-001",
        "name": "HuTube Channel"
      },
      "duration": 312
    }
  ],
  "nextCursor": "...",
  "modelVersion": "mbmf_2026_09_05_v1",
  "source": "RECOMMENDATION"
}
~~~

Frontend chỉ biết response nghiệp vụ này, không biết embedding, latent vector,
behavior head hoặc raw score của model.

### 6.2. Internal API của Python

~~~http
POST /internal/recommendations
X-Service-Token: <service-token>
Content-Type: application/json
~~~

Request:

~~~json
{
  "userId": "user-001",
  "limit": 50,
  "excludeItemIds": ["item-already-seen"]
}
~~~

Response:

~~~json
{
  "modelVersion": "mbmf_2026_09_05_v1",
  "source": "REAL",
  "items": [
    {
      "itemId": "video-001",
      "score": 0.92
    },
    {
      "itemId": "video-002",
      "score": 0.87
    }
  ]
}
~~~

`itemId` là định danh generic theo `source`, không mặc định là ID video. Internal API
không được expose trực tiếp cho browser hoặc Internet nếu không cần thiết. Endpoint
yêu cầu `X-Service-Token`; contract test phải ngăn .NET và Python thay đổi không đồng
bộ. `limit` hợp lệ từ 1 đến 100; service tự loại item đã tương tác và
`excludeItemIds`.

### 6.3. Health và readiness

Python Service nên có tối thiểu:

~~~http
GET /health
GET /ready
~~~

health chỉ kiểm tra process còn sống. ready phải kiểm tra model đã load và
service có thể nhận inference.

## 7. Dữ liệu và quyền sở hữu

### 7.1. Dữ liệu đầu vào

Unified schema cho training:

~~~text
user_id
item_id
rating
like
dislike
comment
share
watch_ratio
source
timestamp
~~~

Quy ước:

- NULL nghĩa là không có tín hiệu; không tự động đổi thành 0 nếu chưa có rule.
- 0 là một giá trị hợp lệ và phải được phân biệt với NULL.
- Video bị xóa hoặc không hợp lệ không được đưa vào catalog public.
- MovieLens chỉ dùng cho benchmark, không trộn vào production dataset của HuTube.

### 7.2. Quyền sở hữu dữ liệu

| Dữ liệu | Owner | Python được làm gì? |
|---|---|---|
| User, Video, quyền truy cập | .NET / HuTube DB | Đọc dữ liệu snapshot cần thiết |
| Raw interaction | HuTube / event pipeline | Đọc để tạo snapshot |
| Training snapshot | Training pipeline | Đọc và biến đổi |
| Model artifact | Model registry/storage | Tạo version, load và reload |
| Public recommendation DTO | .NET API | Quyết định và trả về frontend |

Python không được trở thành nguồn sự thật thứ hai cho User, Video hoặc permission.

## 8. Fallback, timeout và lỗi

Luồng fallback của .NET:

~~~text
Gọi Python
   ├── Thành công → hydrate + filter → recommendation feed
   ├── Timeout   → popular/recent fallback
   ├── HTTP 5xx  → popular/recent fallback
   ├── Model not ready → cold-start fallback
   └── User chưa đủ tín hiệu → cold-start / trending fallback
~~~

> Cấu hình đề xuất:

~~~env
RECOMMENDER_BASE_URL=http://recommendation-service:8000
RECOMMENDER_SERVICE_TOKEN=
RECOMMENDER_TIMEOUT_MS=2000
RECOMMENDATION_DEFAULT_LIMIT=20
RECOMMENDATION_MAX_LIMIT=100
~~~

Timeout phải ngắn hơn ngưỡng chấp nhận của Home API. Fallback không được gọi ngược
lại Python đang lỗi.

## 9. Bảo mật và triển khai

### 9.1. Bảo mật

- Python endpoint inference chỉ cho phép service-to-service traffic.
- Dùng private network, service token hoặc mTLS tùy môi trường deploy.
- Không gửi access token của User sang Python nếu Python không cần token đó.
- Không ghi secret, raw token hoặc dữ liệu cá nhân nhạy cảm vào log.
- Model artifact phải có version, checksum và quyền đọc phù hợp.
- Admin retrain/rollback phải đi qua .NET authorization, không mở endpoint quản trị
  trực tiếp trên Python cho frontend.

### 9.2. Process triển khai

~~~text
1. HuTube API                  .NET Core
2. Recommendation Service     Python FastAPI
3. Training Worker             Python process/job
4. HuTube PostgreSQL           System of record
5. Model Storage               Persistent volume hoặc Cloudflare R2
~~~

Trong môi trường local có thể chạy bằng Docker Compose hoặc mở ba process riêng.
Training Worker không cần chạy cùng lifecycle với online Recommendation Service.

## 10. Model lifecycle

~~~text
Raw Events
  ↓
Snapshot
  ↓
Train
  ↓
Evaluate
  ↓
Register version
  ↓
Quality gate
  ↓
Promote
  ↓
Atomic reload
  ↓
Monitor / rollback
~~~

Model artifact nên chứa tối thiểu:

~~~text
data/artifacts/<model-version>/
├── model.pt
├── config.yaml
├── metrics.json
├── metadata.json
├── user_index.json
├── item_index.json
├── item_metadata.json
├── item_popularity.json
├── seen_items.npz
└── quality_gate.json
~~~

Version benchmark có dạng `mbmf_ml100k_<UTC timestamp>_<config hash>`. Metadata
MovieLens bắt buộc ghi `source=MOVIELENS` và `deployable=false`; pipeline chỉ cập nhật
`benchmark-latest.json`, không tạo production pointer. Artifact production sau này
chỉ chấp nhận source `BOT` hoặc `REAL`.

MBMF có thể blend preference score với log-popularity prior. Trọng số được chọn trên
validation, lưu trong `metadata.ranking.popularityWeight` và dùng lại ở FastAPI để
offline evaluation không lệch online inference.

Report tương ứng nằm trong `reports/<model-version>` và gồm `metrics.json`,
`metrics.csv`, `training_history.csv`, `dataset_summary.csv`, `summary.md`, HTML tự
chứa cùng các biểu đồ PNG. Metric không có dữ liệu quan sát phải ghi `N/A`, không
được thay bằng 0.

Các lệnh terminal chính:

~~~powershell
py -3.11 -m training.cli validate-data --data-dir data/raw/movielens/ml-100k
py -3.11 -m training.cli train --config configs/movielens-100k.yaml
py -3.11 -m training.cli evaluate --artifact data/artifacts/<model-version>
py -3.11 -m training.cli report --artifact data/artifacts/<model-version>
py -3.11 -m training.cli quality-gate --artifact data/artifacts/<model-version>
py -3.11 -m training.cli compare-item-cf --artifact data/artifacts/<model-version> --neighbors 50
~~~

Service phải load model vào memory trước khi promote. `ALLOW_BENCHMARK_MODEL=false`
là mặc định; local demo phải bật rõ ràng. Môi trường production luôn từ chối artifact
`deployable=false`.

## 11. Testing architecture

### Python

- Unit test cho User-Based CF, Item-Based CF, MF/BPR/MBMF.
- Test NULL/0, weighting, mapping và exclude list.
- Test model save/load và reload atomic.
- API contract test cho /internal/recommendations.
- Benchmark test với seed cố định và cùng dataset.

### .NET

- Unit test PythonRecommendationClient.
- Unit test timeout, 5xx, malformed response và fallback.
- Test lọc video Deleted/Private/Blocked/Restricted.
- Integration test public Recommendation API.

### End-to-end

~~~text
Interaction → Snapshot → Train → Model Artifact
             → Python Inference → .NET Hydrate/Filter → Frontend Feed
~~~

E2E tối thiểu phải kiểm tra cả trường hợp Python service unavailable nhưng Home vẫn
trả được fallback.

## 12. Quy tắc không được phá vỡ

1. Không cho Frontend gọi trực tiếp Python Recommendation Service.
2. Không đưa auth, permission và video visibility vào model service.
3. Không để HuTube.Domain phụ thuộc Python hoặc FastAPI.
4. Không chạy training nặng trong request online.
5. Không lưu model binary trong Git.
6. Không trộn MovieLens vào production training dataset.
7. Không để Python trả full Video DTO thay cho .NET.
8. Không để recommendation service failure làm Home API chết.
9. Mọi model được deploy phải có version, mapping và metric.
10. Mọi thay đổi internal contract phải cập nhật contract test và tài liệu này.

## 13. Tài liệu liên quan

- [Project Architecture](./PROJECT_ARCHITECTURE.md)
- [Tech Stack](./TECH_STACK.md)
- [Module CF](../features/Module_CF.md)
- [Sprint 7 - Recommendation](../features/Sprint7.md)
- [CF Lab README](../../../DemoCF/README.md)
