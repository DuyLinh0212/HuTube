from __future__ import annotations

import json
import math
import shutil
import subprocess
import textwrap
import time
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
SCENES_DIR = ASSETS / "scenes"
AUDIO_DIR = ASSETS / "audio"
CLIPS_DIR = ASSETS / "clips"
FINAL = ROOT / "MBMF_GSMF_Giai_Thich.mp4"
THUMBNAIL = ROOT / "MBMF_thumbnail.png"

W, H = 1920, 1080
FPS = 30
BG = "#07111F"
PANEL = "#0E2035"
PANEL_2 = "#102B42"
WHITE = "#F5F7FB"
MUTED = "#A7B8CB"
CYAN = "#35D5E8"
BLUE = "#6C8CFF"
PURPLE = "#AE7CFF"
ORANGE = "#FFB45E"
GREEN = "#58DB9D"
RED = "#FF6F7D"

FONT_REG = r"C:\Windows\Fonts\segoeui.ttf"
FONT_BOLD = r"C:\Windows\Fonts\seguisb.ttf"
FONT_MONO = r"C:\Windows\Fonts\consola.ttf"


@dataclass
class Scene:
    title: str
    kicker: str
    narration: str
    kind: str


SCENES = [
    Scene(
        "Một người dùng, nhiều dấu vết",
        "MULTI-BEHAVIOR MATRIX FACTORIZATION",
        "Một người dùng không chỉ để lại... một loại dấu vết. Họ xem. Họ nhấp. Họ yêu thích, thêm vào giỏ... rồi có thể mới mua. Lượt xem thì nhiều, nhưng tín hiệu còn yếu. Lượt mua ít hơn — đổi lại, nó gần với ý định thật hơn. M B M F học tất cả những dấu vết này cùng lúc, để hiểu sở thích chính xác hơn.",
        "intro",
    ),
    Scene(
        "Vì sao một ma trận là chưa đủ?",
        "BÀI TOÁN",
        "Matrix Factorization truyền thống chỉ làm việc với một ma trận. Và đây là vấn đề. Chỉ dùng hành vi mua? Dữ liệu sẽ rất thưa. Cộng hết mọi hành vi lại? Ta mất luôn ngữ nghĩa — vì một lần xem, rõ ràng, không thể ngang với một lần mua. Cách của M B M F là giữ mỗi hành vi trong một ma trận riêng... nhưng vẫn cho chúng hỗ trợ lẫn nhau.",
        "problem",
    ),
    Scene(
        "Kiến trúc GSMF",
        "SHARED + PRIVATE",
        "Mô hình trung tâm ở đây là Group Sparse Matrix Factorization, gọi tắt là G S M F. Ý tưởng khá gọn: mọi hành vi dùng chung ma trận người dùng U. Nhưng mỗi hành vi lại có một ma trận đối tượng V riêng. Điểm dự đoán là tích vô hướng giữa hai vector. U chung đóng vai trò cây cầu truyền thông tin; còn V riêng giúp từng hành vi giữ được bản sắc của nó.",
        "architecture",
    ),
    Scene(
        "Chỉ học từ điều đã quan sát",
        "MASKING",
        "Với mỗi hành vi, điểm dự đoán được tính bằng U chuyển vị nhân V. Nhưng chú ý nhé: sai số chỉ được tính ở những ô có mặt nạ bằng một. Tại sao? Vì một ô bị thiếu không có nghĩa là người dùng không thích. Có thể họ chỉ... chưa nhìn thấy sản phẩm đó. Mặt nạ giúp mô hình tách rõ tín hiệu âm thật sự, khỏi dữ liệu chưa từng được quan sát.",
        "mask",
    ),
    Scene(
        "Group sparsity: chia sẻ có chọn lọc",
        "Ý TƯỞNG CỐT LÕI",
        "Đây mới là phần đáng chú ý nhất. Nếu mọi hành vi bị ép dùng toàn bộ latent factor, thông tin sai có thể truyền từ hành vi này sang hành vi khác. G S M F xử lý chuyện đó bằng group sparsity. Mỗi hàng của V là một factor trên toàn bộ sản phẩm. Khi một hàng không còn hữu ích, regularization kéo cả hàng về không. Kết quả? Có factor được chia sẻ — và cũng có factor chỉ dành riêng cho một hành vi.",
        "groups",
    ),
    Scene(
        "Hàm mục tiêu gồm ba lực",
        "OBJECTIVE",
        "Hàm mục tiêu có thể nhìn như ba lực kéo. Lực thứ nhất: sai số tái tạo, để dự đoán bám sát dữ liệu. Lực thứ hai: group sparsity, để chọn factor phù hợp cho từng hành vi. Và lực thứ ba: chuẩn L hai, để tham số không phình quá lớn. Trọng số alpha quyết định hành vi nào quan trọng hơn. Còn lambda group càng lớn, càng nhiều factor bị tắt — quá tay thì mô hình sẽ underfit.",
        "objective",
    ),
    Scene(
        "Huấn luyện luân phiên",
        "ALTERNATING OPTIMIZATION",
        "Cách huấn luyện là tối ưu luân phiên. Đầu tiên, khởi tạo U và các V. Sau đó giữ U cố định, rồi cập nhật V cho từng hành vi. Những factor yếu sẽ bị phạt mạnh hơn qua ma trận trọng số D. Tiếp theo, giữ toàn bộ V cố định và cập nhật lại U từ tất cả hành vi. Cứ thế lặp lại... cho đến khi hàm mục tiêu gần như không đổi.",
        "training",
    ),
    Scene(
        "Ví dụ ba latent factor",
        "SHARED FACTOR / PRIVATE FACTOR",
        "Ví dụ có ba latent factor. Với rating, factor một và ba hoạt động; factor hai bị tắt. Với favorite thì ngược lại: factor một và hai hoạt động; factor ba bị tắt. Vậy factor một là phần chung. Factor ba là phần riêng của rating, còn factor hai là phần riêng của favorite. Đây chính là điểm cân bằng: chia sẻ đủ để học tốt hơn, nhưng không trộn tất cả vào nhau.",
        "example",
    ),
    Scene(
        "Khi nào MBMF phát huy hiệu quả?",
        "ỨNG DỤNG & GIỚI HẠN",
        "M B M F phát huy tốt khi các hành vi có liên quan, dữ liệu mục tiêu khá thưa, và ta muốn tận dụng tín hiệu phụ. Nhưng nó không phải thuốc tiên. Bài toán vẫn không lồi, khá nhạy với khởi tạo và hyperparameter, vẫn có nguy cơ negative transfer, và chưa giải quyết trọn vẹn cold start. Nếu mục tiêu là top N trên implicit feedback, hãy cân nhắc B P R hoặc một hàm mất mát dành cho xếp hạng.",
        "limits",
    ),
    Scene(
        "MBMF trong một câu",
        "TÓM TẮT",
        "Chốt lại nhé. M B M F không chỉ phân rã một ma trận — nó học nhiều ma trận có liên hệ cùng lúc. Biểu diễn người dùng chung giúp truyền thông tin. Group sparsity quyết định factor nào nên chia sẻ, và factor nào phải giữ riêng. Nói ngắn gọn: học từ nhiều hành vi... nhưng không đánh mất bản sắc của từng hành vi.",
        "summary",
    ),
]


