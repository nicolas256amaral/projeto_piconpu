create_clock -name clk0 -period 20.000 [get_ports clk0]
set_clock_uncertainty 0.250 [get_clocks clk0]
set_clock_transition 0.100 [get_clocks clk0]

set data_inputs [get_ports {csb0 web0 wmask0[*] addr0[*] din0[*]}]
set data_outputs [get_ports {dout0[*]}]

set_input_delay  -max 2.000 -clock clk0 $data_inputs
set_input_delay  -min 0.500 -clock clk0 $data_inputs
set_output_delay -max 2.000 -clock clk0 $data_outputs
set_output_delay -min 0.500 -clock clk0 $data_outputs

set_input_transition 0.200 $data_inputs
set_load 0.050 $data_outputs
