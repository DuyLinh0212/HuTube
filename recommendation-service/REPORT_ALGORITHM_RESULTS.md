# Tổng hợp thuật toán và kết quả Recommendation Service

## 1. Phạm vi báo cáo

Recommendation Service hiện triển khai Collaborative Filtering thuần bằng
NumPy, gồm hai hướng:

- **User-Based CF**: tìm những user có lịch sử tương tác tương tự user hiện tại.
- **Item-Based CF**: tìm những video tương tự các video user hiện tại đã tương tác.

Mỗi hướng chạy với ba cách tính similarity: **Cosine, Jaccard và Pearson**, tạo
thành sáu biến thể. Báo cáo này trình bày công thức, độ phức tạp và thời gian
chạy. Không kết luận video nào phù hợp với user hơn vì benchmark hiện tại chưa
có nhãn phù hợp độc lập hoặc phản hồi trực tiếp từ người dùng.

## 2. Nguyên lý Collaborative Filtering

CF dựa trên giả định rằng:

> Những user có hành vi tương tự thường có xu hướng quan tâm đến những item tương
> tự; những item thường được cùng một nhóm user tương tác có quan hệ sở thích.

Gọi:

- `U`: số user;
- `I`: số video/item;
- `X ∈ R^(U×I)`: ma trận tương tác;
- `X[u,i]`: rating hoặc giá trị tương tác của user `u` với video `i`.

Trong benchmark MovieLens, rating được dùng làm tín hiệu duy nhất. Ô chưa quan
sát được lưu bằng `0` trong ma trận tính toán, nhưng `0` không được hiểu là rating
bằng 0; khi kiểm tra có tương tác, code dùng điều kiện `X > 0`.

## 3. Tính độ tương đồng

### 3.1. Cosine similarity

Với hai vector `a` và `b`:

```text
sim_cos(a,b) = (Σ_t a_t × b_t)
               -----------------------------
               √(Σ_t a_t²) × √(Σ_t b_t²)
```

Cosine đo mức độ cùng hướng của hai vector. Với rating không âm, rating lớn
đóng góp nhiều hơn rating nhỏ. Nếu chạy binary mode, mỗi tương tác quan sát được
đổi thành `1`, khi đó Cosine phản ánh mức trùng nhau của lịch sử.

### 3.2. Jaccard similarity

Jaccard bỏ qua độ lớn rating và chỉ nhìn việc có hoặc không có tương tác:

```text
sim_jaccard(A,B) = |A ∩ B| / |A ∪ B|
```

### 3.3. Pearson similarity

Pearson đo tương quan giữa các rating mà cả hai phía cùng quan sát:

```text
sim_pearson(a,b) =
  Σ_t (a_t - ā)(b_t - b̄)
  ------------------------
  √Σ_t(a_t - ā)² × √Σ_t(b_t - b̄)²
```

Pearson có thể nhận giá trị âm. Khi chọn neighbor, code chỉ giữ similarity
dương để tránh đưa quan hệ ngược chiều vào điểm xếp hạng.

## 4. Thuật toán User-Based và Item-Based

### 4.1. User-Based CF

Mỗi user là một vector theo chiều video:

```text
user u = [X[u,1], X[u,2], ..., X[u,I]]
S_user = similarity(X, X)
```

Với `N(u)` là tối đa 50 user gần nhất và `s_uv` là similarity giữa `u`, `v`:

```text
score_U(u,i) =
  Σ_v s_uv × X[v,i] × 1[X[v,i] > 0]
  ----------------------------------
  Σ_v s_uv × 1[X[v,i] > 0]
```

Video được những user tương tự tương tác sẽ nhận điểm cao hơn; user càng giống
thì đóng góp càng lớn.

### 4.2. Item-Based CF

Mỗi video là một vector theo chiều user. Code chuyển vị ma trận trước khi tính:

```text
item i = [X[1,i], X[2,i], ..., X[U,i]]
S_item = similarity(Xᵀ, Xᵀ)
```

Với `H(u)` là lịch sử video của user `u`, `N(i)` là các item gần item ứng viên:

```text
score_I(u,i) =
  Σ_j sim(i,j) × X[u,j]
  ----------------------
  Σ_j sim(i,j)
```

