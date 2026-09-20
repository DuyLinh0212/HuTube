# Multi-Behavior Matrix Factorization (MBMF)

## Lý thuyết, công thức và ví dụ minh họa

> **Phạm vi của tài liệu**
>
> Đây là tài liệu lý thuyết độc lập về Multi-Behavior Matrix Factorization
> (MBMF), chỉ tập trung vào mô hình, công thức, quá trình tối ưu, ví dụ và
> giới hạn.

## 1. MBMF là gì?

Trong Matrix Factorization (MF) truyền thống, dữ liệu thường chỉ chứa một loại
tương tác giữa người dùng và đối tượng. Ví dụ:

- người dùng chấm điểm một bộ phim;
- người dùng mua một sản phẩm;
- người dùng nhấn thích một bài hát;
- người dùng theo dõi một tài khoản.

Tuy nhiên, trong một hệ thống thực tế, cùng một người dùng có thể tạo ra nhiều
loại hành vi trên cùng một tập đối tượng. Những hành vi đó thường được gọi là
**multi-behavior data** hoặc **multi-feedback data**.

Ví dụ, với một cặp người dùng - sản phẩm, ta có thể quan sát:

- xem sản phẩm;
- nhấp vào sản phẩm;
- thêm vào giỏ hàng;
- yêu thích;
- mua hàng.

Mỗi loại hành vi cung cấp một phần thông tin khác nhau về sở thích. Hành vi
"xem" thường có số lượng lớn nhưng tín hiệu yếu hơn; hành vi "mua" thường ít
hơn nhưng có quan hệ trực tiếp hơn với ý định cuối cùng. MBMF cố gắng học các
tín hiệu này đồng thời thay vì chỉ dùng một ma trận duy nhất.

### 1.1. MBMF không phải là tên duy nhất của một thuật toán

MBMF thường được dùng như tên gọi chung cho họ mô hình **matrix factorization
trên nhiều ma trận hành vi**. Không có một công thức duy nhất được mọi bài báo
gọi chính xác là "MBMF".

Tài liệu này lấy bài báo sau làm mô hình lý thuyết trung tâm:

> Ting Yuan, Jian Cheng, Xi Zhang, Shuang Qiu, Hanqing Lu,
> **Recommendation by Mining Multiple User Behaviors with Group Sparsity**,
> Proceedings of the Twenty-Eighth AAAI Conference on Artificial Intelligence,
> 2014.

Bài báo đặt tên cho mô hình cụ thể là **Group-Sparse Matrix Factorization
(GSMF)**. GSMF là một dạng MBMF quan trọng: nó phân rã nhiều ma trận hành vi
vào không gian latent chung, sau đó dùng group sparsity để chọn những latent
factor phù hợp với từng hành vi.

