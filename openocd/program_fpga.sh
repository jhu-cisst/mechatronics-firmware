#!/usr/bin/env bash

usage() {
    printf 'Usage: %s <filename.bit>\n' "$0"
    printf 'Temporarily program the FPGA with the specified bitstream.\n'
}

if [[ $# -eq 1 && ( $1 == -h || $1 == --help ) ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 || -z $1 ]]; then
    usage >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1

export FPGA_BIT_FILE="$1"
exec openocd -f "$script_dir/openocd.cfg" \
    -c 'init; program_fpga_filename $::env(FPGA_BIT_FILE); exit'