def font(size: int, bold: bool = False, mono: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_MONO if mono else (FONT_BOLD if bold else FONT_REG)
    return ImageFont.truetype(path, size)


def rr(draw: ImageDraw.ImageDraw, box, radius=28, fill=PANEL, outline=None, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text(draw, xy, value, size, color=WHITE, bold=False, anchor=None, mono=False, spacing=6):
    draw.multiline_text(xy, value, font=font(size, bold, mono), fill=color, anchor=anchor, spacing=spacing)


def wrapped(draw, box, value, size=38, color=MUTED, bold=False, line_spacing=12):
    x1, y1, x2, y2 = box
    f = font(size, bold)
    words = value.split()
    lines, line = [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textbbox((0, 0), trial, font=f)[2] <= x2 - x1:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    draw.multiline_text((x1, y1), "\n".join(lines), font=f, fill=color, spacing=line_spacing)
    return y1 + len(lines) * (size + line_spacing)


def background() -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-250, -280, 720, 690), fill=(38, 113, 180, 65))
    gd.ellipse((1320, 600, 2180, 1430), fill=(128, 72, 205, 50))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.alpha_composite(img.convert("RGBA"), glow)
    d = ImageDraw.Draw(img)
    for x in range(0, W, 80):
        d.line((x, 0, x, H), fill=(255, 255, 255, 7), width=1)
    for y in range(0, H, 80):
        d.line((0, y, W, y), fill=(255, 255, 255, 7), width=1)
    return img


def header(draw, scene: Scene, index: int):
    text(draw, (100, 70), scene.kicker, 24, CYAN, bold=True)
    text(draw, (100, 112), scene.title, 60, WHITE, bold=True)
    draw.line((100, 202, 1820, 202), fill=(255, 255, 255, 28), width=2)
    text(draw, (1820, 82), f"{index + 1:02d} / {len(SCENES):02d}", 22, MUTED, bold=True, anchor="ra")


def footer(draw, index: int):
    x1, y = 100, 1016
    draw.rounded_rectangle((x1, y, 1820, y + 6), radius=3, fill=(255, 255, 255, 26))
    width = int(1720 * (index + 1) / len(SCENES))
    draw.rounded_rectangle((x1, y, x1 + width, y + 6), radius=3, fill=CYAN)
    text(draw, (100, 1040), "HU-TUBE • HỆ THỐNG GỢI Ý", 18, MUTED, bold=True)


def matrix(draw, x, y, rows, cols, cell=58, values=None, active_rows=None, label="R", accent=CYAN):
    text(draw, (x, y - 46), label, 26, accent, bold=True)
    for r in range(rows):
        for c in range(cols):
            x1, y1 = x + c * cell, y + r * cell
            active = active_rows is None or r in active_rows
            fill = accent if active else "#26364A"
            alpha_fill = fill
            draw.rounded_rectangle((x1, y1, x1 + cell - 8, y1 + cell - 8), radius=10, fill=alpha_fill)
            if values:
                value = str(values[r][c])
                text(draw, (x1 + (cell - 8) / 2, y1 + (cell - 8) / 2), value, 20, BG if active else MUTED, bold=True, anchor="mm")
    return x + cols * cell, y + rows * cell


def pill(draw, x, y, label, color, icon=""):
    f = font(29, True)
    width = draw.textbbox((0, 0), icon + label, font=f)[2] + 56
    rr(draw, (x, y, x + width, y + 62), 31, fill=PANEL_2, outline=color, width=2)
    text(draw, (x + width / 2, y + 31), icon + label, 29, WHITE, bold=True, anchor="mm")
    return width


def arrow(draw, start, end, color=CYAN, width=5):
    draw.line((*start, *end), fill=color, width=width)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    for off in (2.55, -2.55):
        p = (end[0] + 18 * math.cos(angle + off), end[1] + 18 * math.sin(angle + off))
        draw.line((*end, *p), fill=color, width=width)


def draw_intro(draw):
    text(draw, (100, 285), "Từ tín hiệu yếu…", 38, MUTED, bold=True)
    x = 100
    for label, color in [("XEM", BLUE), ("NHẤP", CYAN), ("YÊU THÍCH", PURPLE), ("GIỎ HÀNG", ORANGE), ("MUA", GREEN)]:
        w = pill(draw, x, 360, label, color)
        if x + w < 1770:
            arrow(draw, (x + w + 8, 391), (x + w + 38, 391), color=MUTED, width=3)
        x += w + 58
    text(draw, (100, 510), "…đến ý định mạnh", 38, WHITE, bold=True)
    rr(draw, (100, 600, 1820, 900), 36, fill=PANEL)
    text(draw, (160, 670), "MBMF", 112, CYAN, bold=True)
    wrapped(draw, (590, 655, 1720, 850), "Học đồng thời nhiều ma trận hành vi để dự đoán sở thích chưa quan sát.", 46, WHITE, bold=True, line_spacing=18)


def draw_problem(draw):
    rr(draw, (100, 280, 590, 900), 32, fill=PANEL)
    text(draw, (345, 335), "CHỈ MUA", 30, ORANGE, bold=True, anchor="mm")
    values = [["", "", "1", ""], ["", "", "", ""], ["", "1", "", ""], ["", "", "", ""]]
    matrix(draw, 215, 415, 4, 4, 72, values, label="R purchase", accent=ORANGE)
    text(draw, (345, 770), "Quá thưa", 34, RED, bold=True, anchor="mm")
    text(draw, (345, 820), "Thiếu dữ liệu để học", 24, MUTED, anchor="mm")
    rr(draw, (715, 280, 1205, 900), 32, fill=PANEL)
    text(draw, (960, 335), "CỘNG TẤT CẢ", 30, PURPLE, bold=True, anchor="mm")
    matrix(draw, 830, 415, 4, 4, 72, [["3", "1", "2", "4"], ["1", "4", "2", "1"], ["2", "3", "1", "2"], ["1", "2", "4", "3"]], label="R all", accent=PURPLE)
    text(draw, (960, 770), "Mất ngữ nghĩa", 34, RED, bold=True, anchor="mm")
    text(draw, (960, 820), "Xem ≠ Mua", 24, MUTED, anchor="mm")
    rr(draw, (1330, 280, 1820, 900), 32, fill=PANEL, outline=CYAN)
    text(draw, (1575, 335), "MBMF", 30, CYAN, bold=True, anchor="mm")
    for i, (lab, col) in enumerate([("R view", BLUE), ("R favorite", PURPLE), ("R purchase", GREEN)]):
        matrix(draw, 1450, 425 + i * 125, 2, 3, 45, label=lab, accent=col)
    text(draw, (1575, 820), "Riêng nhưng liên kết", 30, GREEN, bold=True, anchor="mm")


def draw_architecture(draw):
    rr(draw, (100, 285, 550, 900), 32, fill=PANEL, outline=CYAN)
    text(draw, (325, 345), "USER FACTOR CHUNG", 28, CYAN, bold=True, anchor="mm")
    matrix(draw, 210, 440, 5, 3, 70, label="U  ∈  R^(k×n)", accent=CYAN)
    text(draw, (325, 835), "Một biểu diễn người dùng", 23, MUTED, anchor="mm")
    arrow(draw, (585, 500), (760, 425), color=BLUE)
    arrow(draw, (585, 600), (760, 600), color=PURPLE)
    arrow(draw, (585, 700), (760, 775), color=GREEN)
    for y, lab, col, active in [
        (320, "V(view)", BLUE, {0, 1, 3}),
        (495, "V(favorite)", PURPLE, {0, 2, 4}),
        (670, "V(purchase)", GREEN, {0, 3, 4}),
    ]:
        rr(draw, (760, y, 1350, y + 145), 25, fill=PANEL)
        text(draw, (800, y + 28), lab, 26, col, bold=True)
        matrix(draw, 1070, y + 30, 5, 4, 22, active_rows=active, label="", accent=col)
    rr(draw, (1435, 390, 1820, 785), 32, fill=PANEL_2)
    text(draw, (1628, 445), "DỰ ĐOÁN", 28, ORANGE, bold=True, anchor="mm")
    text(draw, (1628, 545), "R̂ᵇᵢⱼ", 78, WHITE, bold=True, anchor="mm")
    text(draw, (1628, 635), "=  uᵢᵀ vᵇⱼ", 48, CYAN, bold=True, anchor="mm")
    text(draw, (1628, 715), "theo từng behavior", 24, MUTED, anchor="mm")


def draw_mask(draw):
    rr(draw, (100, 300, 850, 885), 32, fill=PANEL)
    text(draw, (475, 345), "MA TRẬN TƯƠNG TÁC", 28, CYAN, bold=True, anchor="mm")
    vals = [["4", "?", "2", "?", "5"], ["?", "3", "?", "?", "1"], ["5", "?", "?", "4", "?"], ["?", "?", "2", "?", "3"]]
    matrix(draw, 230, 440, 4, 5, 86, vals, label="R(b)", accent=BLUE)
    text(draw, (475, 825), "? = chưa quan sát, không phải số 0", 26, ORANGE, bold=True, anchor="mm")
    rr(draw, (975, 300, 1820, 885), 32, fill=PANEL)
    text(draw, (1398, 345), "MẶT NẠ QUAN SÁT", 28, GREEN, bold=True, anchor="mm")
    vals2 = [["1", "0", "1", "0", "1"], ["0", "1", "0", "0", "1"], ["1", "0", "0", "1", "0"], ["0", "0", "1", "0", "1"]]
    matrix(draw, 1152, 440, 4, 5, 86, vals2, label="M(b)", accent=GREEN)
    text(draw, (1398, 825), "Chỉ M = 1 mới vào loss", 28, WHITE, bold=True, anchor="mm")


def draw_groups(draw):
    text(draw, (100, 280), "Mỗi hàng = một latent factor trên toàn bộ item", 30, MUTED, bold=True)
    rr(draw, (100, 350, 875, 885), 32, fill=PANEL)
    text(draw, (487, 395), "V(rating)", 30, BLUE, bold=True, anchor="mm")
    for r in range(5):
        y = 470 + r * 70
        active = r in (0, 2, 4)
        text(draw, (155, y + 23), f"f{r+1}", 24, MUTED, bold=True, anchor="mm")
        for c in range(8):
            v = [0.9, 0.7, 0.55, 0.75, 0.62, 0.82, 0.68, 0.58][c] if active else 0.05
            w = int(50 * v)
            draw.rounded_rectangle((215 + c * 73, y, 215 + c * 73 + w, y + 46), radius=8, fill=BLUE if active else "#334258")
        text(draw, (820, y + 23), "ON" if active else "OFF", 22, GREEN if active else RED, bold=True, anchor="mm")
    rr(draw, (1000, 350, 1820, 885), 32, fill=PANEL)
    text(draw, (1410, 415), "‖V(b)‖₁,₂  =  Σₜ ‖V(b)ₜ,:‖₂", 42, CYAN, bold=True, anchor="mm")
    text(draw, (1070, 520), "L2 theo từng hàng", 30, WHITE, bold=True)
    text(draw, (1070, 590), "+", 36, MUTED, bold=True)
    text(draw, (1070, 650), "L1 giữa các hàng", 30, WHITE, bold=True)
    arrow(draw, (1075, 750), (1550, 750), color=PURPLE)
    text(draw, (1410, 820), "Cả hàng yếu → về 0", 34, ORANGE, bold=True, anchor="mm")


def draw_objective(draw):
    rr(draw, (100, 300, 1820, 510), 34, fill=PANEL_2, outline=CYAN)
    text(draw, (960, 405), "L =  Σᵦ αᵦ [ fᵦ(U,Vᵦ) + λg ‖Vᵦ‖₁,₂ ]  +  λ₂ [ ‖U‖F² + Σᵦ ‖Vᵦ‖F² ]", 38, WHITE, bold=True, anchor="mm")
    cards = [
        (100, 590, 600, 895, "01", "KHỚP DỮ LIỆU", "Sai số tái tạo\ntrên ô đã quan sát", BLUE),
        (710, 590, 1210, 895, "02", "CHỌN FACTOR", "Group sparsity\ncho từng behavior", PURPLE),
        (1320, 590, 1820, 895, "03", "ỔN ĐỊNH", "L2 regularization\ngiảm overfitting", GREEN),
    ]
    for x1, y1, x2, y2, no, title_, body, col in cards:
        rr(draw, (x1, y1, x2, y2), 30, fill=PANEL, outline=col)
        text(draw, (x1 + 45, y1 + 42), no, 34, col, bold=True)
        text(draw, ((x1 + x2) / 2, y1 + 120), title_, 28, WHITE, bold=True, anchor="mm")
        text(draw, ((x1 + x2) / 2, y1 + 220), body, 27, MUTED, anchor="mm", spacing=10)


def draw_training(draw):
    steps = [
        ("01", "KHỞI TẠO", "U, V(1)…V(B)", BLUE),
        ("02", "CỐ ĐỊNH U", "Cập nhật từng V(b)\n+ reweighted D(b)", PURPLE),
        ("03", "CỐ ĐỊNH V", "Cập nhật U từ\ntất cả hành vi", GREEN),
        ("04", "KIỂM TRA", "Objective / validation", ORANGE),
    ]
    x_positions = [100, 540, 980, 1420]
    for i, ((no, title_, body, col), x) in enumerate(zip(steps, x_positions)):
        rr(draw, (x, 350, x + 380, 770), 34, fill=PANEL, outline=col)
        text(draw, (x + 48, 400), no, 36, col, bold=True)
        text(draw, (x + 190, 510), title_, 30, WHITE, bold=True, anchor="mm")
        text(draw, (x + 190, 635), body, 25, MUTED, anchor="mm", spacing=12)
        if i < 3:
            arrow(draw, (x + 390, 560), (x + 430, 560), color=CYAN, width=4)
    draw.arc((410, 780, 1570, 980), 0, 180, fill=CYAN, width=5)
    arrow(draw, (420, 880), (410, 830), color=CYAN, width=5)
    text(draw, (990, 900), "LẶP ĐẾN KHI HỘI TỤ", 28, CYAN, bold=True, anchor="mm")


def draw_example(draw):
    rr(draw, (100, 290, 850, 895), 34, fill=PANEL)
    text(draw, (475, 340), "RATING", 34, BLUE, bold=True, anchor="mm")
    labels = [("Factor 1", True, "CHUNG"), ("Factor 2", False, "TẮT"), ("Factor 3", True, "RIÊNG")]
    for i, (lab, active, tag) in enumerate(labels):
        y = 455 + i * 130
        text(draw, (170, y), lab, 29, WHITE, bold=True)
        draw.rounded_rectangle((370, y - 5, 700, y + 48), radius=20, fill=BLUE if active else "#27384D")
        text(draw, (745, y + 22), tag, 24, GREEN if active else RED, bold=True, anchor="mm")
    rr(draw, (970, 290, 1820, 895), 34, fill=PANEL)
    text(draw, (1395, 340), "FAVORITE", 34, PURPLE, bold=True, anchor="mm")
    labels2 = [("Factor 1", True, "CHUNG"), ("Factor 2", True, "RIÊNG"), ("Factor 3", False, "TẮT")]
    for i, (lab, active, tag) in enumerate(labels2):
        y = 455 + i * 130
        text(draw, (1040, y), lab, 29, WHITE, bold=True)
        draw.rounded_rectangle((1240, y - 5, 1610, y + 48), radius=20, fill=PURPLE if active else "#27384D")
        text(draw, (1690, y + 22), tag, 24, GREEN if active else RED, bold=True, anchor="mm")
    text(draw, (960, 945), "Srating ∩ Sfavorite = { factor 1 }", 30, CYAN, bold=True, anchor="mm")


def draw_limits(draw):
    rr(draw, (100, 300, 915, 900), 34, fill=PANEL, outline=GREEN)
    text(draw, (165, 360), "NÊN DÙNG KHI", 34, GREEN, bold=True)
    good = ["Nhiều hành vi có liên quan", "Target behavior khá thưa", "Muốn tận dụng tín hiệu phụ", "Chấp nhận biểu diễn latent"]
    for i, item in enumerate(good):
        y = 470 + i * 95
        draw.ellipse((160, y, 196, y + 36), fill=GREEN)
        text(draw, (178, y + 18), "✓", 22, BG, bold=True, anchor="mm")
        text(draw, (225, y + 18), item, 29, WHITE, bold=True, anchor="lm")
    rr(draw, (1005, 300, 1820, 900), 34, fill=PANEL, outline=ORANGE)
    text(draw, (1070, 360), "CẦN LƯU Ý", 34, ORANGE, bold=True)
    warn = ["Objective không lồi", "Nhạy với hyperparameter", "Vẫn có negative transfer", "Top-N có thể cần BPR"]
    for i, item in enumerate(warn):
        y = 470 + i * 95
        draw.ellipse((1070, y, 1106, y + 36), fill=ORANGE)
        text(draw, (1088, y + 18), "!", 22, BG, bold=True, anchor="mm")
        text(draw, (1135, y + 18), item, 29, WHITE, bold=True, anchor="lm")


def draw_summary(draw):
    flow = [
        ("NHIỀU MA TRẬN", BLUE),
        ("SHARED U", CYAN),
        ("GROUP SPARSITY", PURPLE),
        ("SHARED + PRIVATE", ORANGE),
        ("DỰ ĐOÁN", GREEN),
    ]
    y = 315
    for i, (label, col) in enumerate(flow):
        x1 = 250 if i % 2 == 0 else 980
        x2 = x1 + 690
        rr(draw, (x1, y, x2, y + 105), 28, fill=PANEL, outline=col)
        text(draw, ((x1 + x2) / 2, y + 53), label, 31, WHITE, bold=True, anchor="mm")
        if i < len(flow) - 1:
            next_x = 980 if i % 2 == 0 else 250
            arrow(draw, (x2 if i % 2 == 0 else x1, y + 110), (next_x + (0 if i % 2 == 0 else 690), y + 155), color=col, width=4)
        y += 135
    text(draw, (960, 970), "CHIA SẺ ĐÚNG PHẦN • GIỮ RIÊNG ĐÚNG CHỖ", 30, CYAN, bold=True, anchor="mm")


DRAWERS = {
    "intro": draw_intro,
    "problem": draw_problem,
    "architecture": draw_architecture,
    "mask": draw_mask,
    "groups": draw_groups,
    "objective": draw_objective,
    "training": draw_training,
    "example": draw_example,
    "limits": draw_limits,
    "summary": draw_summary,
}


def make_scene(scene: Scene, index: int, path: Path):
    img = background()
    d = ImageDraw.Draw(img)
    header(d, scene, index)
    DRAWERS[scene.kind](d)
    footer(d, index)
    img.convert("RGB").save(path, quality=95)


def run(cmd: list[str]):
    print(f"Running {cmd[0]} -> {Path(cmd[-1]).name}")
    subprocess.run(cmd, check=True)


def duration(path: Path) -> float:
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path)
    ], text=True)
    return float(out.strip())


