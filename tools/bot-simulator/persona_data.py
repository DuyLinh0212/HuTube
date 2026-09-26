"""
Dữ liệu mẫu cho Bot Simulator:
- Danh sách họ, tên đệm và tên tiếng Việt tự nhiên cho người dùng.
- Kho từ điển bình luận (comment) phong phú theo từng thể loại video.
"""

VIETNAMESE_LAST_NAMES = [
    "Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh", "Phan", "Vũ", "Võ",
    "Đặng", "Bùi", "Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Đoàn", "Trịnh", "Mai", "Đinh"
]

VIETNAMESE_MIDDLE_NAMES = [
    "Văn", "Thị", "Quốc", "Minh", "Hải", "Đức", "Thanh", "Hoàng", "Xuân",
    "Ngọc", "Thuỳ", "Gia", "Bảo", "Tuấn", "Phương", "Khánh", "Anh", "Hồng"
]

VIETNAMESE_FIRST_NAMES = [
    "Nam", "Tuấn", "Hùng", "Cường", "Dũng", "Thành", "Đạt", "Huy", "Long", "Khoa",
    "Anh", "Trang", "Linh", "Hà", "Phương", "Thảo", "Hương", "Mai", "Vy", "Yến",
    "Quân", "Sơn", "Tùng", "Bình", "Thắng", "Phúc", "Khang", "Bách", "Nga", "Chi"
]

