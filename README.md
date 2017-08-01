
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

The project can be built using CMake and the Xilinx command line tools, or by loading
one of the project files (FPGA1394-QLA.xise or FPGA1394Eth-QLA.xise) into Xilinx ISE.
When using CMake on Windows, choose the *NMake Makefiles* generator.

CMake will automatically find the Xilinx command line tools if the Xilinx binary directory
is in the `PATH`.  Otherwise, the easiest way to find them is to first set the `XILINX_ISE_BINARY_DIR`
variable in CMake and then configure again, which allow CMake to automatically find them.
It is not necessary to add the Xilinx binary directory to your PATH (or LD_LIBRARY_PATH on Linux)
to be able to compile the software using the CMake-generated makefiles.

Running `make` (on Linux) or `nmake` (on Windows) will build both versions of firmware,
and will update the MCS files in the source tree (`Generated` directory) if they are
different. It will not run the timing analysis (Xilinx ISE `trce` tool). The timing
(for both versions) can be run by invoking `make timing` or `nmake timing`.

Documentation for the firmware is on the wiki: http://github.com/jhu-cisst/mechatronics-firmware/wiki

For an overview of the boards and firmware, see: http://jhu-cisst.github.io/mechatronics/

