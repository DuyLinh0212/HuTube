# Performance — cấu trúc và kế hoạch

Chưa có script load/soak và chưa có benchmark trong đợt này. Profile PERF-BASE/READ/WRITE/AUTH/SPIKE/SOAK/MEDIA/JOB, SLO đề xuất, dataset, metrics, hard stop và budget ở `docs/BACKEND_TEST_SCENARIOS.md`; performance frontend ở tài liệu Web.

Khi triển khai, lưu scripts/config không có secret cùng manifest, report p50/p95/p99/RPS/errors/CPU/RAM/DB locks theo run. Dùng Kestrel/PostgreSQL thật và pool account tạo một lần; không register theo VU/iteration. Media 99 MB chạy 1 rồi 3 concurrent có deadline riêng. Soak chạy riêng, không thêm vào auth smoke. Ngưỡng đề xuất phải hiệu chỉnh theo baseline máy, không coi là kết quả đã đạt.
