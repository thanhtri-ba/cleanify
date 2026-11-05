#!/usr/bin/env python3
"""BƯỚC 4 — MobileNetV3-Large (ONNX): ảnh -> vector 960 chiều (CNN).

Thumbnail 224 -> chuẩn hóa mean/std ImageNet -> mạng -> vector -> L2-normalize.
Vào : thư mục ảnh (--src), model (--model, mặc định ../assets/models/mobilenet.onnx)
Ra  : out/4_embeddings.npz (emb: n x d, valid: n bool)
"""
from pathlib import Path

import numpy as np
from PIL import Image

from common import EMB_THUMB, base_parser, ensure_index, fit_jpeg, load_rgb

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def prep(path: Path):
    import io
    try:
        im = Image.open(io.BytesIO(fit_jpeg(load_rgb(path), EMB_THUMB))).convert("RGB")
        im = im.resize((224, 224), Image.BOX)
        x = (np.asarray(im, dtype=np.float32) / 255.0 - MEAN) / STD
        return np.ascontiguousarray(x.transpose(2, 0, 1))
    except Exception:
        return None


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--model", default=str(Path(__file__).resolve().parent.parent / "assets/models/mobilenet.onnx"))
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--threads", type=int, default=4)
    a = ap.parse_args()
    import onnxruntime as ort

    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = a.threads
    sess = ort.InferenceSession(a.model, opts, providers=["CPUExecutionProvider"])
    inp = sess.get_inputs()[0].name
    n = len(photos)
    emb, valid = None, np.zeros(n, dtype=bool)
    for s in range(0, n, a.batch):
        chunk = [(p["idx"], prep(src / p["path"])) for p in photos[s:s + a.batch]]
        chunk = [(i, x) for i, x in chunk if x is not None]
        if not chunk:
            continue
        o = sess.run(None, {inp: np.stack([x for _, x in chunk])})[0]
        o = np.asarray(o, dtype=np.float32).reshape(len(chunk), -1)
        o /= np.maximum(np.linalg.norm(o, axis=1, keepdims=True), 1e-12)
        if emb is None:
            emb = np.zeros((n, o.shape[1]), dtype=np.float32)
        for (i, _), v in zip(chunk, o):
            emb[i] = v
            valid[i] = True
        if (s // a.batch) % 20 == 0 or s + a.batch >= n:
            print(f"  đã xử lý {min(s + a.batch, n)}/{n} ảnh", flush=True)
    if emb is None:
        raise SystemExit("Không ảnh nào đọc được.")
    np.savez(out / "4_embeddings.npz", emb=emb, valid=valid)
    print(f"Vector {emb.shape[1]} chiều cho {int(valid.sum())}/{n} ảnh -> {out / '4_embeddings.npz'}")


if __name__ == "__main__":
    main()
