# pipeline_steps — chạy từng bước của mô hình Cleanify

Mỗi bước là một script độc lập, đọc file của bước trước trong `out/` và ghi file của mình.
Chạy được từng bước, xem kết quả, đổi ngưỡng rồi chạy lại bước sau. Không sửa code app.
Cần: `numpy`, `pillow`; bước 4 cần `onnxruntime`; bước 6 cần `opencv-python`.

## Chạy
```bash
cd pipeline_steps
python3 make_sample.py --dst sample_photos          # (tùy chọn) ảnh thử tổng hợp
SRC=sample_photos   # hoặc thư mục ảnh thật đã xuất từ iPhone

python3 step1_sha256.py  --src $SRC     # 1. SHA-256: trùng tuyệt đối
python3 step2_pdq.py     --src $SRC     # 2. PDQ hash 256 bit
python3 step3_hamming.py --src $SRC     # 3. Hamming mọi cặp  (--mode lsh để thử LSH)
python3 step3b_lsh_recall.py --src $SRC # 3b. LSH sót bao nhiêu so với mọi cặp
python3 step4_embed.py   --src $SRC     # 4. MobileNetV3 (CNN) -> vector 960 chiều
python3 step5_cosine.py  --src $SRC --exclude-dups   # 5. cosine, top-k, mutual
python3 step6_orb.py     --src $SRC     # 6. (tùy chọn) ORB + RANSAC
python3 step7_merge.py   --src $SRC     # 7. gộp nhóm -> out/7_groups.csv, out/7_report.html
```
Hoặc chạy hết: `./run_all.sh $SRC` (thêm `ORB=1` để chạy bước 6).
Đổi bộ ảnh thì xóa thư mục `out/` rồi chạy lại từ bước 1.

## Bước nào dùng model gì
| Bước | Kỹ thuật | Có CNN? | Độ đo | Ngưỡng mặc định (giống `ScanConfig`) |
|---|---|---|---|---|
| 1 | SHA-256 | không | bằng nhau từng byte | — |
| 2–3 | PDQ + Hamming | không | Hamming trên 256 bit | `--max` 70; <= 32 là "Trùng" |
| 3b | LSH vs mọi cặp | không | recall | — |
| 4–5 | MobileNetV3-Large | có | cosine sau khi trừ trung bình | k=3, `--floor` 0.55, mutual |
| 6 | ORB + RANSAC | không | số inlier | `--min-inliers` 45 (ở bước 7) |
| 7 | gộp thác nước | — | — | `--max-hamming` 32, `--similar-max` 70 |

Ngưỡng ở `common.py` hoặc tham số dòng lệnh. Các ngưỡng 0.55 và 45 CHƯA calibrate (xem `tool/EVAL.md`).

## Lưu ý
- Thumbnail ở đây mô phỏng bằng Pillow nên điểm không khớp từng bit với app (xem `tool/eval_common.py`).
- Bước 5 cần ít nhất 32 vector còn lại, giống app; với `--exclude-dups` mẫu nhỏ có thể không đủ.
- Bước 3b chỉ so LSH với so-mọi-cặp của PDQ, không phải nhãn thật. Cỡ thư viện càng gần thực tế càng có ý nghĩa.
- Nhóm giữ ảnh đại diện (dung lượng lớn nhất) và chỉ ảnh có cạnh trực tiếp với nó, nên ảnh trong chuỗi A~B~C có thể bị loại khỏi nhóm.

## Colab: so sánh mô hình A (hiện tại) và B (đề xuất)
`colab/cleanify_experiment.ipynb` — mở trên Google Colab, Runtime → Run all.
Sinh ảnh biến thể có nhãn, đo thất thoát ở khâu tìm ứng viên, rồi so A và B trên cùng tập test.
Sửa nội dung ở `colab/experiment_src.py` rồi chạy `python3 colab/build_notebook.py` để dựng lại file .ipynb.
