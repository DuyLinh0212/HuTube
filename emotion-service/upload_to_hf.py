import os
import sys

# Đảm bảo in tiếng Việt không bị lỗi encoding trên Windows console
if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import argparse
from pathlib import Path
from huggingface_hub import HfApi, login

def main():
    parser = argparse.ArgumentParser(description="Upload trained emotion model to Hugging Face Hub")
    parser.add_argument("--repo_id", type=str, required=True, help="Tên repo trên Hugging Face dạng: username/ten-model (VD: nguyenvana/visobert-vsmec-moderation)")
    parser.add_argument("--token", type=str, default=None, help="Hugging Face Access Token (quyền WRITE). Nếu đã login qua huggingface-cli thì không cần.")
    parser.add_argument("--model_dir", type=str, default="saved_models/visobert_vsmec_best", help="Đường dẫn thư mục chứa model trọng số")
    parser.add_argument("--private", action="store_true", help="Đặt repo ở chế độ Private (mặc định là Public)")
    args = parser.parse_args()

    model_path = Path(args.model_dir).resolve()
    if not model_path.exists():
        print(f"[!] Lỗi: Không tìm thấy thư mục model tại: {model_path}")
        sys.exit(1)

    print("=" * 60)
    print("   HUGGING FACE HUB MODEL UPLOADER")
    print(f"   Model folder : {model_path}")
    print(f"   Target repo  : {args.repo_id}")
    print(f"   Visibility   : {'Private' if args.private else 'Public'}")
    print("=" * 60)

    # 1. Xác thực đăng nhập
    if args.token:
        print("[*] Đang đăng nhập Hugging Face bằng token...")
        login(token=args.token)
    else:
        print("[*] Sử dụng phiên đăng nhập Hugging Face hiện có...")

    api = HfApi()

    # 2. Tạo repo nếu chưa có
    print(f"[*] Đang tạo/kiểm tra repo: {args.repo_id}...")
    try:
        repo_url = api.create_repo(
            repo_id=args.repo_id,
            repo_type="model",
            private=args.private,
            exist_ok=True
        )
        print(f"[+] Repo đã sẵn sàng: {repo_url}")
    except Exception as e:
        print(f"[!] Lỗi khi tạo repo: {e}")
        sys.exit(1)

    # 3. Tạo file README.md (Model Card) xịn sò nếu chưa có
    readme_path = model_path / "README.md"
    if not readme_path.exists():
        print("[*] Tạo file Model Card README.md...")
        readme_content = f"""---
language:
- vi
license: mit
tags:
- emotion-recognition
- sentiment-analysis
- text-classification
- visobert
- pytorch
datasets:
- tridm/UIT-VSMEC
metrics:
- f1
- accuracy
widget:
- text: "Bài giảng rất dễ hiểu và chi tiết, cảm ơn thầy nhiều ạ!"
- text: "Video xàm vcl lừa đảo quá, cút đi thằng ad ngu ngốc"
- text: "Trời ơi bất ngờ thực sự, không ngờ cái kết lại như vậy"
- text: "Xem đoạn này buồn rơi nước mắt luôn"
---

# ViSoBERT Fine-tuned for Vietnamese Emotion Recognition (UIT-VSMEC)

Mô hình **ViSoBERT** (`uitnlp/visobert`) được huấn luyện tinh chỉnh (fine-tuned) trên tập dữ liệu **UIT-VSMEC** (Vietnamese Social Media Emotion Corpus) phục vụ bài toán:
1. Nhận diện **7 sắc thái cảm xúc**: `Enjoyment`, `Disgust`, `Sadness`, `Anger`, `Fear`, `Surprise`, `Other`.
2. Phân loại **Sắc thái**: Tích cực (Positive), Tiêu cực (Negative), Trung tính (Neutral).
3. **Kiểm duyệt bình luận độc hại tự động** cho nền tảng video HuTube (phát hiện `Anger` + `Disgust` với ngưỡng tối ưu 0.20).

## Hiệu năng trên tập Test (UIT-VSMEC)
- **Độ chính xác kiểm duyệt độc hại:** 81.5% (Recall bình luận độc hại: 75.6%, Precision bình luận sạch: 91.2%)
- **F1 Tiêu cực:** 0.805
- **F1 Tích cực:** 0.674
- **Accuracy tổng thể 7 cảm xúc:** 60.2%

## Cách sử dụng

```python
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

MODEL_ID = "{args.repo_id}"

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_ID)

text = "Video này quá hay và ý nghĩa, cảm ơn tác giả!"
inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=128)

with torch.no_grad():
    logits = model(**inputs).logits
    probs = torch.softmax(logits, dim=-1).squeeze().tolist()

labels = ["Enjoyment", "Disgust", "Sadness", "Anger", "Fear", "Surprise", "Other"]
for label, prob in zip(labels, probs):
    print(f"{{label}}: {{prob:.4f}}")
```
"""
        with open(readme_path, "w", encoding="utf-8") as f:
            f.write(readme_content)

    # 4. Upload toàn bộ thư mục lên Hub
    print(f"[*] Bắt đầu tải các file lên Hugging Face Hub (bao gồm model.safetensors ~390MB)...")
    print("    (Quá trình tải lên có thể mất 1 - 3 phút tùy tốc độ mạng)")
    try:
        api.upload_folder(
            folder_path=str(model_path),
            repo_id=args.repo_id,
            repo_type="model"
        )
        print("\n" + "=" * 60)
        print(f"[SUCCESS] Đã upload thành công mô hình lên Hugging Face!")
        print(f"Link xem mô hình: https://huggingface.co/{args.repo_id}")
        print("=" * 60)
    except Exception as e:
        print(f"\n[!] Lỗi khi upload: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
