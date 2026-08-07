# ============================================================
# WAVE ORGANIZADA - PICONPU
#
# Carregada depois de:
#   vsim work.soc_tb_npu_trace
#
# Organiza o processo:
#   reset -> boot -> UART RX -> CPU/AXI -> NPU -> UART TX
# ============================================================

quietly WaveActivateNextPane {} 0

# Remove sinais previamente adicionados.
catch {delete wave *}

# Adiciona um sinal sem interromper o script caso o caminho não exista.
proc add_signal {args} {
    if {[catch {eval add wave $args} error_message]} {
        puts "WAVE AVISO: sinal nao encontrado ou indisponivel: $args"
    }
}

# ------------------------------------------------------------
# 1. CONTROLE GERAL
# ------------------------------------------------------------
add wave -divider "1. CONTROLE GERAL"

add_signal -label CLK                         sim:/soc_tb_npu_trace/clk
add_signal -label RESET_N                     sim:/soc_tb_npu_trace/resetn
add_signal -label BOOT_MODE                   sim:/soc_tb_npu_trace/boot_mode
add_signal -label CPU_RESET_N                 sim:/soc_tb_npu_trace/uut/cpu_resetn
add_signal -label TRAP                        sim:/soc_tb_npu_trace/trap
add_signal -label TIMER_IRQ                   sim:/soc_tb_npu_trace/timer_irq
add_signal -label NPU_IRQ                     sim:/soc_tb_npu_trace/uut/npu_irq

# ------------------------------------------------------------
# 2. BOOT DO FIRMWARE
# ------------------------------------------------------------
add wave -divider "2. BOOT DO FIRMWARE"

add_signal -label BOOT_UART_SERIAL            sim:/soc_tb_npu_trace/uart_rx_boot
add_signal -label FIRMWARE_SIZE -radix unsigned sim:/soc_tb_npu_trace/firmware_size

add_signal -label ROM_DONE                    sim:/soc_tb_npu_trace/uut/boot_mgr/rom_done
add_signal -label BOOT_WRITE_ENABLE           sim:/soc_tb_npu_trace/uut/boot_we
add_signal -label BOOT_ADDRESS -radix hexadecimal sim:/soc_tb_npu_trace/uut/boot_addr
add_signal -label BOOT_WRITE_DATA -radix hexadecimal sim:/soc_tb_npu_trace/uut/boot_wdata
add_signal -label BOOT_WRITE_COUNT -radix unsigned sim:/soc_tb_npu_trace/boot_write_count

# Sinais internos opcionais do gerador UART do boot.
add_signal -label BOOT_TX                      sim:/soc_tb_npu_trace/tb_boot/uart_tx
add_signal -label BOOT_DONE                    sim:/soc_tb_npu_trace/tb_boot/done

# ------------------------------------------------------------
# 3. UART DE ENTRADA - IMAGEM/FEATURES
# ------------------------------------------------------------
add wave -divider "3. UART RX - PACOTE DE FEATURES"

add_signal -label APP_UART_RX_SERIAL           sim:/soc_tb_npu_trace/uart_rx
add_signal -label FEATURE_INDEX -radix unsigned sim:/soc_tb_npu_trace/feature_i
add_signal -label TX_CHECKSUM -radix hexadecimal sim:/soc_tb_npu_trace/tx_checksum

add_signal -label DUT_RX_DONE                  sim:/soc_tb_npu_trace/uut/uart_inst/rx_done
add_signal -label DUT_RX_BYTE -radix hexadecimal sim:/soc_tb_npu_trace/uut/uart_inst/rx_data_wire

# Sinais internos opcionais da UART AXI.
add_signal -label UART_STATUS_READ             sim:/soc_tb_npu_trace/uut/uart_inst/read_en
add_signal -label UART_TX_BUSY                 sim:/soc_tb_npu_trace/uut/uart_inst/tx_busy

# ------------------------------------------------------------
# 4. CPU / AXI - CANAL DE ESCRITA
# ------------------------------------------------------------
add wave -divider "4. CPU AXI - ESCRITAS PARA NPU"

add_signal -label AWVALID                      sim:/soc_tb_npu_trace/uut/mem_axi_awvalid
add_signal -label AWREADY                      sim:/soc_tb_npu_trace/uut/mem_axi_awready
add_signal -label AWADDR -radix hexadecimal    sim:/soc_tb_npu_trace/uut/mem_axi_awaddr

add_signal -label WVALID                       sim:/soc_tb_npu_trace/uut/mem_axi_wvalid
add_signal -label WREADY                       sim:/soc_tb_npu_trace/uut/mem_axi_wready
add_signal -label WDATA -radix hexadecimal     sim:/soc_tb_npu_trace/uut/mem_axi_wdata
add_signal -label WSTRB -radix hexadecimal     sim:/soc_tb_npu_trace/uut/mem_axi_wstrb

add_signal -label BVALID                       sim:/soc_tb_npu_trace/uut/mem_axi_bvalid
add_signal -label BREADY                       sim:/soc_tb_npu_trace/uut/mem_axi_bready

add_signal -label LAST_WRITE_ADDRESS -radix hexadecimal sim:/soc_tb_npu_trace/tb_trace_last_awaddr
add_signal -label WRITE_ADDRESS_CAPTURED       sim:/soc_tb_npu_trace/tb_trace_aw_seen

# ------------------------------------------------------------
# 5. CPU / AXI - CANAL DE LEITURA
# ------------------------------------------------------------
add wave -divider "5. CPU AXI - LEITURAS DA NPU"

