# Build FPGA1394-QLA (FPGA Rev 1.x) and FPGA1394Eth-QLA (FPGA Rev 2.x)
#
# Tested on Windows 7, 64-bit, with NMAKE (VS 2008) and Xilinx ISE 14.3
# Tested on Ubuntu 12.04, 32-bit, with make (gcc 4.6.3) and Xilinx ISE 14.7

project(FPGA1394_QLA NONE)

# FPGA part number (-2 speed)
set (FPGA_PARTNUM "xc6slx45-2fgg484")

# Path to Verilog source code
set (VERILOG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Verilog")

# Path to generated IP cores
set (IPCORE_DIR         "${CMAKE_CURRENT_SOURCE_DIR}/ipcore_dir")

# Verilog source files used by both versions of firmware
set (VERILOG_SOURCE_COMMON "${VERILOG_SOURCE_DIR}/ClkDiv.v"
                           "${VERILOG_SOURCE_DIR}/Ltc2601x4.v"
                           "${VERILOG_SOURCE_DIR}/Ltc1864x4.v"
                           "${VERILOG_SOURCE_DIR}/LEDPWM.v"
                           "${VERILOG_SOURCE_DIR}/EncQuad.v"
                           "${VERILOG_SOURCE_DIR}/EncPeriod.v"
                           "${VERILOG_SOURCE_DIR}/Debounce.v"
                           "${VERILOG_SOURCE_DIR}/Crc32.v"
                           "${IPCORE_DIR}/pkt_mem_gen.v"
                           "${IPCORE_DIR}/hub_mem_gen.v"
                           "${VERILOG_SOURCE_DIR}/UartSerial.v"
                           "${VERILOG_SOURCE_DIR}/SafetyCheck.v"
                           "${VERILOG_SOURCE_DIR}/QLA25AA128.v"
                           "${VERILOG_SOURCE_DIR}/Max6576.v"
                           "${VERILOG_SOURCE_DIR}/M25P16.v"
                           "${VERILOG_SOURCE_DIR}/HubReg.v"
                           "${VERILOG_SOURCE_DIR}/FireWire.v"
                           "${VERILOG_SOURCE_DIR}/CtrlLED.v"
                           "${VERILOG_SOURCE_DIR}/CtrlEnc.v"
                           "${VERILOG_SOURCE_DIR}/CtrlDout.v"
                           "${VERILOG_SOURCE_DIR}/CtrlDac.v"
                           "${VERILOG_SOURCE_DIR}/CtrlAdc.v"
                           "${VERILOG_SOURCE_DIR}/BoardRegs.v"
                           "${VERILOG_SOURCE_DIR}/DS2505.v"
			   "${VERILOG_SOURCE_DIR}/DataBuffer.v"
			   "${IPCORE_DIR}/Dual_port_RAM_32X1024.v")

# Verilog source files for Rev 1 firmware
set (VERILOG_SOURCE_REV1 ${VERILOG_SOURCE_COMMON}
                         "${VERILOG_SOURCE_DIR}/FPGA1394-QLA.v")

# Verilog source files for Rev 2 firmware
set (VERILOG_SOURCE_REV2 ${VERILOG_SOURCE_COMMON}
                         "${VERILOG_SOURCE_DIR}/EthernetIO.v"
                         "${VERILOG_SOURCE_DIR}/SampleData.v"
                         "${VERILOG_SOURCE_DIR}/FPGA1394Eth-QLA.v")

# Compile the Rev 1 firmware -- output is FPGA1394-QLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394QLA"
                 FPGA_PARTNUM   ${FPGA_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_REV1}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45.ucf"
                 IPCORE_DIR     ${IPCORE_DIR}
                 TOP_LEVEL      "FPGA1394QLA"
                 PROJ_OUTPUT    "FPGA1394-QLA")

# Compile the Rev 2 firmware -- output is FPGA1394Eth-QLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394EthQLA"
                 FPGA_PARTNUM   ${FPGA_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_REV2}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45-Rev2.ucf"
                 IPCORE_DIR     ${IPCORE_DIR}
                 TOP_LEVEL      "FPGA1394EthQLA"
                 PROJ_OUTPUT    "FPGA1394Eth-QLA")

add_custom_target(timing
                  DEPENDS FPGA1394QLA-timing FPGA1394EthQLA-timing)

# Copy MCS files to Generated folder in source tree (if different)
add_custom_target(generated)

add_custom_command(TARGET generated POST_BUILD
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394-QLA.mcs
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394-QLA.mcs
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394Eth-QLA.mcs
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394Eth-QLA.mcs
                   COMMENT "Copying MCS files to source \"Generated\" directory (if different)")
