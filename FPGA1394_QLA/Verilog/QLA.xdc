################################################################################
# QLA I/O Ports
################################################################################

# port PULLUP
set_property PULLUP true [get_ports {IO1[1]}]  ;  # MISO prom_qla
set_property PULLUP true [get_ports {IO1[2]}]  ;  # MOSI prom_qla
set_property PULLUP true [get_ports {IO1[3]}]  ;  # SCLK prom_qla
set_property PULLUP true [get_ports {IO1[4]}]  ;  # /EEPROM
set_property PULLUP true [get_ports {IO1[5]}]  ;  # Dir34
set_property PULLUP true [get_ports {IO1[6]}]  ;  # Dir12
set_property PULLUP true [get_ports {IO1[7]}]  ;  # /MV-FLT (QLA 1.4+)
set_property PULLUP true [get_ports {IO1[8]}]  ;  # /IOEXP (QLA 1.5+)
set_property PULLUP true [get_ports {IO1[9]}]  ;  # /V-FAULT
set_property PULLUP true [get_ports {IO1[12]}] ;  # MISO-P4 (pot 4)
set_property PULLUP true [get_ports {IO1[13]}] ;  # MISO-P3 (pot 3)
set_property PULLUP true [get_ports {IO1[14]}] ;  # MISO-P2 (pot 2)
set_property PULLUP true [get_ports {IO1[15]}] ;  # MISO-P1 (pot 1)
set_property PULLUP true [get_ports {IO1[23]}] ;  # MISO-C1 (cur 1)
set_property PULLUP true [get_ports {IO1[24]}] ;  # MISO-C2 (cur 2)
set_property PULLUP true [get_ports {IO1[25]}] ;  # MISO-C3 (cur 3)
set_property PULLUP true [get_ports {IO1[26]}] ;  # MISO-C4 (cur 4)
set_property PULLUP true [get_ports {IO1[29]}] ;  # Temp1
set_property PULLUP true [get_ports {IO1[30]}] ;  # Temp2

set_property PULLUP true [get_ports {IO2[2]}]  ;  # ENC-I4
set_property PULLUP true [get_ports {IO2[4]}]  ;  # ENC-I3
set_property PULLUP true [get_ports {IO2[6]}]  ;  # ENC-I2
set_property PULLUP true [get_ports {IO2[8]}]  ;  # ENC-I1
set_property PULLUP true [get_ports {IO2[9]}]  ;  # Relay status
set_property PULLUP true [get_ports {IO2[10]}] ;  # ENC-B4
set_property PULLUP true [get_ports {IO2[12]}] ;  # ENC-B3
set_property PULLUP true [get_ports {IO2[13]}] ;  # ENC-B2
set_property PULLUP true [get_ports {IO2[14]}] ;  # LIM-H1
set_property PULLUP true [get_ports {IO2[15]}] ;  # ENC-B1
set_property PULLUP true [get_ports {IO2[16]}] ;  # LIM-H2
set_property PULLUP true [get_ports {IO2[17]}] ;  # ENC-A4
set_property PULLUP true [get_ports {IO2[18]}] ;  # LIM-H3
set_property PULLUP true [get_ports {IO2[19]}] ;  # ENC-A3
set_property PULLUP true [get_ports {IO2[20]}] ;  # LIM-H4
set_property PULLUP true [get_ports {IO2[21]}] ;  # ENC-A2
set_property PULLUP true [get_ports {IO2[22]}] ;  # LIM-N1
set_property PULLUP true [get_ports {IO2[23]}] ;  # ENC-A1
set_property PULLUP true [get_ports {IO2[24]}] ;  # LIM-N3
set_property PULLUP true [get_ports {IO2[25]}] ;  # LIM-N2
set_property PULLUP true [get_ports {IO2[26]}] ;  # LIM-N4
set_property PULLUP true [get_ports {IO2[27]}] ;  # LIM-P1
set_property PULLUP true [get_ports {IO2[28]}] ;  # LIM-P2
set_property PULLUP true [get_ports {IO2[29]}] ;  # LIM-P3
set_property PULLUP true [get_ports {IO2[30]}] ;  # LIM-P4

# port PULLDOWN
set_property PULLDOWN true [get_ports {IO2[11]}] ; # MV-GOOD
set_property PULLDOWN true [get_ports {IO2[31]}] ; # /FAULT 1 (1=amp_on)
set_property PULLDOWN true [get_ports {IO2[33]}] ; # /FAULT 2 (1=amp_on)
set_property PULLDOWN true [get_ports {IO2[35]}] ; # /FAULT 3 (1=amp_on)
set_property PULLDOWN true [get_ports {IO2[37]}] ; # /FAULT 4 (1=amp_on)

# Create generated clocks
create_generated_clock -name clk_12m -source [get_ports clk1394] -divide_by [expr {2**2}] [get_pins div2clk/clkout_reg/Q]

create_generated_clock -name clk400k -source [get_ports clk1394] -divide_by 122 [get_pins divtemp/clkout_reg/Q]

create_generated_clock -name clk_delay -source [get_ports clk1394] -divide_by [expr {2**10}] [get_pins qla/div32clk/clkout_reg/Q]

create_generated_clock -name clk_12hz -source [get_ports clk1394] -divide_by [expr {2**22}] [get_pins qla/divclk12/clkout_reg/Q]

create_generated_clock -name led_clk_768khz -source [get_ports clk1394] -divide_by [expr {2**6}] [get_pins qla/qla_led/div768khz/clkout_reg/Q]

create_generated_clock -name led_clk_pwm -source [get_ports clk1394] -divide_by [expr {2**18}] [get_pins qla/qla_led/divpwm/clkout_reg/Q]

create_generated_clock -name led_clk_pwm_width -source [get_ports clk1394] -divide_by [expr {2**19}] [get_pins qla/qla_led/divpw/clkout_reg/Q]