- [Bản PDF chính thức trên AAAI](https://ojs.aaai.org/index.php/AAAI/article/download/8713/8572)
- [DOI của bài báo GSMF](https://doi.org/10.1609/aaai.v28i1.8713)

Vì vậy, trong tài liệu này:

- **MBMF** là tên gọi của bài toán/họ phương pháp;
- **GSMF** là mô hình cụ thể được dùng để giải thích công thức chi tiết;
- các công thức của GSMF được diễn giải lại bằng tiếng Việt, giữ nguyên ý
  tưởng toán học của bài báo nhưng không sao chép nguyên văn toàn bộ bài báo.

## 2. Bài toán mà MBMF giải quyết

### 2.1. Hạn chế của Matrix Factorization một hành vi

Giả sử chỉ có một ma trận tương tác:

\[
R \in \mathbb{R}^{n \times m}
\]

Trong đó:

- \(n\) là số người dùng;
- \(m\) là số đối tượng;
- \(R_{ij}\) là mức độ tương tác của người dùng \(u_i\) với đối tượng
  \(v_j\).

Ma trận này thường rất thưa. Phần lớn cặp người dùng - đối tượng chưa được
quan sát. Nếu chỉ học từ một loại hành vi, mô hình có thể thiếu dữ liệu để
ước lượng sở thích của người dùng.

Ví dụ, người dùng chưa mua nhiều sản phẩm, nhưng đã xem hoặc nhấp vào rất nhiều
sản phẩm. Nếu chỉ dùng ma trận mua hàng, phần lớn tín hiệu có sẵn bị bỏ qua.

### 2.2. Hạn chế của việc gộp tất cả hành vi vào một ma trận

Nếu các ma trận có cùng kích thước, một cách đơn giản là gộp mọi hành vi thành
một ma trận duy nhất:

\[
R^{all} = R^{(1)} + R^{(2)} + \cdots + R^{(B)}
\]

hoặc gán trọng số:

\[
R^{all} = \sum_{b=1}^{B} \omega_b R^{(b)}
\]

Cách này làm mất ngữ nghĩa của từng hành vi. Hai giá trị bằng nhau trong
\(R^{all}\) có thể đến từ những hành vi hoàn toàn khác nhau.

Ví dụ, một lần xem và một lần mua không nên mặc nhiên được coi là cùng một
tín hiệu. Hành vi có thể khác nhau về:

- mức độ mạnh của tín hiệu;
- độ tin cậy;
- mục tiêu biểu diễn;
- quan hệ với các hành vi khác;
- mức độ thưa dữ liệu.

### 2.3. Hạn chế của việc chia sẻ toàn bộ latent factor

Một hướng khác là cho mọi hành vi dùng chung toàn bộ latent factor. Cách này
giúp truyền thông tin giữa các hành vi, nhưng có thể gây **negative transfer**:

- một factor có ý nghĩa cho hành vi A bị ép phải dùng cho hành vi B;
- thông tin riêng của từng hành vi bị hòa lẫn;
- mô hình không thể biểu diễn trường hợp hai hành vi chỉ chia sẻ một phần
  sở thích.

Ý tưởng cốt lõi của GSMF là:

> Các hành vi nên chia sẻ những latent factor có liên quan, nhưng vẫn phải
> giữ được những latent factor riêng của từng hành vi.

## 3. Ký hiệu toán học

Giả sử có:

- tập người dùng \(\mathcal{U} = \{u_1,\ldots,u_n\}\);
- \(B\) loại hành vi;
- với hành vi \(b\), có tập đối tượng
  \(\mathcal{V}^{(b)} = \{v^{(b)}_1,\ldots,v^{(b)}_{m_b}\}\);
- ma trận tương tác của hành vi \(b\):

\[
R^{(b)} \in \mathbb{R}^{n \times m_b}
\]

Phần tử:

\[
R^{(b)}_{ij}
\]

là giá trị tương tác của người dùng \(u_i\) với đối tượng
\(v^{(b)}_j\) theo hành vi \(b\).

### 3.1. Ma trận hành vi

Mỗi loại hành vi có một ma trận riêng:

\[
\mathcal{R} =
\left\{
R^{(1)}, R^{(2)}, \ldots, R^{(B)}
\right\}
\]

Ví dụ:

\[
\mathcal{R} =
\{
R^{(rating)}, R^{(favorite)}, R^{(purchase)}
\}
\]

Các ma trận có thể có cùng tập đối tượng hoặc khác tập đối tượng. Bài GSMF
cho phép mỗi hành vi có \(m_b\) đối tượng riêng; chỉ chiều người dùng được
giữ chung trong công thức cơ bản.

### 3.2. Mặt nạ quan sát

Không phải mọi phần tử trong ma trận đều là dữ liệu quan sát được. Đặt:

\[
M^{(b)}_{ij} =
\begin{cases}
1 & \text{nếu } R^{(b)}_{ij} \text{ được quan sát},\\
0 & \text{nếu } R^{(b)}_{ij} \text{ bị thiếu}.
\end{cases}
\]

Mặt nạ này rất quan trọng:

- giá trị bị thiếu không được xem là một rating bằng 0;
- chỉ những phần tử có \(M^{(b)}_{ij}=1\) mới tham gia vào sai số huấn luyện;
- nếu giá trị 0 là một quan sát hợp lệ, mặt nạ vẫn bằng 1.

### 3.3. Trọng số hành vi

Ký hiệu \(\alpha_b \ge 0\) là trọng số của hành vi \(b\). Trọng số này giúp
điều chỉnh mức đóng góp của từng ma trận vào hàm mục tiêu.

Nếu các ma trận có thang đo khác nhau, \(\alpha_b\) hoặc bước chuẩn hóa dữ liệu
có thể được dùng để tránh một hành vi chi phối toàn bộ quá trình học.

## 4. Matrix Factorization cơ bản

### 4.1. Không gian latent

MF ánh xạ người dùng và đối tượng vào không gian latent có số chiều \(k\):

\[
\mathbb{R}^k
\]

Theo cách viết của bài GSMF:

\[
U \in \mathbb{R}^{k \times n}
\]

là ma trận latent factor của người dùng, trong đó:

\[
u_i = U_{:,i} \in \mathbb{R}^k
\]

là vector của người dùng \(u_i\).

Với một hành vi duy nhất:

\[
V \in \mathbb{R}^{k \times m}
\]

và:

\[
v_j = V_{:,j} \in \mathbb{R}^k
\]

là vector của đối tượng \(v_j\).

### 4.2. Hàm dự đoán

MF dùng tích vô hướng:

\[
\widehat{R}_{ij} = u_i^T v_j
\]

Triển khai theo từng chiều:

\[
\widehat{R}_{ij}
=
\sum_{t=1}^{k} u_{ti}v_{tj}
\]

Diễn giải trực quan:

- mỗi chiều \(t\) là một latent factor;
- \(u_{ti}\) biểu diễn mức độ người dùng \(u_i\) liên quan đến factor \(t\);
- \(v_{tj}\) biểu diễn mức độ đối tượng \(v_j\) chứa factor \(t\);
- tích của hai giá trị đo mức đóng góp của factor đó vào dự đoán.

Latent factor không nhất thiết có tên hoặc ý nghĩa dễ diễn giải. Việc gọi một
factor là "thể thao", "lãng mạn" hoặc "giá rẻ" chỉ là cách minh họa; mô hình
không tự bảo đảm rằng mỗi chiều tương ứng đúng với một khái niệm như vậy.

### 4.3. Hàm mất mát MF

Chỉ tính sai số trên các phần tử quan sát:

\[
f(U,V)
=
\sum_{i=1}^{n}
\sum_{j=1}^{m}
M_{ij}
\left(
R_{ij}-u_i^T v_j
\right)^2
\]

Thêm regularization Frobenius để hạn chế overfitting:

\[
\mathcal{L}_{MF}
=
f(U,V)
+
\lambda_2
\left(
\lVert U\rVert_F^2+
\lVert V\rVert_F^2
\right)
\]

Trong đó:

- \(\lVert\cdot\rVert_F\) là Frobenius norm;
- \(\lambda_2\) kiểm soát độ mạnh của regularization;
- nếu \(\lambda_2\) quá nhỏ, vector latent có thể có độ lớn bất thường;
- nếu \(\lambda_2\) quá lớn, mô hình bị ép quá mạnh và underfit.

## 5. Mở rộng sang nhiều hành vi

### 5.1. Học độc lập từng hành vi

Với mỗi hành vi \(b\), ta học một cặp ma trận riêng:

\[
R^{(b)}
\approx
(U^{(b)})^T V^{(b)}
\]

Ưu điểm:

- mỗi hành vi có mô hình riêng;
- không có nguy cơ truyền sai thông tin trực tiếp.

Nhược điểm:

- không tận dụng dữ liệu từ các hành vi khác;
- mỗi mô hình đều phải chịu sparsity riêng;
- hành vi phụ không thể hỗ trợ hành vi mục tiêu.

### 5.2. Collective Matrix Factorization

Collective Matrix Factorization (CMF) là tiền đề quan trọng của các mô hình
multi-behavior. Bài của Singh và Gordon mô tả cách đồng thời phân rã nhiều
ma trận có thực thể chung bằng cách chia sẻ các latent parameter của thực thể
đó:

- [Relational Learning via Collective Matrix Factorization - bản PDF của Carnegie Mellon](https://www.cs.cmu.edu/~ggordon/CMU-ML-08-109.pdf)
- [DOI ACM của bài CMF](https://doi.org/10.1145/1401890.1401969)

Trong một dạng CMF cho nhiều hành vi, vector đối tượng có thể được chia sẻ:

\[
\widehat{Y}^{(b)}_{ui}
=
(p^{(b)}_u)^T q_i
\]

Trong đó:

- \(q_i\) là vector của đối tượng \(i\), dùng chung cho các hành vi;
- \(p^{(b)}_u\) là vector của người dùng \(u\) khi tái tạo hành vi \(b\);
- mỗi hành vi vẫn có thể tạo ra dự đoán khác nhau vì vector người dùng phụ
  thuộc hành vi.

Một hàm mục tiêu dạng bình phương có trọng số là:

\[
\min_{\{p^{(b)}\},Q}
\sum_{b=1}^{B}
\sum_{u=1}^{n}
\sum_{i=1}^{m}
c^{(b)}_{ui}
\left(
y^{(b)}_{ui}
-
(p^{(b)}_u)^Tq_i
\right)^2
\]

với regularization \(L_2\) được thêm vào để tránh overfitting.

CMF truyền thông tin tốt khi các quan hệ thực sự có liên quan. Tuy nhiên,
trong một số biến thể, việc chia sẻ toàn bộ vector hoặc toàn bộ latent
dimension có thể quá cứng. GSMF giải quyết điểm này bằng cách chọn một tập
dimension khác nhau cho từng hành vi.

### 5.3. Group-Sparse Matrix Factorization

GSMF dùng:

- một ma trận người dùng \(U\) dùng chung;
- một ma trận đối tượng \(V^{(b)}\) riêng cho từng hành vi;
- group sparsity trên từng \(V^{(b)}\).

Với mỗi hành vi:

\[
V^{(b)}\in\mathbb{R}^{k\times m_b}
\]

Vector của đối tượng \(v_j^{(b)}\) là:

\[
v_j^{(b)}=V^{(b)}_{:,j}
\]

Dự đoán:

\[
\widehat{R}^{(b)}_{ij}
=
u_i^T v_j^{(b)}
\]

Điểm quan trọng là cùng một \(u_i\) được dùng khi dự đoán các hành vi khác
nhau, nhưng \(V^{(b)}\) có cấu trúc sparsity riêng. Nhờ đó, mỗi hành vi có
thể dùng một tập latent dimension khác nhau.

## 6. Group sparsity hoạt động như thế nào?

### 6.1. L1 và L1,2

L1 thông thường phạt từng phần tử:

\[
\lVert x\rVert_1=\sum_t |x_t|
\]

L1 thường tạo ra nhiều phần tử bằng 0 riêng lẻ. GSMF cần một hiệu ứng khác:
toàn bộ một dimension latent phải bị tắt cho một hành vi.

Với \(V^{(b)}\in\mathbb{R}^{k\times m_b}\), hàng thứ \(t\) chứa ảnh hưởng của
factor \(t\) lên tất cả đối tượng của hành vi \(b\):

\[
V^{(b)}_{t,:}
\]

GSMF dùng mixed norm:

\[
\lVert V^{(b)}\rVert_{1,2}
=
\sum_{t=1}^{k}
\left\lVert V^{(b)}_{t,:}\right\rVert_2
\]

Nghĩa là:

1. tính L2 norm của từng hàng;
2. cộng các norm của toàn bộ hàng;
3. regularization có xu hướng làm cả hàng nhỏ về gần 0.

Đây là lý do nó được gọi là **group sparsity**: một hàng là một group gồm
toàn bộ trọng số của một latent factor trong một hành vi.

### 6.2. Tập factor được chọn

Đặt ngưỡng nhỏ \(\tau\). Tập latent factor được xem là đang hoạt động với
hành vi \(b\):

\[
S_b=
\left\{
t:
\left\lVert V^{(b)}_{t,:}\right\rVert_2>\tau
\right\}
\]

Với hai hành vi \(a\) và \(b\):

- factor dùng chung:

\[
S_a\cap S_b
\]

- factor riêng của hành vi \(a\):

\[
S_a\setminus S_b
\]

- factor riêng của hành vi \(b\):

\[
S_b\setminus S_a
\]

Với nhiều hơn hai hành vi, một factor có thể được dùng chung cho một nhóm
hành vi nhưng không dùng cho nhóm khác. Vì vậy, GSMF không ép tất cả hành vi
phải có cùng pattern chia sẻ.

### 6.3. Ý nghĩa của việc dùng chung và dùng riêng

Giả sử có ba latent factor:

- factor 1 ảnh hưởng đến hành vi A và B;
- factor 2 chỉ ảnh hưởng đến hành vi B;
- factor 3 chỉ ảnh hưởng đến hành vi A.

Khi đó:

- factor 1 truyền thông tin giữa A và B;
- factor 2 bảo toàn đặc trưng riêng của B;
- factor 3 bảo toàn đặc trưng riêng của A.

Trong cách tiếp cận chia sẻ toàn bộ latent factor, cả ba factor đều có thể
ảnh hưởng đến mọi hành vi. GSMF cho phép regularization loại bỏ những hàng
không cần thiết khỏi từng \(V^{(b)}\).

## 7. Hàm mục tiêu của GSMF

### 7.1. Sai số tái tạo của từng hành vi

Với hành vi \(b\), sai số tái tạo trên các phần tử quan sát là:

\[
f_b(U,V^{(b)})
=
\sum_{i=1}^{n}
\sum_{j=1}^{m_b}
M^{(b)}_{ij}
\left(
R^{(b)}_{ij}
-
u_i^T v_j^{(b)}
\right)^2
\]

Thành phần này yêu cầu điểm dự đoán gần với giá trị đã quan sát.

### 7.2. Hàm mục tiêu đầy đủ

Một cách viết rõ ràng của objective GSMF là:

\[
\begin{aligned}
\mathcal{L}(U,V^{(1)},\ldots,V^{(B)})
=&
\sum_{b=1}^{B}
\alpha_b
\left[
f_b(U,V^{(b)})
+
\lambda_g
\left\lVert V^{(b)}\right\rVert_{1,2}
\right]
\\
&+
\lambda_2
\left[
\left\lVert U\right\rVert_F^2
+
\sum_{b=1}^{B}
\left\lVert V^{(b)}\right\rVert_F^2
\right].
\end{aligned}
\]

Mục tiêu là:

\[
\min_{U,V^{(1)},\ldots,V^{(B)}}
\mathcal{L}
\]

Các thành phần có ý nghĩa:

| Thành phần | Ý nghĩa |
| --- | --- |
| \(f_b\) | Khớp dữ liệu quan sát của hành vi \(b\) |
| \(\alpha_b\) | Trọng số đóng góp của hành vi \(b\) |
| \(\lambda_g\lVert V^{(b)}\rVert_{1,2}\) | Chọn latent dimension theo group |
| \(\lambda_2\lVert\cdot\rVert_F^2\) | Giới hạn độ lớn tham số, giảm overfitting |
| \(k\) | Số chiều latent factor |
| \(M^{(b)}\) | Loại phần tử chưa quan sát khỏi sai số |

Trong bài gốc, các hệ số regularization được ký hiệu theo cách riêng của
tác giả. Công thức trên viết lại cùng ý tưởng với tên \(\lambda_g\) cho group
sparsity và \(\lambda_2\) cho L2 để dễ đọc.

### 7.3. Các trường hợp đặc biệt

#### Khi chỉ có một hành vi

Nếu \(B=1\), mô hình trở về dạng MF có regularization nhóm. Khi không cần
chọn factor theo hành vi, thành phần group sparsity có thể bỏ đi và ta thu
được MF thông thường.

#### Khi không dùng group sparsity

Nếu \(\lambda_g=0\), mọi hành vi có thể sử dụng toàn bộ latent dimension.
Trong trường hợp này, GSMF suy biến về dạng chia sẻ latent factor gần với
CMF trong cách nhìn của bài báo.

#### Khi không chia sẻ người dùng

Nếu thay \(U\) bằng \(U^{(b)}\) riêng cho từng hành vi, mô hình trở nên gần
với independent MF và mất phần truyền thông tin trực tiếp qua user factor.

## 8. Quy trình huấn luyện

GSMF dùng alternating optimization: cố định một nhóm tham số, tối ưu nhóm
còn lại, rồi lặp lại.

### Bước 1: Khởi tạo

Khởi tạo:

- \(U\);
- \(V^{(1)},\ldots,V^{(B)}\);
- trọng số \(\alpha_b\);
- \(k,\lambda_g,\lambda_2\).

Khởi tạo thường dùng giá trị nhỏ ngẫu nhiên. Vì objective không lồi đồng thời
theo \(U\) và \(V\), seed và cách khởi tạo có thể ảnh hưởng đến nghiệm cuối.

### Bước 2: Cố định U, cập nhật V

Khi \(U\) cố định, các \(V^{(b)}\) có thể được cập nhật riêng theo từng hành
vi. Đây là điểm giúp tận dụng tính thưa và tách bài toán theo behavior.

Để xử lý \(\ell_{1,2}\)-norm, bài báo dùng một dạng reweighted update. Với
mỗi hành vi, tạo ma trận đường chéo \(D^{(b)}\), trong đó phần tử ứng với
factor \(t\) tỉ lệ nghịch với norm của hàng đó:

\[
D^{(b)}_{tt}
\approx
\frac{1}{
\left\lVert V^{(b)}_{t,:}\right\rVert_2+\varepsilon
}
\]

\(\varepsilon>0\) là số nhỏ để tránh chia cho 0 trong triển khai số.

Với \(u_i\) cố định, một dạng cập nhật cho vector đối tượng
\(v_j^{(b)}\) là:

\[
\begin{aligned}
v_j^{(b)}
\leftarrow&
\left[
\alpha_b
\sum_{i=1}^{n}
M^{(b)}_{ij}
u_i u_i^T
+
\lambda_2 I
+
\alpha_b\lambda_gD^{(b)}
\right]^{-1}
\\
&\quad
\left[
\alpha_b
\sum_{i=1}^{n}
M^{(b)}_{ij}
R^{(b)}_{ij}u_i
\right].
\end{aligned}
\]

Đây là hệ phương trình \(k\times k\) cho từng đối tượng. Dạng chính xác của
hệ số có thể thay đổi theo quy ước đặt hệ số 2 trong đạo hàm; ý nghĩa không
đổi:

- phần dữ liệu kéo vector về phía các quan sát;
- L2 giữ vector nhỏ;
- \(D^{(b)}\) làm các hàng nhỏ tiếp tục bị phạt mạnh;
- các hàng yếu dần về 0 và bị loại khỏi hành vi tương ứng.

Sau khi cập nhật \(V^{(b)}\), tính lại \(D^{(b)}\) ở vòng lặp kế tiếp. Đây là
ý tưởng **iteratively reweighted** trong thuật toán của bài báo.

### Bước 3: Cố định V, cập nhật U

Khi tất cả \(V^{(b)}\) cố định, vector người dùng \(u_i\) nhận thông tin từ
tất cả hành vi:

\[
\begin{aligned}
u_i
\leftarrow&
\left[
\lambda_2 I
+
\sum_{b=1}^{B}
\alpha_b
\sum_{j=1}^{m_b}
M^{(b)}_{ij}
v_j^{(b)}(v_j^{(b)})^T
\right]^{-1}
\\
&\quad
\left[
\sum_{b=1}^{B}
\alpha_b
\sum_{j=1}^{m_b}
M^{(b)}_{ij}
R^{(b)}_{ij}v_j^{(b)}
\right].
\end{aligned}
\]

Điểm quan trọng:

- \(u_i\) được cập nhật từ dữ liệu của nhiều hành vi;
- các hành vi chia sẻ thông tin thông qua \(U\);
- pattern group sparsity của từng \(V^{(b)}\) quyết định hành vi nào thực sự
  sử dụng dimension nào.

### Bước 4: Lặp đến hội tụ

Quy trình tổng quát:

~~~text
Khởi tạo U và V^(1), ..., V^(B)

Lặp:
    Với mỗi hành vi b:
        Tính D^(b) từ các row norm của V^(b)
        Cập nhật từng vector đối tượng trong V^(b)

    Với mỗi người dùng i:
        Cập nhật u_i từ tất cả hành vi

    Tính objective hoặc validation error
    Dừng nếu objective thay đổi rất nhỏ hoặc đạt số vòng lặp tối đa

Trả về U và V^(1), ..., V^(B)
~~~

### 8.1. Tại sao alternating optimization có thể dùng được?

Objective của MF không lồi khi tối ưu đồng thời \(U\) và \(V\), nhưng khi cố
định một bên thì bài toán theo bên còn lại có dạng dễ xử lý hơn. Alternating
optimization tận dụng đặc điểm này.

Tuy nhiên:

- không có bảo đảm đạt global optimum;
- nghiệm có thể phụ thuộc khởi tạo;
- objective giảm không đồng nghĩa ranking cuối cùng luôn tốt hơn;
- cần đánh giá bằng metric phù hợp với mục tiêu, chẳng hạn RMSE cho rating
  hoặc ranking metric cho implicit feedback.

## 9. Ví dụ số minh họa

Ví dụ sau chỉ nhằm minh họa phép tính latent factor. Các tên factor chỉ là
nhãn dễ hiểu, không phải ý nghĩa mà mô hình tự biết.

### 9.1. Thiết lập

Có:

- một người dùng \(u\);
- hai loại hành vi: rating và favorite;
- ba latent factor;
- hai đối tượng \(A\) và \(B\) trong mỗi hành vi.

Vector người dùng dùng chung:

\[
u=
\begin{bmatrix}
1.0\\
0.5\\
0.8
\end{bmatrix}
\]

Giả sử ba chiều được minh họa lần lượt là:

1. sở thích chung;
2. tín hiệu riêng cho favorite;
3. tín hiệu riêng cho rating.

Đây chỉ là cách đặt tên phục vụ ví dụ.

### 9.2. Ma trận đối tượng của hành vi rating

\[
V^{(rating)}
=
\begin{bmatrix}
0.8 & 0.6\\
0.0 & 0.0\\
0.4 & 0.5
\end{bmatrix}
\]

Cột 1 là vector của \(A\), cột 2 là vector của \(B\):

\[
v_A^{(rating)}
=
\begin{bmatrix}
0.8\\
0.0\\
0.4
\end{bmatrix},
\quad
v_B^{(rating)}
=
\begin{bmatrix}
0.6\\
0.0\\
0.5
\end{bmatrix}
\]

Hàng thứ hai bằng 0, nên factor 2 không được dùng cho hành vi rating.

Điểm của \(A\):

\[
\begin{aligned}
\widehat{r}^{(rating)}_{u,A}
&=
u^T v_A^{(rating)}\\
&=
(1.0)(0.8)+(0.5)(0.0)+(0.8)(0.4)\\
&=1.12.
\end{aligned}
\]

Điểm của \(B\):

\[
\begin{aligned}
\widehat{r}^{(rating)}_{u,B}
&=
(1.0)(0.6)+(0.5)(0.0)+(0.8)(0.5)\\
&=1.00.
\end{aligned}
\]

Theo hành vi rating, đối tượng \(A\) được xếp trên \(B\).

### 9.3. Ma trận đối tượng của hành vi favorite

\[
V^{(favorite)}
=
\begin{bmatrix}
0.7 & 0.5\\
0.3 & 0.2\\
0.0 & 0.0
\end{bmatrix}
\]

Ở hành vi này, hàng thứ ba bằng 0. Factor 3 không được dùng cho favorite.

Điểm của \(A\):

\[
\begin{aligned}
\widehat{r}^{(favorite)}_{u,A}
&=
(1.0)(0.7)+(0.5)(0.3)+(0.8)(0.0)\\
&=0.85.
\end{aligned}
\]

Điểm của \(B\):

\[
\begin{aligned}
\widehat{r}^{(favorite)}_{u,B}
&=
(1.0)(0.5)+(0.5)(0.2)+(0.8)(0.0)\\
&=0.60.
\end{aligned}
\]

Theo hành vi favorite, \(A\) cũng được xếp trên \(B\), nhưng cơ chế tạo
điểm khác hành vi rating.

### 9.4. Xác định factor chung và riêng

Từ hai ma trận:

\[
S_{rating}=\{1,3\}
\]

\[
S_{favorite}=\{1,2\}
\]

Suy ra:

- factor chung:

\[
S_{rating}\cap S_{favorite}=\{1\}
\]

- factor riêng của rating: \(\{3\}\);
- factor riêng của favorite: \(\{2\}\).

Đây chính là điều GSMF muốn học tự động:

- factor 1 truyền tín hiệu chung;
- factor 2 không làm nhiễu dự đoán rating;
- factor 3 không làm nhiễu dự đoán favorite.

### 9.5. Ví dụ về mặt nạ dữ liệu

Giả sử quan sát của người dùng là:

\[
R^{(rating)}_{u,A}=4
\]

và không có quan sát cho \(B\). Khi đó:

\[
M^{(rating)}_{u,A}=1,
\quad
M^{(rating)}_{u,B}=0.
\]

Sai số của \(A\) được tính:

\[
\left(4-\widehat{r}^{(rating)}_{u,A}\right)^2.
\]

Sai số của \(B\) không được tính vì \(M=0\), dù phần tử thiếu có thể được lưu
trong ma trận dưới dạng 0.

Nếu một hành vi nhị phân có quan sát hợp lệ bằng 0, ví dụ:

\[
R^{(favorite)}_{u,A}=0,
\]

thì:

\[
M^{(favorite)}_{u,A}=1.
\]

Điều này khác hoàn toàn với trường hợp không có bản ghi:

\[
R^{(favorite)}_{u,A}=\text{missing},
\quad
M^{(favorite)}_{u,A}=0.
\]

## 10. MBMF cho implicit feedback và BPR

GSMF dùng sai số bình phương trên các ma trận rating hoặc giá trị nhị phân
được xem như rating. Đó là một lựa chọn hợp lý cho bài toán tái tạo giá trị,
nhưng không phải lúc nào cũng phù hợp nhất cho top-N ranking.

Với implicit feedback, một cách tiếp cận khác là Bayesian Personalized
Ranking (BPR). BPR không cố dự đoán giá trị tuyệt đối; nó yêu cầu một đối
tượng tích cực \(i\) được xếp cao hơn đối tượng âm \(j\):

\[
\widehat{r}_{ui}>\widehat{r}_{uj}
\]

Đặt:

\[
x_{uij}
=
\widehat{r}_{ui}-\widehat{r}_{uj}.
\]

Hàm mất mát BPR:

\[
\mathcal{L}_{BPR}
=
-\sum_{(u,i,j)}
\log
\sigma(x_{uij})
+
\lambda\lVert\Theta\rVert^2
\]

trong đó:

- \(i\) là item tích cực;
- \(j\) là item âm hoặc chưa quan sát;
- \(\sigma\) là sigmoid;
- \(\Theta\) là tập tham số.

Với nhiều hành vi, có thể dùng:

\[
\mathcal{L}_{MB-BPR}
=
\sum_{b=1}^{B}
\alpha_b
\mathcal{L}^{(b)}_{BPR}.
\]

Trong đó mỗi hành vi có tập cặp \((u,i,j)\) và trọng số riêng.

Điểm cần phân biệt:

- đây là một mở rộng theo hướng ranking;
- nó không phải đúng objective squared-error của GSMF;
- BPR phù hợp hơn khi mục tiêu là thứ tự top-N thay vì dự đoán điểm rating;
- cách chọn item âm ảnh hưởng mạnh đến kết quả.

Nguồn gốc của BPR:

- [BPR: Bayesian Personalized Ranking from Implicit Feedback](https://www.cs.mcgill.ca/~uai2009/papers/UAI2009_0139_48141db02b9f0b02bc7158819ebfa2c7.pdf)

## 11. So sánh các cách mô hình hóa

| Mô hình | Có nhiều hành vi | Chia sẻ thông tin | Giữ factor riêng | Cơ chế chính |
| --- | ---: | --- | --- | --- |
| Independent MF | Có | Không | Có | Mỗi hành vi có \(U^{(b)},V^{(b)}\) riêng |
| CMF | Có | Có | Tùy biến thể | Tied latent factors giữa các quan hệ |
| GSMF | Có | Có chọn lọc | Có | Shared \(U\), group sparsity trên \(V^{(b)}\) |
| Multi-behavior BPR | Có | Có qua objective | Có thể có | Tối ưu cặp thứ tự giữa item |
| Neural multi-task | Có | Có | Có thể có | Shared representation và behavior head |

Neural multi-task không phải MBMF cổ điển, nhưng thường được xây dựng dựa
trên cùng vấn đề: nhiều ma trận hành vi và một mục tiêu recommendation.

Một bài báo sau này, **Learning to Recommend With Multiple Cascading
Behaviors**, mô tả CMF là một hướng tiền nhiệm và chỉ ra một số giới hạn của
việc dùng tích vô hướng cố định cùng squared regression cho implicit feedback.
Bài này chuyển sang neural multi-task và NCF, nên được xem là hướng mở rộng,
không phải công thức GSMF:

- [Learning to Recommend With Multiple Cascading Behaviors - PDF](https://fi.ee.tsinghua.edu.cn/~gaochen/papers/TKDE2019-NMTR.pdf)

## 12. Vai trò của từng thành phần trong công thức

### 12.1. Latent dimension \(k\)

\(k\) quyết định dung lượng biểu diễn:

- \(k\) nhỏ: mô hình nhanh, ít tham số, nhưng có thể underfit;
- \(k\) lớn: biểu diễn linh hoạt hơn, nhưng dễ overfit và tốn bộ nhớ;
- group sparsity có thể làm một số dimension không còn được dùng ở từng hành
  vi, nhưng không thay thế hoàn toàn việc chọn \(k\).

### 12.2. Trọng số \(\alpha_b\)

\(\alpha_b\) điều chỉnh mức ảnh hưởng của hành vi:

- hành vi nhiều dữ liệu có thể lấn át hành vi thưa;
- hành vi phụ quá nhiễu không nên có trọng số quá lớn;
- hành vi mục tiêu thường cần được ưu tiên nếu mô hình phục vụ ranking mục
  tiêu.

### 12.3. Group sparsity \(\lambda_g\)

- \(\lambda_g\) nhỏ: nhiều factor được giữ lại, chia sẻ rộng hơn;
- \(\lambda_g\) vừa phải: có thể tách được shared/private factor;
- \(\lambda_g\) quá lớn: nhiều factor bị tắt, gây underfit;
- khi \(\lambda_g=0\), mô hình không còn chọn dimension theo behavior.

### 12.4. L2 regularization \(\lambda_2\)

L2 giúp:

- kiểm soát độ lớn của vector latent;
- giảm nghiệm quá lớn do tích \(u_i^T v_j\);
- ổn định việc tối ưu;
- giảm overfitting.

### 12.5. Mặt nạ \(M^{(b)}\)

Mặt nạ xác định dữ liệu nào được phép đóng góp vào objective. Nếu không có
mặt nạ, mọi phần tử thiếu sẽ bị coi như một nhãn 0 và mô hình sẽ học sai rằng
"không quan sát" đồng nghĩa với "không thích".

## 13. Ưu điểm

### 13.1. Giảm ảnh hưởng của sparsity

Một hành vi có ít dữ liệu có thể nhận thông tin từ các hành vi khác thông qua
user latent factor chung. Điều này hữu ích khi hành vi mục tiêu hiếm.

### 13.2. Truyền thông tin có chọn lọc

GSMF không buộc mọi behavior dùng chung mọi dimension. Group sparsity cho
phép chỉ truyền những phần có khả năng liên quan.

### 13.3. Mô hình hóa được shared và private factor

Đây là ưu điểm lý thuyết quan trọng nhất:

- phần chung biểu diễn sự phụ thuộc giữa hành vi;
- phần riêng biểu diễn tính dị biệt;
- hai loại thông tin không bị trộn hoàn toàn.

### 13.4. Có thể dùng cho giá trị thực và nhị phân

Ma trận hành vi có thể biểu diễn:

- rating thực;
- quan hệ nhị phân;
- giá trị đã được chuẩn hóa hoặc biến đổi về dạng số thực.

Tuy nhiên, hàm mất mát và link function phải được chọn phù hợp với loại dữ
liệu.

### 13.5. Tận dụng cấu trúc thưa

Objective chỉ tính trên các phần tử quan sát. Với dữ liệu sparse, việc lưu và
cập nhật theo non-zero interaction giúp giảm chi phí so với xử lý toàn bộ ma
trận đặc.

## 14. Nhược điểm và giới hạn

### 14.1. Objective không lồi đồng thời

Việc nhân hai ma trận latent làm bài toán không lồi khi tối ưu tất cả tham số
cùng lúc. Alternating optimization thường chỉ tìm được một nghiệm cục bộ.

### 14.2. Phụ thuộc vào hyperparameter

Kết quả phụ thuộc vào:

- số chiều \(k\);
- \(\alpha_b\);
- \(\lambda_g\);
- \(\lambda_2\);
- seed và khởi tạo;
- ngưỡng xác định một row đã bị triệt tiêu.

### 14.3. Có thể vẫn xảy ra negative transfer

Group sparsity làm giảm truyền sai thông tin nhưng không loại bỏ hoàn toàn
nguy cơ đó. Nếu các hành vi có quan hệ yếu hoặc mang semantics xung đột,
việc chia sẻ user factor vẫn có thể gây hại.

### 14.4. Latent factor khó diễn giải tuyệt đối

Một dimension có thể là tổ hợp của nhiều đặc điểm ẩn. Việc một row nhỏ hoặc
lớn không đủ để kết luận chính xác factor đó đại diện cho một khái niệm đời
thực cụ thể.

### 14.5. Missing không phải negative

Trong dữ liệu implicit, không quan sát được một hành vi không có nghĩa người
dùng không thích đối tượng. Nếu tạo negative sample không cẩn thận, mô hình
có thể học sai.

### 14.6. Squared loss chưa chắc tối ưu cho top-N

Tối ưu RMSE có thể không tối ưu thứ tự top-N. Với implicit recommendation,
BPR, logistic loss hoặc một objective ranking có thể phù hợp hơn.

### 14.7. Khác thang đo giữa các hành vi

Rating 1--5, click 0/1 và count không thể luôn cộng hoặc so sánh trực tiếp.
Nếu không chuẩn hóa hoặc điều chỉnh \(\alpha_b\), objective có thể bị behavior
có độ lớn số học lớn chi phối.

### 14.8. Chi phí tăng theo số hành vi

Mỗi hành vi có thêm ma trận latent \(V^{(b)}\), mask và các bước cập nhật. Khi
số behavior lớn, chi phí bộ nhớ và thời gian tăng đáng kể.

### 14.9. Không tự giải quyết cold-start hoàn toàn

Nếu người dùng hoặc đối tượng hoàn toàn mới và không có tương tác hay side
information, MF không có đủ dữ liệu để suy ra vector latent đáng tin cậy.

## 15. Khi nào nên dùng MBMF?

MBMF phù hợp khi:

- có nhiều loại tương tác giữa cùng nhóm người dùng và đối tượng;
- các hành vi có khả năng liên quan nhưng không đồng nhất;
- một hoặc vài hành vi mục tiêu khá thưa;
- muốn tận dụng auxiliary behavior;
- chấp nhận mô hình latent khó giải thích hoàn toàn;
- có đủ dữ liệu để ước lượng tương quan giữa các hành vi.

MBMF không phải lựa chọn mặc định tốt khi:

- chỉ có một hành vi;
- các hành vi không liên quan;
- dữ liệu quá ít ở tất cả các behavior;
- mục tiêu chỉ là dự đoán giá trị tuyệt đối và không cần truyền thông tin;
- cần mô hình có giải thích trực tiếp theo feature quan sát được.

## 16. Cách đọc một mô hình MBMF trên giấy

Khi đọc một bài báo hoặc công thức MBMF, nên kiểm tra lần lượt:

1. Có bao nhiêu ma trận hành vi?
2. Ma trận nào là target behavior?
3. Hành vi được xem là explicit hay implicit?
4. Phần tử thiếu có được mask hay bị coi là 0?
5. User factor nào được chia sẻ?
6. Item factor nào được chia sẻ?
7. Có behavior-specific factor hay offset không?
8. Objective dùng squared loss, logistic loss hay pairwise ranking?
9. Các behavior có trọng số khác nhau không?
10. Cơ chế chống negative transfer là gì?
11. Regularization tạo sparsity ở element, row, column hay group nào?
12. Metric đánh giá có phù hợp với objective hay không?

## 17. Tóm tắt thuật toán bằng một luồng

\[
\boxed{
\text{Nhiều ma trận hành vi}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Tạo mask và chuẩn hóa thang đo}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Ánh xạ user/item vào latent space}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Dùng shared factor để truyền thông tin}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Dùng group sparsity để chọn factor theo behavior}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Tối ưu luân phiên các latent factor}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Tính điểm và xếp hạng theo behavior}
}
\]

