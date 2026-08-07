`timescale 1ns/1ps

module soc_tb_npu_trace;

  // =========================================================
  // CONFIGURAÇÃO DA SIMULAÇÃO
  // =========================================================
  localparam integer TB_CLK_FREQ       = 50_000_000;

  // Somente para simulação: acelera o boot UART de 115200 para 25 Mbaud.
  // O valor padrão sintetizável do SoC continua sendo 115200 baud.
  // Com o firmware atual (890 palavras), o boot cai de ~340 ms para ~1,57 ms.
  localparam integer TB_BOOT_BAUD_RATE = 25_000_000;
  localparam integer TB_BOOT_MEM_WORDS = 1024;

  // =========================================================
  // CLOCK / RESET / BOOT
  // =========================================================
  reg clk;
  reg resetn;
  reg boot_mode;
  reg uart_rx;

  initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;   // 50 MHz
  end

  initial begin
    resetn    = 1'b0;
    boot_mode = 1'b0;
    uart_rx   = 1'b1;         // UART idle

    #200;
    resetn    = 1'b1;
    $display("[%0t] TB: reset liberado.", $time);

    #100;
    boot_mode = 1'b1;
    $display("[%0t] TB: boot_mode ativado.", $time);
    $display("[%0t] TB: boot UART acelerado para %0d baud (somente simulacao).",
             $time, TB_BOOT_BAUD_RATE);
  end

  // =========================================================
  // INTERFACES EXTERNAS
  // =========================================================
  wire uart_tx;

  wire spi_mosi;
  wire spi_miso;
  wire spi_sck;
  wire spi_cs;
  assign spi_miso = 1'b0;

  wire i2c_sda;
  wire i2c_scl;
  pullup(i2c_sda);
  pullup(i2c_scl);

  reg tb_drive_sda_low = 1'b0;
  assign i2c_sda = tb_drive_sda_low ? 1'b0 : 1'bz;

  wire [31:0] gpio_out;
  wire        trap;
  wire        timer_irq;

  wire        uart_rx_boot;
  wire [31:0] firmware_size;

  // =========================================================
  // BOOTLOADER
  // =========================================================
  bootloader_uart #(
    .CLK_FREQ(TB_CLK_FREQ),
    .BAUD_RATE(TB_BOOT_BAUD_RATE),
    .MEM_WORDS(TB_BOOT_MEM_WORDS),
    .FIRMWARE_FILE("firmware.hex")
  ) tb_boot (
    .clk(clk),
    .resetn(resetn),
    .boot_enable(boot_mode),
    .uart_tx(uart_rx_boot),
    .done(),
    .firmware_size(firmware_size)
  );

  // =========================================================
  // DUT
  // =========================================================
  soc_top #(
    .BOOT_CLK_FREQ(TB_CLK_FREQ),
    .BOOT_BAUD_RATE(TB_BOOT_BAUD_RATE),
    .BOOT_MEM_WORDS(TB_BOOT_MEM_WORDS)
  ) uut (
    .clk(clk),
    .resetn(resetn),
    .boot_mode(boot_mode),
    .uart_rx_boot(uart_rx_boot),
    .firmware_size(firmware_size),

    .trap(trap),
    .gpio_out(gpio_out),
    .timer_irq(timer_irq),

    .uart_tx(uart_tx),
    .uart_rx(uart_rx),

    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_sck(spi_sck),
    .spi_cs(spi_cs),

    .i2c_sda(i2c_sda),
    .i2c_scl(i2c_scl)
  );

  // =========================================================
  // CONTROLE DO BOOT
  // =========================================================
  initial begin
    wait(uut.boot_mgr.rom_done == 1'b1);
    $display("[%0t] TB: boot_mgr.rom_done = 1. Firmware recebido.", $time);

    #100;
    boot_mode = 1'b0;
    $display("[%0t] TB: boot_mode desativado. CPU pode executar o firmware.", $time);

    #20_000_000;
    $display("[%0t] TB: fim da simulacao por timeout.", $time);
    $stop;
  end

  // =========================================================
  // CPU saiu do reset
  // =========================================================
  initial begin : cpu_reset_once
    wait(uut.cpu_resetn == 1'b1);
    $display("[%0t] CPU: cpu_resetn liberado. CPU iniciou execucao.", $time);

    $display("===== CONFERENCIA RAM APOS BOOT =====");
    $display("RAM peso[0] = 0x%08h", uut.ram_inst.mem[321]);
    $display("RAM peso[1] = 0x%08h", uut.ram_inst.mem[322]);
    $display("RAM peso[2] = 0x%08h", uut.ram_inst.mem[323]);
    $display("RAM peso[3] = 0x%08h", uut.ram_inst.mem[324]);
    $display("RAM peso[9] = 0x%08h", uut.ram_inst.mem[330]);
  end

  // =========================================================
  // Mapa da NPU no barramento
  // =========================================================
  localparam [31:0] TB_NPU_BASE_ADDR       = 32'h6000_0000;
  localparam [31:0] TB_NPU_END_ADDR        = 32'h6000_1000;

  localparam [31:0] TB_NPU_CMD_ADDR        = 32'h6000_0004;
  localparam [31:0] TB_NPU_CONFIG_ADDR     = 32'h6000_0008;
  localparam [31:0] TB_NPU_WEIGHT_ADDR     = 32'h6000_0010;
  localparam [31:0] TB_NPU_INPUT_ADDR      = 32'h6000_0014;
  localparam [31:0] TB_NPU_OUTPUT_ADDR     = 32'h6000_0018;

  localparam [31:0] TB_NPU_QUANT_CFG_ADDR  = 32'h6000_0040;
  localparam [31:0] TB_NPU_QUANT_MULT_ADDR = 32'h6000_0044;
  localparam [31:0] TB_NPU_CTRL_FLAGS_ADDR = 32'h6000_0048;

  localparam [31:0] TB_NPU_BIAS0_ADDR      = 32'h6000_0080;
  localparam [31:0] TB_NPU_BIAS1_ADDR      = 32'h6000_0084;
  localparam [31:0] TB_NPU_BIAS2_ADDR      = 32'h6000_0088;
  localparam [31:0] TB_NPU_BIAS3_ADDR      = 32'h6000_008C;

  // Ajuste conforme a amostra que o firmware roda em tl_run_sample(...)
  localparam integer TB_SAMPLE_IDX      = 0;
  localparam integer TB_EXPECTED_LABEL  = 1; // 0=red, 1=green para a amostra 0 atual

  // =========================================================
  // Monitor CPU -> NPU
  // =========================================================
  reg [31:0] tb_trace_last_awaddr;
  reg        tb_trace_aw_seen;

  always @(posedge clk) begin
    if (!resetn) begin
      tb_trace_last_awaddr <= 32'h0000_0000;
      tb_trace_aw_seen     <= 1'b0;
    end else begin
      if (uut.mem_axi_awvalid && uut.mem_axi_awready) begin
        tb_trace_last_awaddr <= uut.mem_axi_awaddr;
        tb_trace_aw_seen     <= 1'b1;
      end

      if (uut.mem_axi_wvalid && uut.mem_axi_wready && tb_trace_aw_seen) begin
        if (tb_trace_last_awaddr >= TB_NPU_BASE_ADDR &&
            tb_trace_last_awaddr <  TB_NPU_END_ADDR) begin
          case (tb_trace_last_awaddr)
            TB_NPU_CMD_ADDR:
              $display("[%0t] CPU->NPU WRITE | NPU_CMD    addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_CONFIG_ADDR:
              $display("[%0t] CPU->NPU WRITE | NPU_CONFIG addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_WEIGHT_ADDR:
              $display("[%0t] CPU->NPU WRITE | NPU_WEIGHT addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_INPUT_ADDR:
              $display("[%0t] CPU->NPU WRITE | NPU_INPUT  addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_QUANT_CFG_ADDR:
              $display("[%0t] CPU->NPU WRITE | QUANT_CFG  addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_QUANT_MULT_ADDR:
              $display("[%0t] CPU->NPU WRITE | QUANT_MULT addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_CTRL_FLAGS_ADDR:
              $display("[%0t] CPU->NPU WRITE | CTRL_FLAGS addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            TB_NPU_BIAS0_ADDR, TB_NPU_BIAS1_ADDR, TB_NPU_BIAS2_ADDR, TB_NPU_BIAS3_ADDR:
              $display("[%0t] CPU->NPU WRITE | NPU_BIAS   addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
            default:
              $display("[%0t] CPU->NPU WRITE | NPU_REG    addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_awaddr, uut.mem_axi_wdata);
          endcase
        end
        tb_trace_aw_seen <= 1'b0;
      end
    end
  end

  // =========================================================
  // Monitor CPU <- NPU
  // =========================================================
  reg [31:0] tb_trace_last_araddr;
  reg        tb_trace_ar_seen;

  always @(posedge clk) begin
    if (!resetn) begin
      tb_trace_last_araddr <= 32'h0000_0000;
      tb_trace_ar_seen     <= 1'b0;
    end else begin
      if (uut.mem_axi_arvalid && uut.mem_axi_arready) begin
        tb_trace_last_araddr <= uut.mem_axi_araddr;
        tb_trace_ar_seen     <= 1'b1;
      end

      if (uut.mem_axi_rvalid && uut.mem_axi_rready && tb_trace_ar_seen) begin
        if (tb_trace_last_araddr >= TB_NPU_BASE_ADDR &&
            tb_trace_last_araddr <  TB_NPU_END_ADDR) begin
          case (tb_trace_last_araddr)
            TB_NPU_OUTPUT_ADDR: begin
              $display("[%0t] CPU<-NPU READ  | NPU_OUTPUT addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_araddr, uut.mem_axi_rdata);
              $display("[%0t] >>> EVENTO: CPU recebeu resultado da NPU = 0x%08h",
                       $time, uut.mem_axi_rdata);
            end
            default:
              $display("[%0t] CPU<-NPU READ  | NPU_REG    addr=0x%08h data=0x%08h",
                       $time, tb_trace_last_araddr, uut.mem_axi_rdata);
          endcase
        end
        tb_trace_ar_seen <= 1'b0;
      end
    end
  end

  // =========================================================
  // Wrapper -> NPU
  // =========================================================
  always @(posedge clk) begin
    if (uut.npu_inst.npu_vld_i) begin
      if (uut.npu_inst.npu_we_i) begin
        case (uut.npu_inst.npu_addr_i)
          32'h0000_0004: begin
            $display("[%0t] WRAPPER->NPU WRITE | NPU_CMD    addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
            if (uut.npu_inst.npu_data_i[1]) begin
              $display("[%0t] >>> EVENTO: comando START entregue internamente para a NPU.",
                       $time);
            end
          end
          32'h0000_0008:
            $display("[%0t] WRAPPER->NPU WRITE | NPU_CONFIG addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0010:
            $display("[%0t] WRAPPER->NPU WRITE | NPU_WEIGHT addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0014:
            $display("[%0t] WRAPPER->NPU WRITE | NPU_INPUT  addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0040:
            $display("[%0t] WRAPPER->NPU WRITE | QUANT_CFG  addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0044:
            $display("[%0t] WRAPPER->NPU WRITE | QUANT_MULT addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0048:
            $display("[%0t] WRAPPER->NPU WRITE | CTRL_FLAGS addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          32'h0000_0080, 32'h0000_0084, 32'h0000_0088, 32'h0000_008c:
            $display("[%0t] WRAPPER->NPU WRITE | NPU_BIAS   addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
          default:
            $display("[%0t] WRAPPER->NPU WRITE | NPU_REG    addr=0x%08h data=0x%08h",
                     $time, uut.npu_inst.npu_addr_i, uut.npu_inst.npu_data_i);
        endcase
      end else begin
        case (uut.npu_inst.npu_addr_i)
          32'h0000_0000:
            $display("[%0t] WRAPPER<-NPU READ  | NPU_STATUS addr=0x%08h",
                     $time, uut.npu_inst.npu_addr_i);
          32'h0000_0018:
            $display("[%0t] WRAPPER<-NPU READ  | NPU_OUTPUT addr=0x%08h",
                     $time, uut.npu_inst.npu_addr_i);
          default:
            $display("[%0t] WRAPPER<-NPU READ  | NPU_REG    addr=0x%08h",
                     $time, uut.npu_inst.npu_addr_i);
        endcase
      end
    end
  end

  integer boot_write_count = 0;

always @(posedge clk) begin
    if (uut.boot_we) begin
        if (boot_write_count < 10 ||
            boot_write_count == 255 ||
            boot_write_count == 256 ||
            boot_write_count == 321 ||
            boot_write_count == 324 ||
            boot_write_count == 330) begin

            $display(
                "[%0t] BOOT WRITE[%0d] addr=0x%08h index=%0d data=0x%08h",
                $time,
                boot_write_count,
                uut.boot_addr,
                uut.boot_addr[15:2],
                uut.boot_wdata
            );
        end

        boot_write_count = boot_write_count + 1;
    end
end

  // =========================================================
  // NPU terminou
  // =========================================================
  reg tb_npu_irq_d;

  always @(posedge clk) begin
    if (!resetn) begin
      tb_npu_irq_d <= 1'b0;
    end else begin
      tb_npu_irq_d <= uut.npu_irq;
      if (uut.npu_irq && !tb_npu_irq_d) begin
        $display("[%0t] >>> EVENTO: NPU sinalizou conclusao (npu_irq = 1).",
                 $time);
      end
    end
  end

  // Estimulo da UART de aplicacao
  // Protocolo RX: A5, CMD=01, sample_id, length=63, payload, XOR
  // =========================================================
  localparam integer APP_UART_CLKS_PER_BIT = 20;
  localparam integer TL_FEATURE_DIM_TB = 63;
  localparam [7:0] TL_FEATURE_LEN = 8'd63;
  localparam [7:0] UART_RX_SYNC      = 8'hA5;
  localparam [7:0] UART_CMD_INFER    = 8'h01;
  localparam [7:0] UART_TX_SYNC      = 8'h5A;

  // A amostra atualmente carregada em uart_sample.hex produz score negativo.
  // Convenção do modelo: 0 = red, 1 = green.
  localparam [7:0] TL_EXPECTED_LABEL = 8'd0;

  reg [7:0] tb_features [0:TL_FEATURE_DIM_TB-1];
  integer feature_i;
  reg [7:0] tx_checksum;

  task uart_send_byte;
    input [7:0] value;
    integer bit_i;
    begin
        // Start bit
        @(negedge clk);
        uart_rx = 1'b0;
        repeat (APP_UART_CLKS_PER_BIT) @(posedge clk);

        // 8 bits, LSB primeiro
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            @(negedge clk);
            uart_rx = value[bit_i];
            repeat (APP_UART_CLKS_PER_BIT) @(posedge clk);
        end

        // Stop bit
        @(negedge clk);
        uart_rx = 1'b1;
        repeat (APP_UART_CLKS_PER_BIT) @(posedge clk);

        // Um bit adicional de idle entre bytes
        uart_rx = 1'b1;
        repeat (APP_UART_CLKS_PER_BIT) @(posedge clk);
    end
  endtask

  initial begin : send_dynamic_features
    $readmemh("uart_sample.hex", tb_features);

    wait(uut.cpu_resetn == 1'b1);

    // Aguarda o firmware chegar de fato ao polling do UART_STATUS.
    // Isso evita enviar o primeiro byte enquanto a CPU ainda está
    // executando crt0/inicializacao do programa.
    wait(uut.mem_axi_arvalid &&
         uut.mem_axi_arready &&
         uut.mem_axi_araddr == 32'h2000_0008);

    repeat (20) @(posedge clk);

    tx_checksum = 8'h00;

    $display("[%0t] TB UART: enviando pacote de features dinamicas.", $time);
    uart_send_byte(UART_RX_SYNC);

    uart_send_byte(UART_CMD_INFER);
    tx_checksum = tx_checksum ^ UART_CMD_INFER;

    uart_send_byte(8'h00); // sample_id
    tx_checksum = tx_checksum ^ 8'h00;

    uart_send_byte(TL_FEATURE_LEN);
    tx_checksum = tx_checksum ^ TL_FEATURE_LEN;

    for (feature_i = 0; feature_i < TL_FEATURE_DIM_TB; feature_i = feature_i + 1) begin
      uart_send_byte(tb_features[feature_i]);
      tx_checksum = tx_checksum ^ tb_features[feature_i];
    end

    uart_send_byte(tx_checksum);
    $display("[%0t] TB UART: pacote completo enviado, checksum=0x%02h.",
             $time, tx_checksum);
  end

  // Monitor de recepcao da UART de aplicacao dentro do DUT.
  // Ajuda a confirmar que cada byte transmitido pela TB foi recebido.
  always @(posedge clk) begin
    if (uut.uart_inst.rx_done) begin
      $display("[%0t] DUT UART RX: byte recebido = 0x%02h",
               $time, uut.uart_inst.rx_data_wire);
    end
  end

  // =========================================================
  // Decodifica a resposta UART transmitida pelo firmware
  // Resposta: 5A, sample_id, status, pred, red, green, XOR
  // =========================================================
  wire [7:0] tb_uart_rx_data;
  wire       tb_uart_rx_done;

  uart_rx tb_response_decoder (
    .clk(clk),
    .reset(~resetn),
    .rx(uart_tx),
    .data_out(tb_uart_rx_data),
    .rx_done(tb_uart_rx_done)
  );

  integer response_index = 0;
  reg [7:0] response_bytes [0:6];
  reg [7:0] response_checksum;
  integer response_red;
  integer response_green;

  always @(posedge clk) begin
    if (tb_uart_rx_done) begin
      response_bytes[response_index] = tb_uart_rx_data;
      $display("[%0t] TB UART RX[%0d] = 0x%02h",
               $time, response_index, tb_uart_rx_data);

      response_index = response_index + 1;

      if (response_index == 7) begin
        response_checksum = response_bytes[1] ^ response_bytes[2] ^
                            response_bytes[3] ^ response_bytes[4] ^
                            response_bytes[5];
        response_red   = s8_uart(response_bytes[4]);
        response_green = s8_uart(response_bytes[5]);

        $display("");
        $display("[%0t] ===== RESUMO UART -> NPU -> UART =====", $time);
        $display("[%0t] sync            = 0x%02h", $time, response_bytes[0]);
        $display("[%0t] sample_id       = %0d", $time, response_bytes[1]);
        $display("[%0t] status          = %0d", $time, response_bytes[2]);
        $display("[%0t] predicted_label = %0d", $time, response_bytes[3]);
        $display("[%0t] score_red       = %0d", $time, response_red);
        $display("[%0t] score_green     = %0d", $time, response_green);
        $display("[%0t] checksum_rx     = 0x%02h", $time, response_bytes[6]);
        $display("[%0t] checksum_calc   = 0x%02h", $time, response_checksum);

        if (response_bytes[0] == UART_TX_SYNC &&
            response_bytes[2] == 8'h00 &&
            response_bytes[6] == response_checksum) begin
          $display("[%0t] RESULTADO DO PROTOCOLO: PASS", $time);
        end else begin
          $display("[%0t] RESULTADO DO PROTOCOLO: FAIL", $time);
        end

        if (response_bytes[3] == TL_EXPECTED_LABEL) begin
          if (TL_EXPECTED_LABEL == 8'd0)
            $display("[%0t] CLASSIFICACAO AMOSTRA 0: PASS (esperado RED=0)", $time);
          else
            $display("[%0t] CLASSIFICACAO AMOSTRA 0: PASS (esperado GREEN=1)", $time);
        end else begin
          if (TL_EXPECTED_LABEL == 8'd0)
            $display("[%0t] CLASSIFICACAO AMOSTRA 0: FAIL (esperado RED=0, recebido=%0d)",
                     $time, response_bytes[3]);
          else
            $display("[%0t] CLASSIFICACAO AMOSTRA 0: FAIL (esperado GREEN=1, recebido=%0d)",
                     $time, response_bytes[3]);
        end

        #1000;
        $display("[%0t] TB: encerrando apos inferencia dinamica.", $time);
        $stop;
      end
    end
  end

  function integer s8_uart;
    input [7:0] b;
    begin
      s8_uart = $signed({{24{b[7]}}, b});
    end
  endfunction
  
  initial begin
    wait(uut.cpu_resetn == 1'b1);

    $display("TOTAL DE BOOT WRITES = %0d", boot_write_count);

    $display("RAM[321] = 0x%08h", uut.ram_inst.mem[321]);
    $display("RAM[324] = 0x%08h", uut.ram_inst.mem[324]);
    $display("RAM[330] = 0x%08h", uut.ram_inst.mem[330]);
end
endmodule
