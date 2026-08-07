"""
train_traffic_light_export_v4.py

Versão com recalibração de quantização baseada em acumuladores reais
do conjunto de teste, evitando quant_mult muito pequeno e saída zerada
na NPU.
"""

from __future__ import annotations
import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple
import numpy as np
import cv2

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix
from sklearn.linear_model import LogisticRegression

CLASS_NAMES = ["red", "green"]
CLASS_TO_ID = {name: i for i, name in enumerate(CLASS_NAMES)}
VALID_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

def pack_int8(values: List[int]) -> int:
    out = 0
    for i, v in enumerate(values):
        out |= (int(v) & 0xFF) << (8 * i)
    return out & 0xFFFFFFFF

def clamp_int8_array(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x), -128, 127).astype(np.int32)

def load_image(path: Path, size: Tuple[int, int] = (24, 72)) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"Falha ao ler imagem: {path}")
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
    return img

def central_crop(img_rgb: np.ndarray, frac_w: float = 0.35) -> np.ndarray:
    h, w, _ = img_rgb.shape
    cw = max(4, int(w * frac_w))
    x0 = (w - cw) // 2
    return img_rgb[:, x0:x0+cw]

def normalize_lighting(img_rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
    h, s, v = cv2.split(hsv)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    v = clahe.apply(v)
    hsv_n = cv2.merge([h, s, v])
    return cv2.cvtColor(hsv_n, cv2.COLOR_HSV2RGB)

def red_green_masks(region_rgb: np.ndarray):
    hsv = cv2.cvtColor(region_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV)
    red1 = cv2.inRange(hsv, (0, 80, 60), (12, 255, 255))
    red2 = cv2.inRange(hsv, (165, 80, 60), (179, 255, 255))
    red_mask = cv2.bitwise_or(red1, red2)
    green_mask = cv2.inRange(hsv, (35, 50, 50), (95, 255, 255))
    return red_mask > 0, green_mask > 0, hsv

def region_stats(region_rgb: np.ndarray):
    red_mask, green_mask, hsv = red_green_masks(region_rgb)
    R = region_rgb[:, :, 0].astype(np.float32)
    G = region_rgb[:, :, 1].astype(np.float32)
    B = region_rgb[:, :, 2].astype(np.float32)

    S = R + G + B + 1.0
    r = R / S
    g = G / S

    rg_diff = R - G
    gr_diff = G - R

    red_ratio = float(red_mask.mean()) * 255.0
    green_ratio = float(green_mask.mean()) * 255.0
    red_strength = float(R[red_mask].mean()) if red_mask.any() else 0.0
    green_strength = float(G[green_mask].mean()) if green_mask.any() else 0.0
    red_peak = float(R.max())
    green_peak = float(G.max())

    if red_mask.any():
        ys, _ = np.where(red_mask)
        red_cy = float(ys.mean()) / max(1, region_rgb.shape[0] - 1)
    else:
        red_cy = 0.0

    if green_mask.any():
        ys, _ = np.where(green_mask)
        green_cy = float(ys.mean()) / max(1, region_rgb.shape[0] - 1)
    else:
        green_cy = 0.0

    return [
        float(R.mean()), float(G.mean()), float(B.mean()),
        float(r.mean()), float(g.mean()),
        float(rg_diff.mean()), float(gr_diff.mean()),
        red_ratio, green_ratio,
        red_strength, green_strength,
        red_peak, green_peak,
        red_cy, green_cy,
        float(hsv[:, :, 1].mean()),
        float(hsv[:, :, 2].mean()),
    ]

def extract_features(img_rgb: np.ndarray) -> np.ndarray:
    img = central_crop(img_rgb, frac_w=0.35)
    img = normalize_lighting(img)

    h = img.shape[0]
    top = img[0:h//3]
    mid = img[h//3:2*h//3]
    bot = img[2*h//3:h]

    ft = region_stats(top)
    fm = region_stats(mid)
    fb = region_stats(bot)

    feats = []
    feats.extend(ft)
    feats.extend(fm)
    feats.extend(fb)

    feats.extend([
        ft[0] - fb[0],
        ft[1] - fb[1],
        ft[7] - fb[7],
        ft[8] - fb[8],
        ft[9] - fb[9],
        ft[10] - fb[10],
        ft[11] - fb[11],
        ft[12] - fb[12],
    ])

    red_mask, green_mask, _ = red_green_masks(img)
    feats.extend([
        float(red_mask.mean()) * 255.0,
        float(green_mask.mean()) * 255.0,
        float(img[:, :, 0].mean() / (img[:, :, 1].mean() + 1.0)),
        float(img[:, :, 1].mean() / (img[:, :, 0].mean() + 1.0)),
    ])

    return np.array(feats, dtype=np.float32)

def load_dataset(dataset_dir: Path):
    X, y, paths = [], [], []
    counts = {name: 0 for name in CLASS_NAMES}

    for class_name in CLASS_NAMES:
        cls_dir = dataset_dir / class_name
        if not cls_dir.exists():
            raise FileNotFoundError(f"Pasta não encontrada: {cls_dir}")

        for path in sorted(cls_dir.glob("*")):
            if path.suffix.lower() not in VALID_EXT:
                continue
            img = load_image(path)
            X.append(extract_features(img))
            y.append(CLASS_TO_ID[class_name])
            paths.append(path)
            counts[class_name] += 1

    if not X:
        raise RuntimeError("Nenhuma imagem encontrada no dataset.")

    print("\n=== Contagem por classe ===")
    for k, v in counts.items():
        print(f"{k}: {v}")

    return np.vstack(X), np.array(y, dtype=np.int32), paths

@dataclass
class ExportBundle:
    W_int: np.ndarray
    B_int: np.ndarray
    X_test_int: np.ndarray
    y_test: np.ndarray
    quant_mult: int
    quant_cfg: int
    feature_dim: int
    n_words: int
    acc: float
    best_C: float
    calib_acc_ref: float

def train_and_quantize(dataset_dir: Path, test_size: float = 0.25, random_state: int = 42) -> ExportBundle:
    X, y, _ = load_dataset(dataset_dir)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    scaler = StandardScaler().fit(X_train)
    X_train_s = scaler.transform(X_train)
    X_test_s = scaler.transform(X_test)

    best_acc = -1.0
    best_clf = None
    best_C = None

    print("\n=== Busca de hiperparâmetro C ===")
    for C in [0.03, 0.05, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0]:
        clf = LogisticRegression(
            random_state=0,
            max_iter=4000,
            solver="lbfgs",
            class_weight="balanced",
            C=C
        )
        clf.fit(X_train_s, y_train)
        pred = clf.predict(X_test_s)
        acc = accuracy_score(y_test, pred)
        print(f"C={C:.2f} -> acc={acc:.4f}")
        if acc > best_acc:
            best_acc = acc
            best_clf = clf
            best_C = C

    clf_export = best_clf
    y_pred = clf_export.predict(X_test_s)
    acc = accuracy_score(y_test, y_pred)

    print(f"\nMelhor C linear: {best_C}")
    print("\n=== Relatório de classificação ===")
    print(classification_report(
        y_test,
        y_pred,
        labels=[0, 1],
        target_names=CLASS_NAMES,
        digits=4,
        zero_division=0
    ))
    print("Acurácia exportável:", round(acc, 4))
    print("Matriz de confusão exportável:\n", confusion_matrix(y_test, y_pred, labels=[0, 1]))

    feat_dim = X_train_s.shape[1]
    W_pad = np.zeros((feat_dim, 4), dtype=np.float64)
    B_pad = np.zeros(4, dtype=np.float64)

    if clf_export.coef_.shape[0] == 1:
        W_pad[:, 0] = clf_export.coef_[0]
        B_pad[0] = clf_export.intercept_[0]
    else:
        W_pad[:, :2] = clf_export.coef_.T
        B_pad[:2] = clf_export.intercept_

    max_val = max(np.max(np.abs(W_pad)), np.max(np.abs(X_test_s)))
    scale = 127.0 / max_val if max_val != 0 else 1.0

    W_int = clamp_int8_array(W_pad * scale)
    X_test_int = clamp_int8_array(X_test_s * scale)
    B_int = np.round(B_pad * scale * scale).astype(np.int32)

    scores0 = X_test_int @ W_int[:, 0] + B_int[0]
    scores1 = X_test_int @ W_int[:, 1] + B_int[1]
    abs_scores = np.abs(np.concatenate([scores0, scores1]))

    calib_acc_ref = float(np.percentile(abs_scores, 99.0))
    if calib_acc_ref < 1.0:
        calib_acc_ref = float(np.max(abs_scores))
    if calib_acc_ref < 1.0:
        calib_acc_ref = 1.0

    best_shift = 16
    best_mult = int(round((127.0 / calib_acc_ref) * (1 << best_shift) * 0.85))
    if best_mult <= 0:
        best_mult = 1
    quant_cfg = best_shift

    print("\n=== Recalibração de quantização ===")
    print("percentil 99 |acc|:", round(calib_acc_ref, 2))
    print("quant_mult recalibrado:", best_mult)
    print("quant_cfg:", hex(quant_cfg))

    return ExportBundle(
        W_int=W_int,
        B_int=B_int,
        X_test_int=X_test_int,
        y_test=y_test,
        quant_mult=best_mult,
        quant_cfg=quant_cfg,
        feature_dim=feat_dim,
        n_words=feat_dim,
        acc=acc,
        best_C=best_C,
        calib_acc_ref=calib_acc_ref,
    )

def emit_header(bundle: ExportBundle, out_path: Path, num_samples: int = 8) -> None:
    num_samples = min(num_samples, len(bundle.X_test_int))
    lines = []
    lines.append("#ifndef TRAFFIC_LIGHT_MODEL_H")
    lines.append("#define TRAFFIC_LIGHT_MODEL_H")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("// Gerado automaticamente por train_traffic_light_export_v4.py")
    lines.append(f"// best_C = {bundle.best_C}")
    lines.append(f"// calib_acc_ref_p99 = {bundle.calib_acc_ref}")
    lines.append(f"#define TL_NUM_CLASSES 2u")
    lines.append(f"#define TL_FEATURE_DIM {bundle.feature_dim}u")
    lines.append(f"#define TL_K_DIM {bundle.n_words}u")
    lines.append(f"#define TL_QUANT_CFG  0x{bundle.quant_cfg:08X}u")
    lines.append(f"#define TL_QUANT_MULT 0x{bundle.quant_mult:08X}u")
    lines.append(f"#define TL_NUM_TEST_SAMPLES {num_samples}u")
    lines.append("")
    lines.append("static const int32_t tl_bias[4] = {")
    for i, b in enumerate(bundle.B_int):
        comma = "," if i < 3 else ""
        lines.append(f"    {int(b)}{comma}")
    lines.append("};")
    lines.append("")
    lines.append("static const uint32_t tl_weights[TL_K_DIM] = {")
    for k in range(bundle.feature_dim):
        word = pack_int8(bundle.W_int[k, :].tolist())
        comma = "," if k < bundle.feature_dim - 1 else ""
        lines.append(f"    0x{word:08X}u{comma}")
    lines.append("};")
    lines.append("")
    lines.append("static const uint32_t tl_inputs[TL_NUM_TEST_SAMPLES][TL_K_DIM] = {")
    for s in range(num_samples):
        lines.append("    {")
        x = bundle.X_test_int[s]
        for k in range(bundle.feature_dim):
            word = pack_int8([int(x[k]), 0, 0, 0])
            comma = "," if k < bundle.feature_dim - 1 else ""
            lines.append(f"        0x{word:08X}u{comma}")
        comma_end = "," if s < num_samples - 1 else ""
        lines.append(f"    }}{comma_end}")
    lines.append("};")
    lines.append("")
    label_names = ", ".join(f'\"{n}\"' for n in CLASS_NAMES)
    lines.append(f"static const char * const tl_class_names[TL_NUM_CLASSES] = {{{label_names}}};")
    lines.append("")
    lines.append("static const uint8_t tl_expected_labels[TL_NUM_TEST_SAMPLES] = {")
    for i in range(num_samples):
        comma = "," if i < num_samples - 1 else ""
        lines.append(f"    {int(bundle.y_test[i])}{comma}")
    lines.append("};")
    lines.append("")
    lines.append("#endif")
    lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nHeader gerado em: {out_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument("--out", default="traffic_light_model.h", type=Path)
    parser.add_argument("--samples", default=8, type=int)
    args = parser.parse_args()

    bundle = train_and_quantize(args.dataset)
    emit_header(bundle, args.out, num_samples=args.samples)

if __name__ == "__main__":
    main()
