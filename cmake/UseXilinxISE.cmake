# UseXilinxISE
#
# This package assumes that find_package(XilinxISE) has already been called,
# so that the XILINX_ISE programs have already been found.
#
# Macro: ise_ipcoregen
# Parameters:
#   - TARGET_NAME:        target name
#   - IPCORE_SOURCE_DIR:  directory for source (.xco) files
#   - IPCORE_BINARY_DIR:  directory for build files
#   - XCO_SOURCE:         list of CoreGen Input files (.xco)
#
# Macro: ise_compile_fpga
# Parameters:
#   - PROJ_NAME:       the project name (most output files will use this name)
#   - DEPENDENCIES:    dependencies for this target (e.g., IP cores)
#   - FPGA_PARTNUM:    the FPGA part number
#   - VERILOG_SOURCE:  list of Verilog source code (.v)
#   - UCF_FILE:        User constraints file
#   - IPCORE_DIR:      Directory to search for IP cores
#   - TOP_LEVEL:       Top level module name
#   - PROJ_OUTPUT:     the final output name (can be different from PROJ_NAME)
#
# Note that PROJ_OUTPUT is provided for the final naming because currently the
# PROJ_NAMES are FPGA1394QLA and FPGA1394EthQLA, while the corresponding PROJ_OUTPUT
# are FPGA1394-QLA and FPGA1394Eth-QLA.
#
# There are two implementations:
#   - ise_compile_fpga:      this uses Xilinx XFLOW to do most of the work
#   - ise_compile_fpga_old:  this calls the individual executable programs
#
# For ise_compile_fpga, the command line options are in "opt" files that are copied
# from this directory to the build directory.
#
# For ise_compile_fpga_old, the command line options are included below.
#
# In both cases, the macros could be enhanced to accept parameters that provide options for
# the various compilation steps. Presently, most options are left at their default
# values, with a few exceptions noted. These settings are consistent with the ISE
# project files, FPGA1394-QLA.xise and FPGA1394Eth-QLA.xise.

