# Build all supported combinations of FPGA versions and boards
#
#   FPGAV1 + QLA        (ISE only)
#   FPGAV2 + QLA        (ISE only)
#   FPGAV3 + BCFG       (Vivado or ISE)
#   FPGAV3 + QLA        (Vivado or ISE)
#   FPGAV3 + DQLA       (Vivado or ISE)
#   FPGAV3 + DRAC       (Vivado or ISE)
#
# If Vivado_FOUND, use Vivado to build FPGAV3 bit files; otherwise use ISE
#
# Can only build FPGAV1 and FPGAV2 files with ISE.
#
# Tested on Windows 7, 64-bit, with NMAKE (VS 2008) and Xilinx ISE 14.3
# Tested on Ubuntu 16.04/20.04, 64-bit, with make (gcc 5.4.0/9.4.0) and Xilinx ISE 14.7

project(FPGA1394_QLA NONE)

# FPGA part number (V1 and V2)
set (FPGA_FAMILY  "spartan6")
set (FPGA_DEVICE  "xc6slx45")
set (FPGA_PACKAGE "fgg484")
set (FPGA_SPEED   "-2")
set (FPGA_PARTNUM "${FPGA_DEVICE}${FPGA_SPEED}${FPGA_PACKAGE}")

# FPGA part number (V3)
set (FPGAV3_FAMILY  "zynq")
set (FPGAV3_DEVICE  "xc7z020")
set (FPGAV3_PACKAGE "clg400")
set (FPGAV3_SPEED   "-2")
set (FPGAV3_PARTNUM "${FPGAV3_DEVICE}${FPGAV3_SPEED}${FPGAV3_PACKAGE}")