add_signal -label ARVALID                      sim:/soc_tb_npu_trace/uut/mem_axi_arvalid
add_signal -label ARREADY                      sim:/soc_tb_npu_trace/uut/mem_axi_arready
add_signal -label ARADDR -radix hexadecimal    sim:/soc_tb_npu_trace/uut/mem_axi_araddr

add_signal -label RVALID                       sim:/soc_tb_npu_trace/uut/mem_axi_rvalid
add_signal -label RREADY                       sim:/soc_tb_npu_trace/uut/mem_axi_rready
add_signal -label RDATA -radix hexadecimal     sim:/soc_tb_npu_trace/uut/mem_axi_rdata

add_signal -label LAST_READ_ADDRESS -radix hexadecimal sim:/soc_tb_npu_trace/tb_trace_last_araddr
add_signal -label READ_ADDRESS_CAPTURED        sim:/soc_tb_npu_trace/tb_trace_ar_seen

# ------------------------------------------------------------
# 6. WRAPPER AXI -> NPU
# ------------------------------------------------------------
add wave -divider "6. WRAPPER AXI NPU"

add_signal -label NPU_VALID                    sim:/soc_tb_npu_trace/uut/npu_inst/npu_vld_i
add_signal -label NPU_WRITE_ENABLE             sim:/soc_tb_npu_trace/uut/npu_inst/npu_we_i
add_signal -label NPU_ADDRESS -radix hexadecimal sim:/soc_tb_npu_trace/uut/npu_inst/npu_addr_i
add_signal -label NPU_WRITE_DATA -radix hexadecimal sim:/soc_tb_npu_trace/uut/npu_inst/npu_data_i
add_signal -label NPU_READ_DATA -radix hexadecimal sim:/soc_tb_npu_trace/uut/npu_inst/npu_data_o
add_signal -label NPU_READY                    sim:/soc_tb_npu_trace/uut/npu_inst/npu_rdy_o
add_signal -label NPU_IRQ_DONE                  sim:/soc_tb_npu_trace/uut/npu_inst/irq_done_o

# ------------------------------------------------------------
# 7. NPU INTERNA
#
# Os caminhos abaixo são opcionais. O "catch" impede erro caso
# o nome interno seja diferente na versão atual do RTL.
# ------------------------------------------------------------
add wave -divider "7. EXECUCAO INTERNA DA NPU"

add_signal -label NPU_CONTROLLER_STATE -radix unsigned sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/u_controller/state
add_signal -label NPU_BUSY                     sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/busy
add_signal -label NPU_DONE                     sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/done
add_signal -label MAC_ACCUMULATOR -radix decimal sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/u_datapath/accumulator
add_signal -label MAC_INDEX -radix unsigned    sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/u_datapath/mac_index
add_signal -label WEIGHT_POINTER -radix unsigned sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/u_register_file/weight_ptr
add_signal -label INPUT_POINTER -radix unsigned sim:/soc_tb_npu_trace/uut/npu_inst/u_npu_top/u_register_file/input_ptr

# ------------------------------------------------------------
# 8. RESPOSTA DA NPU E UART DE SAIDA
# ------------------------------------------------------------
add wave -divider "8. RESULTADO NPU -> CPU -> UART"

add_signal -label APP_UART_TX_SERIAL           sim:/soc_tb_npu_trace/uart_tx
add_signal -label NPU_IRQ_DELAYED              sim:/soc_tb_npu_trace/tb_npu_irq_d

add_signal -label RESPONSE_RX_DONE             sim:/soc_tb_npu_trace/tb_uart_rx_done
add_signal -label RESPONSE_RX_BYTE -radix hexadecimal sim:/soc_tb_npu_trace/tb_uart_rx_data
add_signal -label RESPONSE_INDEX -radix unsigned sim:/soc_tb_npu_trace/response_index
add_signal -label RESPONSE_CHECKSUM -radix hexadecimal sim:/soc_tb_npu_trace/response_checksum
add_signal -label SCORE_RED -radix decimal     sim:/soc_tb_npu_trace/response_red
add_signal -label SCORE_GREEN -radix decimal   sim:/soc_tb_npu_trace/response_green

# Bytes do protocolo de resposta:
# [0]=sync, [1]=sample_id, [2]=status, [3]=pred,
# [4]=red, [5]=green, [6]=checksum
add_signal -label RESP_SYNC -radix hexadecimal       sim:/soc_tb_npu_trace/response_bytes(0)
add_signal -label RESP_SAMPLE_ID -radix unsigned     sim:/soc_tb_npu_trace/response_bytes(1)
add_signal -label RESP_STATUS -radix unsigned        sim:/soc_tb_npu_trace/response_bytes(2)
add_signal -label RESP_PREDICTED -radix unsigned     sim:/soc_tb_npu_trace/response_bytes(3)
add_signal -label RESP_RED_BYTE -radix hexadecimal   sim:/soc_tb_npu_trace/response_bytes(4)
add_signal -label RESP_GREEN_BYTE -radix hexadecimal sim:/soc_tb_npu_trace/response_bytes(5)
add_signal -label RESP_CHECKSUM -radix hexadecimal   sim:/soc_tb_npu_trace/response_bytes(6)

# ------------------------------------------------------------
# APRESENTACAO
# ------------------------------------------------------------
configure wave -namecolwidth 260
configure wave -valuecolwidth 130
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits us
configure wave -gridperiod 1
configure wave -griddelta 10
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Mantém toda a execução visível após o run.
wave zoom full