Nói ngắn gọn:

> MBMF không chỉ phân rã một ma trận thành user factor và item factor. Nó
> phân rã nhiều ma trận có liên hệ, quyết định phần nào được chia sẻ, phần nào
> phải giữ riêng, rồi dùng các biểu diễn latent đó để dự đoán tương tác chưa
> quan sát.

## 18. Kết luận

MBMF mở rộng Matrix Factorization từ một hành vi sang nhiều hành vi bằng cách
học đồng thời nhiều ma trận tương tác. Ý tưởng cốt lõi gồm ba lớp:

1. **Low-rank representation**: người dùng và đối tượng được biểu diễn trong
   không gian latent có số chiều thấp.
2. **Information sharing**: các behavior truyền thông tin qua latent factor
   chung.
3. **Behavior-specific selection**: group sparsity chọn những factor được
   phép hoạt động ở từng behavior, giúp giữ lại phần riêng.

Mô hình GSMF trong bài Yuan và cộng sự là một ví dụ rõ ràng của hướng này:

- MF cơ bản cung cấp công thức tích vô hướng;
- CMF cung cấp ý tưởng phân rã nhiều quan hệ và chia sẻ tham số;
- group sparsity giúp việc chia sẻ trở nên có chọn lọc;
- alternating optimization cung cấp cách giải thực tế cho objective.

