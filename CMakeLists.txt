
# Set CMake minimum version requirement. This project has been
# successfully used with CMake Version 2.8.7 (on Ubuntu 12.04),
# so currently setting that as the minimum requirement. It is
# possible that it would work with older CMake versions.
cmake_minimum_required(VERSION 2.8.7)

project(MechatronicsFirmware NONE)

set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(XilinxISE)

if (XilinxISE_FOUND)

  include(${XILINX_ISE_USE_FILE})

  add_subdirectory(FPGA1394_QLA)

else (XilinxISE_FOUND)

  message(SEND_ERROR "Xilinx ISE not found")

endif (XilinxISE_FOUND)
