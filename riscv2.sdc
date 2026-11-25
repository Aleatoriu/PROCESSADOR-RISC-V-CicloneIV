
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

create_generated_clock -name PIXEL_CLK -source [get_ports {CLOCK_50}] \
    -divide_by 2 [get_registers {*u_sync|pclk}]


create_clock -name PROC_CLK -period 40.000 [get_registers {*proc_clk_r}]

derive_clock_uncertainty


set_clock_groups -asynchronous \
    -group {CLOCK_50 PIXEL_CLK} \
    -group {PROC_CLK}

set_false_path -from [get_ports {KEY[*] SW[*] PS2_CLK PS2_DAT}]
set_false_path -to   [get_ports {LEDR[*] LEDG[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] HEX6[*] HEX7[*] LCD_*}]
