# Chính sách & Kiểm duyệt nội dung – HuTube

> Tài liệu định hướng chính sách và thiết kế hệ thống kiểm duyệt cho nền tảng chia sẻ video HuTube/KLCN.
>
> **Phiên bản:** 1.0  
> **Ngày:** 2026-09-13

---

## 1. Mục tiêu

Hệ thống chính sách và kiểm duyệt của HuTube nhằm:

- Bảo vệ người dùng khỏi nội dung nguy hiểm, bất hợp pháp hoặc gây hại.
- Duy trì môi trường video lành mạnh.
- Bảo vệ quyền sở hữu trí tuệ và quyền riêng tư.
- Hạn chế spam, lừa đảo, thao túng hệ thống và hành vi lạm dụng.
- Xử lý nội dung theo mức độ thay vì mặc định xóa.
- Kết hợp kiểm duyệt tự động, báo cáo cộng đồng và kiểm duyệt thủ công.
- Cung cấp cơ chế khiếu nại đối với quyết định kiểm duyệt.

---

# 2. Nguyên tắc kiểm duyệt

## 2.1. Kiểm duyệt theo mức độ

Không phải nội dung không phù hợp với mọi người đều phải bị xóa.

| Mức | Trạng thái | Hướng xử lý |
|---|---|---|
| 0 | Safe | Cho phép hiển thị và đề xuất bình thường |
| 1 | Sensitive | Cho phép nhưng cảnh báo hoặc hạn chế |
| 2 | Age Restricted | Chỉ nhóm người dùng đủ tuổi được xem |
| 3 | Recommendation Restricted | Hạn chế/không đưa vào hệ thống đề xuất |
| 4 | Violation | Gỡ nội dung và áp dụng biện pháp xử lý tài khoản |

## 2.2. Private/Unlisted vẫn chịu kiểm duyệt

Trạng thái hiển thị không đồng nghĩa với miễn kiểm duyệt.

```text
PUBLIC
UNLISTED
PRIVATE
   ↓
Vẫn có thể được kiểm duyệt
```

Private/Unlisted chỉ thay đổi khả năng tiếp cận nội dung.

## 2.3. Kiểm duyệt theo ngữ cảnh

Hệ thống nên xem xét:

- Video/hình ảnh.
- Âm thanh.
- Tiêu đề.
- Mô tả.
- Hashtag.
- Thumbnail.
- Ngữ cảnh giáo dục, tài liệu, khoa học hoặc nghệ thuật.
- Lịch sử vi phạm của tài khoản.

Không nên đánh giá nội dung chỉ dựa trên một từ khóa hoặc một khung hình riêng lẻ.

---

# 3. Khung 12 Trụ cột Chính sách Chuẩn hóa (HuTube 12-Pillars Policy Framework)

