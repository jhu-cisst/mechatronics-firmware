
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
When using CMake on Windows, choose the *NMake Makefiles* generator [Update: CMake dependency
checking seems to be broken on Windows].

CMake will automatically find the Xilinx command line tools if the Xilinx binary directory
is in the `PATH`.  Otherwise, the easiest way to find them is to first set the `XILINX_ISE_BINARY_DIR`
variable in CMake and then configure again, which allow CMake to automatically find them.
It is not necessary to add the Xilinx binary directory to your PATH (or LD_LIBRARY_PATH on Linux)
to be able to compile the software using the CMake-generated makefiles.
On Linux, it is better not to modify your environment (e.g., do not run `source settings64.sh`,
as recommended by Xilinx) because the Xilinx versions of the system libraries, such as `libstdc++.so.6`,
are likely to be incompatible with other software.

Running `make` (on Linux) or `nmake` (on Windows) will build both versions of firmware.
It will not run the timing analysis (Xilinx ISE `trce` tool). The timing
(for both versions) can be run by invoking `make timing` or `nmake timing`.
In addition, typing `make generated` or `nmake generated` will copy the MCS files from
the build tree to the source tree (`Generated` directory) if they are different.
Note that if you have forgotten to get a Xilinx ISE license file, the first few steps will work
and the build will fail when running the `map` tool.

Getting a license file for Xilinx ISE on recent versions of Linux, such as Ubuntu 16.04, is problematic.
In this case, you should run `source settings64.sh` (or `source settings32.sh`) and then run either `ise` (for the IDE,
which will then invoke the license manager) or directly run the license manager, `xlcm`. Then,
either or both of the following changes may be necessary:
1. Set `GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"` in `\etc\default\grub`, invoke `update-grub` and reboot. This sets your network interface to `eth0`, which is required by the license manager (otherwise, it does not find the MAC address).
2. If you are using Firefox, the license manager may fail to launch Firefox, showing an error such as `GLIBCXX_3.4.10` not found. This can be fixed by replacing the `libstdc++.so.6` in the Xilinx `common/lib/lin64` directory with a soft link to the standard library (e.g., in `/usr/lib/x86_64-linux-gnu`). This change can be reverted after getting the license file.

Documentation for the firmware is on the wiki: http://github.com/jhu-cisst/mechatronics-firmware/wiki

For an overview of the boards and firmware, see: http://jhu-cisst.github.io/mechatronics/

