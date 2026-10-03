# Dữ liệu kiểm thử persistent

Account/environment thực tế nằm trong `.state/checkpoint.json`, bị gitignore. Sample cấu hình ở `../config.example.json`. Không dùng email random hoặc tạo account cho từng lần chạy.

Khi triển khai full suite, manifest lưu actor IDs, channel/video/playlist/comment/payment/report/appeal/job IDs, source hash/duration và owner/purpose. Tra cứu/reconcile ID trước create, ghi checkpoint ngay sau mutation thành công. Dataset có nhiều actor chỉ seed một lần theo vai trò cần thiết, dùng chủ đề học tập/lao động đã mô tả trong `docs/WEB_TEST_SCENARIOS.md`.

Video nguồn: `F:\NgDuyLinh\Khoa_Luan_Tot_Nghiep\Em Làm Thì Em Mới Có Ăn_ Không Làm Mà Đòi Có Ăn Thì…_720p.mp4`. Không copy binary lớn vào Git. Bộ auth chưa upload file này. Cleanup chỉ IDs trong manifest; không xóa account/channel/video chính dùng xuyên suốt.
