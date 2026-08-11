# ============================================================
# PicoRV32 AXI hard macro
# Clock: 40 MHz / 25 ns
#
# A interface AXI será conectada a outro hard macro no mesmo
# domínio de clock.
#
# Orçamento inicial:
#   - 4 ns para interconexão externa no setup;
#   - 0 ns no hold, condição conservadora.
# ============================================================

set clock_port clk

create_clock \
    -name $clock_port \
    -period $::env(CLOCK_PERIOD) \
    [get_ports $clock_port]

set clocks [get_clocks $clock_port]

# Sinais recebidos pelo mestre AXI.
set axi_inputs [get_ports {
    mem_axi_awready
    mem_axi_wready
    mem_axi_bvalid
    mem_axi_arready
    mem_axi_rvalid
    mem_axi_rdata*
}]

# Saídas AXI e trap.
set macro_outputs [all_outputs]

# Reserva de 4 ns para caminhos externos entre macros.
set_input_delay  -clock $clocks -max 4.0 $axi_inputs
set_input_delay  -clock $clocks -min 0.0 $axi_inputs

set_output_delay -clock $clocks -max 4.0 $macro_outputs
set_output_delay -clock $clocks -min 0.0 $macro_outputs

# Reset assíncrono.
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
    $axi_inputs

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    [get_ports clk]

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
set_load $cap_load $macro_outputs

set_clock_uncertainty \
    $::env(CLOCK_UNCERTAINTY_CONSTRAINT) \
    $clocks

set_clock_transition \
    $::env(CLOCK_TRANSITION_CONSTRAINT) \
    $clocks

set_timing_derate \
    -early \
    [expr 1 - ($::env(TIME_DERATING_CONSTRAINT) / 100.0)]

set_timing_derate \
    -late \
    [expr 1 + ($::env(TIME_DERATING_CONSTRAINT) / 100.0)]

if {
    [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] &&
    $::env(OPENLANE_SDC_IDEAL_CLOCKS)
} {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