macro (ise_compile_fpga ...)

  # set all keywords and their values to ""
  set (FUNCTION_KEYWORDS
       PROJ_NAME
       DEPENDENCIES
       FPGA_PARTNUM
       VERILOG_SOURCE
       UCF_FILE
       IPCORE_DIR
       TOP_LEVEL
       PROJ_OUTPUT)

  # reset local variables
  foreach(keyword ${FUNCTION_KEYWORDS})
    set (${keyword} "")
  endforeach(keyword)

  # parse input
  foreach (arg ${ARGV})
    list (FIND FUNCTION_KEYWORDS ${arg} ARGUMENT_IS_A_KEYWORD)
    if (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (CURRENT_PARAMETER ${arg})
      set (${CURRENT_PARAMETER} "")
    else (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (${CURRENT_PARAMETER} ${${CURRENT_PARAMETER}} ${arg})
    endif (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
  endforeach (arg)

  file(TO_NATIVE_PATH ${XILINX_ISE_XFLOW} XFLOW_NATIVE)

  # Copy custom flow file (FLW) to build tree (customized to add promgen)
  file (COPY "${XILINX_OPT_DIR}/${XILINX_FPGA_FLW_FILE}" DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

  # Copy OPT files to build tree
  configure_file("${XILINX_OPT_DIR}/${XILINX_SYNTH_OPT_FILE}.in"
                 "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}_synth.opt")
  configure_file("${XILINX_OPT_DIR}/${XILINX_IMPLEMENT_OPT_FILE}.in"
                 "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}_implement.opt")
  file (COPY "${XILINX_OPT_DIR}/${XILINX_BITGEN_OPT_FILE}" DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

  # Create xflow command file (necessary because Linux shell interprets $ character following -g)
  set (CMD_FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}-xflow.cmd")
  file (WRITE  ${CMD_FILE} "-p ${FPGA_PARTNUM}\n")
  file (APPEND ${CMD_FILE} "-synth ${PROJ_NAME}_synth.opt\n")
  file (APPEND ${CMD_FILE} "-implement ${PROJ_NAME}_implement.opt\n")
  file (APPEND ${CMD_FILE} "-config    ${XILINX_BITGEN_OPT_FILE}\n")
  file (APPEND ${CMD_FILE} "-rd reports\n")
  file (APPEND ${CMD_FILE} "-g $proj_output:${PROJ_OUTPUT}\n")

  # Prepare files used by XST (synthesis)
  set (PRJ_FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}.prj")
  file (WRITE ${PRJ_FILE} "")
  foreach (f ${VERILOG_SOURCE})
    file (APPEND ${PRJ_FILE} "verilog work \"${f}\"\n")
  endforeach()

  # Note: Had to add ${CMAKE_CURRENT_BINARY_DIR} to the following two custom commands
  #       and target for CMake dependency checking to work properly.

  add_custom_command (OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_OUTPUT}.mcs"
                      COMMAND ${XFLOW_NATIVE} -f ${PROJ_NAME}-xflow.cmd ${PROJ_NAME}.prj
                      DEPENDS ${VERILOG_SOURCE} ${DEPENDENCIES})

  add_custom_target(${PROJ_NAME} ALL
                    DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_OUTPUT}.mcs")

  # Additional files to clean; ${PROJ_OUTPUT}.mcs is already handled by CMake, so here we
  # add the other generated output files (first two lines) and various log and temporary files.
  set(XILINX_CLEAN_FILES ${XILINX_CLEAN_FILES}
                         ${PROJ_NAME}.ngc ${PROJ_NAME}.ngd ${PROJ_NAME}.pcf
                         ${PROJ_NAME}_map.ncd ${PROJ_NAME}.ncd ${PROJ_NAME}.twr ${PROJ_NAME}.bit
                         ${PROJ_NAME}.bgn ${PROJ_NAME}.bld ${PROJ_OUTPUT}.cfi ${PROJ_NAME}.drc
                         ${PROJ_NAME}.lso ${PROJ_NAME}.pad ${PROJ_NAME}.par ${PROJ_NAME}.prm
                         ${PROJ_NAME}.ptwx ${PROJ_NAME}.srp ${PROJ_NAME}.unroutes ${PROJ_NAME}.xpi
                         ${PROJ_NAME}_map.map ${PROJ_NAME}_map.mrp ${PROJ_NAME}_map.ngm ${PROJ_NAME}_map.xrpt
                         ${PROJ_NAME}_ngdbuild.xrpt ${PROJ_NAME}_pad.csv ${PROJ_NAME}_pad.txt
                         ${PROJ_NAME}.xrpt ${PROJ_NAME}_summary.xml ${PROJ_NAME}_usage.xml)

  set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${XILINX_CLEAN_FILES}")

endmacro (ise_compile_fpga)

macro (ise_compile_fpga_old ...)

  # set all keywords and their values to ""
  set (FUNCTION_KEYWORDS
       PROJ_NAME
       DEPENDENCIES
       FPGA_PARTNUM
       VERILOG_SOURCE
       UCF_FILE
       IPCORE_DIR
       TOP_LEVEL
       PROJ_OUTPUT)

  # reset local variables
  foreach(keyword ${FUNCTION_KEYWORDS})
    set (${keyword} "")
  endforeach(keyword)

  # parse input
  foreach (arg ${ARGV})
    list (FIND FUNCTION_KEYWORDS ${arg} ARGUMENT_IS_A_KEYWORD)
    if (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (CURRENT_PARAMETER ${arg})
      set (${CURRENT_PARAMETER} "")
    else (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (${CURRENT_PARAMETER} ${${CURRENT_PARAMETER}} ${arg})
    endif (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
  endforeach (arg)

  file(TO_NATIVE_PATH ${XILINX_ISE_XST} XST_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_NGDBUILD} NGDBUILD_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_MAP} MAP_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_PAR} PAR_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_TRCE} TRCE_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_BITGEN} BITGEN_NATIVE)
  file(TO_NATIVE_PATH ${XILINX_ISE_PROMGEN} PROMGEN_NATIVE)

  # Prepare files used by XST
  set (PRJ_FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}.prj")
  file (WRITE ${PRJ_FILE} "")
  foreach (f ${VERILOG_SOURCE})
    file (APPEND ${PRJ_FILE} "verilog work \"${f}\"\n")
  endforeach()

  # Create XST input (script) file.
  set (XST_FILE "${CMAKE_CURRENT_BINARY_DIR}/${PROJ_NAME}.xst")
  file (WRITE ${XST_FILE} "# File generated by CMake for ${PROJ_NAME}\n"
                           "run\n"
                           "-ifn ${PROJ_NAME}.prj\n"
                           "-ofn ${PROJ_NAME}.ngc\n"
                           "-p ${FPGA_PARTNUM}\n"
                           "-top ${TOP_LEVEL}\n"
                           "# Following are default values\n"
                           "-opt_mode speed\n"
                           "-opt_level 1\n")
  # file (TO_NATIVE_PATH ${XST_FILE} XST_FILE_NATIVE)

  add_custom_target(${PROJ_NAME}-generate-xst
                    DEPENDS ${VERILOG_SOURCE} ${DEPENDENCIES}
                    COMMENT "Scanning Verilog files")

  # XST Synthesis (Verilog --> NGC)
  add_custom_command (OUTPUT "${PROJ_NAME}.ngc"
                      COMMAND ${XST_NATIVE} -intstyle silent -ifn ${PROJ_NAME}.xst
                      DEPENDS "${PROJ_NAME}-generate-xst" ${VERILOG_SOURCE}
                      COMMENT "Running XST to synthesize design")

  add_custom_target(${PROJ_NAME}-generate-ngc
                    DEPENDS "${PROJ_NAME}.ngc"
                    COMMENT "Checking XST Synthesis")

  # Implementation Step 1 (NGC --> NGD)
  #  -dd <dir>        --> set output directory to <dir>
  #  -sd <dir>        --> search directory <dir>
  add_custom_command(OUTPUT "${PROJ_NAME}.ngd"
                     COMMAND ${NGDBUILD_NATIVE} -intstyle silent -quiet 
                             -dd ${CMAKE_CURRENT_BINARY_DIR}/_ngo
                             -sd ${IPCORE_DIR}
                             -uc ${UCF_FILE}
                             -p  ${FPGA_PARTNUM}
                             ${PROJ_NAME}.ngc
                             ${PROJ_NAME}.ngd
                     DEPENDS "${PROJ_NAME}-generate-ngc" ${PROJ_NAME}.ngc
                     COMMENT "Running NGDBUILD")

  add_custom_target(${PROJ_NAME}-generate-ngd
                    DEPENDS "${PROJ_NAME}.ngd"
                    COMMENT "Checking NGDBUILD")

  # Map
  # Most options left at default. Following options are set; some are at default values,
  # others are uncertain.
  #   -w     --> overwrite existing files
  #   -logic_opt off
  #   -ol high    --> overall effort level (default)
  #   -xt 0
  #   -register_duplication off
  #   -r 4
  #   -mt 2       --> use multi-threading (-mt on)
  #   -ir off     --> uncertain whether this is default
  #   -lc off
  #   -power off
  add_custom_command(OUTPUT "${PROJ_NAME}_map.ncd" "${PROJ_NAME}.pcf"
                     COMMAND ${MAP_NATIVE} -intstyle silent
                             -p  ${FPGA_PARTNUM}
                             -w -logic_opt off -ol high -xt 0 -register_duplication off
                             -r 4 -mt 2 -ir off -lc off -power off
                             -o ${PROJ_NAME}_map.ncd
                             ${PROJ_NAME}.ngd
                             ${PROJ_NAME}.pcf
                     DEPENDS "${PROJ_NAME}-generate-ngd" ${PROJ_NAME}.ngd
                     COMMENT "Running MAP")

  add_custom_target(${PROJ_NAME}-generate-map
                    DEPENDS "${PROJ_NAME}_map.ncd" "${PROJ_NAME}.pcf"
                    COMMENT "Checking MAP")

  # PAR (Place & Route)
  add_custom_command(OUTPUT "${PROJ_NAME}.ncd"
                     COMMAND ${PAR_NATIVE} -intstyle silent
                             -w -ol high -mt 4 
                             ${PROJ_NAME}_map.ncd
                             ${PROJ_NAME}.ncd
                             ${PROJ_NAME}.pcf
                     DEPENDS "${PROJ_NAME}-generate-map" ${PROJ_NAME}_map.ncd ${PROJ_NAME}.pcf
                     COMMENT "Running PAR")

  add_custom_target(${PROJ_NAME}-generate-ncd
                    DEPENDS "${PROJ_NAME}.ncd"
                    COMMENT "Checking PAR")

  # Trace
  #   -v 3         --> generate verbose report, with a limit of 3 items per timing constraint
  #   -s 3         --> device speed (should not be needed, can get it from NCD file)
  #   -n 3         --> number of endpoints to report
  #   -fastpaths   --> report fastest paths of design
  add_custom_command(OUTPUT "${PROJ_NAME}.twr"
                     COMMAND ${TRCE_NATIVE} -intstyle silent
                             -v 3 -s 3 -n 3 -fastpaths
                             -xml ${PROJ_NAME}.twx
                             ${PROJ_NAME}.ncd
                             -o ${PROJ_NAME}.twr
                             ${PROJ_NAME}.pcf
                     DEPENDS "${PROJ_NAME}-generate-ncd" ${PROJ_NAME}.ncd
                     COMMENT "Running TRCE")

  add_custom_target(${PROJ_NAME}-timing
                    DEPENDS "${PROJ_NAME}.twr")

  # Bitgen (NCD --> BIT)
  #   Can set pullup/pulldown; currently using defaults, which are pullup for the
  #   PROG, TCK, TDI, TDO, and TMS pins and pulldown for all unused pins.
  #   Can set UserID to any 8 digit hexadecimal string (default is 0xFFFFFFFF).
  #   TIMER_CFG default for Spartan 6 is 0x0000 (value of watchdog timer in configuration mode)
  add_custom_command(OUTPUT "${PROJ_NAME}.bit"
                     COMMAND ${BITGEN_NATIVE} -intstyle silent
                             -w -g UserID:0xFFFFFFFF -g TIMER_CFG:0xFFFF 
                             ${PROJ_NAME}.ncd
                     DEPENDS "${PROJ_NAME}-generate-ncd" ${PROJ_NAME}.ncd
                     COMMENT "Running BITGEN")

  add_custom_target(${PROJ_NAME}-generate-bit
                    DEPENDS "${PROJ_NAME}.bit")

  # Promgen (BIT --> MCS)
  # When using the IDE, promgen is called by impact.
  # For now, hard-coded values such as prom size of 2048.
  # -w            --> overwrite file
  # -c FF         --> checksum
  # -o <filename> --> output file name
  # -s <size>     --> prom size (in Kbytes)
  # -u 0000       --> load upward starting at address
  # -spi          --> disable bit swapping for compatibility with SPI flash devices
  # -intstyle silent
  add_custom_command(OUTPUT "${PROJ_OUTPUT}.mcs"
                     COMMAND ${PROMGEN_NATIVE} -intstyle silent -w -p mcs -c FF -o ${PROJ_OUTPUT} -s 2048
                                               -u 0000 ${PROJ_NAME}.bit -spi
                     DEPENDS  "${PROJ_NAME}-generate-bit" ${PROJ_NAME}.bit
                     COMMENT "Running promgen to create ${PROJ_OUTPUT}.mcs")

  add_custom_target(${PROJ_NAME} ALL
                    DEPENDS "${PROJ_OUTPUT}.mcs")

  # Additional files to clean; ${PROJ_OUTPUT}.mcs is already handled by CMake, so here we add
  # the other generated output files (first two lines) and various log and temporary files.
  set(XILINX_CLEAN_FILES ${PROJ_NAME}.ngc ${PROJ_NAME}.ngd ${PROJ_NAME}.pcf
                         ${PROJ_NAME}_map.ncd ${PROJ_NAME}.ncd ${PROJ_NAME}.twr ${PROJ_NAME}.bit
                         ${PROJ_NAME}.bgn ${PROJ_NAME}.bld ${PROJ_OUTPUT}.cfi ${PROJ_NAME}.drc
                         ${PROJ_NAME}.lso ${PROJ_NAME}.pad ${PROJ_NAME}.par ${PROJ_NAME}.prm
                         ${PROJ_NAME}.ptwx ${PROJ_NAME}.srp ${PROJ_NAME}.unroutes ${PROJ_NAME}.xpi
                         ${PROJ_NAME}_map.map ${PROJ_NAME}_map.mrp ${PROJ_NAME}_map.ngm ${PROJ_NAME}_map.xrpt
                         ${PROJ_NAME}_ngdbuild.xrpt ${PROJ_NAME}_pad.csv ${PROJ_NAME}_pad.txt
                         ${PROJ_NAME}.xrpt ${PROJ_NAME}_summary.xml ${PROJ_NAME}_usage.xml)

  set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${XILINX_CLEAN_FILES})

endmacro(ise_compile_fpga_old)

macro (ise_ipcoregen ...)

  # set all keywords and their values to ""
  set (FUNCTION_KEYWORDS
       TARGET_NAME
       FPGA_DEVICE
       FPGA_PACKAGE
       FPGA_SPEED
       IPCORE_SOURCE_DIR
       IPCORE_BINARY_DIR
       XCO_SOURCE)

  # reset local variables
  foreach(keyword ${FUNCTION_KEYWORDS})
    set (${keyword} "")
  endforeach(keyword)

  # parse input
  foreach (arg ${ARGV})
    list (FIND FUNCTION_KEYWORDS ${arg} ARGUMENT_IS_A_KEYWORD)
    if (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (CURRENT_PARAMETER ${arg})
      set (${CURRENT_PARAMETER} "")
    else (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
      set (${CURRENT_PARAMETER} ${${CURRENT_PARAMETER}} ${arg})
    endif (${ARGUMENT_IS_A_KEYWORD} GREATER -1)
  endforeach (arg)

  file(TO_NATIVE_PATH ${XILINX_ISE_COREGEN} COREGEN_NATIVE)

  # Create build directory, if it does not already exist
  file (MAKE_DIRECTORY "${IPCORE_BINARY_DIR}")

  if (NOT IPCORE_BINARY_DIR STREQUAL IPCORE_SOURCE_DIR)
    # Probably CMake checks if source and binary directories are equal
    file (COPY "${IPCORE_SOURCE_DIR}/coregen.cgp" DESTINATION "${IPCORE_BINARY_DIR}")
  endif ()
  # Create batch file for CoreGen
  set (COREGEN_FILE "${IPCORE_BINARY_DIR}/${TARGET_NAME}.cmd")
  file (WRITE ${COREGEN_FILE} "")
  foreach (f ${XCO_SOURCE})
    if (NOT IPCORE_BINARY_DIR STREQUAL IPCORE_SOURCE_DIR)
      file (COPY "${IPCORE_SOURCE_DIR}/${f}" DESTINATION "${IPCORE_BINARY_DIR}")
    endif ()
    set (XCO_SOURCE_FULL "${XCO_SOURCE_FULL}" "${IPCORE_BINARY_DIR}/${f}")
    file (APPEND ${COREGEN_FILE} "EXECUTE \"${IPCORE_BINARY_DIR}/${f}\"\n")
  endforeach()

  # CoreGen (XCO --> Verilog)
  add_custom_command (OUTPUT "coregen.log"
                      COMMAND ${COREGEN_NATIVE} -b "${IPCORE_BINARY_DIR}/${TARGET_NAME}.cmd"
                                                -p "${IPCORE_BINARY_DIR}"
                      DEPENDS "${XCO_SOURCE_FULL}"
                      COMMENT "Running COREGEN to generate IP cores")

  add_custom_target(${TARGET_NAME} ALL
                    DEPENDS "coregen.log")

endmacro (ise_ipcoregen)
