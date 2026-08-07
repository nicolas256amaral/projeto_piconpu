`ifndef NPU_PREDICTOR_SV
`define NPU_PREDICTOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class npu_predictor extends uvm_component;
    `uvm_component_utils(npu_predictor)

    // Porta para enviar o resultado esperado (4 bytes empacotados em 1 word)
    uvm_analysis_port #(bit[31:0]) ap_expected;

    // Configurações injetadas dinamicamente pelos testes
    int bias_val;
    bit relu_en;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap_expected = new("ap_expected", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Tenta buscar a configuração injetada pelo teste atual. Se não achar, assume 0.
        if (!uvm_config_db#(int)::get(this, "", "bias_val", bias_val)) bias_val = 0;
        if (!uvm_config_db#(bit)::get(this, "", "relu_en", relu_en)) relu_en = 0;
    endfunction

    // Função matemática que simula a arquitetura exata da NPU
    function void calculate_expected(byte w_bytes[16], byte a_bytes[16]);
        int acc[4];
        bit [31:0] expected_word = 0;

        for(int j=0; j<4; j++) acc[j] = 0;

        // O Array Sistólico Output Stationary multiplica A e W de forma cruzada
        // A linha 3 (base do Array) recebe as ativações A[t][3] cruzadas com os pesos W[t][j]
        for(int t=0; t<4; t++) begin
            byte act_t_3 = a_bytes[t*4 + 3]; // Pega o MSB de cada palavra da ativação
            for(int j=0; j<4; j++) begin
                byte w_t_j = w_bytes[t*4 + j]; // Pega o byte respectivo da coluna j
                acc[j] += int'(act_t_3) * int'(w_t_j);
            end
        end

        // Simulação exata do Pós-Processamento (PPU)
        for(int j=0; j<4; j++) begin
            acc[j] += bias_val;
            
            // Função de Ativação ReLU
            if (relu_en && acc[j] < 0) acc[j] = 0;
            
            // Saturação Dinâmica (Clamping 8-bit com sinal)
            if (acc[j] > 127) acc[j] = 127;
            if (acc[j] < -128) acc[j] = -128;
            
            // Empacota em 32-bits (MSB <- [Col 3 | Col 2 | Col 1 | Col 0] -> LSB)
            expected_word |= ( (acc[j] & 32'hFF) << (j * 8) );
        end

        `uvm_info("PREDICTOR", $sformatf("Matematica Resolvida -> Gabarito Esperado: 0x%08X", expected_word), UVM_HIGH)
        ap_expected.write(expected_word);
    endfunction
endclass

`endif // NPU_PREDICTOR_SV