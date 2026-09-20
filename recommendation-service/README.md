# HuTube Pure Collaborative Filtering Service

Service này chỉ triển khai hai thuật toán lọc cộng tác được viết trực tiếp bằng
NumPy:

- **User-Based CF**: tìm những user có lịch sử tương tác giống user hiện tại,
  sau đó dùng các user lân cận để chấm điểm item chưa xem.
- **Item-Based CF**: tìm những item giống các item user hiện tại đã tương tác,
  sau đó cộng dồn điểm tương đồng để xếp hạng item chưa xem.

Đây là một benchmark độc lập cho đề tài HuTube. Service không dùng mô hình neural,
embedding, thư viện recommender có sẵn hoặc feature genre/title để tạo điểm. Genre
chỉ được dùng sau khi dự đoán để đo mức khớp sở thích trong evaluation và tính diversity.

## 1. Luồng tổng thể

```text
MovieLens u.data/u.item/u.genre
              |
              v
       validate-data + unified CSV
              |
              v
       complete interaction history
              |
              v
        interaction matrix X
          /              \
         v                v
  User-Based CF       Item-Based CF
   user-user sim       item-item sim
         \              /
          v            v
       predict -> evaluate -> compare -> report
                                      |
                                      v
                         user_based.npz/item_based.npz
                                      |
                                      v
                              FastAPI inference
```

Quá trình `train` là quá trình **rebuild offline**: đọc toàn bộ dữ liệu trong
snapshot, tính lại ma trận similarity và ghi artifact. Khi user mở Home, FastAPI
không train lại; nó load artifact vào memory rồi tính Top-K từ ma trận đã rebuild.
Một lần rebuild không tự biết các tương tác phát sinh sau đó, vì vậy dữ liệu mới
chỉ có hiệu lực sau lần rebuild kế tiếp.

## 2. Công thức cốt lõi

Gọi `X[u, i]` là rating của user `u` cho item `i`. Nếu chưa có rating thì ô đó
bằng 0 trong ma trận tính toán; điều này không biến thành một behavior giả.

### User-Based CF

Độ tương đồng cosine giữa hai user:

```text
sim(u, v) = sum_i X[u,i] X[v,i]
            --------------------------------
            sqrt(sum_i X[u,i]^2) sqrt(sum_i X[v,i]^2)
```

Với item `j` chưa được user `u` xem, điểm dự đoán là trung bình có trọng số của
các user lân cận đã có rating cho `j`:

```text
score(u, j) = sum_v sim(u,v) X[v,j]
              --------------------------
              sum_v sim(u,v)
```

Chỉ các similarity dương và tối đa `neighbor_count` hàng xóm mạnh nhất được dùng.
Nếu không có hàng xóm nào biết item đó, hệ thống dùng item mean tính trên tập fit
làm fallback xác định.

### Item-Based CF

Mỗi item được xem như một vector theo user. Độ tương đồng giữa hai item:

```text
sim(i, j) = sum_u X[u,i] X[u,j]
            --------------------------------
            sqrt(sum_u X[u,i]^2) sqrt(sum_u X[u,j]^2)
```

Điểm cho item ứng viên `j` được suy ra từ các item `i` mà user `u` đã tương tác:

```text
score(u, j) = sum_i sim(j,i) X[u,i]
              --------------------------
              sum_i sim(j,i)
```

Sau đó hệ thống loại item đã xem và item nằm trong `excludeItemIds`, sắp xếp giảm
dần theo score, rồi trả tối đa `limit` item.

### Ví dụ nhỏ

Giả sử:

```text
User A: video 1, 2, 3
User B: video 3, 5, 6
User C: video 2, 3, 4
```

Vector nhị phân của A và C có hai item chung là 2 và 3, nên:

```text
cos(A,C) = 2 / (sqrt(3) * sqrt(3)) = 2/3
```

Vector của B và C chỉ chung item 3, nên `cos(B,C) = 1/3`. Vì A gần C hơn B,
User-Based CF ưu tiên các item mà A đã xem nhưng C chưa xem là video 1; sau đó
các item mới từ B là video 5 và 6. Kết quả kỳ vọng là `[1, 5, 6]` sau khi loại
`2, 3, 4`.

Item-Based CF giải cùng tình huống theo chiều ngược lại: xem các video 2, 3, 4
của C, tìm video nào có vector người xem tương tự chúng, rồi cộng điểm từng
video ứng viên.

## 3. Cấu trúc thư mục

