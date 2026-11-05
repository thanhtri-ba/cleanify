#!/usr/bin/env python3
"""BƯỚC 2 — PDQ-style hash 256 bit cho từng ảnh (không dùng model).

Thumbnail 128px -> xám 64x64 -> DCT lấy 16x16 hệ số thấp -> so median -> 256 bit.
Vào : thư mục ảnh (--src)
Ra  : out/2_pdq.csv (idx, pdq hex 64 ký tự; rỗng nếu ảnh lỗi)
"""
from multiprocessing import Pool
from pathlib import Path

from common import PDQ_THUMB, base_parser, bits_to_hex, ensure_index, fit_jpeg, load_rgb, pdq_bits, write_csv


def work(args):
    idx, path = args
    try:
        b = pdq_bits(fit_jpeg(load_rgb(Path(path)), PDQ_THUMB))
        return idx, (bits_to_hex(b) if b is not None else "")
    except Exception:
        return idx, ""


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    jobs = [(p["idx"], str(src / p["path"])) for p in photos]
    with Pool(a.workers) as pool:
        res = sorted(pool.imap_unordered(work, jobs, chunksize=16))
    write_csv(out / "2_pdq.csv", ["idx", "pdq"], [[i, h] for i, h in res])
    bad = sum(1 for _, h in res if not h)
    print(f"{len(res)} ảnh đã băm PDQ, {bad} ảnh lỗi -> {out / '2_pdq.csv'}")


if __name__ == "__main__":
    main()
