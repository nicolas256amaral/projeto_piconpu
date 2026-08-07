"""
image_to_uart_features.py

Seleciona uma imagem do computador, aplica exatamente o pré-processamento
descrito em traffic_light_preprocess.json e gera:

1. uart_sample.hex
   - somente as 63 features quantizadas, uma por linha;
   - formato usado pela testbench que já monta o cabeçalho UART.

2. uart_packet.hex
   - pacote UART completo:
       A5 01 SAMPLE_ID 3F <63 features> CHECKSUM
   - checksum = XOR de VERSION, SAMPLE_ID, LENGTH e FEATURES.
   - o byte de sincronismo A5 não participa do checksum.

Dependências:
    pip install numpy opencv-python
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np


EXPECTED_FEATURE_DIM = 63
DEFAULT_SYNC = 0xA5
DEFAULT_VERSION = 0x01


def choose_image_with_dialog() -> Path:
    """Abre uma janela do Windows para selecionar a imagem."""
    try:
        import tkinter as tk
        from tkinter import filedialog
    except ImportError as exc:
        raise RuntimeError(
            "Tkinter não está disponível. Informe a imagem com --image."
        ) from exc

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    selected = filedialog.askopenfilename(
        title="Selecione a imagem do semáforo",
        filetypes=[
            ("Imagens", "*.jpg *.jpeg *.png *.bmp *.webp"),
            ("Todos os arquivos", "*.*"),
        ],
    )
    root.destroy()

    if not selected:
        raise RuntimeError("Nenhuma imagem foi selecionada.")

    return Path(selected)


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"JSON não encontrado: {path}")

    with path.open("r", encoding="utf-8") as file:
        config = json.load(file)

    required = [
        "image_size",
        "central_crop_frac_w",
        "feature_dim",
        "scaler_mean",
        "scaler_scale",
        "input_quant_scale",
    ]
    missing = [name for name in required if name not in config]
    if missing:
        raise ValueError(f"Campos ausentes no JSON: {', '.join(missing)}")

    if int(config["feature_dim"]) != EXPECTED_FEATURE_DIM:
        raise ValueError(
            f"feature_dim={config['feature_dim']}; esperado {EXPECTED_FEATURE_DIM}."
        )

    mean = np.asarray(config["scaler_mean"], dtype=np.float32)
    scale = np.asarray(config["scaler_scale"], dtype=np.float32)

    if mean.shape != (EXPECTED_FEATURE_DIM,):
        raise ValueError(f"scaler_mean possui formato inválido: {mean.shape}")
    if scale.shape != (EXPECTED_FEATURE_DIM,):
        raise ValueError(f"scaler_scale possui formato inválido: {scale.shape}")
    if np.any(scale == 0):
        raise ValueError("scaler_scale contém valor zero.")

    return config


def load_image(path: Path, width: int, height: int) -> np.ndarray:
    if not path.exists():
        raise FileNotFoundError(f"Imagem não encontrada: {path}")

    image_bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise ValueError(f"O OpenCV não conseguiu ler a imagem: {path}")

    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    return cv2.resize(
        image_rgb,
        (width, height),
        interpolation=cv2.INTER_AREA,
    )


def central_crop(image_rgb: np.ndarray, frac_w: float) -> np.ndarray:
    _, width, _ = image_rgb.shape
    crop_width = max(4, int(width * frac_w))
    x0 = (width - crop_width) // 2
    return image_rgb[:, x0 : x0 + crop_width]


def normalize_lighting(image_rgb: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2HSV)
    hue, saturation, value = cv2.split(hsv)

    clahe = cv2.createCLAHE(
        clipLimit=2.0,
        tileGridSize=(4, 4),
    )
    value_normalized = clahe.apply(value)

    hsv_normalized = cv2.merge([hue, saturation, value_normalized])
    return cv2.cvtColor(hsv_normalized, cv2.COLOR_HSV2RGB)


def red_green_masks(region_rgb: np.ndarray):
    hsv = cv2.cvtColor(region_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV)

    red_low = cv2.inRange(hsv, (0, 80, 60), (12, 255, 255))
    red_high = cv2.inRange(hsv, (165, 80, 60), (179, 255, 255))
    red_mask = cv2.bitwise_or(red_low, red_high) > 0

    green_mask = (
        cv2.inRange(hsv, (35, 50, 50), (95, 255, 255)) > 0
    )

    return red_mask, green_mask, hsv


def region_stats(region_rgb: np.ndarray) -> list[float]:
    red_mask, green_mask, hsv = red_green_masks(region_rgb)

    red = region_rgb[:, :, 0].astype(np.float32)
    green = region_rgb[:, :, 1].astype(np.float32)
    blue = region_rgb[:, :, 2].astype(np.float32)

    rgb_sum = red + green + blue + 1.0
    red_norm = red / rgb_sum
    green_norm = green / rgb_sum

    red_ratio = float(red_mask.mean()) * 255.0
    green_ratio = float(green_mask.mean()) * 255.0

    red_strength = float(red[red_mask].mean()) if red_mask.any() else 0.0
    green_strength = (
        float(green[green_mask].mean()) if green_mask.any() else 0.0
    )

    red_peak = float(red.max())
    green_peak = float(green.max())

    if red_mask.any():
        red_y, _ = np.where(red_mask)
        red_center_y = float(red_y.mean()) / max(1, region_rgb.shape[0] - 1)
    else:
        red_center_y = 0.0

    if green_mask.any():
        green_y, _ = np.where(green_mask)
        green_center_y = (
            float(green_y.mean()) / max(1, region_rgb.shape[0] - 1)
        )
    else:
        green_center_y = 0.0

    return [
        float(red.mean()),
        float(green.mean()),
        float(blue.mean()),
        float(red_norm.mean()),
        float(green_norm.mean()),
        float((red - green).mean()),
        float((green - red).mean()),
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


def extract_features(
    image_rgb: np.ndarray,
    crop_fraction: float,
) -> np.ndarray:
    image = central_crop(image_rgb, crop_fraction)
    image = normalize_lighting(image)

    height = image.shape[0]
    top = image[0 : height // 3]
    middle = image[height // 3 : 2 * height // 3]
    bottom = image[2 * height // 3 : height]

    top_features = region_stats(top)
    middle_features = region_stats(middle)
    bottom_features = region_stats(bottom)

    features: list[float] = []
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

    red_mask, green_mask, _ = red_green_masks(image)
    features.extend(
        [
            float(red_mask.mean()) * 255.0,
            float(green_mask.mean()) * 255.0,
            float(
                image[:, :, 0].mean()
                / (image[:, :, 1].mean() + 1.0)
            ),
            float(
                image[:, :, 1].mean()
                / (image[:, :, 0].mean() + 1.0)
            ),
        ]
    )

    result = np.asarray(features, dtype=np.float32)
    if result.shape != (EXPECTED_FEATURE_DIM,):
        raise RuntimeError(
            f"Foram extraídas {result.size} features; esperado "
            f"{EXPECTED_FEATURE_DIM}."
        )

    if not np.isfinite(result).all():
        raise RuntimeError("As features extraídas contêm NaN ou infinito.")

    return result


def quantize_features(
    raw_features: np.ndarray,
    config: dict[str, Any],
) -> np.ndarray:
    mean = np.asarray(config["scaler_mean"], dtype=np.float32)
    std = np.asarray(config["scaler_scale"], dtype=np.float32)
    quant_scale = float(config["input_quant_scale"])

    standardized = (raw_features - mean) / std
    quantized = np.clip(
        np.round(standardized * quant_scale),
        -128,
        127,
    ).astype(np.int8)

    return quantized


def calculate_request_checksum(
    version: int,
    sample_id: int,
    features: np.ndarray,
) -> int:
    """
    XOR usado pelo protocolo atual:
        VERSION ^ SAMPLE_ID ^ LENGTH ^ feature[0] ... feature[62]

    SYNC não participa do checksum.
    """
    checksum = 0
    checksum ^= version & 0xFF
    checksum ^= sample_id & 0xFF
    checksum ^= len(features) & 0xFF

    for value in features:
        checksum ^= int(value) & 0xFF

    return checksum & 0xFF


def write_hex(path: Path, values: list[int] | np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as file:
        for value in values:
            file.write(f"{int(value) & 0xFF:02X}\n")


def write_debug_report(
    path: Path,
    image_path: Path,
    raw_features: np.ndarray,
    quantized: np.ndarray,
    packet: list[int],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        f"image={image_path.resolve()}",
        f"feature_count={len(quantized)}",
        f"feature_min={int(quantized.min())}",
        f"feature_max={int(quantized.max())}",
        f"sync=0x{packet[0]:02X}",
        f"version=0x{packet[1]:02X}",
        f"sample_id={packet[2]}",
        f"length={packet[3]}",
        f"checksum=0x{packet[-1]:02X}",
        "",
        "index,raw_feature,quantized_int8,uart_byte",
    ]

    for index, (raw, quantized_value) in enumerate(
        zip(raw_features, quantized)
    ):
        lines.append(
            f"{index},{float(raw):.9f},"
            f"{int(quantized_value)},"
            f"0x{int(quantized_value) & 0xFF:02X}"
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Converte uma imagem nova nas 63 features quantizadas usadas "
            "pela NPU e gera arquivos HEX para a testbench/UART."
        )
    )
    parser.add_argument(
        "--image",
        type=Path,
        help=(
            "Imagem a processar. Quando omitido, abre uma janela "
            "para seleção."
        ),
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("traffic_light_preprocess.json"),
        help="JSON de pré-processamento gerado pelo train v5.",
    )
    parser.add_argument(
        "--sample-id",
        type=int,
        default=0,
        help="Identificador de 0 a 255 enviado no pacote UART.",
    )
    parser.add_argument(
        "--sample-out",
        type=Path,
        default=Path("uart_sample.hex"),
        help="Saída contendo somente as 63 features.",
    )
    parser.add_argument(
        "--packet-out",
        type=Path,
        default=Path("uart_packet.hex"),
        help="Saída contendo o pacote UART completo.",
    )
    parser.add_argument(
        "--report-out",
        type=Path,
        default=Path("uart_image_report.csv"),
        help="Relatório das features brutas e quantizadas.",
    )
    args = parser.parse_args()

    if not 0 <= args.sample_id <= 255:
        parser.error("--sample-id deve estar entre 0 e 255.")

    try:
        image_path = args.image or choose_image_with_dialog()
        config = load_config(args.config)

        width = int(config["image_size"]["width"])
        height = int(config["image_size"]["height"])
        crop_fraction = float(config["central_crop_frac_w"])

        image = load_image(image_path, width, height)
        raw_features = extract_features(image, crop_fraction)
        quantized = quantize_features(raw_features, config)

        feature_bytes = [int(value) & 0xFF for value in quantized]
        checksum = calculate_request_checksum(
            DEFAULT_VERSION,
            args.sample_id,
            quantized,
        )

        packet = [
            DEFAULT_SYNC,
            DEFAULT_VERSION,
            args.sample_id,
            len(feature_bytes),
            *feature_bytes,
            checksum,
        ]

        write_hex(args.sample_out, feature_bytes)
        write_hex(args.packet_out, packet)
        write_debug_report(
            args.report_out,
            image_path,
            raw_features,
            quantized,
            packet,
        )

        class_names = config.get("class_names", ["red", "green"])

        print("\nConversão concluída.")
        print(f"Imagem:            {image_path.resolve()}")
        print(f"Features geradas:  {len(feature_bytes)}")
        print(f"Intervalo int8:    {int(quantized.min())} a {int(quantized.max())}")
        print(f"Checksum:          0x{checksum:02X}")
        print(f"Amostra HEX:       {args.sample_out.resolve()}")
        print(f"Pacote UART HEX:   {args.packet_out.resolve()}")
        print(f"Relatório:         {args.report_out.resolve()}")
        print(
            "Classes do modelo: "
            + ", ".join(
                f"{index}={name}" for index, name in enumerate(class_names)
            )
        )

        return 0

    except Exception as exc:
        print(f"\nERRO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
