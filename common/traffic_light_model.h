#ifndef TRAFFIC_LIGHT_MODEL_H
#define TRAFFIC_LIGHT_MODEL_H

#include <stdint.h>

// Gerado automaticamente por train_traffic_light_export_v6.py
// Contém somente parâmetros do modelo; entradas chegam pela UART.
// best_C = 0.03
// accuracy_float = 0.99644128113879
// accuracy_quantized = 1.0
// calib_acc_ref_p99 = 461.39
#define TL_NUM_CLASSES 2u
#define TL_FEATURE_DIM 63u
#define TL_K_DIM 63u
#define TL_QUANT_CFG  0x00000010u
#define TL_QUANT_MULT 0x00003BE5u

static const int32_t tl_bias[4] = {
    22,
    0,
    0,
    0
};

static const uint32_t tl_weights[TL_K_DIM] = {
    0x000000FFu,
    0x000000FFu,
    0x000000FFu,
    0x000000FFu,
    0x00000001u,
    0x000000FFu,
    0x00000001u,
    0x000000FFu,
    0x00000000u,
    0x000000FEu,
    0x00000000u,
    0x000000FFu,
    0x00000000u,
    0x000000FFu,
    0x00000000u,
    0x000000FFu,
    0x000000FFu,
    0x00000000u,
    0x00000001u,
    0x00000000u,
    0x00000000u,
    0x00000001u,
    0x000000FFu,
    0x00000001u,
    0x000000FFu,
    0x00000000u,
    0x000000FFu,
    0x00000001u,
    0x00000000u,
    0x00000000u,
    0x00000000u,
    0x00000001u,
    0x00000000u,
    0x00000000u,
    0x000000FFu,
    0x00000000u,
    0x000000FFu,
    0x000000FFu,
    0x00000001u,
    0x000000FFu,
    0x00000001u,
    0x00000000u,
    0x00000001u,
    0x00000000u,
    0x00000001u,
    0x000000FFu,
    0x00000000u,
    0x00000000u,
    0x00000001u,
    0x00000001u,
    0x00000000u,
    0x000000FFu,
    0x000000FFu,
    0x000000FFu,
    0x000000FFu,
    0x000000FEu,
    0x000000FFu,
    0x00000001u,
    0x00000000u,
    0x000000FFu,
    0x00000001u,
    0x000000FFu,
    0x00000001u
};

static const char * const tl_class_names[TL_NUM_CLASSES] = {"red", "green"};

#endif