# Kho bình luận ngữ cảnh theo thể loại (Category-aware Comments)
COMMENTS_BY_CATEGORY = {
    "music": [
        "Bài này nghe cuốn thật sự, replay từ sáng đến giờ không chán!",
        "Giai điệu bắt tai quá, beat đỉnh chóp luôn.",
        "Giọng hát truyền cảm và ca từ rất ý nghĩa.",
        "Đoạn điệp khúc nghe nổi da gà, quá xuất sắc!",
        "Hóng MV chính thức và các bản live tiếp theo của ca sĩ ạ.",
        "Một tác phẩm âm nhạc quá chất lượng, hòa âm phối khí đỉnh cao.",
        "Nhạc chill hợp nghe lúc làm việc hay thư giãn buổi tối ghê.",
        "Ca khúc này chắc chắn sẽ thành hit lớn trong năm nay!",
        "Nghe xong thấy thư thái và nhiều năng lượng tích cực hẳn.",
        "Phối khí hay quá, phần bass đánh rất tròn và đã tai."
    ],
    "khoa-hoc": [
        "Video giải thích rất trực quan, dễ hiểu hơn hẳn lý thuyết trong sách vở.",
        "Kiến thức bổ ích và thực tế, cảm ơn tác giả đã chia sẻ tâm huyết!",
        "Thí nghiệm này ấn tượng thật sự, xem mở mang tầm mắt.",
        "Phần phân tích logic và dẫn chứng dữ liệu rất thuyết phục.",
        "Mong kênh tiếp tục ra thêm nhiều video chuyên sâu về chủ đề này ạ!",
        "Một góc nhìn khoa học rất mới mẻ và dễ tiếp cận cho mọi người.",
        "Giải thích ngắn gọn mà súc tích, người mới tìm hiểu xem cũng hiểu ngay.",
        "Cách đặt vấn đề và giải quyết bài toán khoa học rất bài bản.",
        "Rất thích các chủ đề công nghệ và khoa học của kênh, 10 điểm!",
        "Kênh làm nội dung khoa học chất lượng nhất mà mình từng xem."
    ],
    "cong-nghe": [
        "Đánh giá chi tiết và khách quan, giúp mình có thêm căn cứ để chọn mua.",
        "Công nghệ mới này đột phá thật sự, tiềm năng ứng dụng rất lớn.",
        "Trải nghiệm thực tế hữu ích, phân tích rõ cả ưu điểm lẫn nhược điểm.",
        "Kênh cập nhật xu hướng công nghệ nhanh và chuẩn xác ghê.",
        "Cách giải thích nguyên lý hoạt động của thiết bị rất mạch lạc.",
        "Mong ad làm thêm video so sánh hiệu năng với phiên bản trước."
    ],
    "sports": [
        "Pha xử lý quá đẳng cấp, xem lại highlight vẫn thấy mãn nhãn!",
        "Trận đấu kịch tính đến những phút bù giờ cuối cùng.",
        "Phong độ thi đấu tuyệt vời, bàn thắng đẹp như tranh vẽ.",
        "Chiến thuật của ban huấn luyện trận này quá chuẩn xác và hiệu quả.",
        "Tinh thần thi đấu quả cảm, xứng đáng nhận được tràng pháo tay!",
        "Pha kiến tạo không tưởng, nhãn quan chiến thuật đỉnh cao.",
        "Xem trận này cảm xúc dâng trào thật sự, cổ vũ hết mình!",
        "Cầu thủ này ngày càng hoàn thiện kỹ năng, tương lai rất sáng."
    ],
    "football": [
        "Bàn thắng quá đẹp mắt, thủ môn hoàn toàn không có cơ hội cản phá!",
        "Trận derby rực lửa đúng nghĩa, các cầu thủ đá hết mình vì màu cờ sắc áo.",
        "Highlight cắt cúp rất mượt, bình luận viên phân tích nhiệt huyết ghê.",
        "Phòng ngự chắc chắn, phản công sắc bén, chiến thắng xứng đáng!",
        "Không thể tin được pha bỏ lỡ ở phút 89, tiếc thật sự.",
        "Đội bóng chơi quá thăng hoa trong hiệp 2, chúc mừng toàn đội!"
    ],
    "game": [
        "Pha combat đỉnh cao lật kèo phút chót quá mãn nhãn anh ơi!",
        "Hướng dẫn lên đồ và combo chi tiết quá, áp dụng leo rank hiệu quả liền.",
        "Xem vừa giải trí vừa học hỏi được khối mẹo chơi game hay.",
        "Kỹ năng cá nhân quá ghê, phản xạ nhanh như chớp.",
        "Tựa game này đồ họa đẹp và cốt truyện sâu sắc thật sự.",
        "Lối chơi sáng tạo ghê, giáo án này leo rank mượt mà luôn ad ơi."
    ],
    "hai-huoc": [
        "Xem video cười đau cả bụng, giải tỏa stress sau ngày làm việc mệt mỏi.",
        "Nội dung duyên dáng, gần gũi và hài hước một cách tự nhiên.",
        "Cách diễn xuất và lồng ghép âm thanh ăn ý ghê.",
        "Xem đi xem lại đoạn giữa vẫn không nhịn được cười haha.",
        "Ủng hộ kênh hết mình, tiếp tục phát huy năng lượng này nhé bạn!"
    ],
    "daily": [
        "Một ngày bình yên và nhiều điều thú vị, xem thấy lòng nhẹ nhàng hơn.",
        "Không khí ấm cúng và cách chia sẻ câu chuyện rất chân thật.",
        "Góc quay đẹp, tông màu ấm áp và âm nhạc nền rất hợp.",
        "Cảm ơn bạn đã lan tỏa năng lượng tích cực đến mọi người.",
        "Thích phong cách vlog nhẹ nhàng và mộc mạc như thế này ghê."
    ],
    "default": [
        "Nội dung video rất chất lượng và bổ ích, cảm ơn kênh nhiều ạ!",
        "Đã like và theo dõi kênh, mong chờ các video tiếp theo của bạn.",
        "Video đầu tư công phu, hình ảnh và âm thanh đều rất chỉn chu.",
        "Một sản phẩm nội dung rất đáng xem, chúc kênh ngày càng phát triển!",
        "Cảm ơn tác giả đã chia sẻ những góc nhìn thú vị này."
    ]
}


def get_comments_for_category(category_slug: str) -> list[str]:
    slug = (category_slug or "").lower().strip()
    if slug in COMMENTS_BY_CATEGORY:
        return list(COMMENTS_BY_CATEGORY[slug])
    # Tìm kiếm gần đúng
    for key, val in COMMENTS_BY_CATEGORY.items():
        if key in slug or slug in key:
            return list(val)
    return list(COMMENTS_BY_CATEGORY.get("default", []))


def add_comment_to_category(category_slug: str, comment: str) -> bool:
    slug = (category_slug or "default").lower().strip()
    cmt = (comment or "").strip()
    if not cmt or len(cmt) < 3:
        return False
    if slug not in COMMENTS_BY_CATEGORY:
        COMMENTS_BY_CATEGORY[slug] = []
    if cmt not in COMMENTS_BY_CATEGORY[slug]:
        COMMENTS_BY_CATEGORY[slug].append(cmt)
        return True
    return False


def delete_comment_from_category(category_slug: str, index: int) -> bool:
    slug = (category_slug or "default").lower().strip()
    if slug in COMMENTS_BY_CATEGORY and 0 <= index < len(COMMENTS_BY_CATEGORY[slug]):
        COMMENTS_BY_CATEGORY[slug].pop(index)
        return True
    return False

