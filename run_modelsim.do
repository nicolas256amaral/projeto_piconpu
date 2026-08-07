vlib work
vmap work work

# =========================
# NPU VHDL
# =========================
vcom -2008 ./pkg/npu_pkg.vhd

vcom -2008 ./rtl/common/fifo_sync.vhd
vcom -2008 ./rtl/common/ram_dual.vhd

vcom -2008 ./rtl/core/input_buffer.vhd
vcom -2008 ./rtl/core/mac_pe.vhd
vcom -2008 ./rtl/core/systolic_array.vhd
vcom -2008 ./rtl/core/npu_core.vhd

vcom -2008 ./rtl/ppu/post_process.vhd

vcom -2008 ./rtl/npu_register_file.vhd
vcom -2008 ./rtl/npu_controller.vhd
vcom -2008 ./rtl/npu_datapath.vhd
vcom -2008 ./rtl/npu_top.vhd

# =========================
# SoC Verilog
# =========================
vlog ./axi/picorv32.v
vlog ./axi/uart_rx.v
vlog ./axi/uart_tx.v

vlog ./axi/axi_ram.v
vlog ./axi/axi_gpio.v
vlog ./axi/axi_uart.v
vlog ./axi/axi_spi.v
vlog ./axi/axi_i2c.v
vlog ./axi/axi_timer.v
vlog ./axi/axi_npu.v
vlog ./axi/axi_interconnect.v

# =========================
# Bootloader
# =========================
vlog ./bootloader/boot_manager.v
vlog ./bootloader/uart_rom_receiver.v
vlog ./bootloader/bootloader_uart.v

# =========================
# Top do SoC
# =========================
vlog ./axi/soc_top.v

# =========================
# Testbench
# =========================
vlog soc_tb_npu_trace.v

# =========================
# Simulação
# =========================
vsim work.soc_tb_npu_trace

add wave -r /*
run -all