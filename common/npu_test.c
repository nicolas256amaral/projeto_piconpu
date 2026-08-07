#include "soc.h"
#include "traffic_light_model.h"
#include <stdint.h>

volatile uint32_t tl_out_words[4];
volatile int32_t  tl_score_red;
volatile int32_t  tl_score_green;
volatile uint32_t tl_predicted_label;
volatile uint32_t tl_expected_label_last;
volatile uint32_t tl_last_sample_index;

static int8_t unpack_byte_s8(uint32_t word, uint32_t byte_index)
{
    uint32_t b = (word >> (8u * byte_index)) & 0xFFu;
    return (b & 0x80u) ? (int8_t)(b - 256u) : (int8_t)b;
}

static void tl_decode_scores_from_last_row(uint32_t word)
{
    tl_score_green = unpack_byte_s8(word, 0u);
    tl_score_red   = unpack_byte_s8(word, 1u);
    tl_predicted_label = (tl_score_green > tl_score_red) ? 1u : 0u;
}

void tl_run_features(const uint8_t features[])
{
    tl_score_red       = 0;
    tl_score_green     = 0;
    tl_predicted_label = 0u;

    mmio_write32(NPU_CMD,
                 NPU_CMD_RST_PTRS |
                 NPU_CMD_RST_W_WR |
                 NPU_CMD_RST_I_WR);

    mmio_write32(NPU_CONFIG, TL_K_DIM);
    mmio_write32(NPU_QUANT_CFG, TL_QUANT_CFG);
    mmio_write32(NPU_QUANT_MULT, TL_QUANT_MULT);
    mmio_write32(NPU_CTRL_FLAGS, 0x0u);

    mmio_write32(NPU_BIAS0, (uint32_t)tl_bias[0]);
    mmio_write32(NPU_BIAS1, (uint32_t)tl_bias[1]);
    mmio_write32(NPU_BIAS2, (uint32_t)tl_bias[2]);
    mmio_write32(NPU_BIAS3, (uint32_t)tl_bias[3]);

    for (uint32_t i = 0u; i < TL_K_DIM; i++) {
        npu_write_weight(tl_weights[i]);
        npu_write_input((uint32_t)features[i]);
    }

    npu_start(NPU_CMD_ACC_CLEAR |
              NPU_CMD_RST_W_RD |
              NPU_CMD_RST_I_RD);

    while ((npu_status() & NPU_STS_DONE) == 0u) {
    }

    for (uint32_t i = 0u; i < 4u; i++) {
        while ((npu_status() & NPU_STS_OUT_VALID) == 0u) {
        }
        tl_out_words[i] = npu_read_output();
    }

    tl_decode_scores_from_last_row(tl_out_words[3]);
}

void tl_run_sample(uint32_t sample_idx)
{
    uint8_t features[TL_K_DIM];

    tl_last_sample_index   = sample_idx;
    tl_expected_label_last = tl_expected_labels[sample_idx];

    for (uint32_t i = 0u; i < TL_K_DIM; i++) {
        features[i] = (uint8_t)(tl_inputs[sample_idx][i] & 0xFFu);
    }

    tl_run_features(features);
}

void tl_run_test_suite(void)
{
    for (uint32_t i = 0u; i < TL_NUM_TEST_SAMPLES; i++) {
        tl_run_sample(i);
    }
}