# Path to Verilog source code
set (VERILOG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Verilog")
set (HLS_GENERATED_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/hls_generated_src")
# Path to CMake-generated source files (e.g., Versions.v)
set (VERILOG_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/Verilog")
file (MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Verilog")

# Paths to IP core files (source and build)
# By default, use files in build tree (IPCORE_BINARY_DIR and IPCOREV3_BINARY_DIR)
set (IPCORE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ipcore_dir")
set (IPCORE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcore_dir")
set (IPCOREV3_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcorev3_dir")
set (XPSCORE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ipcorev3_dir/xps")

# Git is used by CreateVersions.cmake, which is used to generate Versions.v
find_package (Git REQUIRED)

if (XilinxISE_FOUND)
    add_subdirectory(ipcore_dir)
endif ()

add_subdirectory(ipcorev3_dir)

###################### Common Files ####################################

# Source files for everything
set (VERILOG_SOURCE_COMMON "${VERILOG_SOURCE_DIR}/ClkDiv.v"
                           "${VERILOG_SOURCE_DIR}/Constants.v"
                           "${VERILOG_BINARY_DIR}/Versions.v"
                           "${VERILOG_SOURCE_DIR}/ReadAddressTranslation.v"
                           "${VERILOG_SOURCE_DIR}/WriteAddressTranslation.v"
                           "${VERILOG_SOURCE_DIR}/ReadDataValid.v")

add_custom_command (OUTPUT "${VERILOG_BINARY_DIR}/Versions-New.v"
                    COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
                                             -DFIRMWARE_VERSION=${FIRMWARE_VERSION}
                                             -DOUTPUT_FILE="${VERILOG_BINARY_DIR}/Versions-New.v"
                                             -DGIT_EXECUTABLE=${GIT_EXECUTABLE}
                                             -P "${FIRMWARE_CMAKE_PATH}/CreateVersions.cmake"
                    COMMENT "Creating Versions.v")

add_custom_target (VersionFile ALL
                   BYPRODUCTS "${VERILOG_BINARY_DIR}/Versions.v"
                   COMMAND ${CMAKE_COMMAND} -E copy_if_different "${VERILOG_BINARY_DIR}/Versions-New.v"
                                                                 "${VERILOG_BINARY_DIR}/Versions.v"
                   COMMAND ${CMAKE_COMMAND} -E remove -f "${VERILOG_BINARY_DIR}/Versions-New.v"
                   DEPENDS "${VERILOG_BINARY_DIR}/Versions-New.v")

##################### FPGA Versions ####################################

# Source files for all versions of FPGA
set (VERILOG_SOURCE_FPGA "${VERILOG_SOURCE_DIR}/Crc32.v"
                         "${VERILOG_SOURCE_DIR}/HubReg.v"
                         "${VERILOG_SOURCE_DIR}/FireWire.v"
                         "${VERILOG_SOURCE_DIR}/BoardRegs.v")

if (XilinxISE_FOUND)

  # Source files for FPGA V1 and V2
  set (VERILOG_SOURCE_FPGAV1_V2
                         ${VERILOG_SOURCE_FPGA}
                         "${IPCORE_BINARY_DIR}/DPRAM_32x512_sclk.v"
                         "${VERILOG_SOURCE_DIR}/UartSerial.v"
                         "${VERILOG_SOURCE_DIR}/M25P16.v"
                         "${IPCORE_BINARY_DIR}/DPRAM_32x1024_sclk.v"
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

endif ()

# Source files for FPGA V3
set (VERILOG_SOURCE_FPGAV3
                         ${VERILOG_SOURCE_FPGA}
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3.v"
                         "${VERILOG_SOURCE_DIR}/RTL8211F.v"
                         "${VERILOG_SOURCE_DIR}/EthernetIO.v"
                         "${VERILOG_SOURCE_DIR}/EthRtInterface.v"
                         "${VERILOG_SOURCE_DIR}/EthSwitch.v"
                         "${VERILOG_SOURCE_DIR}/VirtualPhy.v"
                         "${VERILOG_SOURCE_DIR}/EmioBus.v")

if (NOT Vivado_FOUND)
  # If using ISE for FPGA V3, add IP wrapper files
  set (VERILOG_SOURCE_FPGAV3 ${VERILOG_SOURCE_FPGAV3}
                             "${IPCOREV3_BINARY_DIR}/DPRAM_32x512_sclk.v"
                             "${IPCOREV3_BINARY_DIR}/DPRAM_32x512_aclk.v"
                             "${IPCOREV3_BINARY_DIR}/DPRAM_32x1024_sclk.v"
                             "${IPCOREV3_BINARY_DIR}/fifo_10x8192.v"
                             "${IPCOREV3_BINARY_DIR}/fifo_4x128.v"
                             "${XPSCORE_BINARY_DIR}/hdl/fpgav3.v")
endif ()

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
                           "${VERILOG_SOURCE_DIR}/DS2505.v")

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

set (VERILOG_SOURCE_DRAC
                           "${VERILOG_SOURCE_DIR}/DRAC.v"
                           "${VERILOG_SOURCE_DIR}/BoardRegs-DRAC.v"
                           "${VERILOG_SOURCE_DIR}/QLA25AA128.v"
                           "${VERILOG_SOURCE_DIR}/AD4008.v"
                           "${VERILOG_SOURCE_DIR}/cdc_pulse.v"
                           "${VERILOG_SOURCE_DIR}/Crc16.v"
                           "${VERILOG_SOURCE_DIR}/DataBuffer.v"
                           "${VERILOG_SOURCE_DIR}/ESPMComm.v"
                           "${VERILOG_SOURCE_DIR}/MotorChannelDRAC.v"
                           "${VERILOG_SOURCE_DIR}/PowerControl.v"
                           "${VERILOG_SOURCE_DIR}/PWM.v"
                           "${VERILOG_SOURCE_DIR}/PwmAdcTiming.v"
                           "${VERILOG_SOURCE_DIR}/ws2811.v")

file(DOWNLOAD
        https://raw.githubusercontent.com/keshuaixu/ws2812-verilog/ws2813/ws2811.v
        "${VERILOG_SOURCE_DIR}/ws2811.v")

# file(GLOB HLS_GENERATED_SOURCES_DRAC_FPGAV1V2 CONFIGURE_DEPENDS "${HLS_GENERATED_SOURCE_DIR}/v1v2/*.v")
file(GLOB HLS_GENERATED_SOURCES_DRAC_FPGAV3 CONFIGURE_DEPENDS "${HLS_GENERATED_SOURCE_DIR}/v3/*.v")

# Source files used by BCFG (boot config)
set (VERILOG_SOURCE_BCFG  "${VERILOG_SOURCE_DIR}/BootConfig.v"
                          "${VERILOG_SOURCE_DIR}/QLA25AA128.v"
                          "${VERILOG_SOURCE_DIR}/ws2811.v")

################### Complete Systems (FPGA + Board) #####################

if (XilinxISE_FOUND)
  ##### FPGAV1 + QLA
  set (VERILOG_SOURCE_FPGAV1_QLA
                           "${VERILOG_SOURCE_DIR}/FPGA1394V1-QLA.v"
                           ${VERILOG_SOURCE_COMMON}
                           ${VERILOG_SOURCE_FPGAV1}
                           ${VERILOG_SOURCE_QLA})

  # Compile the firmware -- output is FPGA1394V1-QLA.bit and FPGA1394V1-QLA.mcs
  ise_compile_fpga(PROJ_NAME      "FPGA1394V1-QLA"
                   DEPENDENCIES   "CoreGenCommon" "VersionFile"
                   FPGA_PARTNUM   ${FPGA_PARTNUM}
                   VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV1_QLA}
                   UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45.ucf"
                   BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/QLA.ucf"
                   IPCORE_DIR     ${IPCORE_BINARY_DIR}
                   TOP_LEVEL      "FPGA1394V1QLA")

  ##### FPGAV2 + QLA
  set (VERILOG_SOURCE_FPGAV2_QLA
                           "${VERILOG_SOURCE_DIR}/FPGA1394V2-QLA.v"
                           ${VERILOG_SOURCE_COMMON}
                           ${VERILOG_SOURCE_FPGAV2}
                           ${VERILOG_SOURCE_QLA})

  # Compile the firmware -- output is FPGA1394V2-QLA.bit and FPGA1394V2-QLA.mcs
  ise_compile_fpga(PROJ_NAME      "FPGA1394V2-QLA"
                   DEPENDENCIES   "CoreGenCommon" "VersionFile"
                   FPGA_PARTNUM   ${FPGA_PARTNUM}
                   VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV2_QLA}
                   UCF_FILE       "${VERILOG_SOURCE_DIR}/XC6S45-Rev2.ucf"
                   BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/QLA.ucf"
                   IPCORE_DIR     ${IPCORE_BINARY_DIR}
                   TOP_LEVEL      "FPGA1394V2QLA")
endif ()

##### FPGAV3 + BCFG
set (VERILOG_SOURCE_FPGAV3_BCFG
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-BCFG.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_BCFG})

##### FPGAV3 + QLA
set (VERILOG_SOURCE_FPGAV3_QLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-QLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_QLA})

##### FPGAV3 + DQLA
set (VERILOG_SOURCE_FPGAV3_DQLA
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-DQLA.v"
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_DQLA})

##### FPGAV3 + dRAC
set (VERILOG_SOURCE_FPGAV3_DRAC
                         "${VERILOG_SOURCE_DIR}/FPGA1394V3-DRAC.v"
                         ${HLS_GENERATED_SOURCES_DRAC_FPGAV3}                         
                         ${VERILOG_SOURCE_COMMON}
                         ${VERILOG_SOURCE_FPGAV3}
                         ${VERILOG_SOURCE_DRAC})

if (NOT Vivado_FOUND)
  # Add IP wrapper for ISE
  set (VERILOG_SOURCE_FPGAV3_DRAC ${VERILOG_SOURCE_FPGAV3_DRAC}
                                  "${IPCOREV3_BINARY_DIR}/pwm_clk_gen_zynq.v")
endif ()

if (Vivado_FOUND)

  set (VERILOG_INCLUDE_DIRS ${VERILOG_SOURCE_DIR} ${VERILOG_BINARY_DIR})

  set (IP_CORES "DPRAM_32x1024_sclk" "DPRAM_32x512_sclk" "DPRAM_32x512_aclk"
                "fifo_10x8192" "fifo_4x128"
                "gmii_to_rgmii_1" "gmii_to_rgmii_2")

  set (VIVADO_DEFS "HAS_DEBUG_DATA" "USE_VIVADO")
  # Following is defined in top-level file (e.g., FPGA1394V3-QLA.v), but
  # for project mode (CREATE_ONLY) it is easier to add it here
  if (CREATE_ONLY)
      set (VIVADO_DEFS ${VIVADO_DEFS} "HAS_ETHERNET")
  endif ()

  # Compile the firmware -- output is FPGA1394V3-BCFG.bit
  vivado_compile_fpga (PROJ_NAME      "FPGA1394V3-BCFG"
                       DEPENDENCIES   "VersionFile"
                       FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                       VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_BCFG}
                       XDC_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.xdc"
                       BOARD_XDC_FILE "${VERILOG_SOURCE_DIR}/BootConfig.xdc"
                       IP_TARGETS     ${IP_CORES}
                       BLOCK_DESIGN   ${BLOCK_DESIGN_NAME}
                       INCLUDE_DIRS   ${VERILOG_INCLUDE_DIRS}
                       TOP_LEVEL      "FPGA1394V3BCFG"
                       USER_MACROS    ${VIVADO_DEFS}
                       CREATE_ONLY    ${CREATE_ONLY})

  # Compile the firmware -- output is FPGA1394V3-QLA.bit
  vivado_compile_fpga (PROJ_NAME      "FPGA1394V3-QLA"
                       DEPENDENCIES   "VersionFile"
                       FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                       VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_QLA}
                       XDC_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.xdc"
                       BOARD_XDC_FILE "${VERILOG_SOURCE_DIR}/QLA.xdc"
                       IP_TARGETS     ${IP_CORES}
                       BLOCK_DESIGN   ${BLOCK_DESIGN_NAME}
                       INCLUDE_DIRS   ${VERILOG_INCLUDE_DIRS}
                       TOP_LEVEL      "FPGA1394V3QLA"
                       USER_MACROS    ${VIVADO_DEFS}
                       CREATE_ONLY    ${CREATE_ONLY})

  # Compile the firmware -- output is FPGA1394V3-DQLA.bit
  vivado_compile_fpga (PROJ_NAME      "FPGA1394V3-DQLA"
                       DEPENDENCIES   "VersionFile"
                       FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                       VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_DQLA}
                       XDC_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.xdc"
                       BOARD_XDC_FILE "${VERILOG_SOURCE_DIR}/DQLA.xdc"
                       IP_TARGETS     ${IP_CORES}
                       BLOCK_DESIGN   ${BLOCK_DESIGN_NAME}
                       INCLUDE_DIRS   ${VERILOG_INCLUDE_DIRS}
                       TOP_LEVEL      "FPGA1394V3DQLA"
                       USER_MACROS    ${VIVADO_DEFS}
                       CREATE_ONLY    ${CREATE_ONLY})

  # Compile the firmware -- output is FPGA1394V3-DRAC.bit
  vivado_compile_fpga (PROJ_NAME      "FPGA1394V3-DRAC"
                       DEPENDENCIES   "VersionFile"
                       FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                       VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_DRAC}
                       XDC_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.xdc"
                       BOARD_XDC_FILE "${VERILOG_SOURCE_DIR}/DRAC.xdc"
                       IP_TARGETS     ${IP_CORES} "pwm_clk_gen_zynq"
                       BLOCK_DESIGN   ${BLOCK_DESIGN_NAME}
                       INCLUDE_DIRS   ${VERILOG_INCLUDE_DIRS}
                       TOP_LEVEL      "FPGA1394V3DRAC"
                       USER_MACROS    ${VIVADO_DEFS}
                       CREATE_ONLY    ${CREATE_ONLY})

