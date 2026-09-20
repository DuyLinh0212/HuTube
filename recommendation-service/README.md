# HuTube Recommendation Service — Pure Collaborative Filtering

Service này là benchmark thuần Collaborative Filtering viết trực tiếp bằng
NumPy, không dùng neural network, embedding, thư viện recommender có sẵn hoặc
genre/title để tạo điểm đề xuất.

Có sáu biến thể được train và so sánh trong cùng một lần chạy:

| Nhóm | Cosine | Jaccard | Pearson |
|---|---:|---:|---:|
| User-Based CF | Có | Có | Có |
| Item-Based CF | Có | Có | Có |

Mục tiêu của benchmark là trả lời câu hỏi: **với cùng dữ liệu tương tác, cách
nhìn theo user hay theo item và cách đo similarity nào tạo ra danh sách có bằng
chứng cộng tác mạnh hơn?**

## 1. Luồng xử lý

```text
MovieLens u.data
      |
      v
validate + UnifiedInteraction + interaction matrix X
      |
      +--> User-Based: similarity giữa các hàng user-user
      |        +--> score item chưa xem --> Top-K
      |
      +--> Item-Based: similarity giữa các cột item-item
               +--> score item chưa xem --> Top-K
      |
      v
Collaborative Support@10/@20/@30 + diagnostics
      |
      v
artifact sáu model + report.html + bảng so sánh
```

`train` là rebuild offline. Nó tính lại similarity và ghi artifact. Khi FastAPI
được gọi, service load một artifact đã rebuild rồi xếp hạng trên ma trận đó; nó
không train lại tại request.

## 2. Ma trận tương tác

Gọi `X[u, i]` là rating của user `u` cho item `i`.

- MovieLens dùng rating 1–5 làm tín hiệu duy nhất.
- Ô chưa quan sát được giữ bằng 0 trong ma trận tính toán, nhưng không được
  hiểu là rating 0.
- `like`, `dislike`, `comment`, `share`, `watch_ratio` vẫn có trong
  `UnifiedInteraction` nhưng là `NULL` và missing mask bằng 0.
- Jaccard chỉ nhìn item có/không có tương tác; nó không dùng độ lớn rating.
- Không dùng `u.user` hoặc demographic làm feature.

## 3. Ba công thức similarity

### 3.1 Cosine

Với hai vector `a` và `b`:

\[
sim_{cos}(a,b)=
\frac{\sum_t a_t b_t}
{\sqrt{\sum_t a_t^2}\sqrt{\sum_t b_t^2}}
\]

Cosine đo góc giữa hai vector. Trong benchmark rating, rating càng lớn thì
đóng góp càng lớn; với mode binary, mọi tương tác có giá trị 1.

### 3.2 Jaccard

Jaccard dùng tập item đã tương tác:

\[
sim_{jac}(A,B)=\frac{|A\cap B|}{|A\cup B|}
\]

Ví dụ A đã xem `{1, 2, 3}`, B đã xem `{2, 3, 5}` thì:

\[
J(A,B)=\frac{2}{4}=0.5
\]

Jaccard phù hợp khi điều quan trọng là **có cùng xem hay không**, không quan
tâm user chấm 3 hay 5 điểm.

### 3.3 Pearson

Pearson đo mức tương quan sau khi trừ trung bình rating:

\[
sim_{pearson}(a,b)=
\frac{\sum_t(a_t-\bar a)(b_t-\bar b)}
{\sqrt{\sum_t(a_t-\bar a)^2}
 \sqrt{\sum_t(b_t-\bar b)^2}}
\]

Chỉ các vị trí mà cả hai phía đều có quan sát mới được dùng. Vì vậy user có
thói quen chấm cao và user hay chấm thấp vẫn có thể tương quan dương nếu thứ tự
sở thích giống nhau. Pearson có thể âm; similarity âm được xem là
counter-evidence và không được dùng để cộng điểm đề xuất.

## 4. User-Based CF

User-Based xem mỗi user là một vector item. Từ user cần đề xuất `u`, hệ thống:

1. Tính `sim(u, v)` với các user khác bằng Cosine, Jaccard hoặc Pearson.
2. Chọn tối đa `neighbor_count` user có similarity dương cao nhất.
3. Với mỗi item chưa xem, cộng bằng chứng từ các user hàng xóm đã tương tác item đó.
4. Sắp xếp điểm item giảm dần và lấy Top-K.

