<!-- converted from ITEM_BASED_CF_EXAMPLE.docx -->

Ví dụ Item Based Collaborative Filtering
# 1. Ma trận tương tác và mục tiêu đề xuất
User cần đề xuất: U1 đã đánh giá V1 = 5, V2 = 4, V3 = 2. Các ứng viên chưa đánh giá là V4, V5, V6 và V7.
| User | V1 | V2 | V3 | V4 | V5 | V6 | V7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U1 | 5 | 4 | 2 | 0 | 0 | 0 | 0 |
| U2 | 5 | 4 | 2 | 5 | 1 | 2 | 0 |
| U3 | 4 | 5 | 1 | 4 | 5 | 1 | 0 |
| U4 | 1 | 2 | 5 | 1 | 4 | 5 | 0 |
| U5 | 0 | 1 | 4 | 0 | 5 | 4 | 3 |
| U6 | 4 | 3 | 2 | 4 | 2 | 1 | 5 |
| U7 | 1 | 0 | 5 | 1 | 4 | 5 | 4 |
# 2. Công thức Cosine similarity

| Ký hiệu | Chú thích trong ví dụ |
| --- | --- |
| a, b | Hai vector rating của hai video cần so sánh. |
| t | Chỉ số user; t chạy qua U1 đến U7. |
| Σₜ aₜbₜ | Tích vô hướng, đo mức cùng xuất hiện của hai vector. |
| √(Σₜaₜ²), √(Σₜbₜ²) | Độ dài của hai vector, dùng để chuẩn hóa độ lớn rating. |
| Kết quả | Giá trị càng gần 1 thì hai video càng có mẫu rating giống nhau. |
## 3.1. Ví dụ tính similarity giữa V4 và V1





# 3. Ma trận tương đồng giữa các video
|  | V1 | V2 | V3 | V4 | V5 | V6 | V7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| V1 | 0.000 | 0.958 | 0.516 | 0.838 | 0.480 | 0.360 | 0.370 |
| V2 | 0.958 | 0.000 | 0.547 | 0.834 | 0.611 | 0.420 | 0.302 |
| V3 | 0.516 | 0.547 | 0.000 | 0.469 | 0.856 | 0.968 | 0.668 |
| V4 | 0.838 | 0.834 | 0.469 | 0.000 | 0.572 | 0.430 | 0.442 |
| V5 | 0.480 | 0.611 | 0.856 | 0.572 | 0.000 | 0.872 | 0.622 |
| V6 | 0.360 | 0.420 | 0.968 | 0.430 | 0.872 | 0.000 | 0.617 |
| V7 | 0.370 | 0.302 | 0.668 | 0.442 | 0.622 | 0.617 | 0.000 |

# 4. Tính điểm đề xuất cho U1


| Ứng viên | S(i,V1) | S(i,V2) | S(i,V3) | Tử số | Mẫu số | Score |
| --- | --- | --- | --- | --- | --- | --- |
| V4 | 0.838 | 0.834 | 0.469 | 8.465 | 2.141 | 3.954 |
| V5 | 0.480 | 0.611 | 0.856 | 6.554 | 1.947 | 3.367 |
| V6 | 0.360 | 0.420 | 0.968 | 5.414 | 1.748 | 3.098 |
| V7 | 0.370 | 0.302 | 0.668 | 4.397 | 1.341 | 3.279 |

Bảng 6. Trọng số similarity và điểm dự đoán cho các video U1 chưa đánh giá
Ví dụ chi tiết cho V4: score(U1,V4) = (5×0.838 + 4×0.834 + 2×0.469) / (0.838 + 0.834 + 0.469) = 3.954.
# 6. Kết quả Top K
| Hạng | Video | Score dự đoán | Trạng thái |
| --- | --- | --- | --- |
| 1 | V4 | 3.954 | Video chưa được U1 đánh giá |
| 2 | V5 | 3.367 | Video chưa được U1 đánh giá |
| 3 | V7 | 3.279 | Video chưa được U1 đánh giá |
| 4 | V6 | 3.098 | Video chưa được U1 đánh giá |

Bảng 7. Xếp hạng các video ứng viên cho U1
Nếu chọn K = 3, kết quả đề xuất là: Top-3(U1) = [V4, V5, V7].
