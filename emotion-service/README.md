# HuTube Emotion & Sentiment Analysis Service (PhoBERT + UIT-VSMEC)

Dự án microservice độc lập (nằm ngoài thư mục `HuTube`) phục vụ việc:
1. **Huấn luyện (Train) mô hình AI nhận diện 7 cảm xúc** từ bộ dữ liệu mạng xã hội Việt Nam [`tridm/UIT-VSMEC`](https://huggingface.co/datasets/tridm/UIT-VSMEC).
2. **Quy đổi cảm xúc sang sắc thái (Sentiment Analysis)**: Tích cực (Positive), Tiêu cực (Negative), Trung tính (Neutral).
3. **Cung cấp REST API (FastAPI - Port 8001)** để tích hợp trực tiếp vào HuTube Backend (ASP.NET Core) phục vụ:
   - Tự động phát hiện và kiểm duyệt bình luận tiêu cực/độc hại (`status: 'held'`).
   - Thống kê tỷ lệ cảm xúc & mức độ yêu thích của khán giả trên từng video cho Creator và Admin.

---

## 1. Cấu Trúc Thư Mục

```text
emotion-service/
├── data/                       # Dữ liệu UIT-VSMEC (tự động tải từ Hugging Face)
│   ├── prepare_data.py         # Script tải & phân tích thống kê dataset
│   ├── train.json              # 5,548 mẫu huấn luyện
│   ├── validation.json         # 686 mẫu kiểm định
│   └── test.json               # 693 mẫu kiểm thử độc lập
├── src/
│   ├── config.py               # Cấu hình siêu tham số, label mapping & VRAM GPU
│   ├── dataset.py              # PyTorch Dataset + Word Segmentation (pyvi)
│   ├── model.py                # Kiến trúc PhoBERT Sequence Classification
│   └── predictor.py            # Engine suy luận, phân loại cảm xúc & sắc thái
├── training/
│   ├── train.py                # Script train local (tối ưu VRAM 4GB RTX 3050)
│   └── evaluate.py             # Đánh giá Accuracy, F1-score trên Test Set
├── api/
│   └── main.py                 # FastAPI Microservice (Port 8001)
├── notebooks/
│   └── train_on_colab.ipynb    # Google Colab 1-click (GPU T4 miễn phí)
├── saved_models/               # Thư mục chứa weights sau khi train
│   └── phobert_vsmec_best/
├── requirements.txt            # Thư viện phụ thuộc
└── README.md                   # Hướng dẫn chi tiết
```

---

## 2. Bản Đồ Ánh Xạ Cảm Xúc (Emotion) -> Sắc Thái (Sentiment)

Bộ dữ liệu `UIT-VSMEC` có 7 nhãn cảm xúc đặc trưng trên mạng xã hội:

| Cảm Xúc (UIT-VSMEC) | Tỷ Lệ Tập Train | Phân Nhóm Sắc Thái | Hành Động Trong HuTube |
|:---|:---:|:---:|:---|
| **Enjoyment** (Thích thú, vui vẻ) | **28.08%** | **POSITIVE (Tích cực)** | Bình luận khen ngợi, tăng điểm đề xuất video |
| **Disgust** (Phản cảm, chê bai) | **19.30%** | **NEGATIVE (Tiêu cực)** | Ghi nhận phản hồi tiêu cực |
| **Sadness** (Buồn bã, thất vọng) | **17.07%** | **NEGATIVE (Tiêu cực)** | Thống kê vào tỷ lệ tiêu cực |
| **Anger** (Tức giận, gay gắt) | **7.05%** | **NEGATIVE (Tiêu cực / Toxic)** | Chuyển trạng thái `held` (chờ duyệt) |
| **Fear** (Sợ hãi, lo lắng) | **5.73%** | **NEGATIVE (Tiêu cực)** | Ghi nhận cảm xúc tiêu cực |
| **Surprise** (Ngạc nhiên) | **4.36%** | **NEUTRAL (Trung tính)** | Cho phép hiển thị bình thường |
| **Other** (Khác / Bình thường) | **18.40%** | **NEUTRAL (Trung tính)** | Cho phép hiển thị bình thường |

---

## 3. Cài Đặt Môi Trường

Tại terminal của máy (thư mục `c:\Users\thait\.vscode\DoAn\emotion-service`):

### Bước 1: Kích hoạt môi trường Python 3.12 và cài đặt PyTorch CUDA
Đối với máy có GPU NVIDIA (như RTX 3050 Laptop):
```powershell
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt
```

*(Nếu chỉ dùng CPU để test API nhẹ: `pip install torch --index-url https://download.pytorch.org/whl/cpu`)*

### Bước 2: Tải và kiểm tra bộ dữ liệu UIT-VSMEC
```powershell
python data/prepare_data.py
```
*(Script sẽ tự động tải các file `train.json`, `validation.json`, `test.json` từ Hugging Face và lưu tại thư mục `data/`)*.

---

## 4. Huấn Luyện Mô Hình (Training)

Có 2 lựa chọn linh hoạt để bạn huấn luyện mô hình:

### Lựa chọn A: Huấn luyện Local bằng GPU RTX 3050 Laptop (Khuyên dùng nếu muốn chạy trực tiếp)
Pipeline trong `training/train.py` đã được cấu hình tối ưu triệt để cho GPU 4GB VRAM:
- `batch_size = 8` kèm `gradient_accumulation_steps = 2` (tương đương batch size 16).
- `max_length = 64` (đủ cho bình luận MXH, tiết kiệm bộ nhớ).
- `fp16 = True` (Mixed Precision) giúp giảm 50% VRAM và tăng gấp đôi tốc độ train.

Chạy lệnh:
```powershell
python training/train.py
```
Sau 4 epochs (~15-20 phút), mô hình tốt nhất (Best F1 Macro) sẽ tự động được lưu vào `saved_models/phobert_vsmec_best/`.

---

### Lựa chọn B: Huấn luyện trên Google Colab (GPU T4 16GB Miễn phí)
Nếu bạn không muốn máy tính chạy nặng hoặc muốn train siêu tốc (~6 phút):
1. Mở [Google Colab](https://colab.research.google.com).
2. Chọn **File -> Upload notebook** và tải lên file `notebooks/train_on_colab.ipynb`.
3. Bật GPU: **Runtime -> Change runtime type -> T4 GPU**.
4. Chạy toàn bộ các ô (Run All).
5. Khi hoàn tất, file `phobert_vsmec_best.zip` sẽ tự động tải về máy bạn.
6. Giải nén vào thư mục `emotion-service/saved_models/phobert_vsmec_best/`.

---

## 5. Đánh Giá Mô Hình (Evaluation)

Chạy script đánh giá trên tập kiểm thử độc lập (`test.json`):
```powershell
python training/evaluate.py
```
Kết quả in ra chi tiết độ chính xác (Precision, Recall, F1) cho cả 7 nhãn cảm xúc và 3 sắc thái Tích cực / Tiêu cực / Trung tính.

---

## 6. Khởi Động API Service Cho HuTube

Chạy FastAPI service tại cổng `8001`:
```powershell
python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload
```
- Swagger UI tài liệu tương tác: `http://localhost:8001/docs`
- Health check: `http://localhost:8001/health`

### Test thử API bằng cURL / PowerShell:
```powershell
curl -X POST "http://localhost:8001/api/v1/analyze" `
  -H "Content-Type: application/json" `
  -d '{"text": "Video hướng dẫn chi tiết và dễ hiểu quá, cảm ơn kênh rất nhiều!"}'
```

**Kết quả trả về JSON:**
```json
{
  "text": "Video hướng dẫn chi tiết và dễ hiểu quá, cảm ơn kênh rất nhiều!",
  "emotion": "Enjoyment",
  "emotion_score": 0.9621,
  "sentiment": "POSITIVE",
  "sentiment_score": 0.9621,
  "sentiment_distribution": {
    "positive": 0.9621,
    "negative": 0.0152,
    "neutral": 0.0227
  },
  "is_negative": false,
  "is_toxic": false,
  "moderation_suggested_status": "visible"
}
```

Với bình luận tiêu cực/xúc phạm:
```powershell
curl -X POST "http://localhost:8001/api/v1/analyze" `
  -H "Content-Type: application/json" `
  -d '{"text": "Video rác rưởi lừa đảo, cút đi thằng ad ngu ngốc"}'
```
**Kết quả:**
```json
{
  "text": "Video rác rưởi lừa đảo, cút đi thằng ad ngu ngốc",
  "emotion": "Anger",
  "emotion_score": 0.9124,
  "sentiment": "NEGATIVE",
  "is_negative": true,
  "is_toxic": true,
  "moderation_suggested_status": "held"
}
```

---

## 7. Tích Hợp Vào HuTube Backend (ASP.NET Core)

Khi người dùng gửi comment qua endpoint `POST /api/v1/videos/{videoId}/comments` trong HuTube Backend, bạn có thể gọi service này để quyết định trạng thái của bình luận:

```csharp
// Trong ContentService.cs hoặc CommentsController.cs của HuTube
public async Task<CommentResponse> CreateCommentAsync(Guid userId, Guid videoId, CreateCommentRequest request, CancellationToken ct)
{
    // 1. Gọi Emotion Service phân tích cảm xúc
    var client = _httpClientFactory.CreateClient();
    var payload = new { content = request.Content };
    var res = await client.PostAsJsonAsync("http://localhost:8001/api/v1/comments/moderate", payload, ct);
    
    string commentStatus = "visible";
    if (res.IsSuccessStatusCode)
    {
        var modResult = await res.Content.ReadFromJsonAsync<ModerationResult>(cancellationToken: ct);
        // Nếu AI phát hiện tiêu cực độc hại -> Đặt status = "held" (chờ duyệt)
        if (modResult?.Status == "held")
        {
            commentStatus = "held";
        }
    }

    // 2. Lưu vào Database PostgreSQL với status tương ứng
    // (Bình luận 'held' sẽ không hiện công khai cho đến khi chủ kênh duyệt trong mục Manage Comments)
    ...
}
```
