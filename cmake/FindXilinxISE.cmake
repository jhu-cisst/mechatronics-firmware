# Find Xilinx ISE installation
#
# This will automatically find the necessary command line programs if the Xilinx ISE binary directory is
# on the system PATH. If not, it is easiest to first set XILINX_ISE_BINARY_DIR and let CMake find the programs.
#
# Future enhancements could include determining the Xilinx ISE version number.

set (XILINX_ISE_BINARY_DIR "" CACHE PATH "Xilinx ISE binary directory")
#set(ENV{PATH} "${XILINX_ISE_BINARY_DIR};$ENV{PATH}")

find_program(XILINX_ISE_XST NAMES "xst" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE XST tool")
find_program(XILINX_ISE_NGDBUILD NAMES "ngdbuild" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE ngdbuild tool")
find_program(XILINX_ISE_MAP NAMES "map" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE map tool")
find_program(XILINX_ISE_PAR NAMES "par" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE par tool")
find_program(XILINX_ISE_TRCE NAMES "trce" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE trce tool")
find_program(XILINX_ISE_BITGEN NAMES "bitgen" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE bitgen tool")
find_program(XILINX_ISE_PROMGEN NAMES "promgen" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE promgen tool")
find_program(XILINX_ISE_COREGEN NAMES "coregen" HINTS ${XILINX_ISE_BINARY_DIR} DOC "Xilinx ISE coregen tool")

set (XILINX_ISE_USE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cmake/UseXilinxISE.cmake")

if (XILINX_ISE_XST AND XILINX_ISE_NGDBUILD AND XILINX_ISE_MAP AND XILINX_ISE_PAR AND
    XILINX_ISE_TRCE AND XILINX_ISE_BITGEN AND XILINX_ISE_PROMGEN AND XILINX_ISE_COREGEN)
  set (XilinxISE_FOUND TRUE)
else()
  set (XilinxISE_FOUND FALSE)
endif()
