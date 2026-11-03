# Calibrate ngưỡng Cleanify bằng ảnh thật (VS Code)

Mục tiêu: chọn 7 ngưỡng cố định cho 3 tab (Trùng, Tương tự, Người) từ ảnh của bạn.
Ảnh và kết quả chỉ nằm trên máy (`eval_real/`, `eval_out/` đã có trong `.gitignore`).

## Chuẩn bị (một lần)
1. Mở thư mục `cleanify` trong VS Code, cài extension **Python**.
2. Chọn interpreter: `Cmd+Shift+P` → *Python: Select Interpreter* → `.venv/bin/python`
   (`.vscode/settings.json` đã trỏ sẵn). Thiếu gói thì: `pip install -r requirements-eval.txt`.
3. Xuất 300–600 ảnh **gốc** từ ứng dụng Ảnh vào `eval_real/` (JPEG "Tương thích nhất",
   hoặc `pip install pillow-heif` để đọc HEIC). Ưu tiên ảnh chụp liên tiếp, cùng địa điểm,
   có người, và ảnh gửi qua ứng dụng nhắn tin.

## Chạy (Run and Debug → chọn cấu hình)
| Bước | Cấu hình | Ra |
|---|---|---|
| 1 | Eval 1: sinh cặp ứng viên | `eval_out/candidates.csv`, `scenes.csv`, `variants/` |
| 2 | Eval 2: gán nhãn | `eval_out/manifest.csv` (mở http://127.0.0.1:8765, phím 1–5, 0 bỏ qua, z hoàn tác) |
| 3 | Eval 3: tính điểm | `eval_out/scores.csv`, `thumbs128/` |
| 4 | Eval 4: calibrate | `eval_out/thresholds.json`, `report.md`, `pr_*.png` |

Nếu cửa sổ 30 phút gộp quá ít cảnh, thêm `--window-min 10` vào cấu hình Eval 1.

## (Tùy chọn) PDQ khớp từng bit với app
```
dart run tool/dump_pdq.dart eval_out/thumbs128 eval_out/pdq_dart.csv
```
rồi chạy cấu hình **Eval 3b**. Script in ra độ lệch giữa bản port Python và code Dart.

## Đọc kết quả
- `report.md` ghi từng ngưỡng cùng precision, cận dưới và recall trên tập train và test.
- Ngưỡng "không đạt" nghĩa là dữ liệu chưa đủ hoặc hai phân phối điểm chồng nhau.
  Với mục tiêu precision 99% cần khoảng 300 cặp dương không lỗi; 95% cần khoảng 60.
- Chỉ đổi `ScanConfig` sau khi tập **test** xác nhận ngưỡng chọn trên tập train.
