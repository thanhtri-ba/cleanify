#!/usr/bin/env bash
# Chạy lần lượt các bước. Dùng: ./run_all.sh <thư_mục_ảnh> [thư_mục_out]
# Bước 6 (ORB) chỉ chạy khi đặt ORB=1 (cần opencv-python).
set -euo pipefail
SRC="${1:?cần thư mục ảnh}"; OUT="${2:-out}"
cd "$(dirname "$0")"
python3 step1_sha256.py  --src "$SRC" --out "$OUT"
python3 step2_pdq.py     --src "$SRC" --out "$OUT"
python3 step3_hamming.py --src "$SRC" --out "$OUT"
python3 step4_embed.py   --src "$SRC" --out "$OUT"
python3 step5_cosine.py  --src "$SRC" --out "$OUT" --exclude-dups
if [ "${ORB:-0}" = "1" ]; then python3 step6_orb.py --src "$SRC" --out "$OUT"; fi
python3 step7_merge.py   --src "$SRC" --out "$OUT"