Điểm item:

\[
score_U(u,i)=
\frac{\sum_{v\in N(u)}sim^+(u,v)\,X[v,i]\,1[X[v,i]>0]}
{\sum_{v\in N(u)}sim^+(u,v)\,1[X[v,i]>0]}
\]

Trong đó `sim+ = max(sim, 0)`. Nếu không có hàng xóm biết item, model dùng
item mean trên dữ liệu đã build làm fallback xếp hạng.

Ví dụ:

```text
User A: 1, 2, 5
User B: 1, 2, 3, 6
User C: 1, 2, 3

sim(C, A) = 0.80
sim(C, B) = 0.60
```

User C chưa xem 5 và 6. Video 5 nhận bằng chứng `0.80`, video 6 nhận bằng
chứng `0.60`; video có tổng điểm cao hơn được đưa lên trước.

## 5. Item-Based CF

Item-Based xem mỗi item là vector theo user. Với user `u` đã có lịch sử `H(u)`:

1. Tính similarity giữa item ứng viên `i` và từng item `j` user đã xem.
2. Cộng similarity của item ứng viên với lịch sử user.
3. Loại item đã xem/exclude.
4. Sắp xếp các item còn lại và lấy Top-K.

Điểm item:

\[
score_I(u,i)=
\frac{\sum_{j\in H(u)\cap N(i)}sim^+(i,j)\,X[u,j]}
{\sum_{j\in H(u)\cap N(i)}sim^+(i,j)}
\]

`N(i)` là tối đa `neighbor_count` item gần nhất của item ứng viên `i`. Nếu không
có hàng xóm item dương, item mean được dùng làm fallback. Hai công
thức score trên dùng rating để xếp hạng khi `interaction_mode=rating`; phần
Collaborative Support bên dưới chỉ đo **có bằng chứng cộng tác**, không biến nó
thành một nhãn thích/chắc chắn thích.

## 6. Lấy Top-K thực sự là so sánh gì?

Similarity chưa phải kết quả cuối cùng. Nó chỉ là trọng số để tính điểm của
từng item ứng viên:

```text
similarity
    -> chọn hàng xóm user/item
    -> tính score(user, candidate_item)
    -> loại item đã xem
    -> so sánh score giữa các candidate item
    -> sort giảm dần
    -> lấy K item đầu tiên
```

`neighbor_count` là số hàng xóm dùng trong bước tính toán; `K` là số item trả
về. Hai con số này không phải một.

## 7. Vì sao dùng Collaborative Support@K?

### 7.1 Định nghĩa

Metric này đo **tỷ lệ đề xuất có ít nhất một bằng chứng cộng tác hợp lệ**. Nó
không nói rằng user chắc chắn sẽ thích video.

Trước hết tính điểm bằng chứng liên tục. Với User-Based CF, bằng chứng của item
`i` cho user `u` là tỷ lệ tổng similarity của các neighbor đã tương tác item đó:

\[
evidence_U(u,i)=
\frac{\sum_{v\in N(u)}sim^+(u,v)\,1[X[v,i]>0]}
{\sum_{v\in N(u)}sim^+(u,v)}
\]

Với Item-Based CF, bằng chứng là similarity trung bình giữa item đề xuất và các
item trong lịch sử user:

\[
evidence_I(u,i)=
\frac{1}{|H(u)|}\sum_{j\in H(u)}sim^+(i,j)
\]

Một item được tính là **có collaborative support** nếu `evidence(u,i) > 0`.
Sau khi có danh sách `R_K(u)`:

\[
Collaborative\ Support@K=
\frac{1}{|U_e|}\sum_{u\in U_e}
\left(\frac{1}{|R_K(u)|}
\sum_{i\in R_K(u)}1[evidence(u,i)>0]\right)
\]

Giá trị nằm trong `[0, 1]`; ví dụ `0.95` nghĩa là trung bình 95% vị trí trong
Top-K có ít nhất một đường User-Based hoặc Item-Based chống đỡ. Report ghi thêm
`Collaborative Evidence Strength@K`, là trung bình của `evidence(u,i)` để biết
bằng chứng mạnh hay chỉ vừa đủ dương.

