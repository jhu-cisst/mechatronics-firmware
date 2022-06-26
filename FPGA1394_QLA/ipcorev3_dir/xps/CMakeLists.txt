
set (PS7_MHS_FILE  fpgav3.mhs)
set (PS7_PRJ_FILE  ps7_fpgav3_prj.xml)

edk_platgen(TARGET_NAME       "PlatgenV3"
            MHS_FILE          "${CMAKE_CURRENT_SOURCE_DIR}/${PS7_MHS_FILE}"
            PRJ_FILE          "data/${PS7_PRJ_FILE}"
            TOP_INSTANCE      "zynq_ps7"
            TOP_MODULE        "zynq_top"
            FPGA_DEVICE       ${FPGAV3_DEVICE}
            FPGA_PACKAGE      ${FPGAV3_PACKAGE}
            FPGA_SPEED        ${FPGAV3_SPEED})

# For convenience, do not automatically clean this (i.e., do not delete platgen.log)
# To regenerate cores, must manually delete platgen.log
set_directory_properties(PROPERTIES CLEAN_NO_CUSTOM TRUE)
