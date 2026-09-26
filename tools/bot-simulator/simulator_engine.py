import asyncio
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import os
import random
import re
import time
from typing import Any, Callable, Dict, List, Optional
import httpx

from persona_data import (
    COMMENTS_BY_CATEGORY,
    VIETNAMESE_FIRST_NAMES,
    VIETNAMESE_LAST_NAMES,
    VIETNAMESE_MIDDLE_NAMES,
)

USERS_FILE = os.path.join(os.path.dirname(__file__), "registered_users.json")
MATRIX_FILE = os.path.join(os.path.dirname(__file__), "user_video_matrix.csv")


def append_record_to_csv(record: InteractionRecord):
    file_exists = os.path.exists(MATRIX_FILE)
    try:
        with open(MATRIX_FILE, "a", encoding="utf-8") as f:
            if not file_exists:
                f.write("user_id,username,display_name,video_id,video_title,category_slug,watch_ratio,watched_seconds,video_duration,like,dislike,rating,comment,subscribed,timestamp\n")
            title_esc = f'"{record.video_title.replace("\"", "\"\"")}"'
            cmt_esc = f'"{record.comment.replace("\"", "\"\"")}"' if record.comment else ""
            f.write(f'{record.user_id},{record.username},{record.display_name},{record.video_id},{title_esc},{record.category_slug},{record.watch_ratio},{record.watched_seconds},{record.video_duration},{1 if record.like else 0},{1 if record.dislike else 0},{record.rating if record.rating is not None else ""},{cmt_esc},{1 if record.subscribed else 0},{record.timestamp}\n')
    except Exception:
        pass


def load_stored_users() -> list[dict[str, Any]]:
    if os.path.exists(USERS_FILE):
        try:
            with open(USERS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, list) else []
        except Exception:
            return []
    return []


