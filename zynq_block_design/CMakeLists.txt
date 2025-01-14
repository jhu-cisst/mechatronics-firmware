
set (FPGAV3_DEVICE  "xc7z020")
set (FPGAV3_PACKAGE "clg400")
set (FPGAV3_SPEED   "-2")
set (FPGAV3_PARTNUM "${FPGAV3_DEVICE}${FPGAV3_PACKAGE}${FPGAV3_SPEED}")

set (EXPORTED_TCL_FILE_IN "${CMAKE_CURRENT_SOURCE_DIR}/exported-block-v${FPGA_VER}.tcl")

vivado_block_config (${BLOCK_DESIGN_IN} ${EXPORTED_TCL_FILE_IN})

vivado_block_build (PROJ_NAME      ${BLOCK_DESIGN_NAME}
                    BD_NAME        "FpgaV${FPGA_VER}"
                    FPGA_PARTNUM   ${FPGAV3_PARTNUM}
                    BLOCK_IN       ${BLOCK_DESIGN_IN}
                    HW_FILE        ${HW_XSA_FILE})
