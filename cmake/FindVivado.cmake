# Find Xilinx Vivado installation
#
# This will automatically find the necessary command line programs if the Xilinx Vivado binary directories are
# on the system PATH. Otherwise, it is necessary to manually specify the path.
#

find_program (XILINX_VIVADO NAMES "vivado" DOC "Xilinx Vivado tool")

# Check Vivado version. Even though the version is usually part of the path, it is better
# to parse the output from "vivado -version". This relies on the version being reported
# with a leading 'v' character, e.g., "v2023.1", which is removed in Vivado_VERSION.
# Note that a work-around appears to be necessary for Vivado 2023.1 (see below).

set (Vivado_VERSION "")
set (Vivado_VERSION_MAJOR "")
set (Vivado_VERSION_MINOR "")
if (XILINX_VIVADO)
  execute_process (COMMAND ${XILINX_VIVADO} -version
                   OUTPUT_VARIABLE VivadoVersionOutput)

  string (REGEX MATCH "v[0-9]+\.[0-9]" VivadoVersionString ${VivadoVersionOutput})
  if (NOT VivadoVersionString)
    # "vivado -version" does not seem to work for Vivado 2023.1 on Windows
    message (STATUS "FindVivado: \"vivado -version\" failed, trying \"vivado -help\"")
    execute_process (COMMAND ${XILINX_VIVADO} -help
                     OUTPUT_VARIABLE VivadoVersionOutput)
    string (REGEX MATCH "v[0-9]+\.[0-9]" VivadoVersionString ${VivadoVersionOutput})
  endif()
  if (VivadoVersionString)
    string (SUBSTRING ${VivadoVersionString} 1 -1 Vivado_VERSION)
    if (Vivado_VERSION)
      string (FIND ${Vivado_VERSION} "." DOT_POS)
      if (DOT_POS EQUAL 4)
        string (SUBSTRING ${Vivado_VERSION} 0  4 Vivado_VERSION_MAJOR)
        string (SUBSTRING ${Vivado_VERSION} 5 -1 Vivado_VERSION_MINOR)
        message (STATUS "Found Vivado ${Vivado_VERSION} (${Vivado_VERSION_MAJOR}, ${Vivado_VERSION_MINOR})")
      else ()
        message (WARNING "FindVivado: invalid version string ${Vivado_VERSION}")
      endif ()
    endif ()
  else ()
    message (WARNING "FindVivado: could not get version string")
  endif ()
endif ()

set (VIVADO_USE_FILE "${CMAKE_SOURCE_DIR}/cmake/UseVivado.cmake")

if (XILINX_VIVADO)
  set (Vivado_FOUND TRUE)
else()
  set (Vivado_FOUND FALSE)
endif()
