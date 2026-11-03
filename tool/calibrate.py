#!/usr/bin/env python3
"""Chọn ngưỡng cho 3 tab của Cleanify từ cặp ảnh đã gán nhãn + điểm đã tính.

Đọc  : <out>/manifest.csv (nhãn, split) và <out>/scores.csv (từ score_pairs.py)
Ghi  : <out>/thresholds.json, <out>/report.md, <out>/pr_*.png (nếu có matplotlib)

Nguyên tắc: chọn ngưỡng DỄ DÃI nhất mà cận dưới (một phía) của precision vẫn đạt
mục tiêu. Chọn trên tập train; báo kết quả trên tập test (chia theo cảnh).

  Trùng    : dương = dup;                 âm = mọi nhãn còn lại
             -> certainHamming, maxHamming, verifyThreshold
  Tương tự : dương = similar|similar_person; âm = different|person_only (bỏ cặp dup)
             -> similarHigh, similarLow
  Người    : dương = similar_person|person_only; âm = different|similar (bỏ cặp dup)
             -> personHigh, personLow

Ví dụ: python tool/calibrate.py --out eval_out
"""
import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_common as ec  # noqa: E402

POS = {"dup": {"dup"}, "similar": {"similar", "similar_person"}, "person": {"similar_person", "person_only"}}
NEG = {"similar": {"different", "person_only"}, "person": {"different", "similar"}}
DUP_NEG = {"similar", "similar_person", "person_only", "different"}


def col(rows, k):
    return np.array([float(r[k]) if r.get(k) not in (None, "") else np.nan for r in rows], dtype=np.float64)


def split_rows(rows):
    tr = [r for r in rows if r.get("split") != "test"]
    te = [r for r in rows if r.get("split") == "test"]
    return tr, te


def labels(rows, pos):
    return np.array([1 if r["label"] in pos else 0 for r in rows], dtype=int)


def fmt(m, alpha):
    if not m or m["n_pred"] == 0:
        return "—"
    lb = ec.precision_lower_bound(m["tp"], m["n_pred"], alpha)
    r = "—" if m["recall"] is None else f"{100 * m['recall']:.0f}%"
    return f"n={m['n_pred']}, tp={m['tp']}, P={100 * m['precision']:.1f}% (cận dưới {100 * lb:.1f}%), R={r}"


def calib_dup(rows, a):
    sel = [r for r in rows if r["label"] in DUP_NEG | {"dup"}]
    tr, te = split_rows(sel)
    res = {"pairs_train": len(tr), "pairs_test": len(te),
           "pos_train": int(labels(tr, POS["dup"]).sum()), "pos_test": int(labels(te, POS["dup"]).sum())}
    h, c, y = col(tr, "hamming"), col(tr, "cos_dino"), labels(tr, POS["dup"])
    ok = ~np.isnan(h)
    certain = ec.select_threshold(h[ok], y[ok], a.dup_target, match_if_ge=False, alpha=a.alpha) if ok.any() else None
    res["certainHamming"] = None if certain is None else int(np.floor(certain))
    res["maxHamming"] = res["certainHamming"]
    res["verifyThreshold"] = None
    if res["certainHamming"] is None:
        res["note"] = "Không có ngưỡng Hamming nào đạt mục tiêu precision (ít dữ liệu hoặc phân phối chồng nhau)."
        return res
    cert = res["certainHamming"]
    # Tìm (maxHamming, verifyThreshold): cặp trong (cert, max] chỉ nhận nếu cosine DINO >= verify.
    okc = ok & ~np.isnan(c)
    if okc.sum() >= 2:
        grid = np.unique(np.quantile(c[okc], np.linspace(0, 1, 101)))
        best = None
        for v in grid:
            for H in range(cert + 1, 71):  # 70 = similarMaxHamming của app
                pred = (h <= cert) | ((h <= H) & (c >= v))
                pred &= ok
                n, tp = int(pred.sum()), int(y[pred].sum())
                if ec.precision_lower_bound(tp, n, a.alpha) >= a.dup_target:
                    key = (tp, v, -H)
                    if best is None or key > best[0]:
                        best = (key, H, float(v))
        if best and best[0][0] > int(y[(h <= cert) & ok].sum()):
            res["maxHamming"], res["verifyThreshold"] = best[1], round(best[2], 4)
    # Đánh giá
    for tag, rr in (("train", tr), ("test", te)):
        if not rr:
            res[tag] = None
            continue
        hh, cc, yy = col(rr, "hamming"), col(rr, "cos_dino"), labels(rr, POS["dup"])
        k = ~np.isnan(hh)
        sure = (hh <= cert) & k
        res[tag] = {"certain_only": ec.evaluate(sure, yy)}
        if res["verifyThreshold"] is not None:
            both = sure | ((hh <= res["maxHamming"]) & (cc >= res["verifyThreshold"]) & k)
            res[tag]["with_verify"] = ec.evaluate(both, yy)
    return res


