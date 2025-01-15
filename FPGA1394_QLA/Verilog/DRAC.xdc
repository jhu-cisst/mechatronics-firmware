################################################################################
# DRAC I/O Ports
################################################################################

# port PULLUP
set_property PULLUP true [get_ports {IO1[1]}]     # MISO prom
set_property PULLUP true [get_ports {IO1[2]}]     # MOSI prom
set_property PULLUP true [get_ports {IO1[3]}]     # SCLK prom
set_property PULLUP true [get_ports {IO1[4]}]     # /CS prom
set_property PULLUP true [get_ports {IO1[14]}]    # FAULTn[4]
set_property PULLUP true [get_ports {IO1[15]}]    # OTWn[4]
set_property PULLUP true [get_ports {IO1[26]}]    # RELAY_GOODn
set_property PULLUP true [get_ports {IO1[27]}]    # FAULTn[5]
set_property PULLUP true [get_ports {IO1[29]}]    # OTWn[5]
set_property PULLUP true [get_ports {IO1[30]}]    # ESPMV_GOODn

set_property PULLUP true [get_ports {IO2[4]}]     # OTWn[3]
set_property PULLUP true [get_ports {IO2[5]}]     # FAULTn[3]
set_property PULLUP true [get_ports {IO2[6]}]     # LVDS_RCLK
set_property PULLUP true [get_ports {IO2[7]}]     # LVDS_RDAT
set_property PULLUP true [get_ports {IO2[23]}]    # OTWn[2]
set_property PULLUP true [get_ports {IO2[25]}]    # FAULTn[2]
set_property PULLUP true [get_ports {IO2[33]}]    # FAULTn[1]
set_property PULLUP true [get_ports {IO2[35]}]    # OTWn[1]
