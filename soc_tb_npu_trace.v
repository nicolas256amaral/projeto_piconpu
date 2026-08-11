// ===========================================================================
// TESTBENCH COMENTADA - soc_tb_npu_trace
//
// Objetivo geral:
//   Validar o caminho completo:
//
//   firmware.hex -> boot UART -> RAM -> PicoRV32
//       -> UART RX da aplicação -> firmware
//       -> AXI4-Lite -> wrapper AXI/NPU -> NPU
//       -> DONE/IRQ -> NPU_OUTPUT -> PicoRV32
//       -> UART TX -> decoder da testbench.
//
// IMPORTANTE:
//   Esta cópia adiciona apenas comentários. A lógica funcional original
//   foi preservada.
// ===========================================================================

`timescale 1ns/1ps

module soc_tb_npu_trace;

// Define parâmetros usados SOMENTE pela testbench.
// O clock é de 50 MHz: período de 20 ns.
// O boot UART é acelerado para reduzir o tempo de simulação.
  // =========================================================
  // CONFIGURAÇÃO DA SIMULAÇÃO
  // =========================================================
  localparam integer TB_CLK_FREQ       = 50_000_000;

  // Somente para simulação: acelera o boot UART de 115200 para 25 Mbaud.
  // O valor padrão sintetizável do SoC continua sendo 115200 baud.
  localparam integer TB_BOOT_BAUD_RATE = 25_000_000;//115200;//
  localparam integer TB_BOOT_MEM_WORDS = 1024;

  // =========================================================
// Estes sinais são gerados pela própria testbench:
//   clk       : clock do SoC;
//   resetn    : reset ativo em nível baixo;
//   boot_mode : seleciona o caminho de boot;
//   uart_rx   : pino RX da UART de aplicação do DUT.
  // CLOCK / RESET / BOOT
  // =========================================================
  reg clk;
  reg resetn;
  reg boot_mode;
  reg uart_rx;

// Geração do clock:
// #10 ns troca o nível lógico; portanto um período completo leva 20 ns.
// 1 / 20 ns = 50 MHz.
  initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;   // 50 MHz
  end

// Sequência inicial da simulação:
// 1) mantém o sistema em reset;
// 2) deixa a UART RX em idle (nível alto);
// 3) após 200 ns libera o reset externo;
// 4) 100 ns depois ativa boot_mode para permitir o carregamento.
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

// Representação dos pinos externos do SoC.
// A testbench não está exercitando SPI/I2C neste teste; por isso são
// fornecidos níveis simples/pull-ups apenas para deixar as interfaces válidas.
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

// O módulo bootloader_uart é um agente da TESTBENCH.
// Ele lê firmware.hex e serializa o firmware em uart_rx_boot.
// Portanto ele simula um equipamento externo enviando o programa ao SoC.
// Ele não é a UART de aplicação usada para enviar as 63 features.
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

// Instância do DUT (Device Under Test): o SoC real que está sendo validado.
// uart_rx_boot recebe o firmware durante o boot.
// uart_rx recebe posteriormente o pacote da aplicação.
// uart_tx devolve o resultado da inferência.
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

// Espera o gerenciador de boot interno afirmar rom_done.
// Isso significa que o firmware já foi recebido/escrito na RAM.
// Em seguida boot_mode é desativado, transferindo o controle para a CPU.
// O timeout evita que uma falha deixe a simulação rodando indefinidamente.
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

// Este bloco executa uma única vez quando cpu_resetn sobe para 1.
// Serve apenas para diagnóstico: confirma que o PicoRV32 começou a executar.
//
// ATENÇÃO: os índices RAM[321], RAM[322] etc. eram usados originalmente
// para conferir uma posição específica do firmware/modelo. Após recompilar
// o firmware esses índices podem conter instruções e não necessariamente pesos.
// Portanto estes displays NÃO devem ser usados hoje como prova de que um peso
// específico foi carregado.
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

// Espelha o mapa MMIO da NPU para a testbench conseguir reconhecer
// quais transações AXI pertencem ao acelerador.
// Faixa completa observada: 0x6000_0000 até 0x6000_0FFF.
// O firmware acessa endereços absolutos; o wrapper depois transforma
// esses endereços em offsets internos como 0x08, 0x10, 0x14 etc.
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

// Estes dois parâmetros pertencem a uma versão anterior do teste.
// Na lógica atual de verificação da resposta UART, quem realmente é usado
// é TL_EXPECTED_LABEL, definido mais abaixo.
// TB_SAMPLE_IDX/TB_EXPECTED_LABEL podem ser removidos se não forem usados
// em outro script/wave.do.
  // Ajuste conforme a amostra que o firmware roda em tl_run_sample(...)
  localparam integer TB_SAMPLE_IDX      = 0;
  localparam integer TB_EXPECTED_LABEL  = 1; // 0=red, 1=green para a amostra 0 atual

// MONITOR DE ESCRITAS AXI DA CPU PARA A NPU.
//
// Canal AW = endereço de escrita.
// Canal W  = dado de escrita.
// AXI4-Lite permite que AW e W façam handshake em ciclos diferentes.
// A intenção aqui é:
//   1) guardar o endereço quando AWVALID && AWREADY;
//   2) quando o dado for aceito, associá-lo ao endereço guardado;
//   3) imprimir apenas acessos dentro de 0x6000_0000..0x6000_0FFF.
//
// NOTA IMPORTANTE:
// Este monitor é simplificado. Como AW e W são canais independentes, ele
// pode associar endereço e dado incorretamente em alguns timings. Foi isso
// que produziu algumas mensagens CPU->NPU aparentemente desalinhadas no log.
// Para confirmar o valor realmente entregue à NPU, o monitor WRAPPER->NPU
// abaixo é mais confiável.
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

// MONITOR DE LEITURAS AXI DA CPU VINDAS DA NPU.
//
// AR = endereço de leitura.
// R  = dado retornado.
// A testbench salva o endereço aceito e, quando RVALID/RREADY ocorre,
// identifica se a leitura foi de NPU_OUTPUT ou de outro registrador.
// O evento mais importante é a leitura de 0x6000_0018 (NPU_OUTPUT).
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

// MONITOR DA INTERFACE INTERNA WRAPPER -> NPU.
//
// Aqui já não observamos o endereço absoluto 0x6000_xxxx.
// O wrapper já decodificou a transação AXI e entrega à NPU apenas o offset:
//   0x04 = CMD
//   0x08 = CONFIG
//   0x10 = WEIGHT
//   0x14 = INPUT
//   0x18 = OUTPUT
//   ...
//
// npu_vld_i indica uma operação válida.
// npu_we_i = 1 indica escrita; npu_we_i = 0 indica leitura.
// Este ponto é excelente para demonstrar que AXI -> wrapper -> NPU funcionou.
  // =========================================================
  // Wrapper -> NPU
  // =========================================================
  always @(posedge clk) begin
    if (uut.npu_inst.npu_vld_i) begin
      if (uut.npu_inst.npu_we_i) begin
        case (uut.npu_inst.npu_addr_i)
// Em NPU_CMD, o bit 1 é o START.
// Portanto, se data_i[1] = 1, a testbench marca o instante exato em que
// o comando START realmente chegou ao núcleo da NPU.
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

// Conta as escritas realizadas pelo caminho de boot na RAM.
// Para não inundar o transcript, somente alguns índices específicos são
// impressos. boot_write_count continua contando todas as escritas.
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

// Detector de BORDA DE SUBIDA da interrupção da NPU.
// tb_npu_irq_d guarda o valor do ciclo anterior.
// A condição npu_irq && !tb_npu_irq_d só é verdadeira em 0 -> 1.
// Assim a mensagem de conclusão aparece apenas uma vez, mesmo que IRQ
// permaneça em nível alto por vários ciclos.
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

// GERAÇÃO DO PACOTE UART DE APLICAÇÃO.
//
// Estrutura enviada ao SoC:
//   [0] 0xA5              -> SYNC
//   [1] 0x01              -> comando de inferência
//   [2] sample_id = 0
//   [3] length = 63
//   [4..66] 63 features INT8
//   [67] checksum XOR
//
// APP_UART_CLKS_PER_BIT = 20 com clock de 50 MHz significa:
//   50 MHz / 20 = 2,5 Mbaud para a UART DE APLICAÇÃO.
// Isso é diferente do TB_BOOT_BAUD_RATE = 25 Mbaud usado no boot.
  // Estimulo da UART de aplicacao
  // Protocolo RX: A5, CMD=01, sample_id, length=63, payload, XOR
  // =========================================================
  localparam integer APP_UART_CLKS_PER_BIT = 20;
  localparam integer TL_FEATURE_DIM_TB = 63;
  localparam [7:0] TL_FEATURE_LEN = 8'd63;
  localparam [7:0] UART_RX_SYNC      = 8'hA5;
  localparam [7:0] UART_CMD_INFER    = 8'h01;
  localparam [7:0] UART_TX_SYNC      = 8'h5A;

  // Convenção do modelo: 0 = red, 1 = green.
  localparam [7:0] TL_EXPECTED_LABEL = 8'd0;

  reg [7:0] tb_features [0:TL_FEATURE_DIM_TB-1];
  integer feature_i;
  reg [7:0] tx_checksum;

// Task que serializa UM BYTE no pino uart_rx do SoC.
// Formato utilizado: 8N1.
//
//   idle=1 -> start=0 -> 8 bits de dados LSB-first -> stop=1.
//
// Cada bit permanece por APP_UART_CLKS_PER_BIT ciclos de clock.
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

// Processo que envia a amostra dinâmica.
//
// Primeiro carrega uart_sample.hex para tb_features[0..62].
// Depois espera a CPU começar a executar e chegar ao polling UART_STATUS.
//
// Com o firmware reorganizado, o polling de UART_STATUS só começa DEPOIS
// de NPU_CONFIG, QUANT, BIAS e WEIGHTS terem sido carregados.
// Por isso este wait garante naturalmente que a imagem seja enviada somente
// depois que o modelo já está residente na NPU.
  initial begin : send_dynamic_features
    $readmemh("uart_sample.hex", tb_features);

    wait(uut.cpu_resetn == 1'b1);

// Endereço 0x2000_0008 pertence ao registrador de STATUS da UART.
// Quando a CPU lê esse endereço, sabemos que o firmware terminou a etapa
// de inicialização e está esperando dados da aplicação.
    // Aguarda o firmware chegar de fato ao polling do UART_STATUS.
    // Isso evita enviar o primeiro byte enquanto a CPU ainda está
    // executando crt0/inicializacao do programa.
    wait(uut.mem_axi_arvalid &&
         uut.mem_axi_arready &&
         uut.mem_axi_araddr == 32'h2000_0008);

    repeat (20) @(posedge clk);

// O checksum começa em zero e NÃO inclui o SYNC 0xA5.
// São acumulados por XOR: CMD, sample_id, length e todas as features.
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

// MONITOR DO RX REAL DENTRO DO DUT.
// Sempre que o receptor UART interno termina de reconstruir um byte,
// rx_done pulsa e a testbench imprime rx_data_wire.
// Isso prova que o sinal serial gerado por uart_send_byte() foi corretamente
// desserializado pelo periférico UART do SoC.
  // Monitor de recepcao da UART de aplicacao dentro do DUT.
  // Ajuda a confirmar que cada byte transmitido pela TB foi recebido.
  always @(posedge clk) begin
    if (uut.uart_inst.rx_done) begin
      $display("[%0t] DUT UART RX: byte recebido = 0x%02h",
               $time, uut.uart_inst.rx_data_wire);
    end
  end

// DECODER DA RESPOSTA DO SoC.
//
// O pino uart_tx do DUT é serial. Para verificar o conteúdo transmitido,
// a testbench instancia OUTRO receptor UART (tb_response_decoder).
// Ele transforma novamente os bits seriais em bytes.
//
// Pacote esperado:
//   5A | sample_id | status | predicted_label | score_red | score_green | XOR
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

// Buffer da resposta recebida pela testbench.
// response_index conta de 0 a 6; quando chega a 7 significa que os sete
// bytes do quadro foram reconstruídos.
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

// Validação após o recebimento dos sete bytes:
// 1) recalcula o checksum;
// 2) converte os scores de 8 bits para inteiros com sinal;
// 3) imprime o resumo;
// 4) valida protocolo;
// 5) valida a classe prevista.
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

// PASS do protocolo exige simultaneamente:
//   SYNC = 0x5A;
//   status = 0 (sem erro);
//   checksum recebido = checksum calculado.
// Isto valida a comunicação/protocolo, não necessariamente a acurácia.
        if (response_bytes[0] == UART_TX_SYNC &&
            response_bytes[2] == 8'h00 &&
            response_bytes[6] == response_checksum) begin
          $display("[%0t] RESULTADO DO PROTOCOLO: PASS", $time);
        end else begin
          $display("[%0t] RESULTADO DO PROTOCOLO: FAIL", $time);
        end

// Validação da classificação.
// TL_EXPECTED_LABEL = 0 significa que, para a amostra atual, espera-se RED.
// O byte predicted_label veio do firmware após comparar os scores da NPU.
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

// Converte um byte UART INT8 para um integer Verilog com sinal.
// Exemplo:
//   8'hDE = 222 se tratado como unsigned;
//   8'hDE = -34 quando interpretado em complemento de dois.
// A concatenação replica o bit de sinal b[7] por 24 bits.
  function integer s8_uart;
    input [7:0] b;
    begin
      s8_uart = $signed({{24{b[7]}}, b});
    end
  endfunction
  
// Bloco de diagnóstico legado: imprime contador de boot e algumas posições
// da RAM assim que a CPU sai do reset.
// Novamente, os índices fixos podem deixar de representar os mesmos dados
// após qualquer alteração/recompilação do firmware.
  initial begin
    wait(uut.cpu_resetn == 1'b1);

    $display("TOTAL DE BOOT WRITES = %0d", boot_write_count);

    $display("RAM[321] = 0x%08h", uut.ram_inst.mem[321]);
    $display("RAM[324] = 0x%08h", uut.ram_inst.mem[324]);
    $display("RAM[330] = 0x%08h", uut.ram_inst.mem[330]);
end
endmodule
