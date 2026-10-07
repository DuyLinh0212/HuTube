# Flow xuyên User và Admin

`moderation.py`: owner publish video fixture → Admin approve → member phát video thật → playlist add/remove → owner chuyển private → member playback bị chặn. Actor dùng browser context riêng và cùng video ID. Case đã approve được reconcile qua queue processed, không tạo lại video.

Các module liên quan: User membership invite/accept/role/remove; Admin users lock/unlock kiểm tra session User; Admin plans catalog; policy version đồng bộ API public. Report/appeal/strike/SoD, payment và realtime notification vẫn chưa hoàn tất. CF Seeder và simulation được loại khỏi phạm vi theo yêu cầu người dùng.
