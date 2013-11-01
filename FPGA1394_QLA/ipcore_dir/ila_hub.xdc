#
# Clock constraints
#
set_false_path -from [get_cells -hierarchical * -filter {NAME =~ */U0/*/U_STAT/U_DIRTY_LDC}] -to [all_registers -edge_triggered]
set_false_path -from [all_registers -edge_triggered] -to [get_cells -hierarchical * -filter {NAME =~ */U0/*/U_STAT/U_DIRTY_LDC}]
set_false_path -from [get_cells -of_object [get_nets -hierarchical CLK]] -to [get_cells -of_object [get_nets -hierarchical CONTROL[0]]]
set_false_path -from [get_cells -of_object [get_nets -hierarchical CONTROL[0]]] -to [get_cells -of_object [get_nets -hierarchical CLK]]

#
# Input keep/save net constraints
#
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG0*}]
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG1*}]
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG2*}]
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG3*}]
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG4*}]
set_property DONT_TOUCH 1 [get_nets -hierarchical * -filter {NAME =~ */TRIG5*}]