```text
recommendation-service/
├── app/
│   ├── api.py                       # /health, /ready, /internal/recommendations
│   ├── config.py                    # biến môi trường và model_type đang phục vụ
│   ├── inference.py                 # map userId/excludeItemIds -> Top-K
│   ├── main.py                      # tạo FastAPI app và lifespan load artifact
│   ├── model_registry.py             # load user_based.npz hoặc item_based.npz
│   ├── schemas.py                   # request/response API
│   ├── data/
│   │   ├── models.py                # UnifiedInteraction, nullable behavior và mask
│   │   ├── movielens.py             # đọc/validate ML-100K, title, genre
│   │   └── mapping.py               # ID <-> index và seen-items CSR
│   └── recommenders/
│       ├── base.py                  # protocol chung của hai model
│       ├── similarity.py             # ma trận X, cosine/Jaccard, Top-K neighbor
│       ├── user_cf.py               # User-Based CF từ công thức
│       └── item_cf.py               # Item-Based CF từ công thức
├── training/
│   ├── cli.py                       # validate-data/train/evaluate/report/compare
│   ├── config.py                    # cấu hình YAML và validation
│   ├── trainer.py                   # fit hai model bằng NumPy
│   ├── evaluate.py                  # preference alignment, coverage, diversity, novelty
│   ├── artifacts.py                 # lưu và version hóa artifact
│   ├── comparison.py                # bảng so sánh hai model
│   ├── reports.py                   # Markdown, HTML, CSV, JSON, PNG
│   └── quality_gate.py              # kiểm tra artifact trước khi dùng
├── configs/
│   ├── movielens-100k.yaml          # cấu hình benchmark đầy đủ
│   └── movielens-100k-smoke.yaml    # chạy nhanh với 40 user
├── data/
│   ├── raw/movielens/ml-100k/       # dataset local, không commit
│   ├── processed/                   # unified_interactions.csv
│   ├── snapshots/                   # chỗ dành cho snapshot HuTube sau này
│   └── artifacts/                   # model artifacts, không commit
├── reports/                         # report sinh tự động, không commit
├── tests/                           # test công thức, pipeline, artifact và API
├── Dockerfile
├── .env.example
└── pyproject.toml
```

## 4. Dữ liệu và schema

`UnifiedInteraction` giữ schema chung để sau này nhận dữ liệu HuTube:

```text
user_id, item_id, rating,
like, dislike, comment, share, watch_ratio,
source, timestamp
```

Với MovieLens, chỉ `rating`, `user_id`, `item_id`, `source=MOVIELENS` và timestamp
được quan sát. `like`, `dislike`, `comment`, `share`, `watch_ratio` vẫn tồn tại
nhưng là `NULL`; không suy diễn rating 4/5 thành Like hoặc watch ratio. Missing mask
được tạo bằng `value is not null`, nên giá trị `0` nếu có thật vẫn có mask bằng 1.

`u.data` là nguồn rating. `u.item` và `u.genre` chỉ phục vụ tên item, genre và
đánh giá diversity. Không dùng demographic từ `u.user` làm feature.

Không dùng exact-item holdout. Toàn bộ lịch sử quan sát của user được dùng để xây
profile sở thích đánh giá. Với MovieLens, các rating từ `4` trở lên được dùng làm
tín hiệu ưu tiên; nếu user chưa có rating cao thì dùng toàn bộ rating của user.
Genre chỉ được dùng ở bước evaluation để xem danh sách Top-K có khớp các genre mà
user thường thích hay không. Hai model vẫn chỉ fit và ranking bằng interaction
matrix, không nhận genre làm feature.

## 5. Chạy bằng terminal

Mở PowerShell tại thư mục service:

```powershell
cd F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\HuTube\recommendation-service
```

Nếu cần tạo môi trường mới:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
```

### Kiểm tra dataset

```powershell
py -3.11 -m training.cli validate-data `
  --data-dir data/raw/movielens/ml-100k
```

Ở chế độ strict, loader phải thấy 100.000 ratings, 943 users, 1.682 items và
19 genres.

### Smoke train

```powershell
py -3.11 -m training.cli train `
  --config configs/movielens-100k-smoke.yaml
```

### Full train và so sánh

```powershell
py -3.11 -m training.cli train `
  --config configs/movielens-100k.yaml

py -3.11 -m training.cli evaluate `
  --artifact data/artifacts/<model-version>