`j` thuộc phần giao giữa lịch sử `H(u)` và danh sách neighbor của item ứng viên
`i`. Video được xếp hạng cao khi tương đồng mạnh với các video user đã xem hoặc
đánh giá cao.

### 4.3. Quy trình lấy Top-K

```text
Ma trận tương tác
      ↓
Tính ma trận similarity
      ↓
Giữ tối đa 50 positive neighbors
      ↓
Tính score cho từng video chưa xem
      ↓
Loại video đã xem và excludeItemIds
      ↓
Sắp xếp score giảm dần
      ↓
Lấy K video đầu tiên
```

Nếu không có neighbor dương hoặc mẫu số bằng 0, code dùng item mean làm điểm
fallback. Khi tích hợp HuTube cần bổ sung popular/recent feed cho user mới,
video mới hoặc user chưa đủ dữ liệu.

## 5. Phạm vi đánh giá hiện tại

Benchmark hiện tại **không dùng chỉ số offline để kết luận độ phù hợp**. Lý do:

- ma trận hiện tại chỉ mô tả lịch sử tương tác, chưa có nhãn user thích/không
  thích cho từng video được đề xuất;
- một video không xuất hiện trong lịch sử kiểm thử không đồng nghĩa user không
  thích video đó;
- việc lấy lại một video đã xem cũng chỉ đo khả năng tái hiện lịch sử, không phải
  mức độ hài lòng thực tế.

Vì vậy không báo cáo Precision@K, Recall@K hay NDCG@K trong kết quả hiện tại.
Phần kết quả của baseline chỉ tập trung vào **thời gian chạy và chi phí tính
toán**. Khi HuTube thu thập được popup feedback, like/dislike, watch ratio,
skip, comment hoặc share, các tín hiệu này mới có thể được dùng để xây dựng
đánh giá mức độ phù hợp.

## 6. Thiết lập thực nghiệm

| Thành phần | Giá trị |
|---|---:|
| Dataset | MovieLens 100K |
| Số rating | 100,000 |
| Số user | 943 |
| Số item | 1,682 |
| Interaction mode | `rating` |
| Neighbor count | 50 |
| Số biến thể | 2 family × 3 similarity = 6 |

## 7. Kết quả thời gian train sáu biến thể

Số liệu lấy từ `training_history.json` của artifact benchmark hiện tại
`cf_ml100k_20260922T174514Z_6074af8a`.

| Mô hình | Similarity | Thời gian fit (s) |
|---|---|---:|
| User-Based | Cosine | 1.313132 |
| User-Based | Jaccard | 1.344860 |
| User-Based | Pearson | 11.767021 |
| Item-Based | Cosine | 3.068375 |
| Item-Based | Jaccard | 4.238901 |
| Item-Based | Pearson | 8.354567 |
| **Tổng** | 6 biến thể | **30.086856** |

Nhận xét về chi phí:

1. Trên dataset này, User-Based có thời gian fit thấp hơn vì số user `U = 943`
   nhỏ hơn số item `I = 1,682`.
2. Item-Based phải xây dựng ma trận item-item lớn hơn nên Cosine và Jaccard có
   thời gian cao hơn User-Based.
3. Thời gian Pearson cao hơn trong lần chạy này vì phép tính tương quan cần xử lý
   các vị trí cùng quan sát theo block; thời gian thực tế phụ thuộc máy và kích
   thước block.
4. Đây là so sánh chi phí chạy, không phải kết luận chất lượng đề xuất.

## 8. Độ phức tạp lý thuyết

| Bước | User-Based | Item-Based |
|---|---:|---:|
| Tạo ma trận `X` | `O(R + UI)` | `O(R + UI)` |
| Similarity dense | `O(U²I)` | `O(I²U)` |
| Bộ nhớ similarity | `O(U²)` | `O(I²)` |
| Tính score một user | `O(IK_n)` | `O(IK_n)` |
| Sort candidate | `O(I log I)` | `O(I log I)` |

Trong đó `R` là số dòng tương tác quan sát được và `K_n` là số neighbor giữ lại.
Điểm cần chú ý khi đưa Item-Based vào HuTube là số video có thể lớn hơn rất
nhiều so với MovieLens, khiến ma trận item-item dense tăng nhanh theo `I²`.

## 9. Benchmark chi phí dựng ma trận Item-Based

