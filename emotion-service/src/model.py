import os
from pathlib import Path
from typing import Tuple, Union

try:
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
except ImportError:
    AutoTokenizer = None
    AutoModelForSequenceClassification = None

from .config import (
    PRETRAINED_MODEL_NAME,
    NUM_LABELS,
    ID2LABEL,
    LABEL2ID,
    BEST_MODEL_DIR
)

def get_tokenizer(model_name_or_path: str = PRETRAINED_MODEL_NAME):
    """Khởi tạo tokenizer cho PhoBERT."""
    if AutoTokenizer is None:
        raise ImportError("Vui lòng cài đặt thư viện 'transformers' để dùng tokenizer.")
    return AutoTokenizer.from_pretrained(model_name_or_path, use_fast=False)

def get_model(model_name_or_path: str = PRETRAINED_MODEL_NAME, num_labels: int = NUM_LABELS):
    """Khởi tạo PhoBERT model cho phân loại cảm xúc (Sequence Classification)."""
    if AutoModelForSequenceClassification is None:
        raise ImportError("Vui lòng cài đặt thư viện 'transformers' để dùng model.")

    model = AutoModelForSequenceClassification.from_pretrained(
        model_name_or_path,
        num_labels=num_labels,
        id2label=ID2LABEL,
        label2id=LABEL2ID
    )
    return model

def load_inference_model_and_tokenizer(model_dir: Union[str, Path] = BEST_MODEL_DIR):
    """Nạp checkpoint model đã train kèm tokenizer để dự đoán (hỗ trợ cả đường dẫn local và Hugging Face Hub repo ID)."""
    model_identifier = str(model_dir)
    if not os.path.exists(model_identifier) and "/" not in model_identifier:
        # Nếu chưa train checkpoint riêng và không phải HF Hub ID, fallback về pretrained model base
        print(f"[!] Chưa tìm thấy checkpoint tại {model_identifier}. Đang nạp mô hình gốc {PRETRAINED_MODEL_NAME}...")
        model_identifier = PRETRAINED_MODEL_NAME

    tokenizer = get_tokenizer(model_identifier)
    model = get_model(model_identifier)
    return model, tokenizer
