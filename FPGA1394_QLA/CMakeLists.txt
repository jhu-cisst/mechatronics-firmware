# Build all supported combinations of FPGA versions and boards
#
#   FPGAV1 + QLA
#   FPGAV2 + QLA
#   FPGAV3 + QLA
#   FPGAV3 + DQLA
#
# Tested on Windows 7, 64-bit, with NMAKE (VS 2008) and Xilinx ISE 14.3
# Tested on Ubuntu 16.04, 64-bit, with make (gcc 5.4.0) and Xilinx ISE 14.7

project(FPGA1394_QLA NONE)

# FPGA part number
set (FPGA_FAMILY  "spartan6")
set (FPGA_DEVICE  "xc6slx45")
set (FPGA_PACKAGE "fgg484")
set (FPGA_SPEED   "-2")
set (FPGA_PARTNUM "${FPGA_DEVICE}${FPGA_SPEED}${FPGA_PACKAGE}")

set (FPGAV3_FAMILY  "zynq")
set (FPGAV3_DEVICE  "xc7z020")
set (FPGAV3_PACKAGE "clg400")
set (FPGAV3_SPEED   "-3")
set (FPGAV3_PARTNUM "${FPGAV3_DEVICE}${FPGAV3_SPEED}${FPGAV3_PACKAGE}")

# Path to Verilog source code
set (VERILOG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Verilog")

# Paths to IP core files (source and build)
# By default, use files in build tree (IPCORE_BINARY_DIR and IPCOREV3_BINARY_DIR)
set (IPCORE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ipcore_dir")
set (IPCORE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcore_dir")
set (IPCOREV3_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcorev3_dir")
set (XPSCORE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcorev3_dir/xps")

add_subdirectory(ipcore_dir)
add_subdirectory(ipcorev3_dir)

###################### Common Files ####################################

# Source files for everything (could also include Constants.v)
set (VERILOG_SOURCE_COMMON "${VERILOG_SOURCE_DIR}/ClkDiv.v")

##################### FPGA Versions ####################################

# Source files for all versions of FPGA
set (VERILOG_SOURCE_FPGA "${VERILOG_SOURCE_DIR}/Crc32.v"
                         "${VERILOG_SOURCE_DIR}/HubReg.v"
                         "${VERILOG_SOURCE_DIR}/FireWire.v"
                         "${VERILOG_SOURCE_DIR}/BoardRegs.v")

# Source files for FPGA V1 and V2
set (VERILOG_SOURCE_FPGAV1_V2
                         ${VERILOG_SOURCE_FPGA}
                         "${IPCORE_BINARY_DIR}/hub_mem_gen.v"
                         "${VERILOG_SOURCE_DIR}/UartSerial.v"
                         "${VERILOG_SOURCE_DIR}/M25P16.v"
                         "${IPCORE_BINARY_DIR}/Dual_port_RAM_32X1024.v"
                         "${VERILOG_SOURCE_DIR}/Reboot.v")

# Source files for FPGA V1
set (VERILOG_SOURCE_FPGAV1
                         ${VERILOG_SOURCE_FPGAV1_V2}
                         "${VERILOG_SOURCE_DIR}/FPGA1394V1.v")

# Source files for FPGA V2
set (VERILOG_SOURCE_FPGAV2
                         ${VERILOG_SOURCE_FPGAV1_V2}
                         "${VERILOG_SOURCE_DIR}/FPGA1394V2.v"
                         "${VERILOG_SOURCE_DIR}/KSZ8851.v"
                         "${VERILOG_SOURCE_DIR}/EthernetIO.v")

# Source files for FPGA V3
set (VERILOG_SOURCE_FPGAV3
                         ${VERILOG_SOURCE_FPGA}
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3.v"
                         "${VERILOG_SOURCE_DIR}/RTL8211F.v"
                         "${VERILOG_SOURCE_DIR}/EthernetIO.v"
                         "${IPCOREV3_BINARY_DIR}/hub_mem_gen.v"
                         "${IPCOREV3_BINARY_DIR}/Dual_port_RAM_32X1024.v"
                         "${IPCOREV3_BINARY_DIR}/fifo_8x8192_16.v"
                         "${IPCOREV3_BINARY_DIR}/fifo_16x2048_8.v"
                         "${IPCOREV3_BINARY_DIR}/fifo_32x32.v"
                         "${XPSCORE_BINARY_DIR}/hdl/fpgav3.v")

################### Boards (QLA, DQLA, DRAC) ###########################

# Source files used by QLA and DQLA
set (VERILOG_SOURCE_QLA_DQLA
                           "${VERILOG_SOURCE_DIR}/Ltc2601x4.v"
                           "${VERILOG_SOURCE_DIR}/Ltc1864x4.v"
                           "${VERILOG_SOURCE_DIR}/LEDPWM.v"
                           "${VERILOG_SOURCE_DIR}/EncQuad.v"
                           "${VERILOG_SOURCE_DIR}/EncPeriod.v"
                           "${VERILOG_SOURCE_DIR}/Debounce.v"
                           "${VERILOG_SOURCE_DIR}/SafetyCheck.v"
                           "${VERILOG_SOURCE_DIR}/QLA25AA128.v"
                           "${VERILOG_SOURCE_DIR}/Max6576.v"
                           "${VERILOG_SOURCE_DIR}/Max7317.v"
                           "${VERILOG_SOURCE_DIR}/CtrlLED.v"
                           "${VERILOG_SOURCE_DIR}/CtrlEnc.v"
                           "${VERILOG_SOURCE_DIR}/CtrlDout.v"
                           "${VERILOG_SOURCE_DIR}/MotorChannelQLA.v"
                           "${VERILOG_SOURCE_DIR}/CtrlDac.v"
                           "${VERILOG_SOURCE_DIR}/DS2505.v"
                           "${VERILOG_SOURCE_DIR}/WriteRtData.v"
                           "${VERILOG_SOURCE_DIR}/SampleData.v")

# Source files used by QLA
set (VERILOG_SOURCE_QLA    ${VERILOG_SOURCE_QLA_DQLA}
                           "${VERILOG_SOURCE_DIR}/CtrlAdc.v"
                           "${VERILOG_SOURCE_DIR}/BoardRegs-QLA.v"
                           "${VERILOG_SOURCE_DIR}/DataBuffer.v"
                           "${VERILOG_SOURCE_DIR}/QLA.v")

# Source files used by DQLA
set (VERILOG_SOURCE_DQLA   ${VERILOG_SOURCE_QLA_DQLA}
                           "${VERILOG_SOURCE_DIR}/Max7301x2.v"
                           "${VERILOG_SOURCE_DIR}/BoardRegs-DQLA.v"
                           "${VERILOG_SOURCE_DIR}/DQLA.v")

################### Complete Systems (FPGA + Board) #####################

##### FPGAV1 + QLA
set (VERILOG_SOURCE_FPGAV1_QLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394-QLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV1}
                         ${VERILOG_SOURCE_QLA})

# Compile the firmware -- output is FPGA1394-QLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394QLA"
                 DEPENDENCIES   "CoreGenCommon"
                 FPGA_PARTNUM   ${FPGA_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV1_QLA}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45.ucf"
                 IPCORE_DIR     ${IPCORE_BINARY_DIR}
                 TOP_LEVEL      "FPGA1394QLA"
                 PROJ_OUTPUT    "FPGA1394-QLA")

##### FPGAV2 + QLA
set (VERILOG_SOURCE_FPGAV2_QLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394Eth-QLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV2}
                         ${VERILOG_SOURCE_QLA})

# Compile the firmware -- output is FPGA1394Eth-QLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394EthQLA"
                 DEPENDENCIES   "CoreGenCommon"
                 FPGA_PARTNUM   ${FPGA_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV2_QLA}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45-Rev2.ucf"
                 IPCORE_DIR     ${IPCORE_BINARY_DIR}
                 TOP_LEVEL      "FPGA1394EthQLA"
                 PROJ_OUTPUT    "FPGA1394Eth-QLA")

##### FPGAV3 + QLA
set (VERILOG_SOURCE_FPGAV3_QLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-QLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_QLA})