py -3.11 -m training.cli compare `
  --artifact data/artifacts/<model-version>

py -3.11 -m training.cli report `
  --artifact data/artifacts/<model-version>

py -3.11 -m training.cli quality-gate `
  --artifact data/artifacts/<model-version>
```

`train` luôn fit cả hai model trên toàn bộ interaction history trong cùng một
artifact version. `compare` tạo bảng winner theo từng metric. Preference alignment,
genre coverage, catalog coverage và diversity càng cao càng tốt; novelty dùng để
đánh giá mức khám phá item ít phổ biến hơn. Các metric này không yêu cầu model phải
đoán đúng một item ID bị che.

## 6. Artifact và report

Một artifact hợp lệ có dạng:

```text
data/artifacts/<model-version>/
├── user_based.npz              # similarity user-user và interaction matrix
├── item_based.npz              # similarity item-item và interaction matrix
├── config.yaml
├── metrics.json
├── training_history.json
├── metadata.json
├── user_index.json
├── item_index.json
├── item_metadata.json
├── seen_items.npz
└── quality_gate.json
```

Version có dạng `cf_ml100k_<UTC timestamp>_<config hash>`. Metadata benchmark ghi
`source=MOVIELENS`, `deployable=false` và cả hai `modelTypes`. Service production
sẽ từ chối artifact benchmark; local demo phải bật rõ `ALLOW_BENCHMARK_MODEL=true`.
File `benchmark-latest.json` chỉ là pointer local, không phải production pointer.

Report nằm tại `reports/<model-version>/` và gồm:

- `metrics.json`, `metrics.csv`, `training_history.csv`, `dataset_summary.csv`;
- `summary.md`, `report.html` tự chứa, mở offline không cần CDN;
- `cf_comparison.json/csv/md/html/png` để so sánh User-Based và Item-Based;
- biểu đồ preference alignment, catalog coverage, diversity, rating distribution,
  behavior coverage, missing coverage và metric theo version.

Binary behavior, watch ratio, fallback rate và cold-start rate được ghi là `N/A`
khi MovieLens không có quan sát tương ứng; service không thay số 0 giả vào report.

## 7. FastAPI inference

Chạy local bằng artifact benchmark:

```powershell
$env:ALLOW_BENCHMARK_MODEL = "true"
$env:RECOMMENDER_SERVICE_TOKEN = "local-token"
$env:MODEL_TYPE = "item_based"       # hoặc user_based
py -3.11 -m uvicorn app.main:app --host 127.0.0.1 --port 8091
```

Endpoint nội bộ:

```http
GET /health
GET /ready
POST /internal/recommendations
X-Service-Token: local-token
```

Request:

```json
{
  "userId": "196",
  "limit": 20,
  "excludeItemIds": ["242"]
}
```

Response dùng `itemId + source`, không gọi MovieLens ID là `videoId`:

```json
{
  "modelVersion": "cf_ml100k_...",
  "source": "MOVIELENS",
  "items": [
    {"itemId": "50", "score": 4.12}
  ]
}
```

`MODEL_TYPE` quyết định model đang phục vụ; đổi từ `item_based` sang `user_based`
chỉ cần đổi biến môi trường rồi restart process. API không train lại tại request.
Token sai trả 401, model chưa load trả 503, user không có trong artifact trả 404,
request sai trả 422.

## 8. Kiểm thử và chất lượng

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check app training tests
```

Test bao phủ:

- cosine/Jaccard và lựa chọn neighbor dương;
- ví dụ User-Based A/B/C và loại item đã xem;
- hai model fit/evaluate trên dữ liệu synthetic;
- xây dựng user preference profile từ complete history;
- nullable behavior và mask `NULL` khác giá trị 0;
- artifact save/load cho recommendation giống nhau;
- quality gate bắt buộc đủ hai model;
- API token, unknown user, exclude item, no-model và request validation;
- HTML report không phụ thuộc Internet.

MovieLens, artifact, report, cache và virtual environment đã được gitignore. Không
đưa dataset hoặc model benchmark vào repository.

## 9. Phạm vi hiện tại

- V1 chỉ benchmark MovieLens 100K.
- Chỉ có User-Based CF và Item-Based CF; không còn pipeline MBMF/neural.
- Genre/title chưa tham gia vào CF score; chỉ dùng cho preference evaluation và diversity.
- Chưa tích hợp HttpClient hoặc adapter của Backend .NET.
- Artifact MovieLens chỉ dùng cho benchmark/local demo, chưa được promote production.
