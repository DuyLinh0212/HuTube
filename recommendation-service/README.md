# HuTube MBMF Recommendation Service

Service này cung cấp pipeline benchmark MovieLens 100K và API inference nội bộ cho
mô hình Multi-Behavior Matrix Factorization (MBMF). Artifact MovieLens chỉ dùng để
kiểm chứng thuật toán, luôn có `source=MOVIELENS`, `deployable=false` và không được
promote thành model production.

## Phạm vi hiện tại

- Shared user/item embedding và các head `rating`, `like`, `dislike`, `comment`,
  `share`, `watch_ratio`, `preference`.
- Item-Based CF adjusted-cosine dùng làm baseline so sánh offline với MBMF.
- MBMF ranking blend thêm popularity prior được chọn bằng validation; full config
  hiện dùng `popularity_weight=0.20`.
- MovieLens chỉ có quan sát cho `rating`; BPR `preference` được tạo từ rating >= 4.
- Không suy diễn rating thành like, dislike, comment, share hoặc watch ratio.
- Data validation, temporal split, model selection, final refit, evaluation,
  artifact, report, quality gate và inference là các bước tách biệt.
- Chưa tích hợp với Backend .NET.

## Cấu trúc

```text
recommendation-service/
├── app/                    # FastAPI, registry, inference, schema và MBMF
├── training/               # CLI, trainer, loss, metrics, artifact, report, quality gate
├── configs/                # Full và smoke configuration
├── data/
│   ├── raw/                # MovieLens local, không commit
│   ├── processed/          # Unified CSV local
│   ├── snapshots/          # Dữ liệu BOT/REAL trong tương lai
│   └── artifacts/          # Model artifact local
├── reports/                # JSON/CSV/Markdown/HTML/PNG local
└── tests/                  # Synthetic tests; không tải MovieLens trong CI
```

## Cài đặt trên Windows

Yêu cầu Python 3.11.

```powershell
cd HuTube/recommendation-service
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
```

Dữ liệu MovieLens phải nằm tại:

```text
data/raw/movielens/ml-100k/
├── u.data
├── u.item
├── u.genre
└── u.info
```

Thư mục `data/raw` bị Git bỏ qua vì giấy phép MovieLens không cho phép phân phối
lại dataset cùng source code.

## Chạy pipeline bằng terminal

```powershell
# Kiểm tra đúng 100.000 ratings, 943 users, 1.682 items, 19 genres
.\.venv\Scripts\python.exe -m training.cli validate-data `
  --data-dir data/raw/movielens/ml-100k

# Smoke train nhanh trên 40 users
.\.venv\Scripts\python.exe -m training.cli train `
  --config configs/movielens-100k-smoke.yaml

# Full benchmark
.\.venv\Scripts\python.exe -m training.cli train `
  --config configs/movielens-100k.yaml

# Tính lại test metrics và tạo lại report
.\.venv\Scripts\python.exe -m training.cli evaluate `
  --artifact data/artifacts/<model-version>
.\.venv\Scripts\python.exe -m training.cli report `
  --artifact data/artifacts/<model-version>

# Chạy quality gate độc lập
.\.venv\Scripts\python.exe -m training.cli quality-gate `
  --artifact data/artifacts/<model-version>

# So sánh MBMF với Item-Based CF trên cùng temporal split
.\.venv\Scripts\python.exe -m training.cli compare-item-cf `
  --artifact data/artifacts/<model-version> `
  --neighbors 50
```

Mỗi lần train tạo `data/artifacts/<model-version>` và
`reports/<model-version>`. File `data/artifacts/benchmark-latest.json` chỉ trỏ tới
benchmark gần nhất; không có production pointer.

Artifact cải tiến lưu thêm `item_popularity.json` và metadata ranking policy để
FastAPI dùng đúng scoring với offline evaluation. Lệnh `compare-item-cf` tạo thêm
`item_cf_comparison.json`, CSV, Markdown, HTML tự
chứa và PNG trong report directory. Item-Based CF chỉ là baseline offline, không
được load bởi FastAPI và không thay thế artifact MBMF.

## Chạy API local

Sao chép `.env.example` thành `.env`, đặt token local và giữ
`ALLOW_BENCHMARK_MODEL=true` khi muốn demo artifact MovieLens:

```powershell
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

```http
GET /health
GET /ready
POST /internal/recommendations
X-Service-Token: <token>
Content-Type: application/json

{
  "userId": "196",
  "limit": 20,
  "excludeItemIds": ["242"]
}
```

Response chỉ chứa định danh generic theo nguồn dữ liệu:

```json
{
  "modelVersion": "mbmf_ml100k_...",
  "source": "MOVIELENS",
  "items": [{"itemId": "50", "score": 0.92}]
}
```

`ALLOW_BENCHMARK_MODEL=false` là mặc định trong code. Ở production, artifact
`deployable=false` luôn bị từ chối dù biến này được bật.

## Kiểm thử

```powershell
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest
```

CI chỉ dùng fixture synthetic; không tải và không commit MovieLens.

## Docker CPU

```powershell
docker build -t hutube-recommendation-service .
docker run --rm -p 8000:8000 `
  -e RECOMMENDER_SERVICE_TOKEN=local-token `
  -e ALLOW_BENCHMARK_MODEL=true `
  -v "${PWD}/data/artifacts:/service/data/artifacts:ro" `
  hutube-recommendation-service
```