def generate_audio(scene: Scene, index: int, path: Path):
    for attempt in range(1, 4):
        try:
            print(f"Generating Vietnamese narration -> {path.name}")
            run([
                "edge-tts", "--voice", "en-US-BrianMultilingualNeural",
                "--rate=+7%", "--pitch=-8Hz", "--volume=+2%",
                "--text", scene.narration, "--write-media", str(path)
            ])
            return
        except subprocess.CalledProcessError:
            if attempt == 3:
                raise
            time.sleep(4 * attempt)


def make_clip(image_path: Path, audio_path: Path, clip_path: Path, seconds: float):
    fade_out = max(0.1, seconds - 0.45)
    # Keep every slide spatially fixed. The animated crop used previously
    # made the grid and text visibly vibrate when repeated at 30 fps.
    vf = (
        "scale=1920:1080:flags=lanczos,fps=30,"
        f"fade=t=in:st=0:d=0.35,fade=t=out:st={fade_out:.3f}:d=0.45,format=yuv420p"
    )
    af = f"afade=t=in:st=0:d=0.18,afade=t=out:st={fade_out:.3f}:d=0.4,loudnorm=I=-16:LRA=7:TP=-1.5"
    run([
        "ffmpeg", "-y", "-loop", "1", "-i", str(image_path), "-i", str(audio_path),
        "-t", f"{seconds:.3f}", "-r", str(FPS), "-vf", vf, "-af", af,
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-c:a", "aac", "-b:a", "192k",
        "-shortest", str(clip_path)
    ])


