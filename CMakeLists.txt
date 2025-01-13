
# Set CMake minimum version requirement.
cmake_minimum_required(VERSION 3.1)

project(MechatronicsFirmware NONE)

set (FIRMWARE_VERSION 9)

set (FIRMWARE_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${FIRMWARE_CMAKE_PATH})
find_package (XilinxISE)
find_package (Vivado)

if (XilinxISE_FOUND OR Vivado_FOUND)

  if (XilinxISE_FOUND)
    include(${XILINX_ISE_USE_FILE})
  endif ()
  if (Vivado_FOUND)
    include(${VIVADO_USE_FILE})
  endif ()

  add_subdirectory(FPGA1394_QLA)

else ()

  message(SEND_ERROR "Xilinx ISE and/or Vivado not found")

endif ()
