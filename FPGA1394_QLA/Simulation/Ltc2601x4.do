# ------------------------------------------------------------------------------
# restart to allow rerunning after editing this file
restart -force

# circuit delay info (for circuit simulation, not logic simulation)
#vsim -sdftyp proj_timesim.sdf proj

# ------------------------------------------------------------------------------
# wave window with signals specified with hierarchy
delete wave *
add wave clkin wr csel sclk mosi busy
view wave

# ------------------------------------------------------------------------------
# default display radix: -unsigned, -signed, -hex, -binary, -decimal, etc.
#radix -hexadecimal
#radix signal clkin -unsigned

# ------------------------------------------------------------------------------
# setup for list window log ("write list log.lst"); trigger/sample
#configure list -usestrobe 0 -usesignaltrigger 1 -timeunits ns
#configure list -usestrobe 1 -strobestart {0 ns} -strobeperiod {20 ns} -timeunits ns
#delete list *
#add list -delta none -width 11 -trigger sig1 -notrigger sig2 sig3
#view list

# ------------------------------------------------------------------------------
# forcing signal states, relative/absolute
force -freeze clkin 1 0ns, 0 10ns -repeat 20ns
force reset 0 @0ns, 1 @40ns

force c1 16#9
force c2 16#9
force c3 16#9
force c4 16#9
force d1 16#AAAA
force d2 16#5555
force d3 16#AAAA
force d4 16#5555

force wr 0 @0ns, 1 @100ns, 0 @200ns
#noforce signame

# ------------------------------------------------------------------------------
# enable breakpoints and setup breakpoint action sequences
#enablebp
#when {clkin'event and clkin='0'} {force sig1 1;}
#when {sig2'event and sig2='1'} {echo "***Successful Latch of sig2 at $now ";}
#onerror {echo "Error at time $now"; abort;}

# ------------------------------------------------------------------------------
# run simulation for specified interval (default in .ini file)
run 5400 ns

# set time scale and cursors on the wave window (case sensitive)
WaveRestoreZoom 0ns 5600ns
#WaveRestoreCursors {4000ns} {4900ns}

echo Simulation completed.
