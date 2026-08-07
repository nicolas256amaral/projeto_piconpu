`ifndef soc_test_SV
`define soc_test_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

`include "environment.sv"
`include "sequence.sv"

// =============================================================================
// Base Test
// =============================================================================
class soc_base_test extends uvm_test;
    `uvm_component_utils(soc_base_test)
    
    soc_env env;
    
    function new(string name = "soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        env = soc_env::type_id::create("env", this);

    endfunction
    
    task run_phase(uvm_phase phase);
        `uvm_info("soc_base_test", "Starting base_test...", UVM_LOW)
    endtask
endclass : soc_base_test

// =============================================================================
// BOOTLOADER Focused Test
// =============================================================================
class soc_bootloader_test extends soc_base_test;
    `uvm_component_utils(soc_bootloader_test)
    
    function new(string name = "soc_bootloader_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        bootloader_seq seq;
        
        phase.raise_objection(this);
        
        seq = bootloader_seq::type_id::create("seq");
        seq.start(env.bootloader_agt.sequencer);
        
        #60ms;
        phase.drop_objection(this);
    endtask
endclass : soc_bootloader_test

// =============================================================================
// UART Focused Test
// =============================================================================
class soc_uart_test extends soc_base_test;
    `uvm_component_utils(soc_uart_test)
    
    function new(string name = "soc_uart_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        uart_seq seq;
        
        phase.raise_objection(this);
        
        seq = uart_seq::type_id::create("seq");
        seq.start(env.uart_agt.sequencer);
        
        #10us;
        phase.drop_objection(this);
    endtask
endclass : soc_uart_test

// =============================================================================
// GPIO Focused Test
// =============================================================================
class soc_gpio_test extends soc_base_test;
    `uvm_component_utils(soc_gpio_test)
    
    function new(string name = "soc_gpio_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        gpio_seq seq;
        
        phase.raise_objection(this);
        
        seq = gpio_seq::type_id::create("seq");
        seq.start(env.gpio_agt.sequencer);
        
        #50us;
        phase.drop_objection(this);
    endtask
endclass : soc_gpio_test


// =============================================================================
// SPI Focused Test
// =============================================================================
class soc_spi_test extends soc_base_test;
    `uvm_component_utils(soc_spi_test)
    
    function new(string name = "soc_spi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        spi_seq seq;
        
        phase.raise_objection(this);
        
        seq = spi_seq::type_id::create("seq");
        seq.start(env.spi_agt.sequencer);
        
        #10us;
        phase.drop_objection(this);
    endtask
endclass : soc_spi_test


// =============================================================================
// I2C Focused Test
// =============================================================================
class soc_i2c_test extends soc_base_test;
    `uvm_component_utils(soc_i2c_test)
    
    function new(string name = "soc_i2c_test", uvm_component parent = null);
        super.new(name, parent);
        `uvm_info("I2C TEST", "NEW", UVM_LOW)
    endfunction
    
    task run_phase(uvm_phase phase);
        i2c_seq seq;
        
        phase.raise_objection(this);
        
        seq = i2c_seq::type_id::create("seq");
        seq.start(env.i2c_agt.sequencer);
        
        #50us;
        phase.drop_objection(this);
    endtask
endclass : soc_i2c_test


// =============================================================================
// TIMER Test - Como não envia dados, não é necessário: consigo fazer uma seq sem enviar nada só para ver o funcionamento do Timer isolado?
// =============================================================================


// =============================================================================
// COMPLETE Focused Test
// =============================================================================
class soc_complete_test extends soc_base_test;
    `uvm_component_utils(soc_complete_test)
    
    function new(string name = "soc_complete_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        soc_virtual_seq seq;
        
        phase.raise_objection(this);
        
        seq = soc_virtual_seq::type_id::create("seq");
        seq.start(env.virtual_seqr);
        
        #10ms;
        phase.drop_objection(this);
    endtask
endclass : soc_complete_test

// =============================================================================
// NPU Base Test (Define a Sequência)
// =============================================================================
class npu_base_test extends soc_base_test;
    `uvm_component_utils(npu_base_test)
    
    function new(string name = "npu_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    task run_phase(uvm_phase phase);
        bootloader_seq boot_seq;
        npu_seq seq;
        uvm_event ev_initial_msg_done = uvm_event_pool::get_global("ev_initial_msg_done");
        
        phase.raise_objection(this);
        
        // 1. Aciona o bootloader para injetar o firmware.hex na memória
        `uvm_info("NPU TEST", "Iniciando o Bootloader...", UVM_LOW)
        boot_seq = bootloader_seq::type_id::create("boot_seq");
        boot_seq.start(env.bootloader_agt.sequencer);
        
        // 2. Aguarda a CPU acordar e enviar a mensagem "SOC IOT PICORV32"
        `uvm_info("NPU TEST", "Aguardando CPU iniciar e destravar o Monitor UART...", UVM_LOW)
        ev_initial_msg_done.wait_ptrigger();
        
        // 3. Inicia a sequência de envio das matrizes para a NPU
        `uvm_info("NPU TEST", "CPU Pronta! Iniciando cálculos da NPU...", UVM_LOW)
        seq = npu_seq::type_id::create("seq");
        seq.start(env.uart_agt.sequencer);
        
        // 4. Dá um tempo extra para a UART finalizar de receber o último pacote
        #5ms;
        
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// Teste 1: CONFIG_BASICA
// =============================================================================
class CONFIG_BASICA extends npu_base_test;
    `uvm_component_utils(CONFIG_BASICA)
    function new(string name = "CONFIG_BASICA", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(int)::set(this, "env.scoreboard.predictor", "bias_val", 0);
        uvm_config_db#(bit)::set(this, "env.scoreboard.predictor", "relu_en", 0);
    endfunction
endclass

// =============================================================================
// Teste 2: BIAS_0x0000_0001
// =============================================================================
class BIAS_0x0000_0001 extends npu_base_test;
    `uvm_component_utils(BIAS_0x0000_0001)
    function new(string name = "BIAS_0x0000_0001", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(int)::set(this, "env.scoreboard.predictor", "bias_val", 1);
        uvm_config_db#(bit)::set(this, "env.scoreboard.predictor", "relu_en", 0);
    endfunction
endclass

// =============================================================================
// Teste 3: RELU_LIGADA
// =============================================================================
class RELU_LIGADA extends npu_base_test;
    `uvm_component_utils(RELU_LIGADA)
    function new(string name = "RELU_LIGADA", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(int)::set(this, "env.scoreboard.predictor", "bias_val", 0);
        uvm_config_db#(bit)::set(this, "env.scoreboard.predictor", "relu_en", 1);
    endfunction
endclass

`endif // soc_test_SV