"""
train_traffic_light_export_v2.py

Versão melhorada para classificar semáforo red / green com features mais específicas:
- recorte central (reduz influência do fundo)
- estatísticas RGB/HSV por 3 faixas verticais
- contagem de pixels vermelhos e verdes por faixa
- razões R/G e G/R por faixa
- localização do pico de brilho por faixa

Estrutura esperada do dataset:
dataset/
  red/
  green/

Uso:
python train_traffic_light_export_v2.py --dataset ./dataset --out traffic_light_model.h --samples 8
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
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix

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


def central_crop(img_rgb: np.ndarray, frac_w: float = 0.5) -> np.ndarray:
    h, w, _ = img_rgb.shape
    cw = max(4, int(w * frac_w))
    x0 = (w - cw) // 2
    return img_rgb[:, x0:x0+cw]


def red_green_masks(region_rgb: np.ndarray):
    hsv = cv2.cvtColor(region_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV)
    red1 = cv2.inRange(hsv, (0, 80, 60), (12, 255, 255))
    red2 = cv2.inRange(hsv, (165, 80, 60), (179, 255, 255))
    red_mask = cv2.bitwise_or(red1, red2)
    green_mask = cv2.inRange(hsv, (35, 50, 50), (95, 255, 255))
    return red_mask > 0, green_mask > 0, hsv


def region_stats(region_rgb: np.ndarray) -> List[float]:
    red_mask, green_mask, hsv = red_green_masks(region_rgb)

    mean_rgb = region_rgb.mean(axis=(0, 1))
    mean_hsv = hsv.mean(axis=(0, 1))
    gray = region_rgb.mean(axis=2)

    red_ratio = float(red_mask.mean()) * 255.0
    green_ratio = float(green_mask.mean()) * 255.0

    red_strength = float(region_rgb[:, :, 0][red_mask].mean()) if red_mask.any() else 0.0
    green_strength = float(region_rgb[:, :, 1][green_mask].mean()) if green_mask.any() else 0.0

    r_mean = float(mean_rgb[0])
    g_mean = float(mean_rgb[1])
    b_mean = float(mean_rgb[2])

    rg_ratio = r_mean / (g_mean + 1.0)
    gr_ratio = g_mean / (r_mean + 1.0)
    rb_ratio = r_mean / (b_mean + 1.0)
    gb_ratio = g_mean / (b_mean + 1.0)

    flat_idx = int(np.argmax(gray))
    peak_y, peak_x = np.unravel_index(flat_idx, gray.shape)
    peak_val = float(gray[peak_y, peak_x])

    return [
        r_mean, g_mean, b_mean,
        float(gray.mean()),
        float(mean_hsv[0]), float(mean_hsv[1]), float(mean_hsv[2]),
        red_ratio, green_ratio,
        red_strength, green_strength,
        rg_ratio, gr_ratio, rb_ratio, gb_ratio,
        float(peak_y) / max(1, gray.shape[0] - 1),
        float(peak_x) / max(1, gray.shape[1] - 1),
        peak_val,
    ]


def extract_features(img_rgb: np.ndarray) -> np.ndarray:
    img = central_crop(img_rgb, frac_w=0.5)
    h = img.shape[0]
    thirds = [img[0:h//3], img[h//3:2*h//3], img[2*h//3:h]]

    feats: List[float] = []
    for reg in thirds:
        feats.extend(region_stats(reg))

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
        if v < 20:
            print(f"AVISO: classe '{k}' com poucas imagens.")

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


def train_and_quantize(dataset_dir: Path, test_size: float = 0.25, random_state: int = 42) -> ExportBundle:
    X, y, _ = load_dataset(dataset_dir)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    scaler = StandardScaler().fit(X_train)
    X_train_s = scaler.transform(X_train)
    X_test_s = scaler.transform(X_test)

    clf = MLPClassifier(
        hidden_layer_sizes=(12,),
        activation="relu",
        solver="adam",
        max_iter=1200,
        random_state=0
    )
    clf.fit(X_train_s, y_train)

    y_pred = clf.predict(X_test_s)
    acc = accuracy_score(y_test, y_pred)

    print("\n=== Relatório de classificação (MLP) ===")
    print(classification_report(
        y_test,
        y_pred,
        labels=[0, 1],
        target_names=CLASS_NAMES,
        digits=4,
        zero_division=0
    ))
    print("Acurácia MLP:", round(acc, 4))
    print("Matriz de confusão MLP:\n", confusion_matrix(y_test, y_pred, labels=[0, 1]))

    from sklearn.linear_model import LogisticRegression
    clf_export = LogisticRegression(random_state=0, max_iter=2000, solver="lbfgs")
    clf_export.fit(X_train_s, y_train)

    y_pred_exp = clf_export.predict(X_test_s)
    acc_exp = accuracy_score(y_test, y_pred_exp)

    print("\n=== Modelo exportável (linear) ===")
    print(classification_report(
        y_test,
        y_pred_exp,
        labels=[0, 1],
        target_names=CLASS_NAMES,
        digits=4,
        zero_division=0
    ))
    print("Acurácia exportável:", round(acc_exp, 4))
    print("Matriz de confusão exportável:\n", confusion_matrix(y_test, y_pred_exp, labels=[0, 1]))

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

    max_acc_theor = int((127 * 127 * feat_dim) + np.max(np.abs(B_int)))
    target_factor = 127.0 / max_acc_theor if max_acc_theor != 0 else 1.0
    best_shift = 16
    best_mult = int(round(target_factor * (1 << best_shift)))
    if best_mult <= 0:
        best_mult = 1
    quant_cfg = best_shift

    print("\n=== Quantização ===")
    print("feature_dim:", feat_dim)
    print("n_words:", feat_dim)
    print("quant_mult:", best_mult)
    print("quant_cfg :", hex(quant_cfg))

    return ExportBundle(
        W_int=W_int,
        B_int=B_int,
        X_test_int=X_test_int,
        y_test=y_test,
        quant_mult=best_mult,
        quant_cfg=quant_cfg,
        feature_dim=feat_dim,
        n_words=feat_dim,
        acc=acc_exp,
    )


def emit_header(bundle: ExportBundle, out_path: Path, num_samples: int = 8) -> None:
    num_samples = min(num_samples, len(bundle.X_test_int))
    lines = []
    lines.append("#ifndef TRAFFIC_LIGHT_MODEL_H")
    lines.append("#define TRAFFIC_LIGHT_MODEL_H")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("// Gerado automaticamente por train_traffic_light_export_v2.py")
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
    parser.add_argument("--dataset", required=True, type=Path, help="Pasta dataset com subpastas red/green")
    parser.add_argument("--out", default="traffic_light_model.h", type=Path, help="Arquivo .h de saída")
    parser.add_argument("--samples", default=8, type=int, help="Número de amostras de teste a exportar")
    args = parser.parse_args()

    bundle = train_and_quantize(args.dataset)
    emit_header(bundle, args.out, num_samples=args.samples)


if __name__ == "__main__":
    main()
