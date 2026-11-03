#!/usr/bin/env python3
"""Export DINOv2 (ViT-S/14) sang ONNX cho Deep Scan "ảnh tương tự" của Cleanify.

Chạy trên máy của bạn (cần mạng để tải trọng số từ Hugging Face).

Cài đặt (một lần):
    python3 -m venv .venv && source .venv/bin/activate
    pip install torch torchvision transformers onnx onnxruntime numpy pillow

Chạy:
    python3 tool/export_dino_onnx.py --out assets/models/dino.onnx

Mặc định dùng facebook/dinov2-small (384 chiều). Hãy đọc model card của đúng
model bạn dùng để biết giấy phép trước khi phát hành app.

Đầu ra: vector 384 chiều cho mỗi ảnh (CLS token đã qua layernorm), batch động,
đầu vào 1x3x224x224. Tiền xử lý trong app phải khớp: resize 224x224, RGB,
chia 255, trừ mean [0.485, 0.456, 0.406], chia std [0.229, 0.224, 0.225], rồi
L2-normalize đầu ra trước khi so cosine.

HÃY GỬI LẠI các dòng script in ra (số chiều, sai lệch, kích thước file).
"""
import argparse
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="facebook/dinov2-small")
    ap.add_argument("--out", type=Path, default=Path("assets/models/dino.onnx"))
    ap.add_argument("--size", type=int, default=224, help="cạnh ảnh đầu vào, bội của 14")
    ap.add_argument("--opset", type=int, default=17)
    a = ap.parse_args()
    if a.size % 14:
        print("--size phải là bội của 14", file=sys.stderr)
        return 1
    try:
        import numpy as np
        import onnx
        import onnxruntime as ort
        import torch
        from transformers import AutoModel
    except ImportError as e:
        print(f"Thiếu thư viện: {e}\nXem phần 'Cài đặt' ở đầu file.", file=sys.stderr)
        return 1

    class Wrap(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            return self.m(pixel_values=x).pooler_output  # CLS đã qua layernorm

    base = AutoModel.from_pretrained(a.model).eval()
    model = Wrap(base).eval()
    dummy = torch.randn(1, 3, a.size, a.size)
    with torch.no_grad():
        ref = model(dummy)
    print(f"PyTorch: đầu ra shape {tuple(ref.shape)}")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model, dummy, str(a.out),
        input_names=["input"], output_names=["embedding"],
        dynamic_axes={"input": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=a.opset, do_constant_folding=True,
    )
    onnx.checker.check_model(onnx.load(str(a.out)))

    sess = ort.InferenceSession(str(a.out), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"input": dummy.numpy()})[0]
    batch = sess.run(None, {"input": np.concatenate([dummy.numpy()] * 3)})[0]
    diff = float(np.abs(got - ref.numpy()).max())
    print(f"ONNX   : đầu ra shape {got.shape}, batch=3 -> {batch.shape}")
    print(f"Sai lệch tối đa so với PyTorch: {diff:.2e}  (kỳ vọng < 1e-3)")
    print(f"Số chiều embedding: {got.shape[1]}")
    print(f"Kích thước file: {a.out.stat().st_size / 1e6:.1f} MB -> {a.out}")
    return 0 if diff <= 1e-3 else 2


if __name__ == "__main__":
    sys.exit(main())
