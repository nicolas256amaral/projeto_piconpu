#include "soc.h"
#include "traffic_light_model.h"
#include <stdint.h>

volatile uint32_t tl_out_words[4];
volatile int32_t  tl_score_red;
volatile int32_t  tl_score_green;
volatile uint32_t tl_predicted_label;
volatile uint32_t tl_model_initialized;

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

/*
 * Carrega na NPU tudo o que pertence ao MODELO e nao muda entre imagens:
 * configuracao, requantizacao, bias e pesos.
 *
 * Esta funcao deve ser chamada uma unica vez apos o boot (ou novamente apenas
 * se a NPU/modelo for resetado/trocado).
 */
void tl_init_model(void)
{
    tl_model_initialized = 0u;

    /* NPU precisa estar IDLE para aceitar as escritas MMIO. */
    while ((npu_status() & NPU_STS_BUSY) != 0u) {
    }

    /* Reinicia os ponteiros de escrita antes da carga inicial do modelo. */
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
    }

    tl_model_initialized = 1u;
}

void tl_run_features(const uint8_t features[])
{
    tl_score_red       = 0;
    tl_score_green     = 0;
    tl_predicted_label = 0u;

    /*
     * Protecao adicional: no fluxo UART normal, main() chama tl_init_model()
     * antes de aguardar a primeira imagem. Caso esta funcao seja chamada
     * diretamente, garante que o modelo esteja carregado.
     */
    if (tl_model_initialized == 0u) {
        tl_init_model();
    }

    /*
     * Nova imagem: preserva pesos/bias/configuracoes e reinicia SOMENTE o
     * ponteiro de escrita da RAM de entradas.
     */
    mmio_write32(NPU_CMD, NPU_CMD_RST_I_WR);

    for (uint32_t i = 0u; i < TL_K_DIM; i++) {
        npu_write_input((uint32_t)features[i]);
    }

    /*
     * Para cada inferencia, os ponteiros de LEITURA voltam ao inicio e os
     * acumuladores sao limpos. Isso nao apaga os pesos armazenados.
     */
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
