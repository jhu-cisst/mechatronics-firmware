
# Set CMake minimum version requirement.
# Need 3.15+ for ADDITIONAL_CLEAN_FILES property
# CMake 3.16 improved dependency checking in add_custom_target
cmake_minimum_required(VERSION 3.16)

project(MechatronicsFirmware NONE)

set (FIRMWARE_VERSION 9)

set (FIRMWARE_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set (CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${FIRMWARE_CMAKE_PATH})
find_package (XilinxISE)
find_package (Vivado)

if (XilinxISE_FOUND OR Vivado_FOUND)

  if (XilinxISE_FOUND)
    include (${XILINX_ISE_USE_FILE})
  endif ()

  if (Vivado_FOUND)

    include (${VIVADO_USE_FILE})
    option (BUILD_FPGAV30 "Build for FPGA V3.0 (instead of V3.1+)" OFF)
    mark_as_advanced (BUILD_FPGAV30)

    if (BUILD_FPGAV30)
      set (FPGA_VER     "30")
    else ()
      set (FPGA_VER     "31")
    endif ()

    # Target names
    #   BLOCK_DESIGN_IN:   updates TCL file exported from Vivado block design GUI,
    #                      which is used as input in zynq_block_design and ipcorev3_dir
    #   BLOCK_DESIGN_NAME: creates block design, including xsa and xpr files

    set (BLOCK_DESIGN_IN   "FpgaV${FPGA_VER}Input")
    set (BLOCK_DESIGN_NAME "FpgaV${FPGA_VER}BlockDesign")

    # Filename of xsa file created by block design
    set (HW_XSA_FILE       "FpgaV${FPGA_VER}.xsa")

    add_subdirectory (zynq_block_design)

  endif ()

  add_subdirectory (FPGA1394_QLA)

else ()

  message (SEND_ERROR "Xilinx ISE and/or Vivado not found")

endif ()

######################### Show graphviz dependencies ###############################
# See GraphVizOptions.cmake for relevant options.
# Note that CMake 3.16 does not support the GRAPHVIZ_CUSTOM_TARGETS option, so the
# resulting graph is empty (since everything is a custom target).

set (DEP_GRAPH "dep-graph")

# Look for graphviz executable; if not found set GRAPHVIZ_DOT to NOP
find_program (GRAPHVIZ_DOT dot NO_CACHE)
if (GRAPHVIZ_DOT)
  set (GRAPHVIZ_COMMENT ", and ${DEP_GRAPH}.png")
else ()
  set (GRAPHVIZ_DOT ${CMAKE_COMMAND} -E true)
endif ()

# Look for a program to view PNG file
if (UNIX)
  find_program (IMG_VIEWER eog NO_CACHE)
  set (IMG_CMD ${IMG_VIEWER} ${DEP_GRAPH}.png &)
elseif (WIN32)
  set (IMG_CMD start ${DEP_GRAPH}.png)
endif ()

add_custom_target (${DEP_GRAPH}
                   COMMAND ${CMAKE_COMMAND} --graphviz=${DEP_GRAPH}.dot .
                   COMMAND ${GRAPHVIZ_DOT} -Tpng -o ${DEP_GRAPH}.png ${DEP_GRAPH}.dot
                   COMMAND ${IMG_CMD}
		   COMMAND_EXPAND_LISTS
                   COMMENT "Creating ${DEP_GRAPH}.dot for graphviz${GRAPHVIZ_COMMENT}")
