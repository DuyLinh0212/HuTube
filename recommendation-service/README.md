# HuTube Recommendation Service

Service FastAPI cho hai biến thể Collaborative Filtering thuần:

- User-Based CF: tìm user có lịch sử tương tác tương tự.
- Item-Based CF: tìm video tương tự với các video user đã tương tác.

Pipeline hiện tại tập trung vào việc xây dựng ma trận tương đồng, tính điểm Top-K
và đo chi phí chạy. Không sinh chỉ số offline để kết luận video có phù hợp hoặc
được user yêu thích hay không, vì dữ liệu benchmark chưa có nhãn phù hợp độc lập.

## Pipeline

```text
MovieLens / UnifiedInteraction
          |
          v
Ma trận user-item X
          |
          +--> similarity giữa user-user  --> User-Based CF
          |
          +--> similarity giữa item-item  --> Item-Based CF
                                      |
                                      v
                             score item chưa xem
                                      |
                                      v
                                  Top-K
                                      |
                                      v
                       runtime + complexity report
```

`train` là bước rebuild offline: tính similarity, lưu artifact và ghi lại thời
gian fit của từng biến thể. Request FastAPI chỉ load artifact và ranking.

## Công thức chính

### Cosine similarity

Với hai vector tương tác `a` và `b`:

```text
sim_cos(a,b) = (sum_t a_t*b_t)
               / (sqrt(sum_t a_t^2) * sqrt(sum_t b_t^2))
```

Item-Based dùng `X.T` để mỗi item trở thành một vector theo user:

```text
S_item = similarity(X.T, X.T)
```

User-Based dùng trực tiếp các hàng của `X`:

```text
S_user = similarity(X, X)
```

### Jaccard và Pearson

```text
sim_jaccard(A,B) = |A ∩ B| / |A ∪ B|
```

Jaccard chỉ nhìn việc có hoặc không có tương tác. Pearson đo tương quan giữa các
rating cùng được quan sát sau khi trừ trung bình rating. Sáu biến thể được train
là ba similarity cho mỗi family User-Based và Item-Based.

### Điểm xếp hạng User-Based

Gọi `N(u)` là các user gần nhất và `s_uv` là similarity giữa user `u`, `v`:

```text
score_U(u,i) =
  sum_v s_uv * X[v,i] * 1[X[v,i] > 0]
  ------------------------------------------------
  sum_v s_uv * 1[X[v,i] > 0]
```

Chỉ các neighbor có tương tác với item ứng viên mới đóng góp vào mẫu số. Nếu
mẫu số bằng 0, code dùng item mean làm fallback.

### Điểm xếp hạng Item-Based

Gọi `H(u)` là lịch sử video của user `u`, `N(i)` là các item gần item ứng viên:

```text
score_I(u,i) =
  sum_j sim(i,j) * X[u,j]
  ------------------------
  sum_j sim(i,j)
```

Trong đó `j` thuộc phần giao giữa lịch sử `H(u)` và neighbor list của `i`.
Video đã xem hoặc nằm trong `excludeItemIds` được loại khỏi danh sách cuối.

## Luồng tính Top-K

```text
X
  -> tính similarity
  -> giữ tối đa neighbor_count neighbor
  -> tính score cho từng video chưa xem
  -> loại video đã xem/exclude
  -> sort giảm dần
  -> lấy K video đầu tiên
```

`neighbor_count` là số hàng xóm dùng trong công thức. `K` là số video trả về.
Hai tham số này khác nhau.

## Report runtime

Report chỉ giữ các thông tin kỹ thuật:

- `fit_seconds`: thời gian train từng biến thể User-Based/Item-Based.
- `total_fit_seconds`: tổng thời gian train các biến thể.
- thời gian dựng ma trận;
- thời gian tính similarity;
- thời gian chọn neighbor;
- tổng wall-clock time;
- peak memory ước tính;
- speedup so với baseline dense.

Các file được tạo trong `reports/<model-version>/`:

- `report.html`: report HTML tự chứa;
- `summary.md`: bản Markdown để đọc nhanh;
- `training_history.csv`: thời gian fit từng model;
- `cf_comparison.csv` và `cf_comparison.html`: so sánh runtime;
- `complexity_benchmark.csv` và `complexity_benchmark.json`;
- `complexity_cost.png`: biểu đồ thời gian và bộ nhớ.

Không dùng report runtime để kết luận model nào đề xuất phù hợp hơn. Khi HuTube
có dữ liệu thật, mức độ phù hợp cần được đo bằng phản hồi hoặc hành vi người dùng
được thu thập riêng.

## Benchmark chi phí Item-Based

Benchmark hiện tại đo chi phí dựng similarity Cosine dense trên cùng dataset:

| Chiến lược | Pair slots | Tổng thời gian | Peak ước tính | Speedup |
|---|---:|---:|---:|---:|
| Baseline dense | 1,413,721 | 4.500 s | 17.81 MiB | 1.00× |

Các tối ưu đang có:

1. Dùng NumPy và `float32` cho phép nhân ma trận vector hóa.
2. Chỉ giữ tối đa `neighbor_count` neighbor sau khi tính similarity.
3. Pearson tính theo block để giảm tensor trung gian.
4. Training chạy offline; request online chỉ load artifact và ranking.