def save_stored_users(users: list[dict[str, Any]]):
    try:
        with open(USERS_FILE, "w", encoding="utf-8") as f:
            json.dump(users, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def add_stored_user(user: dict[str, Any]):
    users = load_stored_users()
    existing = {u.get("username", "").lower(): u for u in users}
    uname = user.get("username", "").lower()
    if uname:
        existing[uname] = user
        save_stored_users(list(existing.values()))



@dataclass
class SimulatorLog:
    id: int
    timestamp: str
    level: str  # INFO, SUCCESS, WARN, ERROR
    user: str
    action: str
    message: str
    http_status: Optional[int] = None
    duration_ms: Optional[int] = None


@dataclass
class InteractionRecord:
    user_id: str
    username: str
    display_name: str
    video_id: str
    video_title: str
    category_slug: str
    watch_ratio: float
    watched_seconds: int
    video_duration: int
    like: bool
    dislike: bool
    rating: Optional[int]
    comment: Optional[str]
    subscribed: bool
    timestamp: str


def remove_accents(input_str: str) -> str:
    """Chuyển tiếng Việt có dấu thành không dấu cho username"""
    s1 = "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    s0 = "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd"
    result = []
    for c in input_str.lower():
        idx = s1.find(c)
        result.append(s0[idx] if idx >= 0 else c)
    return "".join(result)


def generate_vietnamese_name() -> tuple[str, str]:
    """Sinh ngẫu nhiên (DisplayName, Username) tiếng Việt tự nhiên"""
    last = random.choice(VIETNAMESE_LAST_NAMES)
    middle = random.choice(VIETNAMESE_MIDDLE_NAMES)
    first = random.choice(VIETNAMESE_FIRST_NAMES)
    display_name = f"{last} {middle} {first}"

    # Sinh username thân thiện từ họ tên
    clean = remove_accents(f"{first}{last}").lower()
    clean = re.sub(r"[^a-z0-9]", "", clean)
    suffix = random.randint(10, 999)
    username = f"{clean}{suffix}"[:30]
    return display_name, username


def make_username_from_name(display_name: str) -> str:
    """Tạo username hợp lệ từ tên hiển thị bất kỳ do người dùng nhập"""
    clean = remove_accents(display_name).lower()
    clean = re.sub(r"[^a-z0-9]", "", clean)
    if not clean:
        clean = "user"
    suffix = random.randint(10, 999)
    return f"{clean}{suffix}"[:30]


class HuTubeSimulatorEngine:
    def __init__(self, base_url: str = "http://localhost:5080/api/v1"):
        self.base_url = base_url.rstrip("/")
        self.is_running = False
        self._stop_requested = False
        self.logs: list[SimulatorLog] = []
        self.matrix: list[InteractionRecord] = []
        self._load_matrix_from_csv()
        self._log_counter = 0
        self._subscribers: list[Callable[[SimulatorLog], None]] = []

    def _load_matrix_from_csv(self):
        if not os.path.exists(MATRIX_FILE):
            return
        try:
            import csv
            with open(MATRIX_FILE, "r", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for r in reader:
                    rating_val = int(r["rating"]) if r.get("rating") and r["rating"].isdigit() else None
                    rec = InteractionRecord(
                        user_id=r.get("user_id", ""),
                        username=r.get("username", ""),
                        display_name=r.get("display_name", ""),
                        video_id=r.get("video_id", ""),
                        video_title=r.get("video_title", ""),
                        category_slug=r.get("category_slug", "general"),
                        watch_ratio=float(r.get("watch_ratio", 0) or 0),
                        watched_seconds=int(r.get("watched_seconds", 0) or 0),
                        video_duration=int(r.get("video_duration", 0) or 0),
                        like=r.get("like") in ("1", "True", True),
                        dislike=r.get("dislike") in ("1", "True", True),
                        rating=rating_val,
                        comment=r.get("comment") if r.get("comment") else None,
                        subscribed=r.get("subscribed") in ("1", "True", True),
                        timestamp=r.get("timestamp", ""),
                    )
                    self.matrix.append(rec)
        except Exception:
            pass

    def register_log_listener(self, callback: Callable[[SimulatorLog], None]):
        self._subscribers.append(callback)

    def unregister_log_listener(self, callback: Callable[[SimulatorLog], None]):
        if callback in self._subscribers:
            self._subscribers.remove(callback)

    def log(
        self,
        level: str,
        user: str,
        action: str,
        message: str,
        http_status: Optional[int] = None,
        duration_ms: Optional[int] = None,
    ):
        self._log_counter += 1
        now = datetime.now(timezone.utc).strftime("%H:%M:%S")
        entry = SimulatorLog(
            id=self._log_counter,
            timestamp=now,
            level=level,
            user=user,
            action=action,
            message=message,
            http_status=http_status,
            duration_ms=duration_ms,
        )
        self.logs.append(entry)
        if len(self.logs) > 3000:
            self.logs.pop(0)

        for sub in list(self._subscribers):
            try:
                sub(entry)
            except Exception:
                pass

    def stop(self):
        self._stop_requested = True
        self.is_running = False
        self.log("WARN", "SYSTEM", "STOP", "Yêu cầu dừng tiến trình giả lập đã được gửi.")

    def clear_logs(self):
        self.logs.clear()
        self._log_counter = 0

    def clear_matrix(self):
        self.matrix.clear()

    def get_recent_logs(self, limit: int = 50) -> list[dict[str, Any]]:
        return [asdict(item) for item in self.logs[-limit:]]

    def get_matrix_records(self) -> list[dict[str, Any]]:
        return [asdict(item) for item in self.matrix]

    async def create_user_by_name(self, display_name: str, password: str = "HuTube@123456") -> dict[str, Any]:
        """Tạo nhanh tài khoản người xem mới chỉ từ tên người dùng nhập"""
        display_name = display_name.strip()
        username = make_username_from_name(display_name)
        email = f"{username.lower()}@seed.hutube.invalid"
        res = await self.provision_viewer_accounts([{
            "username": username,
            "displayName": display_name,
            "email": email,
            "password": password
        }])
        self.log(
            "SUCCESS",
            display_name,
            "CREATE_USER",
            f"👤 Đã tạo thành công người dùng mới: '{display_name}' (username: {username})",
            http_status=201
        )
        user_obj = {
            "userId": res[0].get("userId", "") if res else "",
            "username": username,
            "displayName": display_name,
            "email": email,
            "password": password,
            "createdAt": datetime.now(timezone.utc).isoformat()
        }
        add_stored_user(user_obj)
        return user_obj

    async def get_registered_users(self) -> list[dict[str, Any]]:
        """Lấy danh sách người dùng đã đăng ký (kết hợp từ HuTube backend và kho đã lưu)"""
        users_map: dict[str, dict[str, Any]] = {}

        # 1. Nạp từ file đã lưu
        for u in load_stored_users():
            uname = u.get("username", "").lower()
            if uname:
                users_map[uname] = u

        # 2. Thử truy vấn từ backend HuTube nếu có endpoint /simulator/users
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                res = await client.get(f"{self.base_url}/simulator/users")
                if res.status_code == 200:
                    data = res.json()
                    if isinstance(data, list):
                        for row in data:
                            uname = row.get("username", "").lower()
                            if uname:
                                users_map[uname] = {
                                    "userId": row.get("userId", ""),
                                    "username": row.get("username", ""),
                                    "displayName": row.get("displayName", row.get("username", "")),
                                    "email": row.get("email", f"{uname}@seed.hutube.invalid"),
                                    "password": "UserPass@123",
                                    "createdAt": row.get("createdAt", datetime.now(timezone.utc).isoformat())
                                }
        except Exception:
            pass

        # 3. Luôn đảm bảo tài khoản mẫu cơ bản
        if "tvhsports" not in users_map:
            users_map["tvhsports"] = {
                "displayName": "TVH Sports",
                "username": "tvhsports",
                "email": "tvhsports@seed.hutube.invalid",
                "password": "UserPass@123",
                "createdAt": "2026-09-26T16:00:00Z"
            }

        sorted_users = sorted(users_map.values(), key=lambda x: x.get("displayName", "").lower())
        save_stored_users(sorted_users)
        return sorted_users


    async def get_categories(self) -> list[dict[str, Any]]:
        """Lấy danh sách Categories từ HuTube backend"""
        url = f"{self.base_url}/categories"
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                res = await client.get(url)
                if res.status_code == 200:
                    data = res.json()
                    return data if isinstance(data, list) else data.get("value", [])
            except Exception as ex:
                self.log("ERROR", "SYSTEM", "FETCH_CATEGORIES", f"Không thể lấy danh mục: {ex}")
        return []

    async def get_videos_by_category(
        self, category_id: Optional[str] = None, limit: int = 50
    ) -> list[dict[str, Any]]:
        """Lấy danh sách video từ backend theo category hoặc tất cả"""
        url = f"{self.base_url}/feed/explore"
        params: dict[str, Any] = {"pageSize": limit, "page": 1, "sort": "popular"}
        if category_id:
            params["categoryId"] = category_id

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                res = await client.get(url, params=params)
                if res.status_code == 200:
                    data = res.json()
                    return data.get("items", [])
            except Exception as ex:
                self.log("ERROR", "SYSTEM", "FETCH_VIDEOS", f"Lỗi lấy video danh mục {category_id}: {ex}")
        return []

    async def provision_viewer_accounts(
        self, accounts: list[dict[str, str]]
    ) -> list[dict[str, Any]]:
        """Cấp nhanh tài khoản người xem (không kênh, kích hoạt sẵn)"""
        url = f"{self.base_url}/simulator/viewers"
        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                t0 = time.time()
                res = await client.post(url, json={"accounts": accounts})
                elapsed = int((time.time() - t0) * 1000)
                if res.status_code in (200, 201):
                    data = res.json()
                    self.log(
                        "SUCCESS",
                        "SYSTEM",
                        "PROVISION_USERS",
                        f"Đã cấp thành công {len(data)} tài khoản người xem vào HuTube.",
                        http_status=res.status_code,
                        duration_ms=elapsed,
                    )
                    return data
                else:
                    self.log(
                        "WARN",
                        "SYSTEM",
                        "PROVISION_USERS",
                        f"Endpoint /simulator/viewers trả {res.status_code}: {res.text}. Thử đăng ký trực tiếp...",
                        http_status=res.status_code,
                    )
            except Exception as ex:
                self.log(
                    "WARN",
                    "SYSTEM",
                    "PROVISION_USERS",
                    f"Không thể gọi /simulator/viewers ({ex}). Thử đăng nhập/đăng ký trực tiếp.",
                )
        return []

    async def login_user(self, username_or_email: str, password: str) -> Optional[dict[str, Any]]:
        """Đăng nhập lấy Access Token JWT của User"""
        url = f"{self.base_url}/auth/login"
        email_to_use = username_or_email if "@" in username_or_email else f"{username_or_email.lower()}@seed.hutube.invalid"
        payload = {
            "email": email_to_use,
            "password": password,
            "platform": "mobile",
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                t0 = time.time()
                res = await client.post(url, json=payload)
                elapsed = int((time.time() - t0) * 1000)
                if res.status_code == 200:
                    data = res.json()
                    self.log(
                        "SUCCESS",
                        username_or_email,
                        "LOGIN",
                        f"Đăng nhập thành công -> Nhận JWT Access Token",
                        http_status=200,
                        duration_ms=elapsed,
                    )
                    return data
                else:
                    self.log(
                        "ERROR",
                        username_or_email,
                        "LOGIN",
                        f"Đăng nhập thất bại ({res.status_code}): {res.text}",
                        http_status=res.status_code,
                        duration_ms=elapsed,
                    )
            except Exception as ex:
                self.log("ERROR", username_or_email, "LOGIN", f"Lỗi kết nối auth: {ex}")
        return None

    async def perform_interaction(
        self,
        token: str,
        user_info: dict[str, Any],
        video: dict[str, Any],
        category_slug: str,
        watch_ratio: float,
        do_like: bool,
        do_dislike: bool,
        rating_score: Optional[int],
        comment_text: Optional[str],
        do_subscribe: bool,
    ) -> InteractionRecord:
        """Thực hiện chuỗi hành vi tương tác cho 1 user trên 1 video qua HTTP API"""
        video_id = video["videoId"]
        title = video.get("title", "Video")
        duration = max(10, video.get("duration", 180))
        headers = {"Authorization": f"Bearer {token}"}
        username = user_info.get("username", "user")
        display_name = user_info.get("displayName", username)
        user_id = user_info.get("userId", "")

        watched_seconds = max(5, int(duration * watch_ratio))

        async with httpx.AsyncClient(timeout=12.0) as client:
            # 1. Gửi Watch Progress (Lưu lịch sử xem & tỷ lệ xem)
            try:
                t0 = time.time()
                wp_res = await client.put(
                    f"{self.base_url}/videos/{video_id}/watch-progress",
                    headers=headers,
                    json={"watchedSeconds": watched_seconds, "saveHistory": True, "newSession": True},
                )
                elapsed = int((time.time() - t0) * 1000)
                self.log(
                    "INFO",
                    display_name,
                    "WATCH_PROGRESS",
                    f"⏱️ Đã xem {watched_seconds}s / {duration}s ({int(watch_ratio * 100)}%) - '{title[:35]}...'",
                    http_status=wp_res.status_code,
                    duration_ms=elapsed,
                )
            except Exception as ex:
                self.log("ERROR", display_name, "WATCH_PROGRESS", f"Lỗi watch progress: {ex}")

            # 0. Kiểm tra trạng thái tương tác hiện tại của user trên video này
            already_liked = False
            already_disliked = False
            try:
                v_res = await client.get(f"{self.base_url}/videos/{video_id}", headers=headers)
                if v_res.status_code == 200:
                    v_data = v_res.json()
                    viewer_state = v_data.get("viewerState") or {}
                    prev_react = (viewer_state.get("reaction") or "").lower()
                    if prev_react == "like":
                        already_liked = True
                    elif prev_react == "dislike":
                        already_disliked = True
            except Exception:
                pass

            # 2. Gửi Reaction (Like / Dislike) - Nếu đã Like rồi thì bỏ qua like, chỉ view/cmt/rate
            reaction_done_like = already_liked
            reaction_done_dislike = already_disliked

            if already_liked:
                self.log(
                    "INFO",
                    display_name,
                    "REACTION",
                    f"ℹ️ Video '{title[:30]}...' đã được thả LIKE trước đó -> Bỏ qua like, chỉ xem và tương tác cmt/rating thêm.",
                    http_status=200,
                )
            elif do_like:
                try:
                    t0 = time.time()
                    react_res = await client.put(
                        f"{self.base_url}/videos/{video_id}/reaction",
                        headers=headers,
                        json={"type": "like"},
                    )
                    elapsed = int((time.time() - t0) * 1000)
                    reaction_done_like = react_res.status_code == 200
                    self.log(
                        "SUCCESS" if reaction_done_like else "WARN",
                        display_name,
                        "REACTION",
                        f"👍 Đã thả LIKE cho video '{title[:30]}...'",
                        http_status=react_res.status_code,
                        duration_ms=elapsed,
                    )
                except Exception as ex:
                    self.log("ERROR", display_name, "REACTION", f"Lỗi gửi like: {ex}")
            elif do_dislike and not already_liked:
                try:
                    t0 = time.time()
                    react_res = await client.put(
                        f"{self.base_url}/videos/{video_id}/reaction",
                        headers=headers,
                        json={"type": "dislike"},
                    )
                    elapsed = int((time.time() - t0) * 1000)
                    reaction_done_dislike = react_res.status_code == 200
                    self.log(
                        "INFO",
                        display_name,
                        "REACTION",
                        f"👎 Đã thả DISLIKE cho video '{title[:30]}...'",
                        http_status=react_res.status_code,
                        duration_ms=elapsed,
                    )
                except Exception as ex:
                    self.log("ERROR", display_name, "REACTION", f"Lỗi gửi dislike: {ex}")

            # 3. Gửi Rating (1-5 sao)
            effective_rating = None
            if rating_score and 1 <= rating_score <= 5:
                try:
                    t0 = time.time()
                    rating_res = await client.put(
                        f"{self.base_url}/videos/{video_id}/rating",
                        headers=headers,
                        json={"score": rating_score},
                    )
                    elapsed = int((time.time() - t0) * 1000)
                    if rating_res.status_code == 200:
                        effective_rating = rating_score
                    self.log(
                        "SUCCESS",
                        display_name,
                        "RATING",
                        f"⭐ Đánh giá {rating_score} sao cho video",
                        http_status=rating_res.status_code,
                        duration_ms=elapsed,
                    )
                except Exception as ex:
                    self.log("ERROR", display_name, "RATING", f"Lỗi gửi rating: {ex}")

            # 4. Gửi Comment
            sent_comment = None
            if comment_text:
                try:
                    t0 = time.time()
                    cmt_res = await client.post(
                        f"{self.base_url}/videos/{video_id}/comments",
                        headers=headers,
                        json={"content": comment_text},
                    )
                    elapsed = int((time.time() - t0) * 1000)
                    if cmt_res.status_code in (200, 201):
                        sent_comment = comment_text
                    self.log(
                        "SUCCESS",
                        display_name,
                        "COMMENT",
                        f"💬 Đăng bình luận: \"{comment_text}\"",
                        http_status=cmt_res.status_code,
                        duration_ms=elapsed,
                    )
                except Exception as ex:
                    self.log("ERROR", display_name, "COMMENT", f"Lỗi gửi comment: {ex}")

            # 5. Gửi Subscribe kênh (nếu có channelId)
            did_sub = False
            channel_id = video.get("channelId")
            if do_subscribe and channel_id:
                try:
                    t0 = time.time()
                    sub_res = await client.post(
                        f"{self.base_url}/channels/{channel_id}/subscribe",
                        headers=headers,
                    )
                    elapsed = int((time.time() - t0) * 1000)
                    did_sub = sub_res.status_code == 200
                    self.log(
                        "SUCCESS" if did_sub else "INFO",
                        display_name,
                        "SUBSCRIBE",
                        f"🔔 Đăng ký kênh '{video.get('channelName', 'Channel')}'",
                        http_status=sub_res.status_code,
                        duration_ms=elapsed,
                    )
                except Exception as ex:
                    self.log("WARN", display_name, "SUBSCRIBE", f"Lỗi đăng ký kênh: {ex}")

        # Ghi nhận vào ma trận
        record = InteractionRecord(
            user_id=user_id,
            username=username,
            display_name=display_name,
            video_id=video_id,
            video_title=title,
            category_slug=category_slug,
            watch_ratio=round(watch_ratio, 2),
            watched_seconds=watched_seconds,
            video_duration=duration,
            like=reaction_done_like,
            dislike=reaction_done_dislike,
            rating=effective_rating,
            comment=sent_comment,
            subscribed=did_sub,
            timestamp=datetime.now(timezone.utc).isoformat(),
        )
        self.matrix.append(record)
        append_record_to_csv(record)
        return record

    async def run_target_user_simulation(
        self,
        username: str,
        display_name: str,
        password: str,
        category_id: str,
        category_slug: str,
        video_count: int = 20,
        watch_ratio: float = 0.75,
        like_ratio: float = 1.0,
        dislike_ratio: float = 0.0,
        rating_ratio: float = 1.0,
        rating_mode: str = "fixed_5",
        custom_rating_score: int = 5,
        comment_ratio: float = 1.0,
        custom_comments_list: Optional[list[str]] = None,
        subscribe_ratio: float = 0.40,
        enable_subscribe: bool = True,
        delay_between_requests: float = 0.2,
        users_list: Optional[list[dict[str, Any]]] = None,
    ):
        """Kịch bản 1: Giả lập tương tác cho 1 hoặc NHIỀU User cụ thể với các tỷ lệ tùy chỉnh"""
        self.is_running = True
        self._stop_requested = False
        eff_sub = subscribe_ratio if enable_subscribe else 0.0

        target_users = users_list if (users_list and len(users_list) > 0) else [
            {"username": username, "displayName": display_name, "password": password}
        ]
        total_users = len(target_users)

        self.log(
            "INFO",
            "SYSTEM",
            "START_TARGET",
            f"🚀 Bắt đầu giả lập cho nhóm {total_users} người dùng: {video_count} video '{category_slug}' | Like: {int(like_ratio*100)}% | Dislike: {int(dislike_ratio*100)}% | Cmt: {int(comment_ratio*100)}% | Rating: {int(rating_ratio*100)}% | Sub: {int(eff_sub*100)}%",
        )

        # 1. Cấp tài khoản viewer cho tất cả user nếu chưa có
        provision_payload = [
            {
                "username": u["username"],
                "displayName": u.get("displayName", u["username"]),
                "email": f"{u['username'].lower()}@seed.hutube.invalid",
                "password": u.get("password", "UserPass@123"),
            }
            for u in target_users
        ]
        await self.provision_viewer_accounts(provision_payload)

        # 2. Lấy video thuộc danh mục 1 lần
        videos = await self.get_videos_by_category(category_id, limit=video_count * 2)
        if not videos:
            self.log("WARN", "SYSTEM", "NO_VIDEOS", f"Không tìm thấy video trong danh mục {category_slug}. Lấy video chung...")
            videos = await self.get_videos_by_category(None, limit=video_count * 2)

        target_videos = videos[:video_count]
        self.log(
            "INFO",
            "SYSTEM",
            "FOUND_VIDEOS",
            f"Tìm thấy {len(target_videos)} video để tiến hành tương tác cho {total_users} người dùng.",
        )

        # Lấy kho comment tương ứng
        comments_pool = custom_comments_list if (custom_comments_list and len(custom_comments_list) > 0) else COMMENTS_BY_CATEGORY.get(category_slug, COMMENTS_BY_CATEGORY["default"])

        # 3. Tiến hành tương tác cho từng User trong nhóm
        for u_idx, u in enumerate(target_users, 1):
            if self._stop_requested:
                break

            curr_uname = u["username"]
            curr_dname = u.get("displayName", curr_uname)
            curr_pwd = u.get("password", "UserPass@123")
            curr_email = f"{curr_uname.lower()}@seed.hutube.invalid"

            self.log(
                "INFO",
                curr_dname,
                "START_USER_SESSION",
                f"[{u_idx}/{total_users}] Khởi động phiên tương tác của '{curr_dname}' (@{curr_uname})...",
            )

            # Đăng nhập
            auth_data = await self.login_user(curr_uname, curr_pwd)
            if not auth_data or "accessToken" not in auth_data:
                auth_data = await self.login_user(curr_email, curr_pwd)
                if not auth_data or "accessToken" not in auth_data:
                    self.log(
                        "ERROR",
                        curr_uname,
                        "LOGIN_FAILED",
                        f"Không thể xác thực tài khoản {curr_uname}. Bỏ qua user này.",
                    )
                    continue

            token = auth_data["accessToken"]
            user_info = auth_data.get("user", {"userId": "", "username": curr_uname, "displayName": curr_dname})

            user_interact_count = 0
            for vid in target_videos:
                if self._stop_requested:
                    break

                user_interact_count += 1

                # 1. Tỷ lệ Like / Dislike (Độc quyền: hoặc Like, hoặc Dislike, hoặc Chỉ xem)
                roll_react = random.random()
                do_like = False
                do_dislike = False
                if roll_react < like_ratio:
                    do_like = True
                elif roll_react < (like_ratio + dislike_ratio):
                    do_dislike = True

                # 2. Đánh giá Rating phù hợp tuyệt đối với Cảm xúc (hoặc 0 đánh giá / None)
                roll_rating = random.random()
                rating_score = None
                if roll_rating < rating_ratio:
                    if do_like:
                        if rating_mode == "fixed_5":
                            rating_score = 5
                        else:
                            rating_score = random.choice([4, 5])
                    elif do_dislike:
                        rating_score = random.choice([1, 2])
                    else:
                        rating_score = 3

                # 3. Bình luận Comment phù hợp với cảm xúc
                roll_cmt = random.random()
                comment_text = None
                if roll_cmt < comment_ratio:
                    if do_dislike:
                        comment_text = random.choice([
                            "Nội dung chưa thực sự ấn tượng như kỳ vọng.",
                            "Cần cải thiện thêm về chất lượng âm thanh và hình ảnh.",
                            "Góp ý kênh nên đầu tư thêm về mặt nội dung.",
                        ])
                    elif comments_pool:
                        comment_text = random.choice(comments_pool)

                # 4. Tỷ lệ Đăng ký kênh (Subscribe)
                roll_sub = random.random()
                do_subscribe = (roll_sub < eff_sub)

                await self.perform_interaction(
                    token=token,
                    user_info=user_info,
                    video=vid,
                    category_slug=category_slug,
                    watch_ratio=watch_ratio,
                    do_like=do_like,
                    do_dislike=do_dislike,
                    rating_score=rating_score,
                    comment_text=comment_text,
                    do_subscribe=do_subscribe,
                )

                if delay_between_requests > 0:
                    await asyncio.sleep(delay_between_requests)

            self.log(
                "SUCCESS",
                curr_dname,
                "FINISH_USER",
                f"[{u_idx}/{total_users}] Hoàn thành phiên tương tác của '{curr_dname}': Đã xem & tương tác {user_interact_count} video.",
            )

        self.is_running = False
        self.log(
            "SUCCESS",
            "SYSTEM",
            "FINISH_TARGET",
            f"🎉 Hoàn thành kịch bản mô phỏng cho toàn bộ {total_users} người dùng đã chọn! Tổng số lượt tương tác đã ghi nhận: {len(self.matrix)}",
        )

    async def run_swarm_simulation(
        self,
        bot_count: int = 10,
        videos_per_bot: int = 15,
        preferred_category_ratio: float = 0.8,
        like_ratio: float = 0.70,
        dislike_ratio: float = 0.20,
        comment_ratio: float = 0.35,
        rating_ratio: float = 0.60,
        subscribe_ratio: float = 0.35,
        custom_comments_list: Optional[list[str]] = None,
        delay_between_requests: float = 0.15,
    ):
        """Kịch bản 2: Giả lập cụm Bot Persona ngẫu nhiên theo danh mục sở thích với tỷ lệ tương tác tùy chỉnh"""
        self.is_running = True
        self._stop_requested = False
        self.log(
            "INFO",
            "SYSTEM",
            "START_SWARM",
            f"🚀 Bắt đầu mô phỏng cụm {bot_count} người dùng giả lập | Like: {int(like_ratio*100)}% | Dislike: {int(dislike_ratio*100)}% | Cmt: {int(comment_ratio*100)}% | Rating: {int(rating_ratio*100)}%",
        )

        categories = await self.get_categories()
        if not categories:
            self.log("ERROR", "SYSTEM", "NO_CATEGORIES", "Không lấy được danh mục từ Backend. Dừng.")
            self.is_running = False
            return

        cat_by_id = {c["categoryId"]: c for c in categories}
        cat_ids = list(cat_by_id.keys())

        # 1. Sinh danh sách người dùng ngẫu nhiên
        generated_accounts = []
        for i in range(bot_count):
            disp, uname = generate_vietnamese_name()
            # Gán gu danh mục chính
            assigned_cat = random.choice(categories)
            generated_accounts.append({
                "username": uname,
                "displayName": disp,
                "email": f"{uname.lower()}@viewer.hutube.invalid",
                "password": "HuTube@123456",
                "persona_cat_id": assigned_cat["categoryId"],
                "persona_cat_slug": assigned_cat.get("slug", "default"),
                "persona_cat_name": assigned_cat.get("name", "Chung"),
            })

        # 2. Cấp tài khoản vào backend
        await self.provision_viewer_accounts([
            {
                "username": acc["username"],
                "displayName": acc["displayName"],
                "email": acc["email"],
                "password": acc["password"],
            }
            for acc in generated_accounts
        ])

        # 3. Lấy trước video theo từng category để cache
        video_cache: dict[str, list[dict[str, Any]]] = {}
        for c in categories:
            cid = c["categoryId"]
            video_cache[cid] = await self.get_videos_by_category(cid, limit=40)

        all_videos = await self.get_videos_by_category(None, limit=100)

        # 4. Chạy từng user
        for idx, bot in enumerate(generated_accounts, 1):
            if self._stop_requested:
                break

            uname = bot["username"]
            dname = bot["displayName"]
            pcat_id = bot["persona_cat_id"]
            pcat_slug = bot["persona_cat_slug"]
            pcat_name = bot["persona_cat_name"]

            self.log(
                "INFO",
                dname,
                "START_USER",
                f"[{idx}/{bot_count}] Bắt đầu phiên xem của '{dname}' (Gu chính: {pcat_name})...",
            )

            auth_data = await self.login_user(uname, bot["password"])
            if not auth_data or "accessToken" not in auth_data:
                auth_data = await self.login_user(bot["email"], bot["password"])
                if not auth_data or "accessToken" not in auth_data:
                    self.log("WARN", dname, "SKIP_USER", f"Không đăng nhập được {uname}. Bỏ qua.")
                    continue

            token = auth_data["accessToken"]
            user_info = auth_data.get("user", {"userId": "", "username": uname, "displayName": dname})

            # Chọn danh sách video xem: đúng gu theo preferred_category_ratio, còn lại danh mục khác
            pref_vids = video_cache.get(pcat_id, [])
            other_vids = [v for v in all_videos if v.get("categoryId") != pcat_id]

            selected_videos: list[tuple[dict[str, Any], str]] = []
            num_pref = int(videos_per_bot * preferred_category_ratio)
            num_other = videos_per_bot - num_pref

            if pref_vids:
                sampled_pref = random.sample(pref_vids, min(num_pref, len(pref_vids)))
                for v in sampled_pref:
                    selected_videos.append((v, pcat_slug))

            if other_vids and num_other > 0:
                sampled_other = random.sample(other_vids, min(num_other, len(other_vids)))
                for v in sampled_other:
                    cat_obj = cat_by_id.get(v.get("categoryId", ""), {})
                    selected_videos.append((v, cat_obj.get("slug", "default")))

            # Xáo trộn thứ tự xem cho tự nhiên
            random.shuffle(selected_videos)

            for vid, cslug in selected_videos:
                if self._stop_requested:
                    break

                is_fav_cat = (cslug == pcat_slug)

                # watch_ratio: nếu đúng gu xem 65% - 95%, nếu lạc gu xem 15% - 45%
                if is_fav_cat:
                    watch_ratio = random.uniform(0.65, 0.95)
                else:
                    watch_ratio = random.uniform(0.15, 0.45)

                # 1. Tỷ lệ Like / Dislike áp dụng theo gu và tỷ lệ cài đặt:
                roll_react = random.random()
                do_like = False
                do_dislike = False
                if is_fav_cat:
                    if roll_react < like_ratio:
                        do_like = True
                    elif roll_react < (like_ratio + dislike_ratio):
                        do_dislike = True
                else:
                    if roll_react < (like_ratio * 0.1):
                        do_like = True
                    elif roll_react < (like_ratio * 0.1 + dislike_ratio):
                        do_dislike = True

                # 2. Tỷ lệ Rating phù hợp với Cảm xúc (hoặc 0 đánh giá):
                rating_score = None
                if random.random() < rating_ratio:
                    if do_like:
                        rating_score = random.choice([4, 5])
                    elif do_dislike:
                        rating_score = random.choice([1, 2])
                    else:
                        rating_score = 3
                # Ngược lại: rating_score = None (0 đánh giá)

                # 3. Tỷ lệ Comment:
                comment_text = None
                if random.random() < comment_ratio:
                    if do_dislike:
                        comment_text = random.choice([
                            "Nội dung chưa thực sự ấn tượng như kỳ vọng.",
                            "Cần cải thiện thêm về chất lượng âm thanh và hình ảnh.",
                            "Góp ý kênh nên đầu tư thêm về mặt nội dung.",
                        ])
                    else:
                        pool = custom_comments_list if (custom_comments_list and len(custom_comments_list) > 0) else COMMENTS_BY_CATEGORY.get(cslug, COMMENTS_BY_CATEGORY["default"])
                        if pool:
                            comment_text = random.choice(pool)

                # Subscribe kênh theo tỷ lệ cài đặt nếu đúng gu
                do_sub = is_fav_cat and (random.random() < subscribe_ratio)

                await self.perform_interaction(
                    token=token,
                    user_info=user_info,
                    video=vid,
                    category_slug=cslug,
                    watch_ratio=watch_ratio,
                    do_like=do_like,
                    do_dislike=do_dislike,
                    rating_score=rating_score,
                    comment_text=comment_text,
                    do_subscribe=do_sub,
                )

                if delay_between_requests > 0:
                    await asyncio.sleep(delay_between_requests)

        self.is_running = False
        self.log(
            "SUCCESS",
            "SYSTEM",
            "FINISH_SWARM",
            f"🎉 Hoàn thành mô phỏng toàn bộ cụm Bot! Tổng số lượt tương tác đã ghi nhận: {len(self.matrix)}",
        )


SimulatorEngine = HuTubeSimulatorEngine
simulator_engine = HuTubeSimulatorEngine()

