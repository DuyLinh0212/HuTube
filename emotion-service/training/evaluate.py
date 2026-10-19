import os
import sys
import numpy as np
from pathlib import Path
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, f1_score

# Fix UTF-8 output on Windows terminal
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Thêm đường dẫn gốc vào sys.path
CURRENT_DIR = Path(__file__).resolve().parent
ROOT_DIR = CURRENT_DIR.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from src.config import (
    BEST_MODEL_DIR,
    EMOTION_LABELS,
    EMOTION_TO_SENTIMENT
)
from src.dataset import load_vsmec_data
from src.predictor import EmotionPredictor

def main():
    print("=" * 70)
    print("ĐÁNH GIÁ MÔ HÌNH TRÊN TẬP KIỂM THỬ (TEST SET - UIT-VSMEC)")
    print(f"Checkpoint: {BEST_MODEL_DIR}")
    print("=" * 70)

    # 1. Tải tập test
    test_data = load_vsmec_data("test")
    print(f"[*] Số lượng mẫu test: {len(test_data)}")

    # 2. Khởi tạo Predictor
    predictor = EmotionPredictor(model_dir=BEST_MODEL_DIR)

    texts = [item["Sentence"] for item in test_data]
    true_emotions = [item["Emotion"] for item in test_data]
    true_sentiments = [EMOTION_TO_SENTIMENT.get(e, "NEUTRAL") for e in true_emotions]

    print("\n[*] Đang chạy dự đoán toàn bộ tập test...")
    predictions = predictor.predict_batch(texts)

    pred_emotions = [p["emotion"] for p in predictions]
    pred_sentiments = [p["sentiment"] for p in predictions]

    # 3. Đánh giá Cảm xúc (7 emotions)
    print("\n" + "=" * 50)
    print("KẾT QUẢ ĐÁNH GIÁ CẢM XÚC (7 EMOTIONS)")
    print("=" * 50)
    print(f"Accuracy (Cảm xúc): {accuracy_score(true_emotions, pred_emotions):.4f}")
    print(f"Macro F1 (Cảm xúc): {f1_score(true_emotions, pred_emotions, average='macro'):.4f}")
    print(f"Weighted F1 (Cảm xúc): {f1_score(true_emotions, pred_emotions, average='weighted'):.4f}\n")
    print(classification_report(true_emotions, pred_emotions, labels=EMOTION_LABELS, zero_division=0))

    # 4. Đánh giá Sắc thái (Sentiment: Positive, Negative, Neutral)
    print("\n" + "=" * 50)
    print("KẾT QUẢ ĐÁNH GIÁ SẮC THÁI BÌNH LUẬN (SENTIMENT)")
    print("=" * 50)
    sentiment_labels = ["POSITIVE", "NEGATIVE", "NEUTRAL"]
    print(f"Accuracy (Sentiment): {accuracy_score(true_sentiments, pred_sentiments):.4f}")
    print(f"Macro F1 (Sentiment): {f1_score(true_sentiments, pred_sentiments, average='macro'):.4f}\n")
    print(classification_report(true_sentiments, pred_sentiments, labels=sentiment_labels, zero_division=0))

    # 5. Đánh giá Kiểm duyệt Độc hại HuTube (Toxic vs Safe with threshold P > 0.4)
    print("\n" + "=" * 50)
    print("KẾT QUẢ ĐÁNH GIÁ KIỂM DUYỆT ĐỘC HẠI HUTUBE (P > 0.4)")
    print("=" * 50)
    true_toxic = [1 if e in ["Anger", "Disgust"] else 0 for e in true_emotions]
    pred_toxic = [1 if p["is_toxic"] else 0 for p in predictions]
    print(f"Accuracy (Kiểm duyệt): {accuracy_score(true_toxic, pred_toxic):.4f}")
    print(f"Macro F1 (Kiểm duyệt): {f1_score(true_toxic, pred_toxic, average='macro'):.4f}\n")
    print(classification_report(true_toxic, pred_toxic, target_names=["An toàn (Visible)", "Độc hại (Held)"], digits=4))

if __name__ == "__main__":
    main()
