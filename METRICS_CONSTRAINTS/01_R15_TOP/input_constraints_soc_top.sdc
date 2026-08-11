create_clock \
    -name clk \
    -period 20.000 \
    [get_ports clk]

set_clock_uncertainty 0.200 [get_clocks clk]

set non_clock_inputs [get_ports -quiet {

    ext_axi_awready
    ext_axi_wready
    ext_axi_bvalid
    ext_axi_arready
    ext_axi_rdata[*]
    ext_axi_rvalid
}]

if {[llength $non_clock_inputs] > 0} {
    set_input_delay \
        -clock [get_clocks clk] \
        2.000 \
        $non_clock_inputs
}

set external_outputs [get_ports -quiet {
    trap
    irq_done

    ext_axi_awaddr[*]
    ext_axi_awprot[*]
    ext_axi_awvalid

    ext_axi_wdata[*]
    ext_axi_wstrb[*]
    ext_axi_wvalid

    ext_axi_bready

    ext_axi_araddr[*]
    ext_axi_arprot[*]
    ext_axi_arvalid

    ext_axi_rready
}]

if {[llength $external_outputs] > 0} {
    set_output_delay \
        -clock [get_clocks clk] \
        2.000 \
        $external_outputs
}

set reset_port [get_ports -quiet resetn]

if {[llength $reset_port] > 0} {
    set_false_path -from $reset_port
}

set_propagated_clock [get_clocks clk]
