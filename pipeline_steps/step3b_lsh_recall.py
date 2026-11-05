#!/usr/bin/env python3
"""BƯỚC 3b — Đo LSH bỏ sót bao nhiêu cặp so với so-mọi-cặp, theo cỡ thư viện.

Đây là phép đo cho vấn đề "thư viện càng lớn càng thất thoát". Lấy mẫu con
ngẫu nhiên các cỡ --sizes, với mỗi cỡ tính recall của LSH ở vài ngưỡng Hamming.
Chuẩn so sánh là chính kết quả so-mọi-cặp của PDQ (không phải nhãn thật của người dùng).
Vào : out/2_pdq.csv
Ra  : in bảng; ghi out/3b_lsh_recall.csv
"""
import random
from pathlib import Path

from common import base_parser, ensure_index, exact_pairs, load_pdq, lsh_pairs, write_csv

THRESHOLDS = (15, 32, 50, 70)


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--sizes", default="500,1000,2000,4000", help="các cỡ mẫu, ngăn bằng dấu phẩy")
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    packed, valid = load_pdq(out, len(photos))
    ids = [i for i in range(len(photos)) if valid[i]]
    sizes = sorted({min(int(s), len(ids)) for s in a.sizes.split(",")} | {len(ids)})
    rnd = random.Random(a.seed)
    rows = []
    print(f"{'n':>7} {'Hamming<=':>10} {'exact':>8} {'LSH':>8} {'recall':>8}")
    for n in sizes:
        pick = sorted(rnd.sample(ids, n))
        p, v = packed[pick], valid[pick]
        ex = exact_pairs(p, v, max(THRESHOLDS))
        ls = lsh_pairs(p, v, max(THRESHOLDS))
        for t in THRESHOLDS:
            e = {(i, j) for i, j, d in ex if d <= t}
            l = {(i, j) for i, j, d in ls if d <= t}
            rec = (len(e & l) / len(e)) if e else float("nan")
            rows.append([n, t, len(e), len(l & e), f"{rec:.4f}"])
            print(f"{n:>7} {t:>10} {len(e):>8} {len(l & e):>8} {rec:>8.1%}")
    write_csv(out / "3b_lsh_recall.csv", ["n", "hamming_max", "exact_pairs", "lsh_found", "recall"], rows)
    print("Ghi chú: mẫu con làm giảm mật độ cặp trùng; hãy chạy trên chính thư viện thật để có số có ý nghĩa.")


if __name__ == "__main__":
    main()