def calib_cos(name, feat, rows, a):
    pos, neg = POS[name], NEG[name]
    sel = [r for r in rows if r["label"] in pos | neg]
    tr, te = split_rows(sel)
    res = {"pairs_train": len(tr), "pairs_test": len(te),
           "pos_train": int(labels(tr, pos).sum()), "pos_test": int(labels(te, pos).sum())}
    x, y = col(tr, feat), labels(tr, pos)
    ok = ~np.isnan(x)
    xt, yt = col(te, feat), labels(te, pos)
    okt = ~np.isnan(xt)
    for tag, target in (("high", a.high_target), ("low", a.low_target)):
        thr = ec.select_threshold(x[ok], y[ok], target, True, a.alpha) if ok.any() else None
        r = {"target": target, "threshold": None if thr is None else round(thr, 4)}
        if thr is not None:
            r["train"] = ec.evaluate(x[ok] >= thr, y[ok])
            r["test"] = ec.evaluate(xt[okt] >= thr, yt[okt]) if okt.any() else None
        res[tag] = r
    return res


def plot_pr(out, name, score, y, lower_is_match=False):
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception:
        return
    ok = ~np.isnan(score)
    s, yy = score[ok], y[ok]
    if len(s) < 2 or yy.sum() == 0:
        return
    s2 = -s if lower_is_match else s
    ts = np.unique(s2)
    prec, rec = [], []
    for t in ts:
        pred = s2 >= t
        n = pred.sum()
        prec.append(yy[pred].sum() / n if n else 1.0)
        rec.append(yy[pred].sum() / yy.sum())
    fig, ax = plt.subplots(figsize=(5, 4))
    ax.plot(rec, prec)
    ax.set_xlabel("recall")
    ax.set_ylabel("precision")
    ax.set_title(name)
    ax.set_ylim(0, 1.02)
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(out / f"pr_{name}.png", dpi=120)
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--dup-target", type=float, default=0.99, help="precision (cận dưới) cho tab Trùng")
    ap.add_argument("--high-target", type=float, default=0.95, help="precision cho dải 'rất giống'")
    ap.add_argument("--low-target", type=float, default=0.80, help="precision cho dải 'nên xem'")
    ap.add_argument("--alpha", type=float, default=0.05, help="mức ý nghĩa cho cận dưới (một phía)")
    ap.add_argument("--min-pos", type=int, default=30, help="cảnh báo nếu ít cặp dương hơn mức này")
    a = ap.parse_args()

    mf, sf = a.out / "manifest.csv", a.out / "scores.csv"
    if not mf.exists() or not sf.exists():
        print("Thiếu manifest.csv hoặc scores.csv. Gán nhãn (label_pairs.py) và chạy score_pairs.py trước.", file=sys.stderr)
        return 1
    with open(mf, newline="", encoding="utf-8") as fh:
        man = {r["pair_id"]: r for r in csv.DictReader(fh)}
    with open(sf, newline="", encoding="utf-8") as fh:
        sc = {r["pair_id"]: r for r in csv.DictReader(fh)}
    rows = []
    for pid, m in man.items():
        if m["label"] in ("", "skip") or pid not in sc:
            continue
        rows.append({"label": m["label"], "split": m.get("split", ""), "kind": m.get("kind", ""),
                     "hamming": sc[pid]["hamming"], "cos_dino": sc[pid]["cos_dino"], "cos_reid": sc[pid]["cos_reid"]})
    if not rows:
        print("Chưa có cặp nào được gán nhãn.", file=sys.stderr)
        return 1

    dup = calib_dup(rows, a)
    sim = calib_cos("similar", "cos_dino", rows, a)
    per = calib_cos("person", "cos_reid", rows, a)

    thresholds = {
        "certainHamming": dup["certainHamming"], "maxHamming": dup["maxHamming"],
        "verifyThreshold": dup["verifyThreshold"],
        "similarHigh": sim["high"]["threshold"], "similarLow": sim["low"]["threshold"],
        "personHigh": per["high"]["threshold"], "personLow": per["low"]["threshold"],
    }
    meta = {"generated": dt.datetime.now().isoformat(timespec="seconds"), "labeled_pairs": len(rows),
            "targets": {"dup": a.dup_target, "high": a.high_target, "low": a.low_target}, "alpha": a.alpha}
    (a.out / "thresholds.json").write_text(json.dumps({"thresholds": thresholds, "meta": meta}, indent=2, ensure_ascii=False),
                                           encoding="utf-8")

    # ---- báo cáo
    from collections import Counter
    cnt = Counter((r["label"], "test" if r["split"] == "test" else "train") for r in rows)
    L = ["# Báo cáo calibrate ngưỡng", "", f"Tạo lúc {meta['generated']} · {len(rows)} cặp đã gán nhãn · "
         f"cận dưới precision một phía, alpha={a.alpha}.", "", "## Dữ liệu", "",
         "| Nhãn | train | test |", "|---|---|---|"]
    for lab in ("dup", "similar", "similar_person", "person_only", "different"):
        L.append(f"| {lab} | {cnt[(lab, 'train')]} | {cnt[(lab, 'test')]} |")
    L += ["", "## Ngưỡng đề xuất", "", "| Tham số | Giá trị | Ghi chú |", "|---|---|---|"]
    notes = {
        "certainHamming": "`ScanConfig.certainHamming` — Hamming ≤ giá trị: nhận luôn",
        "maxHamming": "`ScanConfig.maxHamming` — chỉ nhận vùng (certain, max] khi Deep Scan xác minh được",
        "verifyThreshold": "`OnnxDinoEngine(verifyThreshold)` — cosine DINO tối thiểu ở vùng mơ hồ",
        "similarHigh": "dải 'rất giống' của tab Tương tự (cosine DINO)",
        "similarLow": "tương đương `ScanConfig.similarThreshold` — dải 'nên xem'",
        "personHigh": "dải 'rất giống' của tab Người (cosine OSNet)",
        "personLow": "tương đương `ScanConfig.personThreshold` — dải 'nên xem'",
    }
    for k, v in thresholds.items():
        L.append(f"| {k} | {'**không đạt**' if v is None else v} | {notes[k]} |")
    L += ["", "> Khi Deep Scan TẮT, code hiện tại nhận mọi cặp có Hamming ≤ `maxHamming` mà không xác minh. "
          "Để giữ precision, hãy đặt `maxHamming = certainHamming` cho chế độ Fast Scan.", ""]

    L += ["## Tab Trùng", "", f"Cặp train/test: {dup['pairs_train']}/{dup['pairs_test']}; "
          f"dương: {dup['pos_train']}/{dup['pos_test']}.", ""]
    if dup.get("note"):
        L += [dup["note"], ""]
    for tag in ("train", "test"):
        r = dup.get(tag)
        if r:
            L.append(f"- **{tag}**, chỉ Hamming ≤ {dup['certainHamming']}: {fmt(r['certain_only'], a.alpha)}")
            if "with_verify" in r:
                L.append(f"- **{tag}**, thêm xác minh DINO (≤ {dup['maxHamming']}, cos ≥ {dup['verifyThreshold']}): "
                         f"{fmt(r['with_verify'], a.alpha)}")
    for name, res, unit in (("Tương tự", sim, "cosine DINO"), ("Người", per, "cosine OSNet")):
        L += ["", f"## Tab {name} ({unit})", "", f"Cặp train/test: {res['pairs_train']}/{res['pairs_test']}; "
              f"dương: {res['pos_train']}/{res['pos_test']}.", ""]
        for tag, label in (("high", "rất giống"), ("low", "nên xem")):
            r = res[tag]
            if r["threshold"] is None:
                L.append(f"- **{label}** (mục tiêu P≥{100 * r['target']:.0f}%): không có ngưỡng nào đạt.")
                continue
            L.append(f"- **{label}** (mục tiêu P≥{100 * r['target']:.0f}%) ≥ {r['threshold']}")
            L.append(f"  - train: {fmt(r.get('train'), a.alpha)}")
            L.append(f"  - test: {fmt(r.get('test'), a.alpha)}")

    warns = []
    for nm, res in (("Trùng", dup), ("Tương tự", sim), ("Người", per)):
        if res["pos_train"] < a.min_pos:
            warns.append(f"Tab {nm}: chỉ {res['pos_train']} cặp dương ở tập train (< {a.min_pos}); ngưỡng kém tin cậy.")
        if res["pos_test"] == 0:
            warns.append(f"Tab {nm}: tập test không có cặp dương nào; chưa kiểm chứng được ngưỡng.")
    if warns:
        L += ["", "## Cảnh báo", ""] + [f"- {w}" for w in warns]
    (a.out / "report.md").write_text("\n".join(L) + "\n", encoding="utf-8")

    # ---- biểu đồ precision-recall trên toàn bộ dữ liệu có nhãn
    dsel = [r for r in rows if r["label"] in DUP_NEG | {"dup"}]
    plot_pr(a.out, "dup_hamming", col(dsel, "hamming"), labels(dsel, POS["dup"]), lower_is_match=True)
    for nm, feat in (("similar", "cos_dino"), ("person", "cos_reid")):
        s = [r for r in rows if r["label"] in POS[nm] | NEG[nm]]
        plot_pr(a.out, f"{nm}_{feat}", col(s, feat), labels(s, POS[nm]))

    print("\n".join(L))
    print(f"\nĐã ghi {a.out / 'thresholds.json'} và {a.out / 'report.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
