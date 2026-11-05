#!/usr/bin/env python3
"""BƯỚC 3 — So Hamming giữa các PDQ hash (không dùng model).

--mode exact : so MỌI cặp, không sót (app làm vậy khi thư viện nhỏ).
--mode lsh   : LSH 16 band x 16 bit (app dùng khi thư viện lớn), có thể sót cặp.
Vào : out/2_pdq.csv
Ra  : out/3_pairs_<mode>.csv (a, b, hamming, similarity_pct) với Hamming <= --max (mặc định 70)
Mốc : Hamming <= 32 là "Trùng", 33..70 là "Tương tự" (chỉ xem).
"""
from pathlib import Path

from common import (MAX_HAMMING, SIMILAR_MAX_HAMMING, base_parser, ensure_index, exact_pairs,
                    load_pdq, lsh_pairs, sim_pct, write_csv)


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--mode", choices=["exact", "lsh"], default="exact")
    ap.add_argument("--max", type=int, default=SIMILAR_MAX_HAMMING, help="Hamming tối đa lưu lại")
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    packed, valid = load_pdq(out, len(photos))
    pairs = exact_pairs(packed, valid, a.max) if a.mode == "exact" else lsh_pairs(packed, valid, a.max)
    pairs.sort()
    f = out / f"3_pairs_{a.mode}.csv"
    write_csv(f, ["a", "b", "hamming", "similarity_pct"],
              [[i, j, d, f"{sim_pct(d):.1f}"] for i, j, d in pairs])
    dup = sum(1 for _, _, d in pairs if d <= MAX_HAMMING)
    print(f"[{a.mode}] {len(pairs)} cặp Hamming <= {a.max} "
          f"({dup} cặp <= {MAX_HAMMING} = 'Trùng', {len(pairs) - dup} cặp 'Tương tự') -> {f}")


if __name__ == "__main__":
    main()
