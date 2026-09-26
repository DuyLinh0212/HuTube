#!/usr/bin/env python3
"""
HuTube Model Trainer for Collaborative Filtering (CF).
Trains Item-Based & User-Based CF models on HuTube interaction data (Bot Simulator / Real Interactions).
"""
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")
from typing import Any

import numpy as np
import pandas as pd
import urllib.request
import urllib.error

# Add recommendation-service root to sys.path
SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from app.data.mapping import build_mappings, encode_interactions
from training.artifacts import save_artifact, update_benchmark_pointer
from training.config import TrainConfig
from training.trainer import fit_all_models


def calculate_interaction_score(row: pd.Series) -> float:
    """Chuyển đổi tín hiệu đa hành vi thành điểm tương tác chuẩn 1.0 - 5.0"""
    explicit = row.get("rating")
    if pd.notna(explicit) and explicit is not None:
        try:
            val = float(explicit)
            if 1.0 <= val <= 5.0:
                return val
        except (ValueError, TypeError):
            pass

    score = 3.0
    is_like = str(row.get("like", "")).lower() in ("true", "1")
    is_dislike = str(row.get("dislike", "")).lower() in ("true", "1")
    is_sub = str(row.get("subscribed", "")).lower() in ("true", "1")
    has_comment = bool(str(row.get("comment", "")).strip())

    try:
        watch_ratio = float(row.get("watch_ratio", 0) or 0)
    except (ValueError, TypeError):
        watch_ratio = 0.0

    if is_like:
        score = 4.5
    elif is_dislike:
        score = 1.5
    else:
        if watch_ratio >= 0.8:
            score = 4.0
        elif watch_ratio >= 0.5:
            score = 3.5
        elif watch_ratio >= 0.2:
            score = 3.0
        else:
            score = 2.5

    if has_comment and not is_dislike:
        score = min(5.0, score + 0.3)
    if is_sub:
        score = min(5.0, score + 0.4)

    return round(score, 1)


def fetch_matrix_from_simulator(url: str = "http://localhost:5050/api/matrix") -> list[dict[str, Any]]:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "HuTube-Trainer/1.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except Exception:
        pass
    return []


