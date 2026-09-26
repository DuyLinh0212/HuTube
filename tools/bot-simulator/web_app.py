from __future__ import annotations

import asyncio
from dataclasses import asdict
from datetime import datetime, timezone
import json
import os
from typing import Any, List, Optional
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, Field

from persona_data import (
    COMMENTS_BY_CATEGORY,
    add_comment_to_category,
    delete_comment_from_category,
    get_comments_for_category,
)
from simulator_engine import HuTubeSimulatorEngine, simulator_engine

app = FastAPI(title="HuTube Bot Simulator & Interaction Seeder", version="2.0.0")

# Cấu hình CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

engine = simulator_engine


class CreateUserByNameRequest(BaseModel):
    display_name: str
    password: str = "UserPass@123"


class AddCommentRequest(BaseModel):
    category_slug: str
    comment: str


class DeleteCommentRequest(BaseModel):
    category_slug: str
    index: int


class TargetUserRequest(BaseModel):
    display_name: str = Field(default="TVH Sports")
    username: str = Field(default="tvhsports")
    password: str = Field(default="UserPass@123")
    users: Optional[List[dict]] = None
    category_id: str
    category_slug: str
    video_count: int = Field(default=20, ge=1, le=100)
    watch_ratio: float = Field(default=0.75, ge=0.05, le=1.0)
    like_ratio: float = Field(default=0.80, ge=0.0, le=1.0)
    dislike_ratio: float = Field(default=0.05, ge=0.0, le=1.0)
    rating_ratio: float = Field(default=0.85, ge=0.0, le=1.0)
    rating_mode: str = Field(default="fixed_5")
    custom_rating_score: int = Field(default=5, ge=1, le=5)
    comment_ratio: float = Field(default=0.50, ge=0.0, le=1.0)
    comments_list: Optional[List[str]] = None
    subscribe_ratio: float = Field(default=0.40, ge=0.0, le=1.0)
    enable_subscribe: bool = True
    delay: float = Field(default=0.2, ge=0.0, le=5.0)


class SwarmRequest(BaseModel):
    bot_count: int = Field(default=10, ge=1, le=100)
    videos_per_bot: int = Field(default=15, ge=1, le=50)
    preferred_category_ratio: float = Field(default=0.8, ge=0.5, le=1.0)
    like_ratio: float = Field(default=0.70, ge=0.0, le=1.0)
    dislike_ratio: float = Field(default=0.20, ge=0.0, le=1.0)
    comment_ratio: float = Field(default=0.35, ge=0.0, le=1.0)
    rating_ratio: float = Field(default=0.60, ge=0.0, le=1.0)
    subscribe_ratio: float = Field(default=0.35, ge=0.0, le=1.0)
    comments_list: Optional[List[str]] = None
    delay: float = Field(default=0.15, ge=0.0, le=5.0)


@app.get("/api/status")
async def get_status():
    return {
        "is_running": engine.is_running,
        "total_logs": len(engine.logs),
        "total_interactions": len(engine.matrix),
    }


@app.get("/api/categories")
async def get_categories():
    categories = await engine.get_categories()
    return categories


@app.get("/api/users")
async def get_users():
    users = await engine.get_registered_users()
    return users


@app.post("/api/users/create")
async def create_user_by_name_endpoint(req: CreateUserByNameRequest):
    if not req.display_name or not req.display_name.strip():
        return JSONResponse(status_code=400, content={"error": "Vui lòng nhập họ tên người dùng."})
    user = await engine.create_user_by_name(req.display_name.strip(), req.password)
    return user


@app.get("/api/comments")
async def get_comments(category: str = "music"):
    comments = get_comments_for_category(category)
    return {"category": category, "comments": comments}


@app.post("/api/comments")
async def add_comment(req: AddCommentRequest):
    success = add_comment_to_category(req.category_slug, req.comment)
    comments = get_comments_for_category(req.category_slug)
    return {"success": success, "comments": comments}


@app.delete("/api/comments")
async def delete_comment(category: str, index: int):
    success = delete_comment_from_category(category, index)
    comments = get_comments_for_category(category)
    return {"success": success, "comments": comments}


@app.post("/api/simulate/target")
async def simulate_target(req: TargetUserRequest):
    if engine.is_running:
        return JSONResponse(status_code=400, content={"error": "Một tiến trình mô phỏng khác đang chạy. Hãy đợi hoặc bấm Dừng."})

    asyncio.create_task(
        engine.run_target_user_simulation(
            username=req.username,
            display_name=req.display_name,
            password=req.password,
            category_id=req.category_id,
            category_slug=req.category_slug,
            video_count=req.video_count,
            watch_ratio=req.watch_ratio,
            like_ratio=req.like_ratio,
            dislike_ratio=req.dislike_ratio,
            rating_ratio=req.rating_ratio,
            rating_mode=req.rating_mode,
            custom_rating_score=req.custom_rating_score,
            comment_ratio=req.comment_ratio,
            custom_comments_list=req.comments_list,
            subscribe_ratio=req.subscribe_ratio,
            enable_subscribe=req.enable_subscribe,
            delay_between_requests=req.delay,
            users_list=req.users,
        )
    )
    return {"message": "Đã bắt đầu kịch bản mô phỏng người dùng mục tiêu."}


@app.post("/api/simulate/swarm")
async def simulate_swarm(req: SwarmRequest):
    if engine.is_running:
        return JSONResponse(status_code=400, content={"error": "Một tiến trình mô phỏng khác đang chạy. Hãy đợi hoặc bấm Dừng."})

    asyncio.create_task(
        engine.run_swarm_simulation(
            bot_count=req.bot_count,
            videos_per_bot=req.videos_per_bot,
            preferred_category_ratio=req.preferred_category_ratio,
            like_ratio=req.like_ratio,
            dislike_ratio=req.dislike_ratio,
            comment_ratio=req.comment_ratio,
            rating_ratio=req.rating_ratio,
            subscribe_ratio=req.subscribe_ratio,
            custom_comments_list=req.comments_list,
            delay_between_requests=req.delay,
        )
    )
    return {"message": "Đã bắt đầu kịch bản mô phỏng cụm Bot Persona."}


@app.post("/api/simulate/stop")
async def simulate_stop():
    engine.stop()
    return {"message": "Đã gửi tín hiệu dừng mô phỏng."}


@app.post("/api/logs/clear")
async def clear_logs():
    engine.clear_logs()
    return {"message": "Đã xóa toàn bộ logs."}


@app.get("/api/logs/recent")
async def get_recent_logs(limit: int = 50):
    return engine.get_recent_logs(limit=limit)


@app.get("/api/matrix")
async def get_matrix():
    return engine.get_matrix_records()


