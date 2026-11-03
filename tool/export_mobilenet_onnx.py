#!/usr/bin/env python3
"""Export MobileNetV3-Large / MobileNetV2 (torchvision, ImageNet) sang ONNX
làm bộ embedding cho bước AI của Cleanify (thay DINOv2).

Chạy trên máy của bạn (cần mạng để torchvision tải trọng số ImageNet).

Cài đặt (một lần, trong .venv của project):
    pip install torch torchvision onnx onnxruntime numpy
    # chỉ cần nếu dùng --fp16:
    pip install onnxconverter-common

Chạy:
    python3 tool/export_mobilenet_onnx.py --arch v3l --out assets/models/mobilenet.onnx
    python3 tool/export_mobilenet_onnx.py --arch v2  --out assets/models/mobilenet.onnx

Đầu ra: vector embedding cho mỗi ảnh = đặc trưng SAU global average pooling,
bỏ toàn bộ classifier (V3-Large: 960 chiều, V2: 1280 chiều). Batch động,
đầu vào Nx3x224x224 float32.

Tiền xử lý trong app phải khớp (đã khớp với code DINO cũ nên không cần sửa
dinoPreprocess): resize 224x224, RGB, chia 255, trừ mean [0.485, 0.456, 0.406],
chia std [0.229, 0.224, 0.225]. App L2-normalize đầu ra trước khi so cosine.

Sau khi export, đặt `dinoDim` trong lib/engines/dino/dino_engine.dart đúng với
số chiều script in ra (960 cho v3l, 1280 cho v2).

Để so hai model bằng bộ calibrate hiện có mà không sửa tool/score_pairs.py
(nó đọc <models>/dino.onnx), export mỗi model vào một thư mục riêng với tên đó:
    python3 tool/export_mobilenet_onnx.py --arch v3l --out eval_out/models_v3l/dino.onnx
    python3 tool/score_pairs.py --models eval_out/models_v3l ...

--fp16 chỉ giảm kích thước file (đầu vào/ra vẫn float32). Tốc độ trên điện thoại
KHÔNG được đảm bảo nhanh hơn; hãy đo trước khi chọn. Quantize int8 nên làm sau,
và phải chạy lại calibrate sau đó.

Giấy phép: trọng số torchvision ImageNet, đọc điều khoản của bộ dữ liệu/model
trước khi phát hành app.

HÃY GỬI LẠI các dòng script in ra (số chiều, sai lệch, kích thước file).
"""
import argparse
import sys
from pathlib import Path

DIMS = {"v3l": 960, "v2": 1280}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--arch", choices=sorted(DIMS), default="v3l")
    ap.add_argument("--out", type=Path, default=Path("assets/models/mobilenet.onnx"))
    ap.add_argument("--size", type=int, default=224)
    ap.add_argument("--opset", type=int, default=17)
    ap.add_argument("--fp16", action="store_true", help="đổi trọng số sang fp16 (giữ I/O float32)")
    a = ap.parse_args()
    try:
        import numpy as np
        import onnx
        import onnxruntime as ort
        import torch
        from torchvision import models
    except ImportError as e:
        print(f"Thiếu thư viện: {e}\nXem phần 'Cài đặt' ở đầu file.", file=sys.stderr)
        return 1

    if a.arch == "v3l":
        base = models.mobilenet_v3_large(weights=models.MobileNet_V3_Large_Weights.IMAGENET1K_V1)
    else:
        base = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)

    class Embed(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.features = m.features
            self.pool = torch.nn.AdaptiveAvgPool2d(1)

        def forward(self, x):
            return torch.flatten(self.pool(self.features(x)), 1)

    model = Embed(base).eval()
    dummy = torch.randn(1, 3, a.size, a.size)
    with torch.no_grad():
        ref = model(dummy)
    print(f"PyTorch: đầu ra shape {tuple(ref.shape)}")
    if ref.shape[1] != DIMS[a.arch]:
        print(f"Số chiều {ref.shape[1]} khác kỳ vọng {DIMS[a.arch]} cho {a.arch}", file=sys.stderr)
        return 1

    a.out.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model, dummy, str(a.out),
        input_names=["input"], output_names=["embedding"],
        dynamic_axes={"input": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=a.opset, do_constant_folding=True,
    )
    onnx.checker.check_model(onnx.load(str(a.out)))

    tol = 1e-3
    if a.fp16:
        try:
            from onnxconverter_common import float16
        except ImportError:
            print("--fp16 cần: pip install onnxconverter-common", file=sys.stderr)
            return 1
        m16 = float16.convert_float_to_float16(onnx.load(str(a.out)), keep_io_types=True)
        onnx.save(m16, str(a.out))
        onnx.checker.check_model(onnx.load(str(a.out)))
        tol = 2e-2

    sess = ort.InferenceSession(str(a.out), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"input": dummy.numpy()})[0]
    batch = sess.run(None, {"input": np.concatenate([dummy.numpy()] * 3)})[0]
    diff = float(np.abs(got - ref.numpy()).max())
    print(f"ONNX   : đầu ra shape {got.shape}, batch=3 -> {batch.shape}")
    print(f"Sai lệch tối đa so với PyTorch: {diff:.2e}  (kỳ vọng < {tol:.0e})")
    print(f"Số chiều embedding: {got.shape[1]}  -> đặt dinoDim = {got.shape[1]}")
    print(f"Kích thước file: {a.out.stat().st_size / 1e6:.1f} MB -> {a.out}")
    return 0 if diff <= tol else 2


if __name__ == "__main__":
    sys.exit(main())
