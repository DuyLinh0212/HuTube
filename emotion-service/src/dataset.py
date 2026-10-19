import json
import re
from pathlib import Path
from typing import Optional, List, Dict, Any

try:
    from pyvi import ViTokenizer
    HAS_PYVI = True
except ImportError:
    HAS_PYVI = False

try:
    import torch
    from torch.utils.data import Dataset
except ImportError:
    torch = None
    Dataset = object

from .config import LABEL2ID, DATA_DIR

try:
    import emoji
    HAS_EMOJI = True
except ImportError:
    HAS_EMOJI = False

TEENCODE_DICT = {
    r"\b(k|ko|kh|hong|hổng|hok|kô)\b": "không",
    r"\b(dc|đc)\b": "được",
    r"\b(nhiu|nhìu)\b": "nhiều",
    r"\b(ng|ngừi)\b": "người",
    r"\b(tgian|tg)\b": "thời gian",
    r"\b(ad|admin|chủ tus)\b": "tác giả",
    r"\b(vcl|vl|vcc|vđ|vler)\b": "rất",
    r"\b(bt|bít)\b": "biết",
    r"\b(t|tui|tao)\b": "tôi",
    r"\b(m|mài)\b": "mày",
    r"\b(mk|mik|minh)\b": "mình",
    r"\b(ns)\b": "nói",
    r"\b(cx)\b": "cũng",
    r"\b(z|zậy|dậy)\b": "vậy",
    r"\b(vs)\b": "với",
    r"\b(wa|wá)\b": "quá",
    r"\b(haizz|hazz|haizzz)\b": "thở dài thất vọng",
    r"\b(tks|thanks|cảm ơn ad|thank)\b": "cảm ơn",
    r"\b(xàm|nhảm)\b": "nhảm nhí",
    r"\b(đhs|đéo|đếch)\b": "không thể"
}

# Quy tắc chuẩn hóa cụm từ phủ định kép và tiếng lóng mạng xã hội hiện đại
SLANG_AND_NEGATION_RULES = [
    # 1. Cụm từ phủ định mang nghĩa tích cực (Double Negation / Positive Negation)
    (r"\b(không|k|ko|kh|chẳng|chả|chưa|kô)\s+(hề\s+|thể\s+|thấy\s+)?chán\b", "rất thích thú"),
    (r"\b(nghe|xem|coi)\s+(mãi|hoài|suốt)\s+(không|k|ko|chẳng|chả)\s+chán\b", "rất thích thú say mê"),
    (r"\b(không|k|ko|kh)\s+(thể\s+)?(chê|chê vào đâu được|chê nổi)\b", "rất tuyệt vời"),
    (r"\bmiễn chê\b", "rất tuyệt vời"),
    (r"\b(không|k|ko|kh)\s+(hề\s+)?thất vọng\b", "rất hài lòng"),
    (r"\b(không|k|ko|kh)\s+phải dạng vừa\b", "rất xuất sắc"),

    # 2. Tiếng lóng âm nhạc & khen ngợi video hiện đại (Music / Video Slangs)
    (r"\b(bánh cuốn|nghe cuốn|rất cuốn|quá cuốn|cực cuốn|siêu cuốn|cuốn thật sự|cuốn vcl|cuốn vl|cuốn vđ|cuốn quá|cuốn dã man)\b", "lôi cuốn rất hay"),
    (r"\bcuốn\b", "lôi cuốn"),
    (r"\b(replay|repeate)\b", "nghe lại liên tục"),
    (r"\b(đỉnh chóp|đỉnh của chóp|đỉnh nóc kịch trần|hết nước chấm|hết sảy|10 điểm không có nhưng|quá đỉnh|đỉnh vcl|đỉnh vl|đỉnh vđ)\b", "rất xuất sắc tuyệt vời"),
    (r"\b(cháy quá|quá cháy|cháy khét|cháy phố|cháy vcl|cháy vl)\b", "rất sôi động tuyệt vời"),
    (r"\b(bắt tai|tai bắt|dính tai|quá dính|dính vcl|dính vl|dính thật sự)\b", "rất hấp dẫn bắt tai"),
    (r"\b(nghiện luôn|bị nghiện|nghiện bài này|nghiện giọng này)\b", "rất mê và thích thú"),
    (r"\b(keo lỳ|mlem|đỉnh cao|xịn xò|xịn sò)\b", "rất tuyệt vời"),
]

def clean_social_text(text: str) -> str:
    """Chuẩn hóa văn bản MXH: Emoji -> chữ, rút gọn kéo dài, chuẩn hóa teencode và tiếng lóng/phủ định."""
    if not isinstance(text, str):
        return ""
    if HAS_EMOJI:
        try:
            text = emoji.demojize(text, language="alias")
            text = re.sub(r":([a-zA-Z0-9_]+):", r" \1 ", text)
        except Exception:
            pass
    # Rút gọn chữ kéo dài (quáááá -> quá)
    text = re.sub(r"([a-zA-ZÀ-ỹ])\1{2,}", r"\1", text)
    # Chuẩn hóa teencode
    for pattern, rep in TEENCODE_DICT.items():
        text = re.sub(pattern, rep, text, flags=re.IGNORECASE)
    # Chuẩn hóa cụm từ phủ định và tiếng lóng
    for pattern, rep in SLANG_AND_NEGATION_RULES:
        text = re.sub(pattern, rep, text, flags=re.IGNORECASE)
    # Chuẩn hóa khoảng trắng
    return re.sub(r"\s+", " ", text).strip()

def clean_vietnamese_text(text: str) -> str:
    return clean_social_text(text)

def segment_words(text: str) -> str:
    """Tách từ tiếng Việt."""
    text = clean_social_text(text)
    if HAS_PYVI:
        try:
            return ViTokenizer.tokenize(text)
        except Exception:
            return text
    return text

class VSMECDataset(Dataset):
    """PyTorch Dataset cho tập dữ liệu UIT-VSMEC."""

    def __init__(self, data: List[Dict[str, Any]], tokenizer, max_length: int = 64, do_segment: bool = True):
        self.data = data
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.do_segment = do_segment

    def __len__(self) -> int:
        return len(self.data)

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        item = self.data[idx]
        sentence = item.get("Sentence", "")
        emotion = item.get("Emotion", "Other")

        # Tách từ cho PhoBERT (nếu do_segment = True)
        processed_text = segment_words(sentence) if self.do_segment else clean_vietnamese_text(sentence)

        encoding = self.tokenizer(
            processed_text,
            truncation=True,
            padding="max_length",
            max_length=self.max_length,
            return_tensors="pt"
        )

        item_dict = {
            "input_ids": encoding["input_ids"].squeeze(0),
            "attention_mask": encoding["attention_mask"].squeeze(0),
        }

        if emotion in LABEL2ID:
            item_dict["labels"] = torch.tensor(LABEL2ID[emotion], dtype=torch.long)

        return item_dict

def load_vsmec_data(split: str = "train") -> List[Dict[str, Any]]:
    """Tải dữ liệu split: 'train', 'validation', hoặc 'test'."""
    file_map = {
        "train": DATA_DIR / "train.json",
        "validation": DATA_DIR / "validation.json",
        "valid": DATA_DIR / "validation.json",
        "test": DATA_DIR / "test.json",
    }
    target_path = file_map.get(split)
    if not target_path or not target_path.exists():
        raise FileNotFoundError(f"Không tìm thấy file dữ liệu: {target_path}. Hãy chạy data/prepare_data.py trước.")

    with open(target_path, "r", encoding="utf-8") as f:
        return json.load(f)
