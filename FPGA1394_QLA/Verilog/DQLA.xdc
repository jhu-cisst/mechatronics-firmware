################################################################################
# DQLA I/O Ports
################################################################################

# port PULLUP
set_property PULLUP true [get_ports {IO1[1]}]  ;  # MISO prom_qla
set_property PULLUP true [get_ports {IO1[2]}]  ;  # MOSI prom_qla
set_property PULLUP true [get_ports {IO1[3]}]  ;  # SCLK prom_qla
set_property PULLUP true [get_ports {IO1[4]}]  ;  # /Q2-EEPROM
set_property PULLUP true [get_ports {IO1[10]}] ;  # /Q1-EXP-CS
set_property PULLUP true [get_ports {IO1[11]}] ;  # Q2-DIR34
set_property PULLUP true [get_ports {IO1[12]}] ;  # /Q2-EXP-CS
set_property PULLUP true [get_ports {IO1[15]}] ;  # /QS-IOEXP
set_property PULLUP true [get_ports {IO1[26]}] ;  # Q1-MISO-P2
set_property PULLUP true [get_ports {IO1[27]}] ;  # Q1-MISO-P1
set_property PULLUP true [get_ports {IO1[28]}] ;  # /Q1-EEPROM
set_property PULLUP true [get_ports {IO1[29]}] ;  # Q1-MISO-P4
set_property PULLUP true [get_ports {IO1[30]}] ;  # Q1-MISO-P3
set_property PULLUP true [get_ports {IO1[31]}] ;  # /Q1-IOEXP

set_property PULLUP true [get_ports {IO2[1]}]  ;  # Q1-MISO-C2
set_property PULLUP true [get_ports {IO2[3]}]  ;  # Q1-MISO-C1
set_property PULLUP true [get_ports {IO2[5]}]  ;  # Q1-MISO-C4
set_property PULLUP true [get_ports {IO2[6]}]  ;  # Q1-MISO-C3
set_property PULLUP true [get_ports {IO2[7]}]  ;  # Q1-Temp1
set_property PULLUP true [get_ports {IO2[8]}]  ;  # Q1-Temp2
set_property PULLUP true [get_ports {IO2[9]}]  ;  # Q2-MISO-P2
set_property PULLUP true [get_ports {IO2[10]}] ;  # Q2-MISO-P1
set_property PULLUP true [get_ports {IO2[11]}] ;  # Q2-MISO-P4
set_property PULLUP true [get_ports {IO2[12]}] ;  # Q2-MISO-P3
set_property PULLUP true [get_ports {IO2[13]}] ;  # Q1-LIM-P4
set_property PULLUP true [get_ports {IO2[14]}] ;  # Q1-LIM-P3
set_property PULLUP true [get_ports {IO2[15]}] ;  # Q2-MISO-C4
set_property PULLUP true [get_ports {IO2[16]}] ;  # Q2-MISO-C1
set_property PULLUP true [get_ports {IO2[17]}] ;  # Q2-MISO-C2
set_property PULLUP true [get_ports {IO2[18]}] ;  # Q2-MISO-C3
set_property PULLUP true [get_ports {IO2[19]}] ;  # Q2-Temp2
set_property PULLUP true [get_ports {IO2[20]}] ;  # Q2-Temp1
set_property PULLUP true [get_ports {IO2[21]}] ;  # Q2-LIM-P4
set_property PULLUP true [get_ports {IO2[22]}] ;  # Q1-ENC-A1
set_property PULLUP true [get_ports {IO2[23]}] ;  # Q2-LIM-P3
set_property PULLUP true [get_ports {IO2[24]}] ;  # Q1-ENC-A2
set_property PULLUP true [get_ports {IO2[25]}] ;  # Q2-ENC-A1
set_property PULLUP true [get_ports {IO2[26]}] ;  # Q1-ENC-A3
set_property PULLUP true [get_ports {IO2[27]}] ;  # Q2-ENC-A2
set_property PULLUP true [get_ports {IO2[28]}] ;  # Q1-ENC-A4
set_property PULLUP true [get_ports {IO2[29]}] ;  # Q2-ENC-A3
set_property PULLUP true [get_ports {IO2[30]}] ;  # Q1-ENC-B1
set_property PULLUP true [get_ports {IO2[31]}] ;  # Q2-ENC-A4
set_property PULLUP true [get_ports {IO2[32]}] ;  # Q1-ENC-B2
set_property PULLUP true [get_ports {IO2[33]}] ;  # Q2-ENC-B1
set_property PULLUP true [get_ports {IO2[34]}] ;  # Q1-ENC-B3
set_property PULLUP true [get_ports {IO2[35]}] ;  # Q2-ENC-B2
set_property PULLUP true [get_ports {IO2[36]}] ;  # Q1-ENC-B4
set_property PULLUP true [get_ports {IO2[37]}] ;  # Q2-ENC-B3
set_property PULLUP true [get_ports {IO2[38]}] ;  # Q2-ENC-B4

# Create generated clocks
create_generated_clock -name clk_12m -source [get_ports clk1394] -divide_by [expr {2**2}] [get_pins div2clk/clkout_reg/Q]

create_generated_clock -name clk400k -source [get_ports clk1394] -divide_by 122 [get_pins divtemp/clkout_reg/Q]

create_generated_clock -name clk_delay -source [get_ports clk1394] -divide_by [expr {2**10}] [get_pins dqla/div32clk/clkout_reg/Q]

create_generated_clock -name clk_12hz -source [get_ports clk1394] -divide_by [expr {2**22}] [get_pins dqla/divclk12/clkout_reg/Q]

create_generated_clock -name led_clk_768khz -source [get_ports clk1394] -divide_by [expr {2**6}] [get_pins dqla/qla_led/div768khz/clkout_reg/Q]

create_generated_clock -name led_clk_pwm -source [get_ports clk1394] -divide_by [expr {2**18}] [get_pins dqla/qla_led/divpwm/clkout_reg/Q]

create_generated_clock -name led_clk_pwm_width -source [get_ports clk1394] -divide_by [expr {2**19}] [get_pins dqla/qla_led/divpw/clkout_reg/Q]