def main():
    for directory in (SCENES_DIR, AUDIO_DIR, CLIPS_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    metadata = []
    for i, scene in enumerate(SCENES):
        png = SCENES_DIR / f"scene_{i + 1:02d}.png"
        mp3 = AUDIO_DIR / f"scene_{i + 1:02d}.mp3"
        clip = CLIPS_DIR / f"scene_{i + 1:02d}.mp4"
        make_scene(scene, i, png)
        generate_audio(scene, i, mp3)
        seconds = duration(mp3) + 0.7
        make_clip(png, mp3, clip, seconds)
        metadata.append({"scene": i + 1, "title": scene.title, "duration": duration(clip)})

    concat_file = ASSETS / "concat.txt"
    concat_file.write_text("\n".join(f"file '{p.as_posix()}'" for p in sorted(CLIPS_DIR.glob("scene_*.mp4"))), encoding="utf-8")
    run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_file),
        "-c", "copy", "-movflags", "+faststart", str(FINAL)
    ])

    shutil.copy2(SCENES_DIR / "scene_01.png", THUMBNAIL)
    (ROOT / "video_metadata.json").write_text(
        json.dumps({"title": "Multi-Behavior Matrix Factorization", "total_duration": duration(FINAL), "scenes": metadata}, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    print(f"Created: {FINAL}")


if __name__ == "__main__":
    main()