else ()

  # Compile the firmware -- output is FPGA1394V3-BCFG.bit
  ise_compile_fpga (PROJ_NAME      "FPGA1394V3-BCFG"
                    DEPENDENCIES   "CoreGenV3" "PlatgenV3" "VersionFile"
                    FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                    VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_BCFG}
                    UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                    BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/BootConfig.ucf"
                    IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                    XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                    TOP_LEVEL      "FPGA1394V3BCFG"
                    USER_MACROS    "HAS_DEBUG_DATA"
                    IS_V3          ON)

  # Compile the firmware -- output is FPGA1394V3-QLA.bit
  ise_compile_fpga (PROJ_NAME      "FPGA1394V3-QLA"
                    DEPENDENCIES   "CoreGenV3" "PlatgenV3" "VersionFile"
                    FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                    VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_QLA}
                    UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                    BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/QLA.ucf"
                    IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                    XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                    TOP_LEVEL      "FPGA1394V3QLA"
                    USER_MACROS    "HAS_DEBUG_DATA"
                    IS_V3          ON)

  # Compile the firmware -- output is FPGA1394V3-DQLA.bit
  ise_compile_fpga (PROJ_NAME      "FPGA1394V3-DQLA"
                    DEPENDENCIES   "CoreGenV3" "PlatgenV3" "VersionFile"
                    FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                    VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_DQLA}
                    UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                    BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/DQLA.ucf"
                    IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                    XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                    TOP_LEVEL      "FPGA1394V3DQLA"
                    USER_MACROS    "HAS_DEBUG_DATA"
                    IS_V3          ON)

  # Compile the firmware -- output is FPGA1394V3-DRAC.bit
  ise_compile_fpga (PROJ_NAME      "FPGA1394V3-DRAC"
                    DEPENDENCIES   "CoreGenV3" "PlatgenV3" "VersionFile"
                    FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                    VERILOG_SOURCE ${VERILOG_SOURCE_FPGAV3_DRAC}
                    UCF_FILE       "${VERILOG_SOURCE_DIR}/XC7Z020.ucf"
                    BOARD_UCF_FILE "${VERILOG_SOURCE_DIR}/DRAC.ucf"
                    IPCORE_DIR     ${IPCOREV3_BINARY_DIR}
                    XPSCORE_DIR    "${XPSCORE_BINARY_DIR}/implementation"
                    TOP_LEVEL      "FPGA1394V3DRAC"
                    USER_MACROS    "HAS_DEBUG_DATA"
                    IS_V3          ON)

