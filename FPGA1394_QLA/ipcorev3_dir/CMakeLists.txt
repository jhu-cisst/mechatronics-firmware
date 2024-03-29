
set (IPCORE_DIR "${FPGA1394_QLA_SOURCE_DIR}/ipcore_dir")

# IP core source files used by all versions of firmware.
# Using XCP files instead of XCO because project settings
# (e.g., target device) are set in coregen.cgp.
set (IPCORE_SOURCE_COMMON "${IPCORE_DIR}/hub_mem_gen.xcp"
                          "${IPCORE_DIR}/Dual_port_RAM_32X1024.xcp"
                          "${IPCORE_DIR}/pwm_clk_gen_zynq.xcp")

set (IPCORE_SOURCE ${IPCORE_SOURCE_COMMON}
                   "${CMAKE_CURRENT_SOURCE_DIR}/fifo_8x8192_16.xcp"
                   "${CMAKE_CURRENT_SOURCE_DIR}/fifo_16x2048_8.xcp"
                   "${CMAKE_CURRENT_SOURCE_DIR}/fifo_32x32.xcp")

ise_ipcoregen(TARGET_NAME       "CoreGenV3"
              XCO_SOURCE        ${IPCORE_SOURCE}
              CGP_IN_FILE       "${IPCORE_DIR}/coregen.cgp.in"
              FPGA_FAMILY       ${FPGAV3_FAMILY}
              FPGA_DEVICE       ${FPGAV3_DEVICE}
              FPGA_PACKAGE      ${FPGAV3_PACKAGE}
              FPGA_SPEED        ${FPGAV3_SPEED})

# For convenience, do not automatically clean this (i.e., do not delete coregen.log)
# To regenerate IP cores, must manually delete coregen.log
set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)

# XPS subdirectory for Zynq PS7 core
add_subdirectory(xps)
