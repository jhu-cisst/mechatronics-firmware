
# Set CMake minimum version requirement.
cmake_minimum_required(VERSION 3.1)

project(MechatronicsFirmware NONE)

set (FIRMWARE_VERSION 9)

set (FIRMWARE_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${FIRMWARE_CMAKE_PATH})
find_package(XilinxISE)

if (XilinxISE_FOUND)

  include(${XILINX_ISE_USE_FILE})

  add_subdirectory(FPGA1394_QLA)

else (XilinxISE_FOUND)

  message(SEND_ERROR "Xilinx ISE not found")

endif (XilinxISE_FOUND)
