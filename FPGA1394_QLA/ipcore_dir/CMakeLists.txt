
# IP core source files used by all versions of firmware.
# Using XCP files instead of XCO because project settings
# (e.g., target device) are set in coregen.cgp.
set (IPCORE_SOURCE_COMMON "${CMAKE_CURRENT_SOURCE_DIR}/hub_mem_gen.xcp"
                          "${CMAKE_CURRENT_SOURCE_DIR}/Dual_port_RAM_32X1024.xcp")

# Generate the common IP cores (target name is CoreGenCommon)
ise_ipcoregen(TARGET_NAME       "CoreGenCommon"
              XCO_SOURCE        ${IPCORE_SOURCE_COMMON}
              CGP_IN_FILE       "coregen.cgp.in"
              FPGA_FAMILY       ${FPGA_FAMILY}
              FPGA_DEVICE       ${FPGA_DEVICE}
              FPGA_PACKAGE      ${FPGA_PACKAGE}
              FPGA_SPEED        ${FPGA_SPEED})

# For convenience, do not automatically clean this (i.e., do not delete coregen.log)
# To regenerate IP cores, must manually delete coregen.log
set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)
