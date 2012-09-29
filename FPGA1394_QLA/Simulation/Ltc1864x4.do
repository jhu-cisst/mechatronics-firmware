restart -force

delete wave *
add wave clk seqn sclk conv
view wave

radix -hex
radix signal seqn -unsigned

# ------------------------------------------------------------------------------
force -freeze clk 1 0ns, 0 40ns -repeat 80ns
force seqn 0 @0ns -cancel @1ns
force conv 1 @0ns -cancel @1ns
# ------------------------------------------------------------------------------

run 10000 ns

WaveRestoreZoom 0ns 3000ns
WaveRestoreCursors {80ns} {2800ns} {8400ns}

echo Simulation completed.
