
# Set CMake minimum version requirement.
cmake_minimum_required(VERSION 3.1)

project(MechatronicsFirmware NONE)

set (FIRMWARE_VERSION 8)

find_package (Git)
if (GIT_FOUND)
  execute_process (COMMAND ${GIT_EXECUTABLE} describe --tags --match Rev*
                                             --long --dirty=-d --abbrev=7
                   WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                   OUTPUT_VARIABLE GIT_DESCRIBE_STRING)
  string (REPLACE "-" ";" GIT_DESCRIBE_LIST ${GIT_DESCRIBE_STRING})
  list (LENGTH GIT_DESCRIBE_LIST desc_len)
  if (desc_len GREATER_EQUAL 3)
    list (GET GIT_DESCRIBE_LIST 0 GIT_REV_TAG)
    string (SUBSTRING ${GIT_REV_TAG} 3 -1 GIT_REV)
    list (GET GIT_DESCRIBE_LIST 1 GIT_COMMITS)
    list (GET GIT_DESCRIBE_LIST 2 GIT_SHA_RAW)
    string (SUBSTRING ${GIT_SHA_RAW} 1 7 GIT_SHA)
    if (desc_len EQUAL 4)
      set (GIT_DIRTY ON)
    else ()
      set (GIT_DIRTY OFF)
    endif ()
  endif ()
  if (NOT GIT_REV EQUAL FIRMWARE_VERSION)
    message (WARNING "Firmware source version (git) ${GIT_REV} does not match specified version (cmake) ${FIRMWARE_VERSION}")
  endif ()
  # Following variables can be passed to Verilog source code and stored in a register
  message (STATUS "git describe: ${GIT_COMMITS} ${GIT_SHA} ${GIT_DIRTY}")
endif ()

set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(XilinxISE)

if (XilinxISE_FOUND)

  include(${XILINX_ISE_USE_FILE})

  add_subdirectory(FPGA1394_QLA)

else (XilinxISE_FOUND)

  message(SEND_ERROR "Xilinx ISE not found")

endif (XilinxISE_FOUND)