Benchmark cố định similarity là Cosine, `neighbor_count = 50` trên cùng dataset:

| Chiến lược | Pair slots | Tổng thời gian | Peak ước tính | Speedup |
|---|---:|---:|---:|---:|
| Baseline dense | 1,413,721 | 4.500 s | 17.81 MiB | 1.00× |

Đây là benchmark chi phí của cách dựng ma trận dense. Metadata genre không được
sử dụng trong pipeline Collaborative Filtering.

## 10. Các tối ưu đã có và hướng tiếp theo

Đã có:

1. Dùng NumPy và `float32` thay cho vòng lặp Python ở phần nhân ma trận.
2. Chỉ giữ tối đa 50 neighbor sau khi tính similarity.
3. Pearson tính theo block `block_size = 256` để tránh tensor trung gian quá lớn.
4. Training chạy offline; request online chỉ load artifact và ranking.

Nên làm tiếp:

1. Dùng sparse co-occurrence hoặc inverted index để bỏ qua các cặp không giao
   nhau.
2. Đặt ngưỡng số lượng user/item giao nhau tối thiểu để giảm similarity nhiễu.
3. Lưu top-neighbor dạng sparse thay vì full similarity khi catalog tăng lớn.
4. Cache candidate hoặc score cho user hoạt động thường xuyên.

## 11. Hướng áp dụng vào HuTube

HuTube có thể tạo các ma trận hành vi riêng:

- `X_rating`: rating;
- `X_like`: like;
- `X_watch`: watch ratio hoặc thời lượng xem;
- `X_comment`: comment;
- `X_share`: share;
- `X_dislike`: dislike.

Hai hướng kết hợp có thể triển khai:

### 11.1. Trung bình các ma trận tương đồng

Tính similarity riêng cho từng ma trận rồi lấy trung bình:

```text
S_final = (S_rating + S_like + S_watch + S_comment + S_share) / 5
```

Ưu điểm là đơn giản, dễ giải thích. Nhược điểm là mọi hành vi có ảnh hưởng như
nhau dù like và watch ratio có thể mang thông tin khác nhau.

### 11.2. Trung bình có trọng số

```text
S_final =
  w_rating  × S_rating
  + w_like  × S_like
  + w_watch × S_watch
  + w_comment × S_comment
  + w_share × S_share
  - w_dislike × S_dislike
```

Các trọng số cần được cấu hình hoặc điều chỉnh từ phản hồi thực tế. Có thể dùng
score cuối cùng theo cách tương tự:

```text
score_final(u,i) =
  w_rating  × score_rating(u,i)
  + w_like  × score_like(u,i)
  + w_watch × score_watch(u,i)
  + ...
```

Nên chuẩn hóa các ma trận hoặc score về cùng khoảng trước khi cộng. Với user mới,
ưu tiên popular/recent và category fallback; khi đủ lịch sử mới tăng trọng số CF.

## 12. Kết luận dùng khi thuyết trình

1. CF biến lịch sử tương tác thành similarity giữa user hoặc giữa video.
2. Item-Based dùng các video user đã xem để tính điểm cho video chưa xem và lấy
   Top-K.
3. User-Based làm tương tự nhưng thay similarity video-video bằng user-user.
4. Kết quả hiện tại được báo cáo bằng thời gian fit, thời gian dựng similarity,
   thời gian chọn neighbor, tổng thời gian và bộ nhớ ước tính.
5. Chưa thể nói model nào đề xuất phù hợp hơn khi chưa có nhãn hoặc feedback từ
   người dùng.
6. Khi HuTube có dữ liệu hành vi thật, có thể kết hợp nhiều ma trận bằng trung
   bình hoặc trọng số rồi kiểm chứng bằng feedback/A-B test.

## 13. File liên quan

- Tính similarity: [`app/recommenders/similarity.py`](./app/recommenders/similarity.py)
- Item-Based CF: [`app/recommenders/item_cf.py`](./app/recommenders/item_cf.py)
- User-Based CF: [`app/recommenders/user_cf.py`](./app/recommenders/user_cf.py)
- Huấn luyện và đo thời gian: [`training/trainer.py`](./training/trainer.py)
- Benchmark chi phí: [`training/complexity.py`](./training/complexity.py)
- Sinh runtime report: [`training/reports.py`](./training/reports.py)
