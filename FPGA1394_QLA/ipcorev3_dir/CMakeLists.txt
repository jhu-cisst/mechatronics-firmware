
# IP core source files used by all versions of firmware.
# Using XCP files instead of XCO because project settings
# (e.g., target device) are set in coregen.cgp.
set (IPCORE_SOURCE_COMMON "hub_mem_gen.xcp"
                          "Dual_port_RAM_32X1024.xcp")

ise_ipcoregen(TARGET_NAME       "CoreGenV3"
              XCO_SOURCE        ${IPCORE_SOURCE_COMMON}
              SOURCE_DIR        "${FPGA1394_QLA_SOURCE_DIR}/ipcore_dir"
              FPGA_FAMILY       ${FPGAV3_FAMILY}
              FPGA_DEVICE       ${FPGAV3_DEVICE}
              FPGA_PACKAGE      ${FPGAV3_PACKAGE}
              FPGA_SPEED        ${FPGAV3_SPEED})

# For convenience, do not automatically clean this (i.e., do not delete coregen.log)
# To regenerate IP cores, must manually delete coregen.log
set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)

# XPS subdirectory for Zynq PS7 core
add_subdirectory(xps)
