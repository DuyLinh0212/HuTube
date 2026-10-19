import os
import sys
from pathlib import Path
from typing import List, Optional
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

# Thêm đường dẫn gốc vào sys.path
CURRENT_DIR = Path(__file__).resolve().parent
ROOT_DIR = CURRENT_DIR.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from src.config import BEST_MODEL_DIR, EMOTION_LABELS, EMOTION_TO_SENTIMENT
from src.predictor import EmotionPredictor

app = FastAPI(
    title="HuTube Comment Emotion & Sentiment Analysis Service",
    description="Microservice nhận diện cảm xúc (UIT-VSMEC) và phân loại sắc thái bình luận tích cực/tiêu cực cho HuTube.",
    version="1.0.0"
)

# Khởi tạo predictor lười (lazy load hoặc startup)
predictor: Optional[EmotionPredictor] = None

@app.on_event("startup")
def startup_event():
    global predictor
    try:
        predictor = EmotionPredictor(model_dir=BEST_MODEL_DIR)
        print("[+] EmotionPredictor đã sẵn sàng phục vụ API!")
    except Exception as e:
        print(f"[!] Cảnh báo: Chưa thể tải mô hình ({e}). API sẽ báo lỗi nếu gọi predict.")

# Schemas
class AnalyzeRequest(BaseModel):
    text: str = Field(..., description="Nội dung bình luận tiếng Việt cần phân tích", example="Video rất hay và ý nghĩa, cảm ơn tác giả!")

class BatchAnalyzeRequest(BaseModel):
    texts: List[str] = Field(..., description="Danh sách các bình luận cần phân tích", example=["Hay quá bạn ơi", "Video dở tệ phí thời gian"])

class CommentModerationRequest(BaseModel):
    comment_id: Optional[str] = Field(None, description="UUID bình luận (nếu có)", example="00000000-0000-0000-0000-000000000000")
    video_id: Optional[str] = Field(None, description="UUID video", example="11111111-1111-1111-1111-111111111111")
    content: str = Field(..., description="Nội dung bình luận", example="Thằng admin làm video như rác rưởi")

class ModerationResponse(BaseModel):
    comment_id: Optional[str]
    status: str = Field(..., description="'visible' hoặc 'held' theo schema database HuTube")
    sentiment: str = Field(..., description="'POSITIVE', 'NEGATIVE', hoặc 'NEUTRAL'")
    sentiment_vi: str = Field(..., description="'Tích cực', 'Tiêu cực', hoặc 'Trung tính'")
    emotion: str
    emotion_vi: str
    emotion_score: float
    is_toxic: bool
    reason: str

@app.get("/health", tags=["System"])
def health_check():
    return {
        "status": "healthy",
        "service": "hutube-emotion-sentiment-service",
        "model_loaded": predictor is not None,
        "device": getattr(predictor, "device", "unknown") if predictor else None
    }

@app.get("/api/v1/meta", tags=["Metadata"])
def get_metadata():
    return {
        "emotions": EMOTION_LABELS,
        "emotion_to_sentiment_mapping": EMOTION_TO_SENTIMENT
    }

@app.post("/api/v1/analyze", tags=["Inference"])
def analyze_single_comment(req: AnalyzeRequest):
    if predictor is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Mô hình chưa được nạp hoặc chưa train xong. Hãy kiểm tra checkpoint tại saved_models/."
        )
    if not req.text.strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Nội dung bình luận không được rỗng.")

    return predictor.predict_one(req.text)

@app.post("/api/v1/analyze-batch", tags=["Inference"])
def analyze_batch_comments(req: BatchAnalyzeRequest):
    if predictor is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Mô hình chưa được nạp hoặc chưa train xong."
        )
    return predictor.predict_batch(req.texts)

@app.post("/api/v1/comments/moderate", response_model=ModerationResponse, tags=["HuTube Integration"])
def moderate_hutube_comment(req: CommentModerationRequest):
    """Endpoint chuyên dụng cho HuTube Backend (ASP.NET Core) gọi khi người dùng đăng bình luận mới."""
    if predictor is None:
        # Fallback an toàn nếu mô hình chưa bật: cho phép bình thường
        return ModerationResponse(
            comment_id=req.comment_id,
            status="visible",
            sentiment="NEUTRAL",
            sentiment_vi="Trung tính",
            emotion="Other",
            emotion_vi="Bình thường / Khác",
            emotion_score=1.0,
            is_toxic=False,
            reason="Service đang ở chế độ bypass."
        )

    res = predictor.predict_one(req.content)
    
    reason = "Bình luận bình thường."
    if res["is_toxic"]:
        reason = f"Phát hiện cảm xúc tiêu cực gay gắt ({res['emotion_vi']} {res['emotion_score']*100:.1f}%)."
    elif res["sentiment"] == "NEGATIVE":
        reason = f"Bình luận mang sắc thái tiêu cực ({res['emotion_vi']})."
    elif res["sentiment"] == "POSITIVE":
        reason = "Bình luận tích cực / khen ngợi."

    return ModerationResponse(
        comment_id=req.comment_id,
        status=res["moderation_suggested_status"],
        sentiment=res["sentiment"],
        sentiment_vi=res["sentiment_vi"],
        emotion=res["emotion"],
        emotion_vi=res["emotion_vi"],
        emotion_score=res["emotion_score"],
        is_toxic=res["is_toxic"],
        reason=reason
    )

if __name__ == "__main__":
    import uvicorn
    # Mặc định chạy ở cổng 8001
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
