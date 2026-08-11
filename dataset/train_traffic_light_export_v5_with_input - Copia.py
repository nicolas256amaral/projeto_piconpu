"""
train_traffic_light_export_v5.py

Treina um classificador linear vermelho/verde e exporta:

1. traffic_light_model.h
   - pesos quantizados para a NPU;
   - bias;
   - TL_QUANT_CFG e TL_QUANT_MULT;
   - opcionalmente, amostras de teste já quantizadas.

2. traffic_light_preprocess.json
   - média e desvio do StandardScaler;
   - escala de quantização das features;
   - parâmetros necessários para transformar imagens novas nos mesmos
     63 bytes enviados à NPU pela UART.

A v5 mantém compatibilidade com o firmware usado na integração
UART -> PicoRV32 -> NPU -> UART, sem colocar os vetores float do
pré-processamento dentro do firmware por padrão.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler


CLASS_NAMES = ["red", "green"]
CLASS_TO_ID = {name: i for i, name in enumerate(CLASS_NAMES)}
VALID_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
FEATURE_IMAGE_SIZE = (24, 72)  # largura, altura para cv2.resize
CENTRAL_CROP_FRAC_W = 0.35


# -----------------------------------------------------------------------------
# Utilidades de quantização
# -----------------------------------------------------------------------------

def pack_int8(values: List[int]) -> int:
    """Empacota até quatro valores int8 em uma word de 32 bits, little-endian."""
    if len(values) > 4:
        raise ValueError("pack_int8 aceita no máximo quatro valores.")

    out = 0
    for i, value in enumerate(values):
        out |= (int(value) & 0xFF) << (8 * i)
    return out & 0xFFFFFFFF


def clamp_int8_array(x: np.ndarray) -> np.ndarray:
    """Arredonda e satura um array para o intervalo int8."""
    return np.clip(np.round(x), -128, 127).astype(np.int32)


def quantize_raw_features(
    raw_features: np.ndarray,
    scaler_mean: np.ndarray,
    scaler_scale: np.ndarray,
    input_quant_scale: float,
) -> np.ndarray:
    """
    Reproduz, para uma imagem nova, o mesmo pré-processamento usado no treino.

    Retorna um vetor np.int8 com TL_FEATURE_DIM elementos, pronto para envio
    byte a byte pela UART.
    """
    raw = np.asarray(raw_features, dtype=np.float32)
    mean = np.asarray(scaler_mean, dtype=np.float32)
    std = np.asarray(scaler_scale, dtype=np.float32)

    if raw.shape != mean.shape or raw.shape != std.shape:
        raise ValueError(
            f"Dimensões incompatíveis: raw={raw.shape}, mean={mean.shape}, scale={std.shape}"
        )

    if not np.isfinite(raw).all():
        raise ValueError("As features contêm NaN ou infinito.")

    safe_std = np.where(std == 0.0, 1.0, std)
    standardized = (raw - mean) / safe_std
    quantized = np.clip(
        np.round(standardized * float(input_quant_scale)),
        -128,
        127,
    ).astype(np.int8)
    return quantized


# -----------------------------------------------------------------------------
# Extração das 63 features
# -----------------------------------------------------------------------------

def load_image(
    path: Path,
    size: Tuple[int, int] = FEATURE_IMAGE_SIZE,
) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"Falha ao ler imagem: {path}")

    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
    return img


def central_crop(
    img_rgb: np.ndarray,
    frac_w: float = CENTRAL_CROP_FRAC_W,
) -> np.ndarray:
    _, width, _ = img_rgb.shape
    crop_width = max(4, int(width * frac_w))
    x0 = (width - crop_width) // 2
    return img_rgb[:, x0 : x0 + crop_width]


def normalize_lighting(img_rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2HSV)
    h, s, v = cv2.split(hsv)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    v_normalized = clahe.apply(v)
    hsv_normalized = cv2.merge([h, s, v_normalized])
    return cv2.cvtColor(hsv_normalized, cv2.COLOR_HSV2RGB)


def red_green_masks(region_rgb: np.ndarray):
    hsv = cv2.cvtColor(region_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV)

    red1 = cv2.inRange(hsv, (0, 80, 60), (12, 255, 255))
    red2 = cv2.inRange(hsv, (165, 80, 60), (179, 255, 255))
    red_mask = cv2.bitwise_or(red1, red2)

    green_mask = cv2.inRange(hsv, (35, 50, 50), (95, 255, 255))
    return red_mask > 0, green_mask > 0, hsv


def region_stats(region_rgb: np.ndarray) -> List[float]:
    red_mask, green_mask, hsv = red_green_masks(region_rgb)

    red = region_rgb[:, :, 0].astype(np.float32)
    green = region_rgb[:, :, 1].astype(np.float32)
    blue = region_rgb[:, :, 2].astype(np.float32)

    rgb_sum = red + green + blue + 1.0
    red_norm = red / rgb_sum
    green_norm = green / rgb_sum

    red_green_diff = red - green
    green_red_diff = green - red

    red_ratio = float(red_mask.mean()) * 255.0
    green_ratio = float(green_mask.mean()) * 255.0
    red_strength = float(red[red_mask].mean()) if red_mask.any() else 0.0
    green_strength = float(green[green_mask].mean()) if green_mask.any() else 0.0
    red_peak = float(red.max())
    green_peak = float(green.max())

    if red_mask.any():
        red_y, _ = np.where(red_mask)
        red_center_y = float(red_y.mean()) / max(1, region_rgb.shape[0] - 1)
    else:
        red_center_y = 0.0

    if green_mask.any():
        green_y, _ = np.where(green_mask)
        green_center_y = float(green_y.mean()) / max(1, region_rgb.shape[0] - 1)
    else:
        green_center_y = 0.0

    return [
        float(red.mean()),
        float(green.mean()),
        float(blue.mean()),
        float(red_norm.mean()),
        float(green_norm.mean()),
        float(red_green_diff.mean()),
        float(green_red_diff.mean()),
        red_ratio,
        green_ratio,
        red_strength,
        green_strength,
        red_peak,
        green_peak,
        red_center_y,
        green_center_y,
        float(hsv[:, :, 1].mean()),
        float(hsv[:, :, 2].mean()),
    ]


def extract_features(img_rgb: np.ndarray) -> np.ndarray:
    img = central_crop(img_rgb)
    img = normalize_lighting(img)

    height = img.shape[0]
    top = img[0 : height // 3]
    middle = img[height // 3 : 2 * height // 3]
    bottom = img[2 * height // 3 : height]

    top_features = region_stats(top)
    middle_features = region_stats(middle)
    bottom_features = region_stats(bottom)

    features: List[float] = []
    features.extend(top_features)
    features.extend(middle_features)
    features.extend(bottom_features)

    features.extend(
        [
            top_features[0] - bottom_features[0],
            top_features[1] - bottom_features[1],
            top_features[7] - bottom_features[7],
            top_features[8] - bottom_features[8],
            top_features[9] - bottom_features[9],
            top_features[10] - bottom_features[10],
            top_features[11] - bottom_features[11],
            top_features[12] - bottom_features[12],
        ]
    )

    red_mask, green_mask, _ = red_green_masks(img)
    features.extend(
        [
            float(red_mask.mean()) * 255.0,
            float(green_mask.mean()) * 255.0,
            float(img[:, :, 0].mean() / (img[:, :, 1].mean() + 1.0)),
            float(img[:, :, 1].mean() / (img[:, :, 0].mean() + 1.0)),
        ]
    )

    result = np.asarray(features, dtype=np.float32)
    if result.shape != (63,):
        raise RuntimeError(f"Quantidade inesperada de features: {result.shape[0]} (esperado 63).")
    return result


# -----------------------------------------------------------------------------
# Dataset e treinamento
# -----------------------------------------------------------------------------

def load_dataset(dataset_dir: Path):
    X: List[np.ndarray] = []
    y: List[int] = []
    paths: List[Path] = []
    counts = {name: 0 for name in CLASS_NAMES}

    for class_name in CLASS_NAMES:
        class_dir = dataset_dir / class_name
        if not class_dir.exists():
            raise FileNotFoundError(f"Pasta não encontrada: {class_dir}")

        for path in sorted(class_dir.glob("*")):
            if path.suffix.lower() not in VALID_EXT:
                continue

            X.append(extract_features(load_image(path)))
            y.append(CLASS_TO_ID[class_name])
            paths.append(path)
            counts[class_name] += 1

    if not X:
        raise RuntimeError("Nenhuma imagem válida encontrada no dataset.")

    missing_classes = [name for name, count in counts.items() if count == 0]
    if missing_classes:
        raise RuntimeError(
            "Classes sem imagens: " + ", ".join(missing_classes)
        )

    print("\n=== Contagem por classe ===")
    for class_name, count in counts.items():
        print(f"{class_name}: {count}")

    return np.vstack(X), np.asarray(y, dtype=np.int32), paths


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
    acc_float: float
    acc_quantized: float
    best_C: float
    calib_acc_ref: float
    scaler_mean: np.ndarray
    scaler_scale: np.ndarray
    input_quant_scale: float


def predict_quantized_labels(
    X_int: np.ndarray,
    W_int: np.ndarray,
    B_int: np.ndarray,
) -> np.ndarray:
    """Predição equivalente à comparação de scores usada no firmware."""
    scores_green = X_int @ W_int[:, 0] + B_int[0]
    scores_red = X_int @ W_int[:, 1] + B_int[1]
    return (scores_green > scores_red).astype(np.int32)


def train_and_quantize(
    dataset_dir: Path,
    test_size: float = 0.25,
    random_state: int = 42,
) -> ExportBundle:
    if not 0.0 < test_size < 1.0:
        raise ValueError("--test-size deve estar entre 0 e 1.")

    X, y, _ = load_dataset(dataset_dir)

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=test_size,
        random_state=random_state,
        stratify=y,
    )

    scaler = StandardScaler().fit(X_train)
    X_train_s = scaler.transform(X_train)
    X_test_s = scaler.transform(X_test)

    best_acc = -1.0
    best_clf: LogisticRegression | None = None
    best_C: float | None = None

    print("\n=== Busca do hiperparâmetro C ===")
    for C in [0.03, 0.05, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0]:
        classifier = LogisticRegression(
            random_state=random_state,
            max_iter=4000,
            solver="lbfgs",
            class_weight="balanced",
            C=C,
        )
        classifier.fit(X_train_s, y_train)
        prediction = classifier.predict(X_test_s)
        candidate_acc = accuracy_score(y_test, prediction)
        print(f"C={C:.2f} -> acc={candidate_acc:.4f}")

        if candidate_acc > best_acc:
            best_acc = candidate_acc
            best_clf = classifier
            best_C = C

    if best_clf is None or best_C is None:
        raise RuntimeError("Não foi possível treinar um classificador válido.")

    y_pred_float = best_clf.predict(X_test_s)
    acc_float = accuracy_score(y_test, y_pred_float)

    print(f"\nMelhor C linear: {best_C}")
    print("\n=== Relatório de classificação em ponto flutuante ===")
    print(
        classification_report(
            y_test,
            y_pred_float,
            labels=[0, 1],
            target_names=CLASS_NAMES,
            digits=4,
            zero_division=0,
        )
    )
    print("Acurácia float:", round(acc_float, 4))
    print(
        "Matriz de confusão float:\n",
        confusion_matrix(y_test, y_pred_float, labels=[0, 1]),
    )

    feature_dim = X_train_s.shape[1]
    W_pad = np.zeros((feature_dim, 4), dtype=np.float64)
    B_pad = np.zeros(4, dtype=np.float64)

    # Para LogisticRegression binária, coef_[0] representa a classe 1 (green).
    # O firmware compara score_green (byte 0) com score_red (byte 1).
    if best_clf.coef_.shape[0] == 1:
        W_pad[:, 0] = best_clf.coef_[0]
        B_pad[0] = best_clf.intercept_[0]
    else:
        W_pad[:, :2] = best_clf.coef_.T
        B_pad[:2] = best_clf.intercept_

    max_abs = max(
        float(np.max(np.abs(W_pad))),
        float(np.max(np.abs(X_test_s))),
    )
    input_quant_scale = 127.0 / max_abs if max_abs != 0.0 else 1.0

    W_int = clamp_int8_array(W_pad * input_quant_scale)
    X_test_int = clamp_int8_array(X_test_s * input_quant_scale)
    B_int = np.round(B_pad * input_quant_scale * input_quant_scale).astype(np.int32)

    y_pred_quantized = predict_quantized_labels(X_test_int, W_int, B_int)
    acc_quantized = accuracy_score(y_test, y_pred_quantized)

    print("\n=== Validação do modelo quantizado ===")
    print("Acurácia quantizada:", round(acc_quantized, 4))
    print(
        "Matriz de confusão quantizada:\n",
        confusion_matrix(y_test, y_pred_quantized, labels=[0, 1]),
    )

    scores_green = X_test_int @ W_int[:, 0] + B_int[0]
    scores_red = X_test_int @ W_int[:, 1] + B_int[1]
    absolute_scores = np.abs(np.concatenate([scores_green, scores_red]))

    calib_acc_ref = float(np.percentile(absolute_scores, 99.0))
    if calib_acc_ref < 1.0:
        calib_acc_ref = float(np.max(absolute_scores))
    if calib_acc_ref < 1.0:
        calib_acc_ref = 1.0

    quant_cfg = 16
    quant_mult = int(round((127.0 / calib_acc_ref) * (1 << quant_cfg) * 0.85))
    quant_mult = max(1, min(quant_mult, 0xFFFFFFFF))

    print("\n=== Recalibração da saída da NPU ===")
    print("percentil 99 |acc|:", round(calib_acc_ref, 2))
    print("quant_mult recalibrado:", quant_mult)
    print("quant_cfg:", hex(quant_cfg))
    print("input_quant_scale:", input_quant_scale)

    return ExportBundle(
        W_int=W_int,
        B_int=B_int,
        X_test_int=X_test_int,
        y_test=y_test,
        quant_mult=quant_mult,
        quant_cfg=quant_cfg,
        feature_dim=feature_dim,
        n_words=feature_dim,
        acc_float=float(acc_float),
        acc_quantized=float(acc_quantized),
        best_C=float(best_C),
        calib_acc_ref=calib_acc_ref,
        scaler_mean=scaler.mean_.astype(np.float32),
        scaler_scale=scaler.scale_.astype(np.float32),
        input_quant_scale=float(input_quant_scale),
    )


# -----------------------------------------------------------------------------
# Exportações
# -----------------------------------------------------------------------------

def emit_model_header(
    bundle: ExportBundle,
    out_path: Path,
    num_samples: int = 8,
    embed_preprocess: bool = False,
) -> None:
    if num_samples < 0:
        raise ValueError("--samples não pode ser negativo.")

    num_samples = min(num_samples, len(bundle.X_test_int))
    lines: List[str] = []

    lines.append("#ifndef TRAFFIC_LIGHT_MODEL_H")
    lines.append("#define TRAFFIC_LIGHT_MODEL_H")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("// Gerado automaticamente por train_traffic_light_export_v5.py")
    lines.append(f"// best_C = {bundle.best_C}")
    lines.append(f"// accuracy_float = {bundle.acc_float}")
    lines.append(f"// accuracy_quantized = {bundle.acc_quantized}")
    lines.append(f"// calib_acc_ref_p99 = {bundle.calib_acc_ref}")
    lines.append(f"#define TL_NUM_CLASSES 2u")
    lines.append(f"#define TL_FEATURE_DIM {bundle.feature_dim}u")
    lines.append(f"#define TL_K_DIM {bundle.n_words}u")
    lines.append(f"#define TL_QUANT_CFG  0x{bundle.quant_cfg:08X}u")
    lines.append(f"#define TL_QUANT_MULT 0x{bundle.quant_mult:08X}u")
    lines.append(f"#define TL_NUM_TEST_SAMPLES {num_samples}u")
    lines.append("")

    lines.append("static const int32_t tl_bias[4] = {")
    for index, bias in enumerate(bundle.B_int):
        comma = "," if index < 3 else ""
        lines.append(f"    {int(bias)}{comma}")
    lines.append("};")
    lines.append("")

    lines.append("static const uint32_t tl_weights[TL_K_DIM] = {")
    for k in range(bundle.feature_dim):
        word = pack_int8(bundle.W_int[k, :].tolist())
        comma = "," if k < bundle.feature_dim - 1 else ""
        lines.append(f"    0x{word:08X}u{comma}")
    lines.append("};")
    lines.append("")

    if num_samples > 0:
        lines.append(
            "static const uint32_t tl_inputs[TL_NUM_TEST_SAMPLES][TL_K_DIM] = {"
        )
        for sample_index in range(num_samples):
            lines.append("    {")
            sample = bundle.X_test_int[sample_index]
            for k in range(bundle.feature_dim):
                word = pack_int8([int(sample[k]), 0, 0, 0])
                comma = "," if k < bundle.feature_dim - 1 else ""
                lines.append(f"        0x{word:08X}u{comma}")
            comma_end = "," if sample_index < num_samples - 1 else ""
            lines.append(f"    }}{comma_end}")
        lines.append("};")
        lines.append("")

        label_names = ", ".join(f'\"{name}\"' for name in CLASS_NAMES)
        lines.append(
            "static const char * const tl_class_names[TL_NUM_CLASSES] = "
            f"{{{label_names}}};"
        )
        lines.append("")

        lines.append(
            "static const uint8_t tl_expected_labels[TL_NUM_TEST_SAMPLES] = {"
        )
        for index in range(num_samples):
            comma = "," if index < num_samples - 1 else ""
            lines.append(f"    {int(bundle.y_test[index])}{comma}")
        lines.append("};")
        lines.append("")

    if embed_preprocess:
        lines.append("// Parâmetros para pré-processamento em software externo.")
        lines.append(
            f"#define TL_INPUT_QUANT_SCALE {bundle.input_quant_scale:.9f}f"
        )
        lines.append("")

        lines.append("static const float tl_scaler_mean[TL_FEATURE_DIM] = {")
        for index, value in enumerate(bundle.scaler_mean):
            comma = "," if index < bundle.feature_dim - 1 else ""
            lines.append(f"    {float(value):.9g}f{comma}")
        lines.append("};")
        lines.append("")

        lines.append("static const float tl_scaler_scale[TL_FEATURE_DIM] = {")
        for index, value in enumerate(bundle.scaler_scale):
            comma = "," if index < bundle.feature_dim - 1 else ""
            lines.append(f"    {float(value):.9g}f{comma}")
        lines.append("};")
        lines.append("")

    lines.append("#endif")
    lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nHeader do modelo gerado em: {out_path}")


def emit_preprocess_json(bundle: ExportBundle, out_path: Path) -> None:
    data = {
        "format_version": 5,
        "class_names": CLASS_NAMES,
        "class_to_id": CLASS_TO_ID,
        "image_size": {
            "width": FEATURE_IMAGE_SIZE[0],
            "height": FEATURE_IMAGE_SIZE[1],
        },
        "central_crop_frac_w": CENTRAL_CROP_FRAC_W,
        "feature_dim": bundle.feature_dim,
        "scaler_mean": [float(v) for v in bundle.scaler_mean],
        "scaler_scale": [float(v) for v in bundle.scaler_scale],
        "input_quant_scale": bundle.input_quant_scale,
        "quantization": {
            "rounding": "numpy_round",
            "minimum": -128,
            "maximum": 127,
            "uart_encoding": "int8 represented as one unsigned byte",
        },
        "npu_output": {
            "quant_cfg": bundle.quant_cfg,
            "quant_mult": bundle.quant_mult,
            "score_green_byte": 0,
            "score_red_byte": 1,
            "prediction_rule": "green_score > red_score => class 1, otherwise class 0",
        },
        "training": {
            "best_C": bundle.best_C,
            "accuracy_float": bundle.acc_float,
            "accuracy_quantized": bundle.acc_quantized,
            "calib_acc_ref_p99": bundle.calib_acc_ref,
        },
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Pré-processamento gerado em: {out_path}")


def emit_uart_sample_hex(
    bundle: ExportBundle,
    out_path: Path,
    sample_index: int,
) -> None:
    if not 0 <= sample_index < len(bundle.X_test_int):
        raise IndexError(
            f"Amostra {sample_index} inválida. Faixa disponível: "
            f"0..{len(bundle.X_test_int) - 1}."
        )

    sample = bundle.X_test_int[sample_index].astype(np.int8)
    lines = [f"{int(value) & 0xFF:02X}" for value in sample]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"Amostra UART gerada em: {out_path}")
    print(
        f"Label esperado da amostra {sample_index}: "
        f"{int(bundle.y_test[sample_index])} "
        f"({CLASS_NAMES[int(bundle.y_test[sample_index])]})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Treina e exporta o modelo de semáforo para PicoRV32 + NPU."
    )
    parser.add_argument("--dataset", required=True, type=Path)
    parser.add_argument(
        "--out",
        default=Path("traffic_light_model.h"),
        type=Path,
        help="Header C usado pelo firmware.",
    )
    parser.add_argument(
        "--preprocess-out",
        default=Path("traffic_light_preprocess.json"),
        type=Path,
        help="JSON usado pelo programa externo que envia imagens pela UART.",
    )
    parser.add_argument(
        "--samples",
        default=8,
        type=int,
        help="Quantidade de amostras de teste embutidas no header. Use 0 no firmware dinâmico.",
    )
    parser.add_argument("--test-size", default=0.25, type=float)
    parser.add_argument("--random-state", default=42, type=int)
    parser.add_argument(
        "--embed-preprocess",
        action="store_true",
        help=(
            "Inclui média, desvio e escala float no header. Não recomendado para "
            "o firmware atual por aumentar o tamanho do firmware.hex."
        ),
    )
    parser.add_argument(
        "--uart-sample-out",
        type=Path,
        default=None,
        help="Opcional: gera um arquivo HEX com uma amostra quantizada para a testbench UART.",
    )
    parser.add_argument(
        "--uart-sample-index",
        type=int,
        default=0,
        help="Índice da amostra usada por --uart-sample-out.",
    )

    args = parser.parse_args()

    bundle = train_and_quantize(
        args.dataset,
        test_size=args.test_size,
        random_state=args.random_state,
    )

    emit_model_header(
        bundle,
        args.out,
        num_samples=args.samples,
        embed_preprocess=args.embed_preprocess,
    )
    emit_preprocess_json(bundle, args.preprocess_out)

    if args.uart_sample_out is not None:
        emit_uart_sample_hex(
            bundle,
            args.uart_sample_out,
            args.uart_sample_index,
        )

    if args.samples > 0:
        estimated_sample_bytes = args.samples * bundle.feature_dim * 4
        print(
            "\nAviso: as amostras embutidas ocupam aproximadamente "
            f"{estimated_sample_bytes} bytes no header antes das otimizações do linker."
        )
        print(
            "Para o firmware UART dinâmico, prefira --samples 0 e use "
            "--uart-sample-out para a testbench."
        )


if __name__ == "__main__":
    main()