Hướng tối ưu tiếp theo:

1. Sparse co-occurrence hoặc inverted index để bỏ qua cặp không giao nhau.
2. Min-overlap threshold để loại similarity sinh từ quá ít quan sát.
3. Lưu top-neighbor sparse thay vì full similarity khi quy mô catalog tăng.
4. Cache score hoặc candidate set cho user hoạt động thường xuyên.

## Cấu trúc chính

```text
recommendation-service/
├── app/
│   ├── api.py
│   ├── inference.py
│   ├── model_registry.py
│   └── recommenders/
│       ├── similarity.py
│       ├── user_cf.py
│       └── item_cf.py
├── training/
│   ├── cli.py
│   ├── trainer.py
│   ├── complexity.py
│   ├── reports.py
│   ├── comparison.py
│   └── quality_gate.py
├── configs/
├── data/
├── reports/
└── tests/
```

## Chạy

Mở PowerShell tại service:

```powershell
cd F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\HuTube\recommendation-service
```

Kiểm tra dataset:

```powershell
.\.venv\Scripts\python.exe -m training.cli validate-data `
  --data-dir data/raw/movielens/ml-100k
```

Train đầy đủ sáu biến thể:

```powershell
.\.venv\Scripts\python.exe -m training.cli train `
  --config configs/movielens-100k.yaml
```

Sinh lại report runtime từ artifact:

```powershell
.\.venv\Scripts\python.exe -m training.cli report `
  --artifact data/artifacts/<model-version>
```

Xem runtime đã lưu:

```powershell
.\.venv\Scripts\python.exe -m training.cli evaluate `
  --artifact data/artifacts/<model-version>
```

Chạy kiểm thử:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check app training tests
```

## Artifact

Mỗi artifact chứa các file model, mapping, cấu hình, metadata, `metrics.json` với
runtime payload và `training_history.json`. Artifact MovieLens có
`source=MOVIELENS` và `deployable=false`, không được promote trực tiếp vào
production.

FastAPI nhận `userId`, `limit`, `excludeItemIds` và trả về `itemId`, `score`,
`modelVersion`, `source`. Backend .NET chịu trách nhiệm hydrate metadata, kiểm tra
quyền và lọc video private/deleted/blocked.

## Tích hợp HuTube và cập nhật model

Super Admin dùng `/recommendations` trên admin web. Backend .NET tạo một dòng CSV cho mỗi cặp user–video từ PostgreSQL, ghi CSV vào `collaborative_cf/YYYY/MM/DD/` trên R2, rồi gọi `POST /internal/model/train` với `X-Model-Admin-Token`, khóa CSV và SHA-256. Endpoint chỉ huấn luyện **Item-Based Cosine**. Artifact được lưu trên R2; `collaborative_cf/active.json` công bố phiên bản đang hoạt động. Khi khởi động lại, service xác minh hash artifact và nạp model từ R2 vào bộ nhớ. Model cũ tiếp tục phục vụ nếu cập nhật thất bại.

`POST /internal/recommendations` yêu cầu `X-Service-Token` riêng. Browser không gọi service Python. Backend truyền lịch sử xem mới nhất trong `excludeItemIds` và lọc kết quả lần cuối, kể cả video phổ biến bù. MovieLens và sáu biến thể CF vẫn có thể benchmark local bằng pipeline benchmark riêng.

Để huấn luyện thủ công từ CSV đã xuất, chỉ rõ file thật:

```powershell
python -m training.train_hutube --matrix-csv interactions_current.csv
```

File cần có `user_id`, `video_id`, `score`, tối thiểu 2 user, 2 video và 3 cặp. `score` phải là giá trị chuẩn hóa trong `[0,1]`; production nhận thêm `scoreAggregation` với `mode` là `average` (mặc định) hoặc `weighted` và map trọng số cho `rating`, `like`, `dislike`, `watch`, `comment`, `subscribe`. Không có dữ liệu giả hoặc tự nạp dữ liệu từ simulator cũ.

Local: cấu hình hai token riêng và các biến `R2_*` trong `.env` (xem `.env.example`), đặt `Recommendation__ServiceUrl`, `Recommendation__ServiceToken`, `Recommendation__AdminToken` cùng thông tin `Storage__R2__*` cho API .NET. Chạy `./scripts/run-recommender.ps1`; script chỉ bind `127.0.0.1`. Trên Render, cấu hình các biến trong `render.yaml`; web miễn phí có thể ngủ và request đầu có thể rơi về feed mặc định.

## Giới hạn và Hướng phát triển tiếp theo

- Đã tích hợp hoàn tất HttpClient với Backend .NET và bảng tin Trang chủ.
- Hiện hỗ trợ cả tập dữ liệu MovieLens 100K benchmark lẫn dữ liệu tương tác thực tế / mô phỏng của HuTube.
- Hướng phát triển tiếp theo: Hybrid Recommendation kết hợp giữa Collaborative Filtering (CF) và Content-Based Filtering (dựa trên thể loại, tag, mô tả video).