endif ()

##################### Create mechatronics-firmware-config.cmake #####################

set (CONFIG_FILE "${CMAKE_BINARY_DIR}/mechatronics-firmware-config.cmake")
file (WRITE  ${CONFIG_FILE} "#\n# CMake configuration file for mechatronics-firmware\n#\n\n")
file (APPEND ${CONFIG_FILE} "set (FIRMWARE_VERSION ${FIRMWARE_VERSION})\n\n")
file (APPEND ${CONFIG_FILE} "set (FIRMWARE_BINARY_DIR \"\${CMAKE_CURRENT_LIST_DIR}/FPGA1394_QLA\")\n\n")
file (APPEND ${CONFIG_FILE} "set (FPGAV1_MCS_FILES \"\${FIRMWARE_BINARY_DIR}/FPGA1394V1-QLA.mcs\")\n")
file (APPEND ${CONFIG_FILE} "set (FPGAV2_MCS_FILES \"\${FIRMWARE_BINARY_DIR}/FPGA1394V2-QLA.mcs\")\n\n")
file (APPEND ${CONFIG_FILE} "set (FPGAV3_BCFG_BIT_FILE \"\${FIRMWARE_BINARY_DIR}/FPGA1394V3-BCFG.bit\")\n")
file (APPEND ${CONFIG_FILE} "set (FPGAV3_HW_BIT_FILES  \"\${FIRMWARE_BINARY_DIR}/FPGA1394V3-QLA.bit\"\n")
file (APPEND ${CONFIG_FILE} "                          \"\${FIRMWARE_BINARY_DIR}/FPGA1394V3-DQLA.bit\"\n")
file (APPEND ${CONFIG_FILE} "                          \"\${FIRMWARE_BINARY_DIR}/FPGA1394V3-DRAC.bit\")\n")
if (Vivado_FOUND)
  file (APPEND ${CONFIG_FILE} "\nset (Vivado_VERSION  \"${Vivado_VERSION}\")\n")
  file (APPEND ${CONFIG_FILE} "set (HW_XSA_FILE     \"\${CMAKE_CURRENT_LIST_DIR}/zynq_block_design/${HW_XSA_FILE}\")\n")
endif ()
