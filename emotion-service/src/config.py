import os
from pathlib import Path

# Paths
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
SAVED_MODELS_DIR = BASE_DIR / "saved_models"

# Hugging Face Hub Repository ID
HF_MODEL_REPO = "aabcv/visobert-vsmec-moderation"

# Model directory (ưu tiên thư mục local nếu có, ngược lại tải từ Hugging Face Hub)
if (SAVED_MODELS_DIR / "visobert_vsmec_best").exists():
    BEST_MODEL_DIR = SAVED_MODELS_DIR / "visobert_vsmec_best"
elif (SAVED_MODELS_DIR / "phobert_vsmec_best").exists():
    BEST_MODEL_DIR = SAVED_MODELS_DIR / "phobert_vsmec_best"
else:
    BEST_MODEL_DIR = HF_MODEL_REPO

OUTPUTS_DIR = BASE_DIR / "training" / "outputs"

# Ensure directories exist
SAVED_MODELS_DIR.mkdir(parents=True, exist_ok=True)
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

# Pretrained base model
PRETRAINED_MODEL_NAME = "vinai/phobert-base-v2"

# 7 Cảm xúc chuẩn theo UIT-VSMEC
EMOTION_LABELS = [
    "Enjoyment",
    "Disgust",
    "Sadness",
    "Anger",
    "Fear",
    "Surprise",
    "Other"
]

LABEL2ID = {label: idx for idx, label in enumerate(EMOTION_LABELS)}
ID2LABEL = {idx: label for idx, label in enumerate(EMOTION_LABELS)}
NUM_LABELS = len(EMOTION_LABELS)

# Ánh xạ từ Cảm xúc (Emotion) sang Sắc thái (Sentiment)
EMOTION_TO_SENTIMENT = {
    "Enjoyment": "POSITIVE",
    "Disgust": "NEGATIVE",
    "Sadness": "NEGATIVE",
    "Anger": "NEGATIVE",
    "Fear": "NEGATIVE",
    "Surprise": "NEUTRAL",
    "Other": "NEUTRAL"
}

# Tên tiếng Việt thân thiện để hiển thị lên giao diện HuTube
EMOTION_VI = {
    "Enjoyment": "Thích thú / Vui vẻ",
    "Disgust": "Ghê tởm / Phản cảm",
    "Sadness": "Buồn bã / Thất vọng",
    "Anger": "Tức giận / Gay gắt",
    "Fear": "Sợ hãi / Lo lắng",
    "Surprise": "Ngạc nhiên / Bất ngờ",
    "Other": "Bình thường / Khác"
}

SENTIMENT_VI = {
    "POSITIVE": "Tích cực",
    "NEGATIVE": "Tiêu cực",
    "NEUTRAL": "Trung tính"
}

# Tiêu chuẩn phân loại cmt tiêu cực cần kiểm duyệt (Moderation)
NEGATIVE_EMOTIONS = {"Disgust", "Anger", "Sadness", "Fear"}
TOXIC_EMOTIONS = {"Anger", "Disgust"}

# Hyperparameters mặc định tối ưu cho GPU
TRAINING_CONFIG = {
    "max_length": 128,            # Tăng lên 128 giữ trọn vẹn ngữ cảnh
    "per_device_train_batch_size": 8,  # Giữ VRAM < 2.5GB
    "per_device_eval_batch_size": 16,
    "gradient_accumulation_steps": 2, # Tương đương batch size 16 hiệu dụng
    "learning_rate": 2.5e-5,
    "lr_scheduler_type": "cosine",
    "num_train_epochs": 15,       # 15 Epochs
    "weight_decay": 0.01,
    "warmup_steps": 150,
    "fp16": True,                 # Bật mixed precision trên NVIDIA GPU
    "logging_steps": 50,
    "eval_strategy": "epoch",
    "save_strategy": "epoch",
    "save_total_limit": 2,
    "load_best_model_at_end": True,
    "metric_for_best_model": "f1_macro",
    "greater_is_better": True,
}
