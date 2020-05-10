
# IP core source files used by both versions of firmware
set (IPCORE_SOURCE_COMMON "pkt_mem_gen.xco"
                          "hub_mem_gen.xco"
                          "Dual_port_RAM_32X1024.xco")

# Generate the common IP cores (target name is CoreGenCommon)
ise_ipcoregen(TARGET_NAME       "CoreGenCommon"
              XCO_SOURCE        ${IPCORE_SOURCE_COMMON})

# For convenience, do not automatically clean this (i.e., do not delete coregen.log)
# To regenerate IP cores, must manually delete coregen.log
set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)
