# CMake module to create the specified version file
#
# This module is involved using "cmake -P"; the caller should first define:
#   SOURCE_DIR        path to the git source directory
#   FIRMWARE_VERSION  the firmware version number
#   OUTPUT_FILE       full path to the output file


find_package (Git REQUIRED QUIET)

execute_process (COMMAND ${GIT_EXECUTABLE} describe --tags --match Rev*
                                           --long --dirty=-d --abbrev=7
                 WORKING_DIRECTORY ${SOURCE_DIR}
                 OUTPUT_VARIABLE GIT_DESCRIBE_STRING)
string (REPLACE "-" ";" GIT_DESCRIBE_LIST ${GIT_DESCRIBE_STRING})
list (LENGTH GIT_DESCRIBE_LIST desc_len)
if (desc_len LESS 3)
  message (FATAL_ERROR "git describe output invalid: ${GIT_DESCRIBE_STRING}")
endif ()
list (GET GIT_DESCRIBE_LIST 0 GIT_REV_TAG)
string (SUBSTRING ${GIT_REV_TAG} 3 -1 GIT_REV)
list (GET GIT_DESCRIBE_LIST 1 GIT_COMMITS)
list (GET GIT_DESCRIBE_LIST 2 GIT_SHA_RAW)
string (SUBSTRING ${GIT_SHA_RAW} 1 7 GIT_SHA)

file (WRITE  ${OUTPUT_FILE} "`define FW_VERSION 32'd${FIRMWARE_VERSION}        // firmware version = ${FIRMWARE_VERSION}\n\n")
file (APPEND ${OUTPUT_FILE} "`define GIT_FW_VERSION 32'd${GIT_REV}    // git version (based on Rev tag)\n")
file (APPEND ${OUTPUT_FILE} "`define GIT_COMMITS ${GIT_COMMITS}           // number of commits since git version tag\n")
file (APPEND ${OUTPUT_FILE} "`define GIT_SHA 24'h${GIT_SHA}     // git SHA\n")
if (desc_len EQUAL 4)
  file (APPEND ${OUTPUT_FILE} "`define GIT_DIRTY 1'b1          // local changes (not committed)\n")
else ()
  file (APPEND ${OUTPUT_FILE} "`define GIT_DIRTY 1'b0          // no local changes\n")
endif ()