Tham khảo chuẩn mực YouTube ([YouTube Policy Center](https://www.youtube.com/howyoutubeworks/our-policies/)) và pháp luật Việt Nam:

```text
HUTUBE POLICY
│
├── 01. Community Safety (An toàn trẻ em, Khiêu dâm, Tự hại, Bạo lực, Ngược đãi động vật, Thù địch, Quấy rối, Nguy hiểm)
├── 02. Integrity & Deception (Spam, Scam, Mạo danh, Tương tác ảo, Thao túng nền tảng, Metadata sai lệch, Link ngoài)
├── 03. Information Integrity (Tin giả sai lệch, Y tế phản khoa học, Bầu cử, Nội dung AI / Deepfake)
├── 04. Privacy (Doxxing, Dữ liệu cá nhân, Nội dung không đồng thuận, Quyền riêng tư trẻ em)
├── 05. Intellectual Property (Bản quyền DMCA/SHTT, Nhãn hiệu thương mại, Tải lậu Re-upload)
├── 06. Regulated Content (Hàng cấm, Vũ khí, Ma túy/chất kích thích, Dịch vụ cờ bạc)
├── 07. Content Surface (Video, Thumbnail, Title, Description, Comment, Playlist, Link, Profile)
├── 08. Policy Exceptions (EDSA: Giáo dục, Tài liệu, Khoa học, Nghệ thuật, Lợi ích công chúng)
├── 09. Enforcement (Nhắc nhở, Khóa đào tạo, Cảnh cáo gậy 1-2-3, Giới hạn, Tạm ngưng, Chấm dứt)
├── 10. Appeals (Khiếu nại video, Khiếu nại tài khoản, Khiếu nại bản quyền, Khiếu nại riêng tư)
├── 11. Monetization (Điều kiện Đối tác, Thân thiện nhà quảng cáo Ad-suitability, Giới hạn doanh thu)
└── 12. Enforcement Infrastructure (AI Screening, Chuyên viên duyệt, Báo cáo, Risk Scoring, Audit Log, Versioning, Báo cáo minh bạch)
```

Chi tiết quy chuẩn toàn diện được đặc tả tại tài liệu [docs/design/policy/policy.md](file:///d:/KLTN/Source%20code/HuTube/docs/design/policy/policy.md).

---

## 3.1. Nội dung tình dục và khỏa thân

### Cấm

- Nội dung khiêu dâm.
- Nội dung tình dục rõ ràng.
- Nội dung tình dục liên quan trẻ vị thành niên.
- Khai thác hoặc ép buộc tình dục.

### Có thể hạn chế

- Giáo dục giới tính.
- Nội dung y khoa.
- Nghệ thuật có yếu tố khỏa thân nhưng không mang tính khiêu dâm.

```text
Explicit Sexual Content → Remove
Child Sexual Content → Remove + Escalate
Educational Content → Context Review
Non-explicit Mature Content → Possible Age Restriction
```

---

## 3.2. An toàn trẻ em

Đây là nhóm ưu tiên cao.

Cấm:

- Nội dung bóc lột hoặc lạm dụng trẻ em.
- Nội dung tình dục liên quan trẻ em.
- Khuyến khích hành vi nguy hiểm đối với trẻ em.
- Khai thác trẻ em để câu tương tác.
- Tiết lộ thông tin cá nhân nhạy cảm của trẻ em.

Các trường hợp nghiêm trọng cần quy trình escalation đặc biệt.

---

## 3.3. Bạo lực và nội dung gây sốc

### Có thể cho phép

- Tin tức hoặc nội dung tài liệu có ngữ cảnh.
- Phim, game hoặc nội dung hư cấu phù hợp.

### Có thể hạn chế

- Hình ảnh bạo lực mạnh.
- Nội dung gây sốc.
- Nội dung máu me nhưng có giá trị ngữ cảnh.

### Cấm

- Cổ súy hoặc hướng dẫn thực hiện hành vi bạo lực nghiêm trọng.
- Nội dung kích động bạo lực.
- Nội dung bạo lực đồ họa không có ngữ cảnh phù hợp.

---

## 3.4. Tự gây hại và tự sát

Cấm:

- Khuyến khích tự sát hoặc tự gây thương tích.
- Hướng dẫn chi tiết cách thực hiện.
- Cổ súy hoặc lãng mạn hóa hành vi tự hại.

Có thể cho phép:

- Nội dung giáo dục.
- Phòng ngừa.
- Chia sẻ trải nghiệm phục hồi.
- Nội dung hỗ trợ.

Có thể áp dụng cảnh báo và hạn chế đề xuất.

---

## 3.5. Hate Speech và phân biệt đối xử

Cấm nội dung:

- Kích động thù ghét đối với nhóm người.
- Đe dọa hoặc cổ súy bạo lực dựa trên đặc điểm được bảo vệ.
- Phi nhân hóa một nhóm người.
- Khuyến khích đàn áp hoặc loại trừ một nhóm người.

Cần phân biệt:

```text
Criticism of an idea/person
        ≠
Attack against a protected group
```

---

## 3.6. Quấy rối và bắt nạt

Xử lý:

- Đe dọa trực tiếp.
- Doxxing hoặc phát tán thông tin riêng tư.
- Kêu gọi cộng đồng tấn công một cá nhân.
- Bắt nạt có hệ thống.
- Hạ nhục nhằm gây tổn hại nghiêm trọng.

Tranh luận, phê bình hoặc phản biện không nên tự động bị coi là quấy rối.

---

## 3.7. Hành vi nguy hiểm

Cấm hoặc hạn chế:

- Thử thách nguy hiểm.
- Hướng dẫn hành vi có nguy cơ gây thương tích nghiêm trọng.
- Khuyến khích người xem thực hiện hành động nguy hiểm.
- Hành vi nguy hiểm liên quan trẻ em.

Nội dung giáo dục/an toàn có thể được xem xét theo ngữ cảnh.

---

## 3.8. Hoạt động bất hợp pháp

Xử lý:

- Hướng dẫn thực hiện tội phạm.
- Mua bán hàng hóa/dịch vụ bất hợp pháp.
- Lừa đảo.
- Tổ chức hoặc tuyển người cho hoạt động phạm pháp.
- Hướng dẫn né tránh cơ quan thực thi pháp luật.

Không nên đồng nhất nội dung đưa tin/giáo dục về tội phạm với nội dung cổ súy tội phạm.

---

## 3.9. Spam, Scam và thao túng nền tảng

Bao gồm:

- Upload hàng loạt nội dung rác.
- Tiêu đề/mô tả gây hiểu nhầm.
- Link lừa đảo.
- Giả mạo thương hiệu hoặc người khác.
- Mua bán tương tác giả.
- Bot hoặc tự động hóa nhằm thao túng lượt xem.
- Spam bình luận.
- Lừa người dùng cung cấp thông tin.

Có thể áp dụng:

```text
Content Removal
↓
Feature Restriction
↓
Account Warning
↓
Temporary Suspension
↓
Permanent Ban
```

---

# 4. Bản quyền và sở hữu trí tuệ

Nên tách **Community Guidelines** và **Intellectual Property Policy** thành hai nhóm chính sách riêng.

## 4.1. Bản quyền

Có thể xử lý:

- Video được tải lên trái phép.
- Âm thanh/nhạc có bản quyền.
- Phim hoặc chương trình truyền hình bị đăng lại.
- Re-upload toàn bộ nội dung của người khác.

Quy trình:

```text
Upload
  ↓
Copyright Detection
  ↓
Potential Match
  ↓
Policy Decision
  ├── Allow
  ├── Claim/Restriction
  └── Remove
```

## 4.2. Khiếu nại bản quyền

Nên lưu:

- Người báo cáo.
- Nội dung bị báo cáo.
- Bằng chứng/quyền sở hữu.
- Lý do.
- Trạng thái xử lý.
- Người xử lý.
- Thời điểm.
- Cơ chế phản hồi/khiếu nại.

---

# 5. Quy trình kiểm duyệt

## 5.1. Kiểm duyệt khi upload

```text
User Upload
    ↓
Metadata Validation
    ↓
Automated Moderation
    ├── Video Analysis
    ├── Audio Analysis
    ├── Text Analysis
    ├── Thumbnail Analysis
    └── Spam/Risk Detection
    ↓
Risk Score
    ↓
Decision
```

## 5.2. Phân loại theo confidence

```text
HIGH CONFIDENCE
→ Tự động xử lý

MEDIUM CONFIDENCE
→ Hạn chế tạm thời + Human Review

LOW CONFIDENCE
→ Cho phép + tiếp tục theo dõi
```

AI không nên tự động xóa mọi nội dung trong các trường hợp không chắc chắn.

---

# 6. Human Review

Nên chuyển sang kiểm duyệt thủ công khi:

- AI có confidence thấp/trung bình.
- Nội dung có ngữ cảnh phức tạp.
- Có khiếu nại.
- Có tranh chấp.
- Vi phạm nghiêm trọng.
- Nội dung liên quan trẻ em.
- Có yêu cầu pháp lý.
- Tranh chấp bản quyền phức tạp.

Reviewer nên thấy:

```text
Video
Title
Description
Thumbnail
Detected Categories
AI Confidence
Reports
Previous Enforcement
User Appeal
```

---

# 7. Báo cáo từ cộng đồng

Người dùng nên có:

```text
Report Video
Report Comment
Report User
Report Copyright
Report Privacy Violation
```

## 7.1. Luồng xử lý

```text
User Report
     ↓
Create Report
     ↓
Deduplicate / Prioritize
     ↓
Automated Analysis
     ↓
Human Review (if required)
     ↓
Decision
     ↓
Notify Reporter / Content Owner
```

Không nên để số lượng report đơn thuần quyết định video có bị xóa hay không.

---

# 8. Enforcement – Xử lý vi phạm

## 8.1. Cảnh cáo

Thông báo nên bao gồm:

- Nội dung vi phạm.
- Chính sách bị vi phạm.
- Lý do.
- Hình thức xử lý.
- Cách khiếu nại.

## 8.2. Strike

Có thể sử dụng:

```text
Warning
   ↓
Strike 1
   ↓
Strike 2
   ↓
Strike 3
   ↓
Temporary Suspension
   ↓
Permanent Termination
```

Vi phạm nghiêm trọng có thể bỏ qua các bước trung gian.

## 8.3. Hạn chế tính năng

Có thể hạn chế:

- Upload video.
- Livestream.
- Bình luận.
- Nhắn tin.
- Kiếm tiền.
- Đề xuất video.
- Tạo playlist.
- Một số tính năng cộng đồng.

---

# 9. Appeal – Khiếu nại

Người dùng nên có quyền yêu cầu xem xét lại quyết định trong các trường hợp phù hợp.

```text
Enforcement
     ↓
User Appeal
     ↓
Appeal Review
     ↓
┌───────────────┐
│ Decision      │
├───────────────┤
│ Uphold        │
│ Reverse       │
│ Modify        │
└───────────────┘
```

Mỗi appeal nên lưu:

- Appeal ID.
- User ID.
- Content ID.
- Enforcement ID.
- Lý do khiếu nại.
- Bằng chứng.
- Người/nhóm xử lý.
- Kết quả.
- Thời gian xử lý.
- Lý do quyết định.

---

# 10. Trạng thái video

Đề xuất:

```text
PROCESSING
    ↓
UNDER_REVIEW
    ↓
PUBLISHED
    ├── NORMAL
    ├── SENSITIVE
    ├── AGE_RESTRICTED
    └── RECOMMENDATION_RESTRICTED

REMOVED
    ├── POLICY_VIOLATION
    ├── COPYRIGHT
    ├── LEGAL_REQUEST
    └── PRIVACY
```

**Visibility** và **moderation status** nên là hai thuộc tính độc lập.

Ví dụ:

```text
visibility = PRIVATE
moderation_status = SAFE
```

hoặc:

```text
visibility = PUBLIC
moderation_status = AGE_RESTRICTED
```

---

# 11. Moderation và Recommendation

Một video có thể được phép tồn tại nhưng bị hạn chế đề xuất:

```text
Allowed
+
Recommendation Restricted
```

Video có thể không xuất hiện hoặc bị giảm phân phối trong:

- Home Feed.
- Recommended.
- Trending.
- Shorts/Reels feed.
- Search recommendation.

Điều này phù hợp với nội dung nhạy cảm nhưng chưa đến mức phải xóa.

---

# 12. Moderation Score

Có thể thiết kế:

```text
RiskScore =
    ContentRisk
  + MetadataRisk
  + UserRisk
  + ReportRisk
  + HistoricalRisk
```

Ví dụ:

| Risk Score | Hành động |
|---:|---|
| 0–20 | Allow |
| 21–40 | Allow + Monitor |
| 41–60 | Restrict |
| 61–80 | Human Review |
| 81–100 | Remove / Escalate |

> Đây là ngưỡng thiết kế ban đầu, cần hiệu chỉnh bằng dữ liệu thực tế và đánh giá false positive/false negative.

---

# 13. Audit Log

Mọi quyết định quan trọng nên có audit log.

```text
ModerationAction
├── id
├── content_id
├── user_id
├── reviewer_id
├── action
├── policy_code
├── reason
├── confidence
├── created_at
└── metadata
```

Mục đích:

- Truy vết quyết định.
- Điều tra khiếu nại.
- Đánh giá chất lượng moderator.
- Cải thiện mô hình.
- Phát hiện lạm dụng quyền moderator.

---

# 14. Phân quyền Moderation

Đề xuất:

```text
ADMIN
  ↓
MODERATION_MANAGER
  ↓
SENIOR_MODERATOR
  ↓
MODERATOR
  ↓
AI / AUTOMATED SYSTEM
```

AI không nhất thiết có quyền giống Moderator.

Các quyết định nghiêm trọng nên có quy trình escalation phù hợp:

- Xóa tài khoản vĩnh viễn.
- Xử lý nội dung liên quan trẻ em.
- Yêu cầu pháp lý.
- Tranh chấp bản quyền phức tạp.

---

# 15. Minh bạch

Khi xử lý nội dung, nên giải thích:

```text
Video bị hạn chế
↓
Policy: Violence
↓
Reason: Nội dung chứa hình ảnh bạo lực đồ họa
↓
Action: Recommendation Restricted
↓
Appeal: Available
```

Không nên chỉ hiển thị:

```text
"Video của bạn vi phạm chính sách."
```

mà không cung cấp lý do.

---

# 16. Policy Code

Mỗi chính sách nên có mã để Backend dễ quản lý.

Ví dụ:

```text
SEXUAL.EXPLICIT
SEXUAL.MINOR
VIOLENCE.GRAPHIC
VIOLENCE.INCITEMENT
HATE.SPEECH
HARASSMENT.THREAT
SELF_HARM.PROMOTION
CHILD_SAFETY.EXPLOITATION
ILLEGAL.INSTRUCTION
SPAM.MASS_UPLOAD
SCAM.PHISHING
PRIVACY.DOXXING
COPYRIGHT.UNAUTHORIZED_UPLOAD
```

Cấu trúc:

```text
CATEGORY.SUBCATEGORY
```

Có thể mở rộng:

```text
CATEGORY.SUBCATEGORY.SEVERITY
```

Ví dụ:

```text
VIOLENCE.GRAPHIC.HIGH
```

---

# 17. Kiến trúc tổng thể

```text
                    ┌─────────────────┐
                    │     Upload      │
                    └────────┬────────┘
                             ↓
                    ┌─────────────────┐
                    │ Content Process │
                    └────────┬────────┘
                             ↓
              ┌──────────────────────────┐
              │ Automated Moderation     │
              ├──────────────────────────┤
              │ Video / Image / Audio    │
              │ Text / Spam / Copyright  │
              └────────────┬─────────────┘
                           ↓
                    ┌───────────────┐
                    │ Risk Scoring  │
                    └───────┬───────┘
                            ↓
              ┌─────────────────────────┐
              │ Policy Decision Engine  │
              └───────────┬─────────────┘
                          ↓
          ┌───────────────┼────────────────┐
          ↓               ↓                ↓
       Allow           Restrict          Remove
          │               │                │
          └───────────────┼────────────────┘
                          ↓
                  ┌───────────────┐
                  │ Human Review  │
                  └───────┬───────┘
                          ↓
                    Final Decision
                          ↓
                       Appeal
```

---

# 18. Use Case liên quan

## Người dùng

- Báo cáo video.
- Báo cáo bình luận.
- Báo cáo người dùng.
- Khiếu nại quyết định kiểm duyệt.
- Xem trạng thái vi phạm.
- Xem lý do video bị hạn chế.

## Moderator

- Xem hàng đợi kiểm duyệt.
- Kiểm tra nội dung.
- Xác nhận vi phạm.
- Từ chối báo cáo.
- Áp dụng biện pháp xử lý.
- Xử lý appeal.
- Escalate nội dung.

## Admin

- Quản lý policy.
- Quản lý policy code.
- Quản lý mức xử phạt.
- Quản lý Moderator.
- Xem thống kê moderation.
- Xem audit log.

---

# 19. Chỉ số đánh giá

## AI Moderation

- Precision.
- Recall.
- F1-score.
- False Positive Rate.
- False Negative Rate.
- Accuracy.
- Confidence Calibration.

## Human Moderation

- Average Review Time.
- Appeal Rate.
- Appeal Reversal Rate.
- Moderator Agreement Rate.
- Escalation Rate.

## Platform Safety

- Violation Rate.
- Repeat Offender Rate.
- Report Resolution Time.
- Content Removal Rate.
- Recommendation Restriction Rate.

---

# 20. Nguyên tắc thiết kế cuối cùng

HuTube nên theo mô hình:

```text
          SAFETY
             +
       FAIR ENFORCEMENT
             +
        TRANSPARENCY
             +
          APPEAL
             +
       HUMAN OVERSIGHT
             +
      AUTOMATED SYSTEM
             +
       USER REPORTING
```

Mục tiêu không phải là **xóa càng nhiều càng tốt**, mà là:

> **Đưa mỗi nội dung vào mức xử lý phù hợp với mức độ rủi ro và ngữ cảnh của nội dung.**

Hệ thống cần bảo đảm:

1. **An toàn:** Nội dung nguy hiểm/vi phạm nghiêm trọng được xử lý nhanh.
2. **Công bằng:** Nội dung hợp lệ không bị xóa chỉ vì AI hoặc report sai.
3. **Minh bạch:** Người dùng hiểu nội dung bị xử lý vì chính sách nào và có cơ chế khiếu nại.

---

# 21. Tài liệu tham khảo định hướng

Các nền tảng lớn có thể được dùng làm nguồn tham khảo khi xây dựng chính sách:

- YouTube – Community Guidelines.
- TikTok – Community Guidelines.
- Twitch – Community Guidelines.
- Chính sách Copyright, Privacy, Child Safety và Appeal của từng nền tảng.

> Chính sách HuTube cần được xây dựng độc lập dựa trên mục tiêu, đối tượng người dùng, pháp luật áp dụng và kiến trúc hệ thống của dự án; không sao chép nguyên văn chính sách của nền tảng khác.

---

## Changelog

### v1.0 – 2026-09-13

- Xây dựng khung chính sách kiểm duyệt.
- Phân loại 5 mức enforcement.
- Bổ sung AI Moderation + Human Review.
- Bổ sung User Report.
- Bổ sung Appeal.
- Bổ sung Copyright.
- Bổ sung Recommendation Restriction.
- Bổ sung Policy Code.
- Bổ sung Audit Log.
- Bổ sung định hướng Use Case và chỉ số đánh giá.
