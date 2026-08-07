#pragma once
#include <stdint.h>

#define RAM_BASE   0x00000000u
#define RAM_SIZE   0x00004000u  /* 16 KiB */
#define RAM_END    (RAM_BASE + RAM_SIZE - 1u)
#define GPIO_BASE  0x10000000u
#define UART_BASE  0x20000000u
#define SPI_BASE   0x30000000u
#define I2C_BASE   0x40000000u
#define TIMER_BASE 0x50000000u
#define NPU_BASE   0x60000000u

static inline void mmio_write32(uint32_t addr, uint32_t value){
    *(volatile uint32_t*)addr = value;
}

static inline uint32_t mmio_read32(uint32_t addr){
    return *(volatile uint32_t*)addr;
}

/* UART application registers */
#define UART_TX_DATA (UART_BASE + 0x00u)
#define UART_RX_DATA (UART_BASE + 0x04u)
#define UART_STATUS  (UART_BASE + 0x08u)

#define UART_STS_TX_READY (1u << 0)
#define UART_STS_RX_VALID (1u << 1)

static inline uint32_t uart_status(void){
    return mmio_read32(UART_STATUS);
}

static inline uint8_t uart_read_byte_blocking(void){
    while ((uart_status() & UART_STS_RX_VALID) == 0u) {
    }
    return (uint8_t)mmio_read32(UART_RX_DATA);
}

static inline void uart_write_byte_blocking(uint8_t value){
    while ((uart_status() & UART_STS_TX_READY) == 0u) {
    }
    mmio_write32(UART_TX_DATA, (uint32_t)value);
}

/* NPU offsets */
#define NPU_STATUS       (NPU_BASE + 0x00u)
#define NPU_CMD          (NPU_BASE + 0x04u)
#define NPU_CONFIG       (NPU_BASE + 0x08u)
#define NPU_W_PORT       (NPU_BASE + 0x10u)
#define NPU_I_PORT       (NPU_BASE + 0x14u)
#define NPU_O_DATA       (NPU_BASE + 0x18u)

#define NPU_QUANT_CFG    (NPU_BASE + 0x40u)
#define NPU_QUANT_MULT   (NPU_BASE + 0x44u)
#define NPU_CTRL_FLAGS   (NPU_BASE + 0x48u)

#define NPU_BIAS0        (NPU_BASE + 0x80u)
#define NPU_BIAS1        (NPU_BASE + 0x84u)
#define NPU_BIAS2        (NPU_BASE + 0x88u)
#define NPU_BIAS3        (NPU_BASE + 0x8Cu)

#define NPU_STS_BUSY         (1u << 0)
#define NPU_STS_DONE         (1u << 1)
#define NPU_STS_OUT_VALID    (1u << 3)

#define NPU_CMD_RST_PTRS     (1u << 0)
#define NPU_CMD_START        (1u << 1)
#define NPU_CMD_ACC_CLEAR    (1u << 2)
#define NPU_CMD_NO_DRAIN     (1u << 3)
#define NPU_CMD_RST_W_RD     (1u << 4)
#define NPU_CMD_RST_I_RD     (1u << 5)
#define NPU_CMD_RST_W_WR     (1u << 6)
#define NPU_CMD_RST_I_WR     (1u << 7)

static inline void npu_write_weight(uint32_t w){
    mmio_write32(NPU_W_PORT, w);
}

static inline void npu_write_input(uint32_t x){
    mmio_write32(NPU_I_PORT, x);
}

static inline uint32_t npu_read_output(void){
    return mmio_read32(NPU_O_DATA);
}

static inline uint32_t npu_status(void){
    return mmio_read32(NPU_STATUS);
}

static inline void npu_start(uint32_t cmd_flags){
    mmio_write32(NPU_CMD, cmd_flags | NPU_CMD_START);
}
