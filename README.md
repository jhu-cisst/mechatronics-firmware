
Verilog source code for the Xilinx Spartan 6 on the FPGA1394 board
==================================================================

The FPGA1394_QLA subdirectory is the source code for the FPGA1394 board paired
with the QLA. Currently, the QLA is the only supported companion board, but
support for other boards could be added in different sub-directories. In that
case, it would make sense to make a separate sub-directory for functionality
on the FPGA1394 board, such as the FireWire interface, so that it can
be shared between the different board configurations.

Note that there are two versions of the FPGA1394 board, Rev 1.x and Rev 2.x,
where the latter version also contains an Ethernet interface. Thus, there
are two main Verilog modules: FPGA1394_QLA.v (for Rev 1.x) and FPGA1394Eth_QLA.v
(for Rev 2.x).

Documentation for the firmware is on the wiki: http://github.com/jhu-cisst/mechatronics-firmware/wiki

For an overview of the boards and firmware, see: http://jhu-cisst.github.io/mechatronics/