Khi áp dụng MBMF cho dữ liệu implicit hoặc mục tiêu top-N, cần cân nhắc thay
squared loss bằng logistic hoặc pairwise ranking objective như BPR. Không có
một biến thể duy nhất luôn tốt nhất; lựa chọn phụ thuộc vào loại feedback,
mức độ liên quan giữa các behavior và mục tiêu đánh giá.

## 19. Tài liệu tham khảo

1. Ting Yuan, Jian Cheng, Xi Zhang, Shuang Qiu, Hanqing Lu. **Recommendation
   by Mining Multiple User Behaviors with Group Sparsity**. Proceedings of the
   Twenty-Eighth AAAI Conference on Artificial Intelligence, 2014,
   pp. 222--228.
   - [PDF chính thức AAAI](https://ojs.aaai.org/index.php/AAAI/article/download/8713/8572)
   - [DOI](https://doi.org/10.1609/aaai.v28i1.8713)

2. Ajit P. Singh, Geoffrey J. Gordon. **Relational Learning via Collective
   Matrix Factorization**. Proceedings of the 14th ACM SIGKDD International
   Conference on Knowledge Discovery and Data Mining, 2008, pp. 650--658.
   - [Bản PDF của Carnegie Mellon](https://www.cs.cmu.edu/~ggordon/CMU-ML-08-109.pdf)
   - [DOI ACM](https://doi.org/10.1145/1401890.1401969)

3. Steffen Rendle, Christoph Freudenthaler, Zeno Gantner, Lars
   Schmidt-Thieme. **BPR: Bayesian Personalized Ranking from Implicit
   Feedback**. Proceedings of the 25th Conference on Uncertainty in Artificial
   Intelligence, 2009, pp. 452--461.
   - [PDF bài báo](https://www.cs.mcgill.ca/~uai2009/papers/UAI2009_0139_48141db02b9f0b02bc7158819ebfa2c7.pdf)

4. Chen Gao et al. **Learning to Recommend With Multiple Cascading Behaviors**.
   IEEE Transactions on Knowledge and Data Engineering, 2021.
   - [Bản PDF tác giả](https://fi.ee.tsinghua.edu.cn/~gaochen/papers/TKDE2019-NMTR.pdf)

### Ghi chú về bản dịch

Tài liệu này là bản diễn giải và dịch thuật ngữ sang tiếng Việt dựa trên các
bài báo ở trên. Công thức được chuẩn hóa ký hiệu cho dễ đọc; khi triển khai
hoặc trích dẫn học thuật, nên đối chiếu lại công thức, giả thiết và quy ước
notation trong bản PDF gốc.