def fetch_videos_from_backend(backend_url: str = "http://localhost:5080/api/v1") -> list[dict[str, Any]]:
    try:
        req = urllib.request.Request(f"{backend_url.rstrip('/')}/feed/home?pageSize=100", headers={"User-Agent": "HuTube-Trainer/1.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("items", [])
    except Exception:
        pass
    return []


def train_hutube_model(
    matrix_csv_path: str | Path | None = None,
    simulator_url: str = "http://localhost:5050/api/matrix",
    backend_url: str = "http://localhost:5080/api/v1",
    artifact_root: Path | None = None,
) -> Path:
    if artifact_root is None:
        artifact_root = SERVICE_ROOT / "data" / "artifacts"
    artifact_root.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, Any]] = []

    # 1. Đọc từ file CSV nếu có
    if matrix_csv_path and Path(matrix_csv_path).is_file():
        print(f"[+] Đang nạp dữ liệu từ file CSV: {matrix_csv_path}")
        df_csv = pd.read_csv(matrix_csv_path)
        records = df_csv.to_dict(orient="records")

    # 2. Nếu chưa có, thử lấy từ Web Simulator API
    if not records:
        print(f"[+] Đang thử lấy tương tác từ Web Simulator ({simulator_url})...")
        records = fetch_matrix_from_simulator(simulator_url)

    # 3. Nếu vẫn chưa có tương tác (chưa chạy simulator), sinh tương tác seed từ kho video backend
    if not records:
        print("[!] Chưa tìm thấy lịch sử tương tác nào.")
        print("[+] Đang lấy danh mục video từ Backend để khởi tạo mô hình ban đầu...")
        videos = fetch_videos_from_backend(backend_url)
        if not videos:
            raise RuntimeError(
                "Không thể lấy danh sách video từ Backend (5080) và không có file tương tác. "
                "Hãy bật Backend và chạy Simulator trước."
            )
        # Tạo dữ liệu giả lập ban đầu để khởi tạo ma trận
        bot_user_id = "00000000-0000-0000-0000-000000000001"
        for i, vid in enumerate(videos):
            records.append({
                "user_id": bot_user_id,
                "video_id": vid["videoId"],
                "video_title": vid["title"],
                "category_slug": "general",
                "watch_ratio": 1.0,
                "like": True if i % 2 == 0 else False,
                "dislike": False,
                "rating": 5 if i % 2 == 0 else 4,
                "comment": "Video hay",
                "subscribed": False,
                "timestamp": datetime.now(UTC).isoformat(),
            })

    print(f"[+] Tổng số dòng tương tác nạp được: {len(records)}")

    # Xây dựng DataFrame tương tác
    df = pd.DataFrame(records)
    df["user_id"] = df["user_id"].astype(str)
    df["item_id"] = df["video_id"].astype(str)
    df["rating"] = df.apply(calculate_interaction_score, axis=1)
    df["source"] = "BOT"
    df["timestamp"] = pd.to_datetime(df.get("timestamp", datetime.now(UTC).isoformat()), utc=True)

    # Xây dựng DataFrame items và thể loại (categories)
    genres = sorted(list({str(c) for c in df.get("category_slug", ["general"]) if pd.notna(c)}))
    if not genres:
        genres = ["general"]

    items_list = []
    for item_id, group in df.groupby("item_id"):
        title = group["video_title"].iloc[0] if "video_title" in group else str(item_id)
        slug = group["category_slug"].iloc[0] if "category_slug" in group else "general"
        row_dict = {"item_id": item_id, "title": str(title)}
        for g in genres:
            row_dict[g] = 1 if g == slug else 0
        items_list.append(row_dict)

    df_items = pd.DataFrame(items_list)

    # Xây dựng Index Mappings
    mappings = build_mappings(df, item_ids=df_items["item_id"].tolist())
    interactions_encoded = encode_interactions(df, mappings)

    # Cấu hình huấn luyện
    config = TrainConfig(
        project_root=SERVICE_ROOT,
        data={
            "path": Path("data/processed"),
            "processed_path": Path("data/processed/unified.csv"),
        },
        model={
            "similarities": ["cosine", "jaccard", "pearson"],
            "interaction_mode": "rating",
            "neighbor_count": 50,
        },
        preference={"positive_rating_threshold": 4.0},
        evaluation={"k": [5, 10, 20]},
        output={"artifact_root": Path(str(artifact_root)), "report_root": Path("reports")},
    )

    print(f"[+] Bắt đầu huấn luyện Collaborative Filtering trên {len(mappings.user_to_index)} người dùng, {len(mappings.item_to_index)} video...")
    fitted = fit_all_models(interactions_encoded, config=config, mappings=mappings)
    models = {mtype: res.model for mtype, res in fitted.items()}

    model_version = f"cf_hutube_{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}"
    metadata = {
        "modelVersion": model_version,
        "source": "BOT",
        "deployable": True,
        "trainedAt": datetime.now(UTC).isoformat(),
        "usersCount": len(mappings.user_to_index),
        "itemsCount": len(mappings.item_to_index),
        "interactionsCount": len(df),
    }

    history = [
        {
            "model": mtype,
            "fit_seconds": fitted[mtype].fit_seconds,
            "neighbor_count": config.model.neighbor_count,
        }
        for mtype in fitted
    ]

    artifact_dir = save_artifact(
        artifact_root=artifact_root,
        model_version=model_version,
        models=models,
        config=config,
        mappings=mappings,
        fit_interactions=interactions_encoded,
        items=df_items,
        genre_names=genres,
        metrics={"totalInteractions": len(df)},
        history=history,
        metadata=metadata,
    )

    update_benchmark_pointer(artifact_root, model_version)
    try:
        import urllib.request
        req = urllib.request.Request("http://127.0.0.1:8000/internal/reload", data=b"", method="POST")
        urllib.request.urlopen(req, timeout=2)
        print("[+] Đã tự động kích hoạt nạp Model mới vào Recommendation Service (http://127.0.0.1:8000)!")
    except Exception:
        pass
    print(f"🎉 Huấn luyện thành công! Artifact đã lưu tại: {artifact_dir}")
    print(f"👉 Model Version: {model_version}")
    return artifact_dir


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train HuTube Collaborative Filtering Model")
    parser.add_argument("--matrix-csv", type=str, default="", help="Đường dẫn file CSV tương tác")
    parser.add_argument("--simulator-url", type=str, default="http://localhost:5050/api/matrix", help="URL API Web Simulator")
    parser.add_argument("--backend-url", type=str, default="http://localhost:5080/api/v1", help="URL API Backend HuTube")
    args = parser.parse_args()

    default_csv = Path(__file__).resolve().parents[2] / "tools" / "bot-simulator" / "user_video_matrix.csv"
    csv_to_use = args.matrix_csv or (str(default_csv) if default_csv.is_file() else "")

    train_hutube_model(
        matrix_csv_path=csv_to_use,
        simulator_url=args.simulator_url,
        backend_url=args.backend_url,
    )
