restart -force

delete wave *
add wave sysclk state ctl data buffer count crc_inv crc_in
view wave

radix -hexadecimal
radix signal state -unsigned
radix signal count -decimal

# ------------------------------------------------------------------------------
force -freeze sysclk 1 0ns, 0 10ns -repeat 20ns
force reset 0 @0ns, 1 @40ns

force state 0 @0ns, 16#4 @60ns -cancel @61ns
force tx_type 16#4

force rx_dest 16#5555
force rx_src 16#1249
force rx_tag 16#0
force reg_rdata 16#AAAAAAAA
# ------------------------------------------------------------------------------

run 600 ns

WaveRestoreZoom 50ns 550ns
WaveRestoreCursors {420ns} {500ns}

echo Simulation completed.
