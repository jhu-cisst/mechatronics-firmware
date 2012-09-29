restart -force

delete wave *
add wave clk reset set_enc a b ticks code count dir overflow
view wave

radix -hexadecimal
radix signal count -unsigned

# ------------------------------------------------------------------------------
force -freeze clk 1 0ns, 0 10ns -repeat 20ns
force reset 0 @0ns, 1 @40ns
force preload 10#21
force set_enc 0 @0ns, 1 @140ns, 0 @160ns, 1 @7600ns, 0 @7620ns
# ------------------------------------------------------------------------------

# simulate preload trigger (set_enc) arrival with encoders not moving
force a 0
force b 0
run 500ns

# move encoders, check if counter works
force a 0 0ns, 1  60ns, 0 180ns -repeat 240ns -cancel 1700ns
force b 0 0ns, 1 120ns          -repeat 240ns -cancel 1700ns
run 1700 ns

# change encoder direction, check direction and overflow flags
force a 0 0ns, 1 80ns, 0 200ns -repeat 240ns -cancel 3770ns
force b 0 0ns, 1 20ns, 0 140ns -repeat 240ns -cancel 3770ns
run 3770 ns

# change directions again, make sure overflow still flagged
#   also check if preload works
force a 1 0ns, 0 90ns, 1 210ns -repeat 240ns -cancel 2030ns
force b 0 0ns, 1 30ns, 0 150ns -repeat 240ns -cancel 2030ns
run 2030 ns

WaveRestoreZoom 6000ns 8040ns
WaveRestoreCursors {2200ns} {5970ns} {7600ns}

echo Simulation completed.