# Compile the firmware -- output is FPGA1394V3-QLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394V3QLA"
                 DEPENDENCIES   "CoreGenV3" "PlatgenV3"
                 FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_QLA}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                 IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                 XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                 TOP_LEVEL      "FPGA1394V3QLA"
                 PROJ_OUTPUT    "FPGA1394V3-QLA"
                 IS_V3          ON)

##### FPGAV3 + DQLA
set (VERILOG_SOURCE_FPGAV3_DQLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-DQLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_DQLA})

# Compile the firmware -- output is FPGA1394V3-DQLA.mcs, which is copied
# to the Generated subdirectory in the source directory (if different).
ise_compile_fpga(PROJ_NAME      "FPGA1394V3DQLA"
                 DEPENDENCIES   "CoreGenV3" "PlatgenV3"
                 FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                 VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_DQLA}
                 UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                 IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                 XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                 TOP_LEVEL      "FPGA1394V3DQLA"
                 PROJ_OUTPUT    "FPGA1394V3-DQLA"
                 IS_V3          ON)

######################### Copy Generated Files #################################

# Copy MCS and BIT files to Generated folder in source tree (if different)
add_custom_target(generated)

add_custom_command(TARGET generated POST_BUILD
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394-QLA.mcs
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394-QLA.mcs
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394QLA.bit
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394-QLA.bit
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394Eth-QLA.mcs
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394Eth-QLA.mcs
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394EthQLA.bit
                           ${CMAKE_CURRENT_SOURCE_DIR}/Generated/FPGA1394Eth-QLA.bit
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394V3-QLA.mcs
                           ${CMAKE_CURRENT_SOURCE_DIR}/../Generated/FPGA1394V3-QLA.mcs
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394V3QLA.bit
                           ${CMAKE_CURRENT_SOURCE_DIR}/../Generated/FPGA1394V3-QLA.bit
                   COMMAND ${CMAKE_COMMAND}
                   ARGS -E copy_if_different
                           ${CMAKE_CURRENT_BINARY_DIR}/FPGA1394V3DQLA.bit
                           ${CMAKE_CURRENT_SOURCE_DIR}/../Generated/FPGA1394V3-DQLA.bit
                   COMMENT "Copying MCS and BIT files to source \"Generated\" directory (if different)")
