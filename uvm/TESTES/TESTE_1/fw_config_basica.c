#include <stdint.h>

#define UART_TX    (*(volatile uint32_t*)0x20000000)
#define UART_RX    (*(volatile uint32_t*)0x20000004)
#define UART_STAT  (*(volatile uint32_t*)0x20000008)

#define NPU_STATUS (*(volatile uint32_t*)0x60000000)
#define NPU_CMD    (*(volatile uint32_t*)0x60000004)
#define NPU_CONFIG (*(volatile uint32_t*)0x60000008)
#define NPU_WPORT  (*(volatile uint32_t*)0x60000010)
#define NPU_IPORT  (*(volatile uint32_t*)0x60000014)
#define NPU_ODATA  (*(volatile uint32_t*)0x60000018)
#define NPU_Q_CFG  (*(volatile uint32_t*)0x60000040)
#define NPU_Q_MULT (*(volatile uint32_t*)0x60000044)
#define NPU_CTRL   (*(volatile uint32_t*)0x60000048)
#define NPU_BIAS0  (*(volatile uint32_t*)0x60000080)
#define NPU_BIAS1  (*(volatile uint32_t*)0x60000084)
#define NPU_BIAS2  (*(volatile uint32_t*)0x60000088)
#define NPU_BIAS3  (*(volatile uint32_t*)0x6000008C)

void uart_send(uint8_t d) {
    while(!(UART_STAT & 0x1)); // Espera o bit 0 (!busy) ser 1
    UART_TX = d;
}

uint8_t uart_recv() {
    while(!(UART_STAT & 0x2)); // Espera o bit 1 (rx_valid) ser 1
    return UART_RX & 0xFF;
}

void print_msg(const char* str) {
    while(*str) {
        uart_send(*str++);
    }
}

// ---- NOVA FUNÇÃO DE LEITURA SEGURA ----
uint32_t read_fifo() {
    // Trava até a FIFO garantir que tem um dado pronto (Bit 3 = 1)
    while(!(NPU_STATUS & 0x08)); 
    return NPU_ODATA;
}
// ---------------------------------------

// ================= TESTE 1 =================
void setup_npu() {
    NPU_CONFIG = 4;
    NPU_Q_CFG  = 0;
    NPU_Q_MULT = 1;
    NPU_CTRL   = 0;  // ReLU = 0
    NPU_BIAS0  = 0;  // Bias = 0
    NPU_BIAS1  = 0;
    NPU_BIAS2  = 0;
    NPU_BIAS3  = 0;
}

int main() {
    
    print_msg("SOC IOT PICORV32");
    setup_npu();

    while(1) {
        if (uart_recv() == 0x46) { // CMD NPU
            
            // 1. Reseta os ponteiros de ESCRITA da RAM antes de injetar novos dados (Bit 0 = 1)
            NPU_CMD = 0x01; 

            for(int i=0; i<4; i++) {
                uint32_t w = 0;
                w |= uart_recv(); w |= (uart_recv()<<8); w |= (uart_recv()<<16); w |= (uart_recv()<<24);
                NPU_WPORT = w;
            }
            
            for(int i=0; i<4; i++) {
                uint32_t a = 0;
                a |= uart_recv(); a |= (uart_recv()<<8); a |= (uart_recv()<<16); a |= (uart_recv()<<24);
                NPU_IPORT = a;
            }

            // 2. Aciona o START(2), ACC_CLEAR(4) e Reseta os ponteiros de LEITURA (16 + 32)
            // 2 + 4 + 16 + 32 = 54 (0x36 em HEX)
            NPU_CMD = 0x36; 
            
            while(!(NPU_STATUS & 0x2)); // Espera a NPU terminar de calcular

            uint32_t out_row3 = read_fifo(); 
            uint32_t drop1    = read_fifo(); 
            uint32_t drop2    = read_fifo(); 
            uint32_t drop3    = read_fifo(); 
            uint32_t drop4    = read_fifo(); 
            uint32_t drop5    = read_fifo();

            uart_send(out_row3 & 0xFF);
            uart_send((out_row3 >> 8) & 0xFF);
            uart_send((out_row3 >> 16) & 0xFF);
            uart_send((out_row3 >> 24) & 0xFF);
        }
    }
    return 0;
}