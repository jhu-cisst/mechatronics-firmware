
Verilog source code for the Xilinx FPGA on the FPGA1394 board
==================================================================

This repository contains the FPGA firmware, written in Verilog, for all versions
of the FPGA1394 board, currently Rev 1.x, Rev 2.x and Rev 3.x.

For an overview of the boards and firmware, see: https://jhu-cisst.github.io/mechatronics/

FPGA1394 Rev 1.x and Rev 2.x both use the Xilinx Spartan 6 FPGA, whereas Rev 3.x
uses the Xilinx Zynq 7000 SoC (FPGA + ARM processor). All board versions contain two
FireWire (IEEE-1394) connectors. The primary difference between
Rev 1.x and Rev 2.x is that the latter also contains an Ethernet port.
Rev 3.x contains two Ethernet ports.

For historical reasons, all source code is in the FPGA1394_QLA subdirectory, where
the name indicates that the FPGA1394 board was paired with the QLA.
Starting with firmware Rev 8, however, the FPGA1394 board can be paired with
other companion boards, including the DQLA (Dual QLA) and DRAC, and this
subdirectory contains all files to support these boards.

In the future, it may make sense to create separate subdirectories for functionality
specific to the FPGA1394 boards and to the different companion boards.

The project should be built using CMake and the Xilinx command line tools.
See the [wiki build instructions](https://github.com/jhu-cisst/mechatronics-firmware/wiki/FPGA-Build-Instructions).

Note that in March 2023, the V1 firmware designation was changed from FPGA1394-QLA to FPGA1394V1-QLA and
the V2 firmware designation was changed from FPGA1394Eth-QLA to FPGA1394V2-QLA.

Documentation for the firmware is on the wiki: https://github.com/jhu-cisst/mechatronics-firmware/wiki
