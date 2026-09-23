# Block Design

This directory contains the TCL files that specify the block design created using Vivado:

  * `exported-block-v31.tcl` -- block design for FPGA V3.1; this is what most people should use
  * `exported-block-v30.tcl` -- block design for FPGA V3.0; only a few of these boards exist

The TCL files are created by starting Vivado, opening the block design, and then selecting
File...Export...Export Block Design...

To make changes to the block design, use Vivado to open the `xpr` file (e.g., `FpgaV31BlockDesign.xpr`)
in the `block_design` subdirectory of the build tree.
