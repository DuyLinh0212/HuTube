import os
import sys
import json
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
from collections import Counter

# Fix UTF-8 on Windows terminal
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Thư mục lưu biểu đồ
DATA_DIR = Path(__file__).resolve().parent
CHARTS_DIR = DATA_DIR / "charts"
CHARTS_DIR.mkdir(parents=True, exist_ok=True)

# Cấu hình font và style
sns.set_theme(style="whitegrid")
plt.rcParams['font.sans-serif'] = 'DejaVu Sans'

# Màu sắc phân loại sắc thái
COLOR_MAP = {
    "Enjoyment": "#2ecc71",  # Xanh lá - Tích cực
    "Disgust": "#e74c3c",    # Đỏ - Tiêu cực
    "Sadness": "#3498db",    # Xanh dương - Buồn / Tiêu cực
    "Anger": "#c0392b",      # Đỏ thẫm - Giận dữ
    "Fear": "#9b59b6",       # Tím - Sợ hãi
    "Surprise": "#f39c12",   # Cam - Ngạc nhiên
    "Other": "#95a5a6"       # Xám - Trung tính
}

SENTIMENT_COLORS = {
    "POSITIVE": "#2ecc71",
    "NEGATIVE": "#e74c3c",
    "NEUTRAL": "#95a5a6"
}

def load_data(split_name):
    file_path = DATA_DIR / f"{split_name}_annotated.json"
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)

def plot_emotion_distribution(train_data):
    """Vẽ biểu đồ phân bố 7 nhãn cảm xúc trên tập Train."""
    counts = Counter(d["Emotion"] for d in train_data)
    labels, values = zip(*counts.most_common())
    colors = [COLOR_MAP.get(l, "#34495e") for l in labels]
    
    total = len(train_data)
    percentages = [(v / total) * 100 for v in values]

    plt.figure(figsize=(10, 5.5))
    bars = plt.bar(labels, values, color=colors, edgecolor="black", linewidth=0.8)

    for bar, pct, val in zip(bars, percentages, values):
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width() / 2.0, yval + 20, f"{val}\n({pct:.1f}%)", ha="center", va="bottom", fontsize=10, fontweight="bold")

    plt.title(f"Phân Bố 7 Nhãn Cảm Xúc UIT-VSMEC (Tập Train - {total:,} mẫu)", fontsize=14, fontweight="bold", pad=15)
    plt.xlabel("Nhãn Cảm Xúc (Emotion)", fontsize=12)
    plt.ylabel("Số Lượng Bình Luận", fontsize=12)
    plt.ylim(0, max(values) * 1.18)
    plt.tight_layout()

    output_path = CHARTS_DIR / "uit_vsmec_emotion_distribution.png"
    plt.savefig(output_path, dpi=200)
    plt.close()
    print(f"[+] Đã lưu biểu đồ phân bố cảm xúc: {output_path}")

def plot_sentiment_distribution(train_data):
    """Vẽ biểu đồ tỷ lệ sắc thái (Tích cực / Tiêu cực / Trung tính)."""
    counts = Counter(d["Sentiment"] for d in train_data)
    labels = ["POSITIVE (Tích cực)", "NEGATIVE (Tiêu cực)", "NEUTRAL (Trung tính)"]
    keys = ["POSITIVE", "NEGATIVE", "NEUTRAL"]
    values = [counts[k] for k in keys]
    colors = [SENTIMENT_COLORS[k] for k in keys]

    plt.figure(figsize=(8, 6))
    wedges, texts, autotexts = plt.pie(
        values,
        labels=labels,
        colors=colors,
        autopct="%1.1f%%",
        startangle=140,
        wedgeprops=dict(width=0.45, edgecolor='black', linewidth=1),
        textprops=dict(fontsize=11, fontweight="bold")
    )
    plt.setp(autotexts, size=11, weight="bold", color="white")
    plt.title(f"Tỷ Lệ Sắc Thái Bình Luận (Sentiment) UIT-VSMEC\n(Tổng: {len(train_data):,} mẫu)", fontsize=13, fontweight="bold", pad=15)
    plt.tight_layout()

    output_path = CHARTS_DIR / "uit_vsmec_sentiment_pie.png"
    plt.savefig(output_path, dpi=200)
    plt.close()
    print(f"[+] Đã lưu biểu đồ sắc thái tròn: {output_path}")

def plot_splits_comparison(train, val, test):
    """So sánh tỷ lệ 3 split train/val/test."""
    splits = ["Train", "Validation", "Test"]
    totals = [len(train), len(val), len(test)]
    colors = ["#3498db", "#f1c40f", "#e67e22"]

    plt.figure(figsize=(8, 5))
    bars = plt.bar(splits, totals, color=colors, edgecolor="black", width=0.5)

    for bar, val in zip(bars, totals):
        pct = (val / sum(totals)) * 100
        plt.text(bar.get_x() + bar.get_width() / 2.0, val + 50, f"{val:,}\n({pct:.1f}%)", ha="center", va="bottom", fontsize=11, fontweight="bold")

    plt.title(f"Phân Bổ Kích Thước Các Tập Dữ Liệu UIT-VSMEC (Tổng: {sum(totals):,} mẫu)", fontsize=13, fontweight="bold", pad=15)
    plt.ylabel("Số lượng mẫu", fontsize=12)
    plt.ylim(0, max(totals) * 1.15)
    plt.tight_layout()

    output_path = CHARTS_DIR / "uit_vsmec_splits_comparison.png"
    plt.savefig(output_path, dpi=200)
    plt.close()
    print(f"[+] Đã lưu biểu đồ phân chia tập: {output_path}")

def main():
    train_data = load_data("train")
    val_data = load_data("validation")
    test_data = load_data("test")

    plot_emotion_distribution(train_data)
    plot_sentiment_distribution(train_data)
    plot_splits_comparison(train_data, val_data, test_data)
    print("\n[+] Đã tạo xong tất cả sơ đồ đánh giá trực quan!")

if __name__ == "__main__":
    main()
