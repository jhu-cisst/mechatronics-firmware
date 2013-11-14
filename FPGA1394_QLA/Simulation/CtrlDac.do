restart -force

delete wave *
add wave reset blk_wen sysclk addr_dac dac/data sclk csel mosi dac/word dac/count
view wave

radix -unsigned
radix signal dac/data -hexadecimal
radix signal dac/word -hexadecimal

# ------------------------------------------------------------------------------
force -freeze sysclk 1 0ns, 0 10ns -repeat 20ns
force reset 0 @0ns, 1 @40ns
force blk_wen 0 @0ns, 1 @100ns, 0 @200ns
# ------------------------------------------------------------------------------

run 5400 ns

WaveRestoreZoom 0ns 5600ns
WaveRestoreCursors {100 ns}

echo Simulation completed.
