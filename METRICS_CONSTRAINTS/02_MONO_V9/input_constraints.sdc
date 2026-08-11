# PicoRV32 + NPU real - restricoes de fechamento fisico V9
# Clock alvo de signoff: 40 MHz (25 ns).
#
# Diagnostico da V8 no STA pos-PnR:
# - setup max_ss_100C_1v60: WNS -2.343295 ns em 20 ns;
# - hold max_ss_100C_1v60: WNS -1.300009 ns;
# - setup critico interno na NPU (registrador -> registrador);
# - hold SS apenas em entradas AXI -> registradores;
# - corners TT fecharam hold na V8.
#
# Estrategia V9:
# - aumentar o periodo de 20 ns para 25 ns;
# - manter os atrasos de entrada comprovados nos corners TT;
# - executar reparo fisico de hold nos corners SS criticos;
# - preservar setup com margens e proibir reparo que aceite setup negativo.
#
# Observacao de interface:
# Os atrasos de I/O continuam provisórios e devem ser substituidos pelos
# valores reais do componente AXI externo no signoff da placa.

set clock_port clk
create_clock -name $clock_port -period $::env(CLOCK_PERIOD) [get_ports $clock_port]
set clocks [get_clocks $clock_port]

set data_inputs_other [get_ports {
    ext_axi_awready
    ext_axi_wready
    ext_axi_arready
    ext_axi_rvalid
    ext_axi_rdata*
}]

set data_inputs_bvalid [get_ports {
    ext_axi_bvalid
}]

set data_inputs_all [get_ports {
    ext_axi_awready
    ext_axi_wready
    ext_axi_bvalid
    ext_axi_arready
    ext_axi_rvalid
    ext_axi_rdata*
}]

set data_outputs [all_outputs]

set_input_delay  -clock $clocks -max 4.0 $data_inputs_all
set_input_delay  -clock $clocks -min 2.6 $data_inputs_other
set_input_delay  -clock $clocks -min 2.8 $data_inputs_bvalid
set_output_delay -clock $clocks -max 4.0 $data_outputs
set_output_delay -clock $clocks -min 0.0 $data_outputs

# resetn e assincrono; a desativacao deve ser sincronizada pelo integrador.
set_false_path -from [get_ports resetn]

if { [info exists ::env(MAX_FANOUT_CONSTRAINT)] } {
    set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    $data_inputs_all

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    [get_ports clk]

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
set_load $cap_load $data_outputs

set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks

set_timing_derate -early [expr 1 - ($::env(TIME_DERATING_CONSTRAINT) / 100.0)]
set_timing_derate -late  [expr 1 + ($::env(TIME_DERATING_CONSTRAINT) / 100.0)]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
