# False Paths
#set_clock_groups -asynchronous -group {clk_kernel_psl_to_kernel} -group {userclk2}
#set_clock_groups -asynchronous -group {clk_out1_clk_div} -group {userclk2}

create_generated_clock -name clkdiv2 -source [get_pins a0/ha0_pclock] -divide_by 2 [get_pins a0/action_w/action_0/arrow_pairhmm_inst/pairhmm_gen[0].pairhmm_inst/kernel_clock_gen/clk_out1]
create_generated_clock -name clkkernel -source [get_pins get_pins a0/action_w/action_0/arrow_pairhmm_inst/pairhmm_gen[0].pairhmm_inst/kernel_clock_gen/clk_out1] -divide_by 2 [get_pins a0/action_w/action_0/arrow_pairhmm_inst/pairhmm_gen[0].pairhmm_inst/kernel_clock_gen/clk_out1]
