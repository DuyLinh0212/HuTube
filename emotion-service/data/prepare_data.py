import os
import json
import urllib.request
import sys
from collections import Counter

# Fix UTF-8 output on Windows terminal
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

DATA_DIR = os.path.dirname(os.path.abspath(__file__))

HF_RAW_BASE = "https://huggingface.co/datasets/tridm/UIT-VSMEC/raw/main"
SPLITS = {
    "train": f"{HF_RAW_BASE}/train.json",
    "validation": f"{HF_RAW_BASE}/valid.json",
    "test": f"{HF_RAW_BASE}/test.json"
}

EMOTION_TO_SENTIMENT = {
    "Enjoyment": "POSITIVE",
    "Disgust": "NEGATIVE",
    "Sadness": "NEGATIVE",
    "Anger": "NEGATIVE",
    "Fear": "NEGATIVE",
    "Surprise": "NEUTRAL",
    "Other": "NEUTRAL"
}

EMOTION_LABELS = [
    "Enjoyment",
    "Disgust",
    "Sadness",
    "Anger",
    "Fear",
    "Surprise",
    "Other"
]

def download_split(split_name: str, url: str) -> list[dict]:
    target_path = os.path.join(DATA_DIR, f"{split_name}.json")
    if os.path.exists(target_path):
        print(f"[*] Found cached {split_name}.json at: {target_path}")
        with open(target_path, "r", encoding="utf-8") as f:
            return json.load(f)

    print(f"[*] Downloading {split_name} from Hugging Face: {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp:
        content = resp.read().decode("utf-8")

    data = json.loads(content)
    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"[+] Saved {len(data)} items to {target_path}")
    return data

def main():
    print("=" * 60)
    print("CHUẨN BỊ DỮ LIỆU UIT-VSMEC TỪ HUGGING FACE")
    print("=" * 60)

    stats = {}
    for split_name, url in SPLITS.items():
        data = download_split(split_name, url)
        # Add sentiment mapping
        for item in data:
            item["Sentiment"] = EMOTION_TO_SENTIMENT.get(item.get("Emotion", "Other"), "NEUTRAL")

        # Save annotated split
        annotated_path = os.path.join(DATA_DIR, f"{split_name}_annotated.json")
        with open(annotated_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        emotion_counter = Counter(d["Emotion"] for d in data)
        sentiment_counter = Counter(d["Sentiment"] for d in data)
        stats[split_name] = {
            "total": len(data),
            "emotions": emotion_counter,
            "sentiments": sentiment_counter
        }

    print("\n--- THỐNG KÊ DỮ LIỆU ---")
    for split_name, st in stats.items():
        print(f"\n[Split: {split_name.upper()}] - Tổng cộng: {st['total']} mẫu")
        print("  Phân bố Cảm xúc (Emotion):")
        for emo, count in st["emotions"].most_axis() if hasattr(st["emotions"], "most_axis") else st["emotions"].items():
            pct = (count / st["total"]) * 100
            print(f"    - {emo:12}: {count:5} ({pct:5.2f}%)")
        print("  Phân bố Sắc thái (Sentiment):")
        for sent, count in st["sentiments"].items():
            pct = (count / st["total"]) * 100
            print(f"    - {sent:12}: {count:5} ({pct:5.2f}%)")

    print("\n[+] Hoàn tất chuẩn bị dữ liệu!")

if __name__ == "__main__":
    main()