Lần này report bắt buộc có:

- `Collaborative Support@10`
- `Collaborative Support@20`
- `Collaborative Support@30`

### 7.2 Vì sao không lấy NDCG@K, Recall@K, Precision@K làm metric chính?

Precision, Recall và NDCG cần một nhãn đánh giá hoặc một tập positive làm
ground-truth. Cách phổ biến là che một số item trong lịch sử rồi bắt model đoán
lại đúng item bị che. Cách đó trả lời câu hỏi **“model có đoán lại đúng item ID
đã ẩn không?”**, không hoàn toàn trả lời câu hỏi **“đề xuất này có bằng chứng
cộng tác hợp lý không?”**.

Trong ngữ cảnh đề tài, user C đã xem các video 1, 2, 3; nếu video 5 có cùng
mẫu người xem hoặc rất giống các item C đã xem thì video 5 là đề xuất hợp lý,
dù nó không phải một item ID bị holdout. Precision/Recall/NDCG sẽ chấm nó là
không đúng nếu tập ground-truth không chứa video 5.

Vì vậy benchmark này không tạo “đáp án duy nhất” giả định cho user. Nó dùng
Collaborative Support@K để kiểm tra tính nhất quán của bằng chứng CF. Đây là
**intrinsic metric**, không phải phép đo hài lòng cuối cùng. Khi HuTube có traffic
thật, cần bổ sung online signal như click, watch ratio, thời gian xem, dislike và
retention để biết user thực sự phản hồi thế nào.

Genre chỉ có thể xuất hiện dưới dạng diagnostic phụ để đọc dữ liệu MovieLens;
genre không đi vào similarity hoặc score CF.

## 8. Cấu trúc thư mục gọn

```text
recommendation-service/
├── app/
│   ├── api.py                    # health, ready, internal recommendations
│   ├── config.py                 # environment và model_type được phục vụ
│   ├── inference.py              # map ID và trả Top-K
│   ├── main.py                   # FastAPI lifespan
│   ├── model_registry.py         # load một trong sáu artifact model
│   ├── schemas.py
│   ├── data/
│   │   ├── models.py             # UnifiedInteraction + nullable masks
│   │   ├── movielens.py          # loader/validator ML-100K
│   │   └── mapping.py            # ID mapping + seen items
│   └── recommenders/
│       ├── similarity.py         # Cosine/Jaccard/Pearson từ đầu
│       ├── user_cf.py            # User-Based score/rank
│       └── item_cf.py            # Item-Based score/rank
├── training/
│   ├── cli.py                    # validate/train/evaluate/report/compare/cohort-report
│   ├── config.py                 # YAML config
│   ├── trainer.py                # train sáu biến thể
│   ├── evaluate.py               # Support@K + diagnostics
│   ├── artifacts.py              # save/load inputs cho deployment
│   ├── comparison.py             # bảng sáu model
│   ├── complexity.py             # benchmark dense/genre construction
│   ├── cohorts.py                # temporal split + bảng cohort Support@K
│   ├── reports.py                # HTML/Markdown/CSV/PNG
│   └── quality_gate.py
├── configs/
│   ├── movielens-100k.yaml
│   └── movielens-100k-smoke.yaml
├── data/                         # raw/processed/artifacts, không commit
├── reports/                      # report sinh tự động, không commit
└── tests/
```

## 9. Chạy bằng terminal

Mở PowerShell tại service:

```powershell
cd F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\HuTube\recommendation-service
```

Kiểm tra dataset:

```powershell
py -3.11 -m training.cli validate-data `
  --data-dir data/raw/movielens/ml-100k
```

Smoke train:

```powershell
.\.venv\Scripts\python.exe -m training.cli train `
  --config configs/movielens-100k-smoke.yaml
```

Train đầy đủ cả sáu biến thể:

```powershell
.\.venv\Scripts\python.exe -m training.cli train `
  --config configs/movielens-100k.yaml
```

Lệnh `train` đồng thời benchmark hai cách xây dựng Item-Based bằng Cosine:

1. `Baseline dense`: ma trận user-item dense và ma trận item-item đầy đủ;
2. `Genre-blocked matrices`: tạo block similarity riêng cho từng genre, bỏ qua
   cặp khác genre;

Benchmark đo thời gian dựng ma trận, tính similarity, chọn Top-N, số vị trí cặp
similarity, ước tính bộ nhớ và speedup so với baseline. Có thể tắt bằng:

```yaml
benchmark:
  enabled: false
