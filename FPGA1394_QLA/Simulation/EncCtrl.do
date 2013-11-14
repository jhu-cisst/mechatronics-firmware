restart -force

delete wave *
add wave sysclk reset reg_we reg_addr reg_wdata reg_rdata set_enc mem_data
view wave

radix -hexadecimal
radix signal set_enc -binary

# ------------------------------------------------------------------------------
force -freeze sysclk 1 0ns, 0 10ns -repeat 20ns
force reset 0 @0ns, 1 @40ns

# write preload registers and check quad outputs (reg_rdata and mem_data)
force reg_we 0 @0ns, 1 @100ns, 0 @120ns, 1 @200ns, 0 @220ns, 1 @300ns, 0 @320ns, 1 @400ns, 0 @420ns
force reg_addr  0 @0ns, 16#0014 @90ns, 16#0024 @190ns, 16#0034 @290ns, 16#0044 @390ns
force reg_wdata 0 @0ns, 16#DD13 @90ns, 16#DD14 @190ns, 16#DD15 @290ns, 16#DD16 @390ns
# ------------------------------------------------------------------------------

run 4000 ns

WaveRestoreZoom 0ns 640ns
WaveRestoreCursors {81ns} {1249ns} {2490ns}

echo Simulation completed.
