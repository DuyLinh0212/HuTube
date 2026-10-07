# Flow Admin

Users (search/filter, 55-row pagination, lock/unlock), Channels (list/detail/CSV), Topics, Plans, Policies và RBAC có script riêng; Account ở `tests/admin_account.py`. Duyệt video ở `flows/cross_app/moderation.py`. Xem [Web suite](../../tests/WEB_SUITE.md) để chạy và xem phần còn PLANNED. Mutation được đối chiếu API/reload; toast không thay bằng chứng persist. CF Seeder và simulation được loại khỏi phạm vi theo yêu cầu người dùng.