```

Kết quả terminal trả về `modelVersion`, `artifact` và đường dẫn `report`. Có thể
chạy lại report/evaluation:

```powershell
.\.venv\Scripts\python.exe -m training.cli evaluate `
  --artifact data/artifacts/<model-version>

.\.venv\Scripts\python.exe -m training.cli compare `
  --artifact data/artifacts/<model-version>

.\.venv\Scripts\python.exe -m training.cli report `
  --artifact data/artifacts/<model-version>
```

Đánh giá ảnh hưởng của lượng lịch sử user bằng temporal cohort:

```powershell
.\.venv\Scripts\python.exe -m training.cli cohort-report `
  --config configs/movielens-100k.yaml
```

Lệnh này chia mỗi user thành 2/3 tương tác sớm để train và 1/3 tương tác muộn
để test, sau đó tạo các cohort `>=20`, `>=30`, `>=40`, `>=50`, `>=60`, `>=70`,
`>=80`, `>=100` tương tác.

Chạy kiểm thử:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check app training tests
```

## 10. Artifact và report

Artifact mới gồm:

```text
data/artifacts/<model-version>/
├── user_based_cosine.npz
├── user_based_jaccard.npz
├── user_based_pearson.npz
├── item_based_cosine.npz
├── item_based_jaccard.npz
├── item_based_pearson.npz
├── user_based.npz             # alias cosine cho cấu hình cũ
├── item_based.npz             # alias cosine cho cấu hình cũ
├── config.yaml
├── metrics.json
├── training_history.json
├── metadata.json
├── user_index.json
├── item_index.json
├── item_metadata.json
└── seen_items.npz
```

`reports/<model-version>/report.html` là HTML tự chứa, không cần CDN/Internet.
Trong đó có bảng sáu biến thể theo các cột:

- `collaborative_support@10`, `@20`, `@30`;
- `collaborative_evidence_strength@10`, `@20`, `@30`;
- catalog coverage, diversity, novelty;
- winner của từng metric.

Report cũng có mục `Computational cost benchmark` và các file:

- `complexity_benchmark.json`;
- `complexity_benchmark.csv`;
- `complexity_cost.png`.

Số liệu benchmark là wall-clock trên máy chạy lệnh. `Genre-blocked matrices`
giảm working set bằng cách tính từng block genre, nhưng có đánh đổi: các cặp
item khác genre bị bỏ qua và item thuộc nhiều genre có thể xuất hiện ở nhiều
block. Đây là benchmark chi phí của hai cách dựng similarity còn được giữ lại.

`cf_comparison.html`, `cf_comparison.csv` và `cf_comparison.md` là các bản tách
riêng của cùng bảng. Artifact MovieLens có `source=MOVIELENS` và
`deployable=false`; không được promote thẳng vào production.

`reports/cohort_<version>/cohort_report.html` là bảng riêng để so sánh Support@K
theo số lượng tương tác tối thiểu của user. `heldout_item_overlap@K` chỉ là
diagnostic tham khảo, không thay thế Collaborative Support và không dùng để
chọn model thắng.

## 11. FastAPI local

Chọn một trong sáu biến thể bằng `MODEL_TYPE`; alias `item_based` và
`user_based` tương ứng với Cosine:

```powershell
$env:ALLOW_BENCHMARK_MODEL = "true"
$env:RECOMMENDER_SERVICE_TOKEN = "local-token"
$env:MODEL_TYPE = "item_based_pearson"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8091
```

Endpoint `POST /internal/recommendations` nhận `userId`, `limit` và
`excludeItemIds`, trả `itemId + source`; API không train lại khi request đến.

## 12. Phạm vi và giới hạn

- V1 chỉ benchmark MovieLens 100K.
- MovieLens chỉ có rating; behavior còn lại không được suy diễn giả.
- Collaborative Support đo bằng chứng nội tại, không thay thế A/B test hoặc
  satisfaction/engagement thật.
- Chưa tích hợp HttpClient với Backend .NET.
- Chưa dùng genre/content feature để tạo recommendation score.
