import os
import sys
import json

if sys.platform.startswith("win"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

import torch
import torch.nn.functional as F
from typing import List, Dict, Any, Union
from pathlib import Path

from .config import (
    BEST_MODEL_DIR,
    EMOTION_LABELS,
    EMOTION_TO_SENTIMENT,
    EMOTION_VI,
    SENTIMENT_VI,
    NEGATIVE_EMOTIONS,
    TOXIC_EMOTIONS,
    ID2LABEL
)
from .dataset import segment_words
from .model import load_inference_model_and_tokenizer

class EmotionPredictor:
    """Bộ suy luận (Inference Engine) nhận diện Cảm xúc và Sắc thái bình luận."""

    def __init__(self, model_dir: Path = BEST_MODEL_DIR, device: str = None):
        import json
        if device is None:
            self.device = "cuda" if torch and torch.cuda.is_available() else "cpu"
        else:
            self.device = device

        model_str = str(model_dir)
        self.model_dir = model_str
        self.toxic_threshold = 0.20  # Mặc định tối ưu là 0.20

        # Tự động đọc cấu hình tối ưu nếu có file inference_config.json
        if os.path.exists(model_str):
            cfg_file = Path(model_str) / "inference_config.json"
            if cfg_file.exists():
                try:
                    with open(cfg_file, "r", encoding="utf-8") as f:
                        cfg = json.load(f)
                        self.toxic_threshold = float(cfg.get("toxic_threshold", 0.20))
                        print(f"[*] Đã nạp inference_config.json: toxic_threshold = {self.toxic_threshold}")
                except Exception as e:
                    print(f"[!] Không thể đọc inference_config.json: {e}")
        elif "/" in model_str:
            try:
                from huggingface_hub import hf_hub_download
                downloaded_cfg = hf_hub_download(repo_id=model_str, filename="inference_config.json")
                with open(downloaded_cfg, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    self.toxic_threshold = float(cfg.get("toxic_threshold", 0.20))
                    print(f"[*] Đã tải inference_config.json từ Hub: toxic_threshold = {self.toxic_threshold}")
            except Exception:
                pass

        print(f"[*] Khởi tạo EmotionPredictor trên thiết bị: {self.device}")
        self.model, self.tokenizer = load_inference_model_and_tokenizer(self.model_dir)
        self.model.to(self.device)
        self.model.eval()
        self._cache: Dict[str, Dict[str, Any]] = {}

    def predict_one(self, text: str) -> Dict[str, Any]:
        """Phân tích một bình luận."""
        results = self.predict_batch([text])
        return results[0]

    def _infer_chunk(self, chunk_texts: List[str], max_length: int = 128) -> List[Dict[str, Any]]:
        segmented_texts = [segment_words(t) for t in chunk_texts]
        inputs = self.tokenizer(
            segmented_texts,
            truncation=True,
            padding=True,
            max_length=max_length,
            return_tensors="pt"
        ).to(self.device)

        with torch.no_grad():
            outputs = self.model(**inputs)
            logits = outputs.logits
            probs = F.softmax(logits, dim=-1).cpu().numpy()

        chunk_results = []
        for idx, text in enumerate(chunk_texts):
            prob_dict = {
                EMOTION_LABELS[i]: float(probs[idx][i])
                for i in range(len(EMOTION_LABELS))
            }

            best_emotion_idx = int(probs[idx].argmax())
            best_emotion = ID2LABEL[best_emotion_idx]
            best_emotion_score = float(probs[idx][best_emotion_idx])

            p_pos = prob_dict.get("Enjoyment", 0.0)
            p_neg = sum(prob_dict.get(e, 0.0) for e in NEGATIVE_EMOTIONS)
            p_neu = sum(prob_dict.get(e, 0.0) for e in ["Other", "Surprise"])

            sentiment = EMOTION_TO_SENTIMENT.get(best_emotion, "NEUTRAL")
            sentiment_score = best_emotion_score

            p_toxic = prob_dict.get("Anger", 0.0) + prob_dict.get("Disgust", 0.0)
            is_toxic = bool(p_toxic >= self.toxic_threshold)
            suggested_status = "held" if is_toxic else "visible"

            chunk_results.append({
                "text": text,
                "emotion": best_emotion,
                "emotion_vi": EMOTION_VI.get(best_emotion, best_emotion),
                "emotion_score": round(best_emotion_score, 4),
                "sentiment": sentiment,
                "sentiment_vi": SENTIMENT_VI.get(sentiment, sentiment),
                "sentiment_score": round(sentiment_score, 4),
                "sentiment_distribution": {
                    "positive": round(p_pos, 4),
                    "negative": round(p_neg, 4),
                    "neutral": round(p_neu, 4)
                },
                "emotion_probabilities": {k: round(v, 4) for k, v in prob_dict.items()},
                "is_negative": sentiment == "NEGATIVE",
                "is_toxic": is_toxic,
                "moderation_suggested_status": suggested_status
            })
        return chunk_results

    def predict_batch(self, texts: List[str], max_length: int = 128, batch_size: int = 32) -> List[Dict[str, Any]]:
        """Phân tích hàng loạt danh sách bình luận (có cache và mini-batch 32 tối ưu CPU)."""
        if not texts:
            return []

        # Tách các văn bản chưa có trong cache
        missing_texts = []
        for t in texts:
            if t not in self._cache and t not in missing_texts:
                missing_texts.append(t)

        # Xử lý theo từng khối (chunk) 32 để tận dụng tối đa cache CPU
        for i in range(0, len(missing_texts), batch_size):
            chunk = missing_texts[i:i + batch_size]
            chunk_results = self._infer_chunk(chunk, max_length=max_length)
            for res in chunk_results:
                if len(self._cache) > 20000:
                    self._cache.clear()
                self._cache[res["text"]] = res

        return [self._cache.get(t, {
            "text": t,
            "emotion": "Other",
            "emotion_vi": "Khác",
            "emotion_score": 1.0,
            "sentiment": "NEUTRAL",
            "sentiment_vi": "Trung lập",
            "sentiment_score": 1.0,
            "sentiment_distribution": {"positive": 0.0, "negative": 0.0, "neutral": 1.0},
            "emotion_probabilities": {},
            "is_negative": False,
            "is_toxic": False,
            "moderation_suggested_status": "visible"
        }) for t in texts]
