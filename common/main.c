#include "npu_test.h"
#include "soc.h"
#include "traffic_light_model.h"
#include <stdint.h>

#define UART_RX_SYNC       0xA5u
#define UART_RX_CMD_INFER  0x01u
#define UART_TX_SYNC       0x5Au

#define UART_RESP_OK       0x00u
#define UART_RESP_BAD_CMD  0x01u
#define UART_RESP_BAD_LEN  0x02u
#define UART_RESP_BAD_CSUM 0x03u

static uint8_t checksum_add(uint8_t checksum, uint8_t value)
{
    return (uint8_t)(checksum ^ value);
}

static void uart_send_response(uint8_t sample_id, uint8_t status)
{
    uint8_t prediction = (uint8_t)tl_predicted_label;
    uint8_t red        = (uint8_t)(int8_t)tl_score_red;
    uint8_t green      = (uint8_t)(int8_t)tl_score_green;
    uint8_t checksum   = 0u;

    uart_write_byte_blocking(UART_TX_SYNC);

    uart_write_byte_blocking(sample_id);
    checksum = checksum_add(checksum, sample_id);

    uart_write_byte_blocking(status);
    checksum = checksum_add(checksum, status);

    uart_write_byte_blocking(prediction);
    checksum = checksum_add(checksum, prediction);

    uart_write_byte_blocking(red);
    checksum = checksum_add(checksum, red);

    uart_write_byte_blocking(green);
    checksum = checksum_add(checksum, green);

    uart_write_byte_blocking(checksum);
}

int main(void)
{
    uint8_t features[TL_K_DIM];

    /*
     * Carrega o modelo UMA VEZ apos o boot, antes de aguardar a primeira
     * imagem pela UART. Pesos, bias e parametros permanecem na NPU.
     */
    tl_init_model();

    for (;;) {
        uint8_t byte;
        uint8_t command;
        uint8_t sample_id;
        uint8_t length;
        uint8_t checksum;
        uint8_t received_checksum;

        do {
            byte = uart_read_byte_blocking();
        } while (byte != UART_RX_SYNC);

        command   = uart_read_byte_blocking();
        sample_id = uart_read_byte_blocking();
        length    = uart_read_byte_blocking();

        checksum = 0u;
        checksum = checksum_add(checksum, command);
        checksum = checksum_add(checksum, sample_id);
        checksum = checksum_add(checksum, length);

        if (command != UART_RX_CMD_INFER) {
            for (uint32_t i = 0u; i < (uint32_t)length; i++) {
                byte = uart_read_byte_blocking();
                checksum = checksum_add(checksum, byte);
            }
            received_checksum = uart_read_byte_blocking();
            (void)received_checksum;
            uart_send_response(sample_id, UART_RESP_BAD_CMD);
            continue;
        }

        if (length != (uint8_t)TL_K_DIM) {
            for (uint32_t i = 0u; i < (uint32_t)length; i++) {
                byte = uart_read_byte_blocking();
                checksum = checksum_add(checksum, byte);
            }
            received_checksum = uart_read_byte_blocking();
            (void)received_checksum;
            uart_send_response(sample_id, UART_RESP_BAD_LEN);
            continue;
        }

        for (uint32_t i = 0u; i < TL_K_DIM; i++) {
            features[i] = uart_read_byte_blocking();
            checksum = checksum_add(checksum, features[i]);
        }

        received_checksum = uart_read_byte_blocking();
        if (received_checksum != checksum) {
            uart_send_response(sample_id, UART_RESP_BAD_CSUM);
            continue;
        }

        // A amostra recebida pela UART já está em 'features'.
        // Não é mais necessário guardar sample_id em variável global de teste.
        tl_run_features(features);
        uart_send_response(sample_id, UART_RESP_OK);
    }
}