@app.get("/api/matrix/export.csv")
async def export_matrix_csv():
    records = engine.get_matrix_records()
    header = "user_id,username,display_name,video_id,video_title,category_slug,watch_ratio,watched_seconds,video_duration,like,dislike,rating,comment,subscribed,timestamp\n"
    lines = [header]
    for r in records:
        title_esc = f'"{r.get("video_title", "").replace("\"", "\"\"")}"'
        cmt_esc = f'"{r.get("comment", "").replace("\"", "\"\"")}"' if r.get("comment") else ""
        lines.append(
            f'{r.get("user_id","")},{r.get("username","")},{r.get("display_name","")},'
            f'{r.get("video_id","")},{title_esc},{r.get("category_slug","")},'
            f'{r.get("watch_ratio",0)},{r.get("watched_seconds",0)},{r.get("video_duration",0)},'
            f'{1 if r.get("like") else 0},{1 if r.get("dislike") else 0},'
            f'{r.get("rating") if r.get("rating") is not None else ""},'
            f'{cmt_esc},{1 if r.get("subscribed") else 0},{r.get("timestamp","")}\n'
        )
    csv_data = "".join(lines)
    return StreamingResponse(
        iter([csv_data]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=cf_interactions_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"},
    )


@app.get("/api/logs/stream")
async def stream_logs(request: Request):
    """Server-Sent Events (SSE) để truyền logs realtime về trình duyệt"""
    async def event_generator():
        last_id = 0
        while True:
            if await request.is_disconnected():
                break

            current_logs = engine.logs
            if len(current_logs) > last_id:
                new_items = current_logs[last_id:]
                last_id = len(current_logs)
                for item in new_items:
                    payload = asdict(item) if hasattr(item, "__dataclass_fields__") else item
                    yield f"data: {json.dumps(payload)}\n\n"
            else:
                yield ": keepalive\n\n"
            await asyncio.sleep(0.4)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return Response(status_code=204)


@app.get("/", response_class=HTMLResponse)
async def index_page():
    return HTML_CONTENT


HTML_CONTENT = """<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HuTube Bot Simulator & Interaction Seeder Pro</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🤖</text></svg>">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-dark: #080c16;
      --bg-surface: #0e1526;
      --bg-card: rgba(17, 24, 39, 0.78);
      --bg-card-hover: rgba(30, 41, 59, 0.85);
      --border: rgba(255, 255, 255, 0.08);
      --border-focus: rgba(99, 102, 241, 0.5);
      --primary: #3b82f6;
      --primary-hover: #2563eb;
      --primary-glow: rgba(59, 130, 246, 0.35);
      --success: #10b981;
      --warning: #f59e0b;
      --danger: #ef4444;
      --accent-sub: #ec4899;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --font-sans: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      --font-mono: 'JetBrains Mono', monospace;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg-dark);
      background-image: 
        radial-gradient(circle at 10% 10%, rgba(59, 130, 246, 0.09), transparent 35%),
        radial-gradient(circle at 90% 90%, rgba(139, 92, 246, 0.08), transparent 35%),
        radial-gradient(circle at 50% 50%, rgba(236, 72, 153, 0.03), transparent 50%);
      color: var(--text);
      font-family: var(--font-sans);
      line-height: 1.5;
      padding: 24px;
      min-height: 100vh;
    }

    .container { max-width: 1560px; margin: 0 auto; }

    /* Header */
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 20px;
      margin-bottom: 24px;
      border-bottom: 1px solid var(--border);
      flex-wrap: wrap;
      gap: 16px;
    }

    .brand { display: flex; align-items: center; gap: 14px; }
    .brand-logo {
      background: linear-gradient(135deg, #ef4444 0%, #8b5cf6 50%, #3b82f6 100%);
      width: 46px; height: 46px; border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-weight: 800; font-size: 22px; color: #fff;
      box-shadow: 0 0 20px rgba(59, 130, 246, 0.4);
    }
    .brand-title h1 {
      font-size: 20px; font-weight: 700; letter-spacing: -0.3px;
      background: linear-gradient(90deg, #ffffff 0%, #cbd5e1 100%);
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    }
    .brand-title p { font-size: 13px; color: var(--text-muted); }

    .header-pills { display: flex; align-items: center; gap: 10px; }
    .backend-pill {
      display: inline-flex; align-items: center; gap: 6px;
      padding: 6px 14px; border-radius: 9999px;
      font-size: 12px; font-weight: 500;
      background: rgba(30, 41, 59, 0.6); color: #93c5fd;
      border: 1px solid rgba(59, 130, 246, 0.25);
    }
    .status-badge {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 6px 16px; border-radius: 9999px;
      font-size: 13px; font-weight: 600;
      background: rgba(16, 185, 129, 0.12); color: var(--success);
      border: 1px solid rgba(16, 185, 129, 0.3);
      transition: all 0.3s ease;
    }
    .status-badge.running {
      background: rgba(59, 130, 246, 0.15); color: #60a5fa;
      border-color: rgba(59, 130, 246, 0.4);
      box-shadow: 0 0 16px rgba(59, 130, 246, 0.3);
    }
    .pulse-dot {
      width: 8px; height: 8px; border-radius: 50%; background: currentColor;
      box-shadow: 0 0 10px currentColor;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }

    /* Metrics Grid */
    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .metric-card {
      background: var(--bg-card);
      backdrop-filter: blur(12px);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 16px 20px;
      display: flex; flex-direction: column; gap: 6px;
      transition: all 0.25s ease;
      position: relative; overflow: hidden;
    }
    .metric-card::before {
      content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
      background: linear-gradient(90deg, #3b82f6, #8b5cf6);
      opacity: 0; transition: opacity 0.25s;
    }
    .metric-card:hover {
      border-color: rgba(255, 255, 255, 0.15);
      transform: translateY(-2px);
    }
    .metric-card:hover::before { opacity: 1; }
    .metric-label {
      font-size: 12px; font-weight: 600; text-transform: uppercase;
      letter-spacing: 0.6px; color: var(--text-muted);
      display: flex; align-items: center; justify-content: space-between;
    }
    .metric-value {
      font-family: var(--font-mono);
      font-size: 26px; font-weight: 700; color: #fff;
    }

    /* Layout Split */
    .grid-layout {
      display: grid;
      grid-template-columns: 560px 1fr;
      gap: 24px;
      align-items: start;
    }
    @media (max-width: 1200px) {
      .grid-layout { grid-template-columns: 1fr; }
    }

    /* Card styling */
    .card {
      background: var(--bg-card);
      backdrop-filter: blur(12px);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 22px;
      margin-bottom: 20px;
      box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.5);
    }
    .card-title {
      font-size: 15px; font-weight: 700; margin-bottom: 16px;
      display: flex; align-items: center; justify-content: space-between;
      color: #f1f5f9;
    }

    /* Quick User Selection Panel */
    .user-picker-card {
      background: linear-gradient(145deg, rgba(30, 41, 59, 0.7), rgba(15, 23, 42, 0.8));
      border: 1px solid rgba(99, 102, 241, 0.25);
      border-radius: 14px;
      padding: 18px;
      margin-bottom: 20px;
    }
    .user-picker-header {
      display: flex; justify-content: space-between; align-items: center;
      margin-bottom: 12px;
    }
    .user-picker-title {
      font-size: 13px; font-weight: 700; text-transform: uppercase;
      letter-spacing: 0.5px; color: #93c5fd;
      display: flex; align-items: center; gap: 8px;
    }
    .btn-refresh {
      background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border);
      color: #cbd5e1; border-radius: 6px; padding: 4px 10px; font-size: 11px;
      cursor: pointer; display: inline-flex; align-items: center; gap: 4px;
      transition: all 0.2s;
    }
    .btn-refresh:hover { background: rgba(255, 255, 255, 0.1); color: #fff; }

    /* Form Controls */
    .form-group { margin-bottom: 16px; }
    .form-row {
      display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px;
    }
    label {
      display: flex; justify-content: space-between; align-items: center;
      font-size: 12px; font-weight: 600; color: #cbd5e1; margin-bottom: 6px;
    }
    .val-label {
      font-family: var(--font-mono); font-size: 12px; font-weight: 700;
      color: #60a5fa;
    }
    .form-control {
      width: 100%; padding: 10px 14px;
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid var(--border);
      border-radius: 8px;
      color: #fff; font-size: 13px; font-family: inherit;
      transition: all 0.2s;
    }
    .form-control:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px var(--primary-glow);
    }
    select.form-control {
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 24 24' stroke='%2394a3b8'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M19 9l-7 7-7-7'%3E%3C/path%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 12px center;
      background-size: 16px;
      padding-right: 38px;
    }

    /* Range Sliders */
    input[type="range"] {
      width: 100%; height: 6px;
      background: #1e293b; border-radius: 9999px;
      outline: none; appearance: none; -webkit-appearance: none;
      margin: 8px 0;
    }
    input[type="range"]::-webkit-slider-thumb {
      appearance: none; -webkit-appearance: none;
      width: 18px; height: 18px; border-radius: 50%;
      background: #3b82f6; cursor: pointer;
      box-shadow: 0 0 10px rgba(59, 130, 246, 0.6);
      transition: transform 0.15s ease;
    }
    input[type="range"]::-webkit-slider-thumb:hover { transform: scale(1.15); }
    #targetLikeRatio::-webkit-slider-thumb { background: #10b981; box-shadow: 0 0 10px rgba(16, 185, 129, 0.6); }
    #targetDislikeRatio::-webkit-slider-thumb { background: #ef4444; box-shadow: 0 0 10px rgba(239, 68, 68, 0.6); }
    #targetSubscribeRatio::-webkit-slider-thumb { background: #ec4899; box-shadow: 0 0 10px rgba(236, 72, 153, 0.6); }
    #targetRatingRatio::-webkit-slider-thumb { background: #f59e0b; box-shadow: 0 0 10px rgba(245, 158, 11, 0.6); }

    /* Visual Distribution Bar */
    .distribution-bar-wrap {
      margin: 12px 0 16px 0;
      background: rgba(15, 23, 42, 0.9);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 10px 14px;
    }
    .distribution-bar {
      display: flex; height: 10px; border-radius: 9999px;
      overflow: hidden; margin-bottom: 8px;
      background: #1e293b;
    }
    .dist-segment { transition: width 0.25s ease; }
    .dist-like { background: #10b981; }
    .dist-dislike { background: #ef4444; }
    .dist-none { background: #64748b; }
    .dist-legend {
      display: flex; justify-content: space-between; font-size: 11px; color: var(--text-muted);
    }
    .dist-item { display: inline-flex; align-items: center; gap: 5px; }
    .dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }

    /* Info notice box */
    .info-box {
      background: rgba(59, 130, 246, 0.08); border: 1px dashed rgba(59, 130, 246, 0.25);
      border-radius: 10px; padding: 10px 14px; font-size: 12px; color: #cbd5e1; margin-bottom: 14px;
      line-height: 1.5;
    }
    .info-box strong { color: #60a5fa; }

    /* Tabs */
    .tabs-header {
      display: flex; gap: 8px; margin-bottom: 18px;
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid var(--border);
      border-radius: 10px; padding: 4px;
    }
    .tab-btn {
      flex: 1; padding: 9px 14px; border: none; border-radius: 7px;
      background: transparent; color: var(--text-muted); font-size: 13px;
      font-weight: 600; cursor: pointer; transition: all 0.2s;
    }
    .tab-btn.active {
      background: rgba(59, 130, 246, 0.2);
      color: #93c5fd;
      border: 1px solid rgba(59, 130, 246, 0.3);
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
    }
    .tab-content { display: none; }
    .tab-content.active { display: block; }

    /* Buttons */
    .btn {
      display: inline-flex; align-items: center; justify-content: center; gap: 8px;
      width: 100%; padding: 12px 18px; border-radius: 10px; font-size: 14px;
      font-weight: 700; cursor: pointer; transition: all 0.2s; border: none;
      font-family: inherit;
    }
    .btn-primary {
      background: linear-gradient(135deg, #2563eb 0%, #4f46e5 100%);
      color: #fff;
      box-shadow: 0 4px 16px rgba(37, 99, 235, 0.4);
    }
    .btn-primary:hover {
      background: linear-gradient(135deg, #1d4ed8 0%, #4338ca 100%);
      transform: translateY(-1px);
      box-shadow: 0 6px 20px rgba(37, 99, 235, 0.5);
    }
    .btn-danger {
      background: rgba(239, 68, 68, 0.15);
      border: 1px solid rgba(239, 68, 68, 0.3);
      color: #f87171;
    }
    .btn-danger:hover {
      background: rgba(239, 68, 68, 0.25);
      color: #fff;
    }

    /* Comment Pool Management */
    .comment-tags-container {
      max-height: 200px; overflow-y: auto;
      border: 1px solid var(--border); border-radius: 10px;
      padding: 10px; background: rgba(15, 23, 42, 0.8);
      display: flex; flex-direction: column; gap: 6px;
      margin-bottom: 12px;
    }
    .comment-tag-item {
      display: flex; justify-content: space-between; align-items: center;
      background: rgba(30, 41, 59, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.05);
      border-radius: 6px; padding: 6px 10px; font-size: 12px; color: #e2e8f0;
    }
    .btn-del-cmt {
      background: transparent; border: none; color: #ef4444;
      cursor: pointer; font-size: 12px; padding: 2px 6px;
      border-radius: 4px; transition: background 0.15s;
    }
    .btn-del-cmt:hover { background: rgba(239, 68, 68, 0.2); }

    /* macOS Styled Terminal */
    .terminal-window {
      background: #090e1a;
      border: 1px solid var(--border);
      border-radius: 14px;
      overflow: hidden;
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.6);
      margin-bottom: 20px;
    }
    .terminal-topbar {
      background: #0f172a;
      padding: 12px 16px;
      display: flex; justify-content: space-between; align-items: center;
      border-bottom: 1px solid var(--border);
    }
    .mac-dots { display: flex; gap: 7px; align-items: center; }
    .mac-dot { width: 11px; height: 11px; border-radius: 50%; }
    .dot-red { background: #ef4444; }
    .dot-yellow { background: #f59e0b; }
    .dot-green { background: #10b981; }
    .terminal-title {
      font-size: 12px; font-weight: 600; color: #94a3b8; font-family: var(--font-mono);
    }
    .terminal-controls { display: flex; gap: 8px; align-items: center; }
    .btn-term {
      background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border);
      color: #94a3b8; border-radius: 6px; padding: 4px 10px; font-size: 11px;
      cursor: pointer; font-family: inherit; transition: all 0.2s;
    }
    .btn-term:hover { background: rgba(255, 255, 255, 0.1); color: #fff; }
    .terminal-body {
      height: 480px; overflow-y: auto; padding: 14px;
      font-family: var(--font-mono); font-size: 12px;
      background: #080d1a;
    }
    .log-line {
      display: flex; align-items: flex-start; gap: 10px;
      padding: 4px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.02);
      word-break: break-word; line-height: 1.45;
    }
    .log-time { color: #64748b; font-size: 11px; flex-shrink: 0; }
    .log-tag {
      font-size: 10px; font-weight: 700; padding: 2px 6px; border-radius: 4px;
      text-transform: uppercase; flex-shrink: 0;
    }
    .log-tag.INFO { background: rgba(59, 130, 246, 0.15); color: #60a5fa; }
    .log-tag.SUCCESS { background: rgba(16, 185, 129, 0.15); color: #34d399; }
    .log-tag.WARN { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
    .log-tag.ERROR { background: rgba(239, 68, 68, 0.2); color: #f87171; }
    .log-user { color: #cbd5e1; font-weight: 600; flex-shrink: 0; }
    .log-msg { color: #e2e8f0; flex-grow: 1; }

    /* Interaction Table */
    .table-card {
      background: var(--bg-card);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 18px;
    }
    .table-wrap {
      max-height: 300px; overflow-y: auto;
      border: 1px solid var(--border); border-radius: 10px;
    }
    table { width: 100%; border-collapse: collapse; font-size: 12.5px; text-align: left; }
    th {
      position: sticky; top: 0; background: #0f172a;
      padding: 10px 14px; font-weight: 700; color: #94a3b8;
      border-bottom: 1px solid var(--border);
    }
    td { padding: 8px 14px; border-bottom: 1px solid var(--border); }
    tr:hover td { background: rgba(255, 255, 255, 0.02); }
    .badge {
      display: inline-block; padding: 2px 8px; border-radius: 4px;
      font-size: 11px; font-weight: 600;
    }
    .badge-like { background: rgba(16, 185, 129, 0.15); color: #34d399; }
    .badge-dislike { background: rgba(239, 68, 68, 0.15); color: #f87171; }
    .badge-sub { background: rgba(236, 72, 153, 0.15); color: #f472b6; }
    .badge-star { color: #fbbf24; font-weight: 700; }

    /* Multi User Checklist */
    .user-checklist {
      max-height: 200px;
      overflow-y: auto;
      border: 1px solid var(--border);
      border-radius: 10px;
      background: rgba(15, 23, 42, 0.9);
      padding: 8px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      margin-bottom: 12px;
    }
    .user-item-card {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 8px 12px;
      background: rgba(30, 41, 59, 0.45);
      border: 1px solid var(--border);
      border-radius: 8px;
      cursor: pointer;
      user-select: none;
      transition: all 0.2s;
    }
    .user-item-card:hover {
      background: rgba(59, 130, 246, 0.1);
      border-color: rgba(59, 130, 246, 0.3);
    }
    .user-item-card.selected {
      background: rgba(59, 130, 246, 0.18);
      border-color: rgba(59, 130, 246, 0.5);
    }
    .user-item-card input[type="checkbox"] {
      width: 16px;
      height: 16px;
      accent-color: #3b82f6;
      cursor: pointer;
    }
    .user-avatar-badge {
      width: 28px;
      height: 28px;
      border-radius: 50%;
      background: linear-gradient(135deg, #3b82f6, #8b5cf6);
      color: #fff;
      font-weight: 700;
      font-size: 11px;
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .user-text-info {
      flex-grow: 1;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .user-dname {
      font-weight: 600;
      font-size: 12.5px;
      color: #f1f5f9;
    }
    .user-uname {
      font-size: 11px;
      color: #94a3b8;
      font-family: var(--font-mono);
    }
  </style>
</head>
<body>
  <div class="container">
    <!-- Header -->
    <header>
      <div class="brand">
        <div class="brand-logo">H</div>
        <div class="brand-title">
          <h1>HuTube Bot Simulator & Interaction Seeder</h1>
          <p>Tự sinh hành vi người dùng, đánh giá sao, like/dislike độc quyền & xuất ma trận CF</p>
        </div>
      </div>
      <div class="header-pills">
        <span class="backend-pill">
          🔌 HuTube API: <code>localhost:5080/api/v1</code>
        </span>
        <span id="statusBadge" class="status-badge">
          <span class="pulse-dot"></span> Sẵn sàng
        </span>
      </div>
    </header>

    <!-- Metrics -->
    <div class="metrics-grid">
      <div class="metric-card">
        <div class="metric-label">
          <span>Tổng Tương Tác</span>
          <span>📊</span>
        </div>
        <div id="statInteractions" class="metric-value">0</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">
          <span>Lượt Thích (Likes)</span>
          <span style="color:#10b981;">👍</span>
        </div>
        <div id="statLikes" class="metric-value" style="color:#34d399;">0</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">
          <span>Bình Luận (Comments)</span>
          <span style="color:#3b82f6;">💬</span>
        </div>
        <div id="statComments" class="metric-value" style="color:#60a5fa;">0</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">
          <span>Đánh Giá & Đăng Ký</span>
          <span style="color:#f59e0b;">⭐ / 🔔</span>
        </div>
        <div class="metric-value" style="color:#fbbf24;">
          <span id="statRatings">0</span> <small style="font-size:14px; color:#cbd5e1;">sao</small>
          <span style="font-size:18px; color:#f472b6; margin-left: 6px;">| <span id="statSubs">0</span> sub</span>
        </div>
      </div>
    </div>

    <!-- Main Workspace Layout -->
    <div class="grid-layout">
      <!-- Cột Trái: Control Panel & Forms -->
      <div>
        <!-- KHU VỰC CHỌN NHIỀU NGƯỜI DÙNG ĐỂ CHẠY CÙNG LÚC -->
        <div class="user-picker-card">
          <div class="user-picker-header">
            <span class="user-picker-title">
              <span>👥</span> Chọn Người Dùng Để Chạy (Hỗ Trợ Chọn Nhiều Người)
            </span>
            <div style="display:flex; gap:6px;">
              <button type="button" class="btn-refresh" onclick="selectAllUsers(true)">✅ Chọn hết</button>
              <button type="button" class="btn-refresh" onclick="selectAllUsers(false)">❌ Bỏ chọn</button>
              <button type="button" class="btn-refresh" onclick="loadRegisteredUsers()" title="Tải lại danh sách từ HuTube">🔄</button>
            </div>
          </div>

          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; font-size:12px; color:#94a3b8;">
            <span>Danh sách tài khoản (<span id="totalUsersCount">0</span>):</span>
            <span style="color:#60a5fa; font-weight:600;">Đã chọn: <strong id="selectedUsersCount" style="color:#34d399;">1</strong> người</span>
          </div>

          <!-- Danh sách Checkbox người dùng -->
          <div id="userChecklist" class="user-checklist">
            <!-- Render danh sách checkbox tại đây -->
          </div>

          <!-- Tạo nhanh người dùng mới bằng họ tên -->
          <div style="border-top: 1px dashed var(--border); padding-top: 10px; margin-top: 10px;">
            <label style="margin-bottom: 6px;">
              <span>Hoặc tạo nhanh User mới bằng Họ Tên:</span>
              <span id="createdUserBadge" style="font-size:11px; color:#34d399;"></span>
            </label>
            <div style="display:flex; gap:8px;">
              <input type="text" id="quickNameInput" class="form-control" placeholder="Nhập tên, VD: TVH Sports, Hoàng Nam, Thu Trang...">
              <button type="button" class="btn-term" style="background:#2563eb; color:#fff; border:none; padding:0 16px; font-weight:600; flex-shrink:0;" onclick="handleQuickCreate()">
                ➕ Tạo & Chọn
              </button>
            </div>
          </div>
        </div>

        <!-- TABS ĐIỀU KHIỂN KỊCH BẢN -->
        <div class="card">
          <div class="tabs-header">
            <button class="tab-btn active" onclick="switchTab('targetTab')">🎯 User Mục Tiêu</button>
            <button class="tab-btn" onclick="switchTab('swarmTab')">🤖 Cụm Bot Persona</button>
            <button class="tab-btn" onclick="switchTab('commentsTab')">💬 Kho Bình Luận</button>
          </div>

          <!-- TAB 1: USER MỤC TIÊU -->
          <div id="targetTab" class="tab-content active">
            <form id="targetForm" onsubmit="handleStartTarget(event)">
              <div id="targetUserInfoBox" style="background: rgba(59, 130, 246, 0.08); border: 1px solid rgba(59, 130, 246, 0.25); border-radius: 8px; padding: 10px 14px; margin-bottom: 14px; display: flex; justify-content: space-between; align-items: center;">
                <div>
                  <div style="font-size: 11px; color: #94a3b8; text-transform: uppercase;">Người dùng thực hiện kịch bản:</div>
                  <div id="targetSelectedUsersSummary" style="font-size: 13px; font-weight: 700; color: #93c5fd; margin-top: 2px;">TVH Sports (@tvhsports)</div>
                </div>
                <span id="targetSelectedCountBadge" class="badge" style="background: rgba(16, 185, 129, 0.2); color: #34d399; font-size: 12px; padding: 4px 8px;">1 user</span>
              </div>
              <input type="hidden" id="targetDisplayName" value="TVH Sports">
              <input type="hidden" id="targetUsername" value="tvhsports">

              <div class="form-group">
                <label>Danh mục video mục tiêu</label>
                <select id="targetCategory" class="form-control" onchange="onCategoryChanged()" required>
                  <option value="">Đang tải danh mục từ HuTube...</option>
                </select>
              </div>

              <div class="form-row">
                <div class="form-group">
                  <label>Số lượng video tương tác</label>
                  <input type="number" id="targetCount" class="form-control" value="20" min="1" max="100">
                </div>
                <div class="form-group">
                  <label>Thời lượng xem (watch_ratio) <span id="watchRatioText" class="val-label">75%</span></label>
                  <input type="range" id="targetWatchRatio" min="10" max="100" value="75" oninput="updateRangeText(this, 'watchRatioText')">
                </div>
              </div>

              <!-- RÀNG BUỘC CẢM XÚC ĐỘC QUYỀN & TỶ LỆ HÀNH VI -->
              <div style="margin: 16px 0 10px 0; border-top: 1px dashed var(--border); padding-top: 14px;">
                <div class="info-box">
                  💡 <strong>Quy tắc độc quyền & Thông minh:</strong><br>
                  • <strong>Like & Dislike:</strong> 1 video chỉ có 1 trong 3 trạng thái: <em>Like</em>, <em>Dislike</em> hoặc <em>Chỉ xem</em> (Tổng &le; 100%).<br>
                  • <strong>Đã Like trước đó:</strong> Nếu user đã từng Like video này &rarr; <em>Tự động bỏ qua like</em>, chỉ tăng view và cmt/rating thêm.<br>
                  • <strong>Rating sao:</strong> Khi Like &rarr; 4-5 sao; Khi Dislike &rarr; 1-2 sao; Chỉ xem &rarr; 3 sao; Còn lại &rarr; 0 đánh giá.
                </div>

                <!-- Thước đo phân bổ cảm xúc 3 màu trực quan -->
                <div class="distribution-bar-wrap">
                  <div class="distribution-bar">
                    <div id="distLike" class="dist-segment dist-like" style="width: 80%;"></div>
                    <div id="distDislike" class="dist-segment dist-dislike" style="width: 10%;"></div>
                    <div id="distNone" class="dist-segment dist-none" style="width: 10%;"></div>
                  </div>
                  <div class="dist-legend">
                    <span class="dist-item"><span class="dot dist-like"></span> Like: <strong id="lblLike">80%</strong></span>
                    <span class="dist-item"><span class="dot dist-dislike"></span> Dislike: <strong id="lblDislike">10%</strong></span>
                    <span class="dist-item"><span class="dot dist-none"></span> Chỉ xem: <strong id="lblNone">10%</strong></span>
                  </div>
                </div>

                <div class="form-row">
                  <div class="form-group">
                    <label>👍 Tỷ lệ Thích (Like) <span id="likeRatioText" class="val-label">80%</span></label>
                    <input type="range" id="targetLikeRatio" min="0" max="100" value="80" oninput="updateReactionSliders('like')">
                  </div>
                  <div class="form-group">
                    <label>👎 Tỷ lệ Dislike <span id="dislikeRatioText" class="val-label">10%</span></label>
                    <input type="range" id="targetDislikeRatio" min="0" max="100" value="10" oninput="updateReactionSliders('dislike')">
                  </div>
                </div>

                <div class="form-row">
                  <div class="form-group">
                    <label>⭐ Tỷ lệ Đánh giá sao <span id="ratingRatioText" class="val-label">85%</span></label>
                    <input type="range" id="targetRatingRatio" min="0" max="100" value="85" oninput="updateRangeText(this, 'ratingRatioText')">
                    <div style="font-size:11px; color:#94a3b8; margin-top:2px;">
                      Không đánh giá (0 rating): <strong id="ratingNoneText" style="color:#e2e8f0">15%</strong>
                    </div>
                  </div>
                  <div class="form-group">
                    <label>💬 Tỷ lệ Bình luận <span id="cmtRatioText" class="val-label">50%</span></label>
                    <input type="range" id="targetCommentRatio" min="0" max="100" value="50" oninput="updateRangeText(this, 'cmtRatioText')">
                  </div>
                </div>

                <!-- TỶ LỆ ĐĂNG KÝ KÊNH (SUBSCRIBE RATIO) -->
                <div class="form-group" style="background: rgba(236, 72, 153, 0.06); border: 1px solid rgba(236, 72, 153, 0.2); border-radius: 10px; padding: 12px 14px; margin-top: 10px;">
                  <label style="color:#f472b6;">
                    <span>🔔 Tỷ lệ Đăng ký Kênh (Subscribe Ratio)</span>
                    <span id="subRatioText" class="val-label" style="color:#f472b6;">40%</span>
                  </label>
                  <input type="range" id="targetSubscribeRatio" min="0" max="100" value="40" oninput="updateRangeText(this, 'subRatioText')">
                  <div style="font-size:11px; color:#94a3b8; margin-top:4px;">
                    Mỗi video tương tác có xác suất bấm Subscribe kênh sản xuất video đó.
                  </div>
                </div>
              </div>

              <button type="submit" id="btnStartTarget" class="btn btn-primary" style="margin-top: 8px;">
                🚀 Khởi Chạy Mô Phỏng Cho User Này
              </button>
            </form>
          </div>

          <!-- TAB 2: CỤM BOT PERSONA -->
          <div id="swarmTab" class="tab-content">
            <form id="swarmForm" onsubmit="handleStartSwarm(event)">
              <div class="form-row">
                <div class="form-group">
                  <label>Số lượng Bot sinh ra</label>
                  <input type="number" id="swarmBots" class="form-control" value="10" min="1" max="100">
                </div>
                <div class="form-group">
                  <label>Số video mỗi Bot xem</label>
                  <input type="number" id="swarmVideos" class="form-control" value="15" min="1" max="50">
                </div>
              </div>

              <div class="form-group">
                <label>Tỷ lệ xem đúng gu danh mục chính <span id="prefRatioText" class="val-label">80%</span></label>
                <input type="range" id="swarmPrefRatio" min="50" max="100" value="80" oninput="updateRangeText(this, 'prefRatioText')">
              </div>

              <div class="form-row">
                <div class="form-group">
                  <label>👍 Tỷ lệ Thích (Like) <span id="swarmLikeText" class="val-label">70%</span></label>
                  <input type="range" id="swarmLikeRatio" min="0" max="100" value="70" oninput="updateSwarmSliders('like')">
                </div>
                <div class="form-group">
                  <label>👎 Tỷ lệ Dislike <span id="swarmDislikeText" class="val-label">20%</span></label>
                  <input type="range" id="swarmDislikeRatio" min="0" max="100" value="20" oninput="updateSwarmSliders('dislike')">
                </div>
              </div>

              <div class="form-row">
                <div class="form-group">
                  <label>⭐ Tỷ lệ Đánh giá (Rating) <span id="swarmRatingText" class="val-label">60%</span></label>
                  <input type="range" id="swarmRatingRatio" min="0" max="100" value="60" oninput="updateRangeText(this, 'swarmRatingText')">
                </div>
                <div class="form-group">
                  <label>💬 Tỷ lệ Bình luận (Comment) <span id="swarmCmtText" class="val-label">35%</span></label>
                  <input type="range" id="swarmCmtRatio" min="0" max="100" value="35" oninput="updateRangeText(this, 'swarmCmtText')">
                </div>
              </div>

              <div class="form-group" style="background: rgba(236, 72, 153, 0.06); border: 1px solid rgba(236, 72, 153, 0.2); border-radius: 10px; padding: 12px 14px;">
                <label style="color:#f472b6;">
                  <span>🔔 Tỷ lệ Đăng ký Kênh (Subscribe)</span>
                  <span id="swarmSubText" class="val-label" style="color:#f472b6;">35%</span>
                </label>
                <input type="range" id="swarmSubRatio" min="0" max="100" value="35" oninput="updateRangeText(this, 'swarmSubText')">
              </div>

              <button type="submit" id="btnStartSwarm" class="btn btn-primary" style="margin-top: 8px;">
                ⚡ Khởi Chạy Cụm Bot Persona
              </button>
            </form>
          </div>

          <!-- TAB 3: KHO BÌNH LUẬN -->
          <div id="commentsTab" class="tab-content">
            <div class="form-group">
              <label>Danh mục quản lý</label>
              <select id="cmtCategorySelect" class="form-control" onchange="onCmtCategoryChanged()">
                <option value="music">Âm nhạc (music)</option>
                <option value="sports">Thể thao (sports)</option>
                <option value="cong-nghe">Công nghệ (cong-nghe)</option>
                <option value="game">Game (game)</option>
                <option value="hai-huoc">Hài hước (hai-huoc)</option>
                <option value="default">Mặc định (default)</option>
              </select>
            </div>

            <div class="form-group">
              <label>Danh sách câu bình luận hiện có</label>
              <div id="commentTagsList" class="comment-tags-container">
                <!-- Danh sách tags -->
              </div>
            </div>

            <div class="form-group">
              <label>Thêm câu bình luận mới</label>
              <div style="display:flex; gap:8px;">
                <input type="text" id="newCmtInput" class="form-control" placeholder="Nhập nội dung bình luận khen/góp ý...">
                <button type="button" class="btn-term" style="background:#10b981; color:#fff; border:none; padding:0 14px; font-weight:600; flex-shrink:0;" onclick="handleAddNewComment()">
                  ➕ Thêm
                </button>
              </div>
            </div>
          </div>
        </div>

        <button type="button" onclick="stopSimulation()" class="btn btn-danger" style="margin-bottom: 20px;">
          ⏹️ Dừng Tiến Trình Mô Phỏng Đang Chạy
        </button>
      </div>

      <!-- Cột Phải: Live Realtime Terminal & Ma Trận Tương Tác -->
      <div>
        <!-- TERMINAL CHUYÊN NGHIỆP -->
        <div class="terminal-window">
          <div class="terminal-topbar">
            <div class="mac-dots">
              <span class="mac-dot dot-red"></span>
              <span class="mac-dot dot-yellow"></span>
              <span class="mac-dot dot-green"></span>
              <span class="terminal-title" style="margin-left: 8px;">LIVE CONSOLE — REALTIME STREAM</span>
            </div>
            <div class="terminal-controls">
              <button class="btn-term" onclick="clearLogs()">Xóa logs</button>
              <button class="btn-term" onclick="exportCSV()">📥 Tải CSV</button>
            </div>
          </div>
          <div id="terminal" class="terminal-body">
            <!-- Các dòng logs được stream vào đây -->
          </div>
        </div>

        <!-- BẢNG MA TRẬN TƯƠNG TÁC (USER-ITEM MATRIX) -->
        <div class="table-card">
          <div class="card-title">
            <span>📊 Ma Trận Tương Tác Gần Nhất (User-Item Interaction)</span>
            <span id="matrixCount" style="font-size: 12px; font-weight: 500; color: var(--text-muted);">0 bản ghi</span>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Người xem</th>
                  <th>Video</th>
                  <th>Danh mục</th>
                  <th>Xem</th>
                  <th>Cảm xúc</th>
                  <th>Đánh giá</th>
                  <th>Đăng ký</th>
                  <th>Bình luận</th>
                </tr>
              </thead>
              <tbody id="matrixTableBody">
                <tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 18px;">Chưa có dữ liệu tương tác. Hãy bắt đầu giả lập.</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script>
    let registeredUsers = [];
    let categoriesList = [];
    let currentCategoryComments = [];
    let isRunning = false;

    function switchTab(tabId) {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      event.target.classList.add('active');
      document.getElementById(tabId).classList.add('active');
    }

    function updateRangeText(el, textId) {
      document.getElementById(textId).innerText = el.value + '%';
      if (textId === 'ratingRatioText') {
        const noneRate = 100 - parseInt(el.value);
        document.getElementById('ratingNoneText').innerText = noneRate + '%';
      }
    }

    function updateReactionSliders(source) {
      const likeEl = document.getElementById('targetLikeRatio');
      const dislikeEl = document.getElementById('targetDislikeRatio');
      let likeVal = parseInt(likeEl.value);
      let dislikeVal = parseInt(dislikeEl.value);

      if (source === 'like') {
        if (likeVal + dislikeVal > 100) {
          dislikeVal = 100 - likeVal;
          dislikeEl.value = dislikeVal;
        }
      } else if (source === 'dislike') {
        if (likeVal + dislikeVal > 100) {
          likeVal = 100 - dislikeVal;
          likeEl.value = likeVal;
        }
      }

      const noneVal = 100 - likeVal - dislikeVal;
      document.getElementById('likeRatioText').innerText = likeVal + '%';
      document.getElementById('dislikeRatioText').innerText = dislikeVal + '%';

      document.getElementById('lblLike').innerText = likeVal + '%';
      document.getElementById('lblDislike').innerText = dislikeVal + '%';
      document.getElementById('lblNone').innerText = noneVal + '%';

      document.getElementById('distLike').style.width = likeVal + '%';
      document.getElementById('distDislike').style.width = dislikeVal + '%';
      document.getElementById('distNone').style.width = noneVal + '%';
    }

    function updateSwarmSliders(source) {
      const likeEl = document.getElementById('swarmLikeRatio');
      const dislikeEl = document.getElementById('swarmDislikeRatio');
      let likeVal = parseInt(likeEl.value);
      let dislikeVal = parseInt(dislikeEl.value);

      if (source === 'like') {
        if (likeVal + dislikeVal > 100) {
          dislikeVal = 100 - likeVal;
          dislikeEl.value = dislikeVal;
        }
      } else if (source === 'dislike') {
        if (likeVal + dislikeVal > 100) {
          likeVal = 100 - dislikeVal;
          likeEl.value = likeVal;
        }
      }
      document.getElementById('swarmLikeText').innerText = likeVal + '%';
      document.getElementById('swarmDislikeText').innerText = dislikeVal + '%';
    }

    /* 1. Tải danh sách người dùng đã đăng ký & Hỗ trợ chọn nhiều người */
    let selectedUsersSet = new Set(['tvhsports']);

    async function loadRegisteredUsers() {
      try {
        const res = await fetch('/api/users');
        if (res.ok) {
          registeredUsers = await res.json();
          // Mặc định nếu chưa có ai được chọn thì chọn TVH Sports hoặc user đầu tiên
          if (selectedUsersSet.size === 0 && registeredUsers.length > 0) {
            selectedUsersSet.add(registeredUsers[0].username);
          }
          renderUserChecklist();
        }
      } catch (err) {
        console.error('Lỗi nạp users:', err);
      }
    }

    function renderUserChecklist() {
      const container = document.getElementById('userChecklist');
      const totalSpan = document.getElementById('totalUsersCount');
      if (totalSpan) totalSpan.innerText = registeredUsers.length;

      if (!registeredUsers.length) {
        container.innerHTML = '<div style="color:var(--text-muted); font-size:12px; padding:12px; text-align:center;">Chưa có tài khoản nào. Hãy tạo tài khoản mới bên dưới.</div>';
        updateSelectedUsersDisplay();
        return;
      }

      container.innerHTML = registeredUsers.map(u => {
        const isChecked = selectedUsersSet.has(u.username);
        const initial = (u.displayName || u.username || 'U').trim().charAt(0).toUpperCase();
        return `
          <div class="user-item-card ${isChecked ? 'selected' : ''}" onclick="toggleUserSelection('${u.username}')">
            <input type="checkbox" id="chk_${u.username}" ${isChecked ? 'checked' : ''} onclick="event.stopPropagation(); toggleUserSelection('${u.username}')">
            <div class="user-avatar-badge">${initial}</div>
            <div class="user-text-info">
              <span class="user-dname">${u.displayName || u.username}</span>
              <span class="user-uname">@${u.username}</span>
            </div>
          </div>
        `;
      }).join('');

      updateSelectedUsersDisplay();
    }

    function toggleUserSelection(username) {
      if (selectedUsersSet.has(username)) {
        selectedUsersSet.delete(username);
      } else {
        selectedUsersSet.add(username);
      }
      renderUserChecklist();
    }

    function selectAllUsers(selectAll) {
      if (selectAll) {
        registeredUsers.forEach(u => selectedUsersSet.add(u.username));
      } else {
        selectedUsersSet.clear();
      }
      renderUserChecklist();
    }

    function updateSelectedUsersDisplay() {
      const countEl = document.getElementById('selectedUsersCount');
      const badgeEl = document.getElementById('targetSelectedCountBadge');
      const summaryEl = document.getElementById('targetSelectedUsersSummary');
      const btnEl = document.getElementById('btnStartTarget');

      const count = selectedUsersSet.size;
      if (countEl) countEl.innerText = count;
      if (badgeEl) badgeEl.innerText = `${count} user${count > 1 ? 's' : ''}`;

      const selectedNames = registeredUsers
        .filter(u => selectedUsersSet.has(u.username))
        .map(u => u.displayName || u.username);

      if (summaryEl) {
        if (count === 0) {
          summaryEl.innerHTML = '<span style="color:#ef4444;">Chưa chọn người dùng nào (Hãy tích chọn bên trên)</span>';
        } else if (count === 1) {
          summaryEl.innerText = `${selectedNames[0]} (@${Array.from(selectedUsersSet)[0]})`;
        } else if (count <= 3) {
          summaryEl.innerText = selectedNames.join(', ');
        } else {
          summaryEl.innerText = `${selectedNames.slice(0, 2).join(', ')} và ${count - 2} người dùng khác...`;
        }
      }

      if (btnEl) {
        btnEl.innerText = count === 0 
          ? '⚠️ Vui lòng chọn ít nhất 1 người dùng bên trên' 
          : `🚀 Khởi Chạy Mô Phỏng Cho (${count}) Người Dùng Đã Chọn`;
        btnEl.disabled = (count === 0);
      }
    }

    /* 2. Tạo nhanh user mới bằng Họ Tên */
    async function handleQuickCreate() {
      const input = document.getElementById('quickNameInput');
      const name = input.value.trim();
      const badge = document.getElementById('createdUserBadge');
      if (!name) {
        alert('Vui lòng nhập tên người dùng.');
        return;
      }

      badge.style.color = '#60a5fa';
      badge.innerText = 'Đang cấp tài khoản...';

      try {
        const res = await fetch('/api/users/create', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ display_name: name })
        });
        const data = await res.json();
        if (res.ok) {
          badge.style.color = '#34d399';
          badge.innerText = `✓ Đã tạo & chọn: ${data.displayName} (@${data.username})`;
          selectedUsersSet.add(data.username);
          input.value = '';
          await loadRegisteredUsers();
        } else {
          badge.style.color = '#ef4444';
          badge.innerText = `❌ Lỗi: ${data.error || 'Không tạo được user'}`;
        }
      } catch (err) {
        badge.style.color = '#ef4444';
        badge.innerText = 'Lỗi kết nối: ' + err;
      }
    }

    /* 3. Tải danh mục video */
    async function loadCategories() {
      try {
        const res = await fetch('/api/categories');
        const cats = await res.json();
        categoriesList = cats;
        const select = document.getElementById('targetCategory');
        select.innerHTML = '';
        cats.forEach(c => {
          const opt = document.createElement('option');
          opt.value = c.categoryId;
          opt.dataset.slug = c.slug;
          opt.innerText = c.name + (c.slug ? ` (${c.slug})` : '');
          if (c.slug === 'music' || c.name.toLowerCase().includes('nhạc')) {
            opt.selected = true;
          }
          select.appendChild(opt);
        });
        await onCategoryChanged();
      } catch (err) {
        console.error('Error loading categories:', err);
      }
    }

    async function onCategoryChanged() {
      const sel = document.getElementById('targetCategory');
      const opt = sel.options[sel.selectedIndex];
      const slug = opt ? (opt.dataset.slug || 'music') : 'music';
      await loadCommentsForCategory(slug);
    }

    async function onCmtCategoryChanged() {
      const sel = document.getElementById('cmtCategorySelect');
      const slug = sel.value;
      await loadCommentsForCategory(slug);
    }

    async function loadCommentsForCategory(slug) {
      try {
        const res = await fetch(`/api/comments?category=${encodeURIComponent(slug)}`);
        const data = await res.json();
        currentCategoryComments = data.comments || [];
        renderCommentsList();
      } catch (err) {
        console.error('Error fetching comments:', err);
      }
    }

    function renderCommentsList() {
      const container = document.getElementById('commentTagsList');
      if (!currentCategoryComments.length) {
        container.innerHTML = '<div style="color:var(--text-muted); font-size:12px; padding:6px;">Chưa có bình luận trong danh mục này. Hãy thêm câu mới bên dưới.</div>';
        return;
      }
      container.innerHTML = currentCategoryComments.map((cmt, idx) => `
        <div class="comment-tag-item">
          <span title="${cmt}">${cmt}</span>
          <button type="button" class="btn-del-cmt" onclick="removeComment(${idx})" title="Xóa câu này">✖</button>
        </div>
      `).join('');
    }

    async function handleAddNewComment() {
      const input = document.getElementById('newCmtInput');
      const val = input.value.trim();
      if (!val) return;
      const sel = document.getElementById('cmtCategorySelect');
      const slug = sel.value || 'music';

      try {
        const res = await fetch('/api/comments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ category_slug: slug, comment: val })
        });
        const data = await res.json();
        currentCategoryComments = data.comments || [];
        input.value = '';
        renderCommentsList();
      } catch (err) {
        alert('Lỗi thêm bình luận: ' + err);
      }
    }

    async function removeComment(index) {
      const sel = document.getElementById('cmtCategorySelect');
      const slug = sel.value || 'music';

      try {
        const res = await fetch(`/api/comments?category=${encodeURIComponent(slug)}&index=${index}`, {
          method: 'DELETE'
        });
        const data = await res.json();
        currentCategoryComments = data.comments || [];
        renderCommentsList();
      } catch (err) {
        alert('Lỗi xóa bình luận: ' + err);
      }
    }

    /* 4. SSE Realtime Logs */
    function connectSSE() {
      const evtSource = new EventSource('/api/logs/stream');
      evtSource.onmessage = function(e) {
        if (!e.data || e.data.startsWith(':')) return;
        try {
          const item = JSON.parse(e.data);
          appendLogLine(item);
        } catch (err) {}
      };
      evtSource.onerror = function() {
        console.log('SSE connection dropped, reconnecting...');
      };
    }

    function appendLogLine(item) {
      const term = document.getElementById('terminal');
      const div = document.createElement('div');
      div.className = 'log-line';
      div.innerHTML = `
        <span class="log-time">[${item.timestamp}]</span>
        <span class="log-tag ${item.level}">${item.action}</span>
        <span class="log-user">${item.user}</span>
        <span class="log-msg">${item.message}</span>
      `;
      term.appendChild(div);
      term.scrollTop = term.scrollHeight;
    }

    /* 5. Matrix & Polling */
    async function refreshStatusAndMatrix() {
      try {
        const stRes = await fetch('/api/status');
        const st = await stRes.json();
        isRunning = st.is_running;

        const badge = document.getElementById('statusBadge');
        if (isRunning) {
          badge.className = 'status-badge running';
          badge.innerHTML = '<span class="pulse-dot"></span> Đang mô phỏng...';
        } else {
          badge.className = 'status-badge';
          badge.innerHTML = '<span class="pulse-dot"></span> Sẵn sàng';
        }

        const mRes = await fetch('/api/matrix');
        const matrix = await mRes.json();
        updateMatrixUI(matrix);
      } catch (err) {}
    }

    function updateMatrixUI(records) {
      document.getElementById('statInteractions').innerText = records.length;
      document.getElementById('matrixCount').innerText = `${records.length} bản ghi`;

      let likes = 0, comments = 0, ratings = 0, subs = 0;
      records.forEach(r => {
        if (r.like) likes++;
        if (r.comment) comments++;
        if (r.rating) ratings++;
        if (r.subscribed) subs++;
      });
      document.getElementById('statLikes').innerText = likes;
      document.getElementById('statComments').innerText = comments;
      document.getElementById('statRatings').innerText = ratings;
      document.getElementById('statSubs').innerText = subs;

      const tbody = document.getElementById('matrixTableBody');
      if (!records.length) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 18px;">Chưa có dữ liệu tương tác. Hãy bắt đầu mô phỏng.</td></tr>';
        return;
      }

      const rows = records.slice(-40).reverse().map(r => `
        <tr>
          <td><strong>${r.display_name}</strong><br><small style="color:var(--text-muted)">@${r.username}</small></td>
          <td title="${r.video_title}">${r.video_title.length > 22 ? r.video_title.substring(0, 22) + '...' : r.video_title}</td>
          <td><span class="badge" style="background:#1e293b; color:#94a3b8;">${r.category_slug}</span></td>
          <td><strong>${Math.round(r.watch_ratio * 100)}%</strong></td>
          <td>
            ${r.like ? '<span class="badge badge-like">👍 Like</span>' : ''}
            ${r.dislike ? '<span class="badge badge-dislike">👎 Dislike</span>' : ''}
            ${!r.like && !r.dislike ? '<span style="color:#64748b; font-size:11px;">Chỉ xem</span>' : ''}
          </td>
          <td>${r.rating ? `<span class="badge-star">★ ${r.rating}</span>` : '<span style="color:#64748b; font-size:11px;">0 đánh giá</span>'}</td>
          <td>${r.subscribed ? '<span class="badge badge-sub">🔔 Sub</span>' : '<span style="color:#64748b">-</span>'}</td>
          <td><small style="color:#cbd5e1">${r.comment ? (r.comment.length > 25 ? r.comment.substring(0, 25) + '...' : r.comment) : '<span style="color:#64748b">-</span>'}</small></td>
        </tr>
      `).join('');
      tbody.innerHTML = rows;
    }

    /* 6. Kích hoạt Simulation */
    async function handleStartTarget(e) {
      e.preventDefault();
      const sel = document.getElementById('targetCategory');
      const opt = sel.options[sel.selectedIndex];

      const selectedUsersList = registeredUsers
        .filter(u => selectedUsersSet.has(u.username))
        .map(u => ({
          username: u.username,
          displayName: u.displayName || u.username,
          password: u.password || "UserPass@123"
        }));

      if (selectedUsersList.length === 0) {
        alert('Vui lòng tích chọn ít nhất 1 người dùng trong danh sách bên trên để chạy mô phỏng.');
        return;
      }

      const payload = {
        display_name: selectedUsersList[0].displayName,
        username: selectedUsersList[0].username,
        password: "UserPass@123",
        users: selectedUsersList,
        category_id: sel.value,
        category_slug: opt ? (opt.dataset.slug || 'music') : 'music',
        video_count: parseInt(document.getElementById('targetCount').value),
        watch_ratio: parseFloat(document.getElementById('targetWatchRatio').value) / 100.0,
        like_ratio: parseFloat(document.getElementById('targetLikeRatio').value) / 100.0,
        dislike_ratio: parseFloat(document.getElementById('targetDislikeRatio').value) / 100.0,
        rating_ratio: parseFloat(document.getElementById('targetRatingRatio').value) / 100.0,
        rating_mode: "smart_exclusive",
        custom_rating_score: 5,
        comment_ratio: parseFloat(document.getElementById('targetCommentRatio').value) / 100.0,
        comments_list: currentCategoryComments,
        subscribe_ratio: parseFloat(document.getElementById('targetSubscribeRatio').value) / 100.0,
        enable_subscribe: true,
        delay: 0.2
      };

      try {
        const res = await fetch('/api/simulate/target', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (!res.ok) alert(data.error || 'Có lỗi xảy ra.');
      } catch (err) {
        alert('Lỗi kết nối simulator: ' + err);
      }
    }

    async function handleStartSwarm(e) {
      e.preventDefault();
      const payload = {
        bot_count: parseInt(document.getElementById('swarmBots').value),
        videos_per_bot: parseInt(document.getElementById('swarmVideos').value),
        preferred_category_ratio: parseFloat(document.getElementById('swarmPrefRatio').value) / 100.0,
        like_ratio: parseFloat(document.getElementById('swarmLikeRatio').value) / 100.0,
        dislike_ratio: parseFloat(document.getElementById('swarmDislikeRatio').value) / 100.0,
        comment_ratio: parseFloat(document.getElementById('swarmCmtRatio').value) / 100.0,
        rating_ratio: parseFloat(document.getElementById('swarmRatingRatio').value) / 100.0,
        subscribe_ratio: parseFloat(document.getElementById('swarmSubRatio').value) / 100.0,
        comments_list: currentCategoryComments,
        delay: 0.15
      };

      try {
        const res = await fetch('/api/simulate/swarm', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (!res.ok) alert(data.error || 'Có lỗi xảy ra.');
      } catch (err) {
        alert('Lỗi kết nối simulator: ' + err);
      }
    }

    async function stopSimulation() {
      await fetch('/api/simulate/stop', { method: 'POST' });
    }

    async function clearLogs() {
      await fetch('/api/logs/clear', { method: 'POST' });
      document.getElementById('terminal').innerHTML = '';
    }

    function exportCSV() {
      window.location.href = '/api/matrix/export.csv';
    }

    window.addEventListener('DOMContentLoaded', () => {
      loadRegisteredUsers();
      loadCategories();
      connectSSE();
      updateReactionSliders('like');
      setInterval(refreshStatusAndMatrix, 2000);
    });
  </script>
</body>
</html>
"""
